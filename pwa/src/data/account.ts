import { ChangeNotifier } from '../infra/changeNotifier';
import type { Prefs } from '../infra/prefs';
import { Achievement as Badge } from '../model/achievements';
import { LocalDate } from '../model/localDate';
import {
  Api,
  ApiError,
  NetworkError,
  type AchievementInput,
  type AchievementKind,
  type ActivityKind,
  type Cheers,
  type FeedPage,
  type FriendEntry,
  type Profile,
  type RequestOutcome,
  type Requests,
  type SearchResult,
  type Settings,
  type StreakInput,
  type StreakSnapshot,
  type Streaks,
  type User,
} from './api';
import type { ImportResult, ReadingStore } from './marks';

/**
 * The reader's account: who they are, their friends, the achievements
 * feed, and the mirror of their learning the server keeps so friends can
 * see it.
 *
 * An account is optional and the app is whole without one. With one, the
 * local `ReadingStore` stays the source of truth — the streak, the points,
 * the badges are decided on the device, offline, as they always were — and
 * this controller tells the server what happened: the streak as it stands,
 * the days something was done, the things worth a cheer. What it has to
 * tell is written to a queue in Prefs first and sent after, so a day
 * learnt on a train is a day the server hears of when the train comes out
 * of the tunnel, or the next time the app is opened.
 */
export type AccountStatus = 'loading' | 'signedOut' | 'signedIn' | 'offline';

export interface AccountCounts {
  friends: number;
  pendingRequests: number;
}

export interface AccountOptions {
  prefs: Prefs;
  reading: ReadingStore;
  /** The client to use; a test hands one in with a fake `fetch`. */
  api?: Api;
  /** A `fetch` for the default client. */
  fetch?: typeof fetch;
  /** How long after a change in `reading` the sync runs, in ms. */
  debounceMs?: number;
}

export interface ReminderPatch {
  /** `HH:MM`, or null to turn the daily reminder off. */
  reminderTime?: string | null;
  /** Bitmask, Mon=1 … Sun=64. */
  reminderDays?: number;
  reminderOnlyIfUndone?: boolean;
  friendReminders?: boolean;
}

export interface ProfilePatch {
  displayName?: string;
  bio?: string;
  email?: string | null;
}

export interface AchievementRecord {
  key: string;
  kind: AchievementKind;
  title: string;
  detail?: string;
  earnedAt?: Date | string;
}

/** What `enablePush` came to. */
export type PushOutcome = 'enabled' | 'denied' | 'unsupported' | 'failed';

/** Where the mirror stands, for the "Backed up" line under the streak. */
export type SyncState = 'signedOut' | 'synced' | 'pending' | 'offline';

/** One call waiting to be sent. */
export interface QueuedCall {
  id: number;
  method: 'POST' | 'PUT';
  path: string;
  body: unknown;
}

/**
 * What the server has already been told (or is queued to be told), so a
 * change in `reading` can be turned into only what is new.
 */
interface Shadow {
  /** The streak last queued, as JSON. */
  streak: string | null;
  /** `kind:day` for each activity queued, newest last. */
  done: string[];
  /** `BOOK/chapter` of the reading position last seen. */
  readChapter: string | null;
  /** Plan slots ticked, over every plan, when last seen. */
  planSlots: number;
  perfectRounds: number;
  level: number;
  /** Keys of the achievements queued. */
  keys: string[];
}

const kToken = 'account.token';
const kUser = 'account.user';
const kSettings = 'account.settings';
const kCounts = 'account.counts';
const kQueue = 'account.queue';
const kShadow = 'account.shadow';
const kBackupAt = 'account.backupAt';
const kSyncedAt = 'account.syncedAt';
const kPush = 'account.pushEndpoint';

/** Streak lengths worth telling friends about. */
export const streakMilestones: readonly number[] = [7, 30, 100, 365];

/** How many `kind:day` marks are remembered: more than the days of points kept. */
const doneKept = 400;

/** The server takes days up to 400 behind today; stay inside it. */
const oldestDayBehind = 395;

/** Monday's bit is 1, Sunday's 64, as the server keeps `reminderDays`. */
export function weekdayBit(date: Date): number {
  return 1 << ((date.getDay() + 6) % 7);
}

export const everyDay = 127;

/** The device's IANA time zone, or null where it cannot be told. */
export function localTimeZone(): string | null {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || null;
  } catch {
    return null;
  }
}

/**
 * Whether the day's reminder is due and unanswered: a reminder time is
 * set, today is one of its days, the time has passed, and nothing has been
 * learnt today. For the nudge the Library shows where no push can reach
 * the reader (an iOS tab, permission refused, a browser without push).
 */
export function reminderDueNow(settings: Settings | null | undefined, reading: Pick<ReadingStore, 'streak'>, now: Date = new Date()): boolean {
  if (!settings || !settings.reminderTime) return false;
  const m = /^(\d{1,2}):(\d{2})$/.exec(settings.reminderTime.trim());
  if (!m) return false;
  const hour = Number(m[1]);
  const minute = Number(m[2]);
  if (hour > 23 || minute > 59) return false;
  if ((settings.reminderDays & weekdayBit(now)) === 0) return false;
  const due = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute, 0, 0);
  if (now.getTime() < due.getTime()) return false;
  return !reading.streak.practisedOn(now);
}

export class AccountController extends ChangeNotifier {
  readonly api: Api;
  private readonly prefs: Prefs;
  private readonly reading: ReadingStore;
  private readonly debounceMs: number;

  private _status: AccountStatus = 'loading';
  private _user: User | null = null;
  private _settings: Settings | null = null;
  private _streak: StreakSnapshot | null = null;
  private _counts: AccountCounts = { friends: 0, pendingRequests: 0 };

  private queue: QueuedCall[] = [];
  private nextQueueId = 1;
  private shadow: Shadow | null = null;
  private flushing: Promise<void> | null = null;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private started = false;
  private readonly onReading = () => this.schedule();
  private readonly onOnline = () => void this.cameOnline();

  constructor(options: AccountOptions) {
    super();
    this.prefs = options.prefs;
    this.reading = options.reading;
    this.debounceMs = options.debounceMs ?? 800;
    this.api = options.api ?? new Api({ fetch: options.fetch, token: () => this.token });
    this.restore();
  }

  // ----------------------------------------------------------------- state

  get status(): AccountStatus {
    return this._status;
  }

  /** Who is signed in — from the server, or the copy kept for when it cannot be reached. */
  get user(): User | null {
    return this._user;
  }

  /** Reminder preferences. */
  get settings(): Settings | null {
    return this._settings;
  }

  /** The streak as the server has it, which is what friends see. */
  get streak(): StreakSnapshot | null {
    return this._streak;
  }

  get counts(): AccountCounts {
    return this._counts;
  }

  /** Whether there is an account on this device, reachable just now or not. */
  get isSignedIn(): boolean {
    return this._user !== null && (this._status === 'signedIn' || this._status === 'offline');
  }

  /** Calls still to be sent. */
  get pendingCount(): number {
    return this.queue.length;
  }

  /** The calls waiting, oldest first: for tests and for curiosity. */
  get pending(): readonly QueuedCall[] {
    return [...this.queue];
  }

  /** When the queue last ran dry. */
  get lastSyncedAt(): Date | null {
    return readDate(this.prefs.getString(kSyncedAt));
  }

  /** When the backup was last put on the account from this device. */
  get lastBackupAt(): Date | null {
    return readDate(this.prefs.getString(kBackupAt));
  }

  get syncState(): SyncState {
    if (!this.isSignedIn) return 'signedOut';
    if (this._status === 'offline') return 'offline';
    return this.queue.length > 0 ? 'pending' : 'synced';
  }

  /** Whether this browser's push subscription is registered with the account. */
  get pushEnabled(): boolean {
    return this.prefs.getString(kPush) !== null;
  }

  private get token(): string | null {
    return this.prefs.getString(kToken);
  }

  /** Reads what was kept, so `user` is there before the server answers. */
  private restore(): void {
    this._user = readJson<User>(this.prefs.getString(kUser));
    this._settings = readJson<Settings>(this.prefs.getString(kSettings));
    this._counts = readJson<AccountCounts>(this.prefs.getString(kCounts)) ?? { friends: 0, pendingRequests: 0 };
    this.shadow = readJson<Shadow>(this.prefs.getString(kShadow));
    const queue = readJson<QueuedCall[]>(this.prefs.getString(kQueue));
    this.queue = Array.isArray(queue) ? queue.filter((c) => c && typeof c.path === 'string' && typeof c.method === 'string') : [];
    this.nextQueueId = this.queue.reduce((max, c) => (c.id >= max ? c.id + 1 : max), 1);
  }

  // ----------------------------------------------------------------- start

  /**
   * Restores the session. Where a token was kept, the server is asked who
   * we are; if it cannot be reached the kept copy of the user stands, with
   * status `offline`, so the screens still show whose account this is.
   * Never throws.
   */
  async start(): Promise<void> {
    if (!this.started) {
      this.started = true;
      this.reading.addListener(this.onReading);
      if (typeof window !== 'undefined' && typeof window.addEventListener === 'function') {
        window.addEventListener('online', this.onOnline);
      }
    }
    if (this.token === null) {
      // No session was ever made here: nothing to ask, and the app must
      // not need a server to start.
      this.setStatus('signedOut');
      return;
    }
    await this.refresh();
  }

  override dispose(): void {
    this.reading.removeListener(this.onReading);
    if (typeof window !== 'undefined' && typeof window.removeEventListener === 'function') {
      window.removeEventListener('online', this.onOnline);
    }
    if (this.timer) clearTimeout(this.timer);
    if (this.retryTimer) clearTimeout(this.retryTimer);
    super.dispose();
  }

  /** Asks the server for the account as it stands, then sends what is waiting. */
  async refresh(): Promise<void> {
    if (this.token === null) {
      this.setStatus('signedOut');
      return;
    }
    try {
      const me = await this.api.me();
      this._user = me.user;
      this._settings = me.settings;
      this._streak = me.streak;
      this._counts = me.counts;
      this.persistAccount();
      this.setStatus('signedIn', true);
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) {
        this.forgetSession();
        return;
      }
      // Offline, or the server is down: whoever was signed in still is.
      this.setStatus(this._user !== null ? 'offline' : 'signedOut');
      return;
    }
    await this.syncNow();
  }

  private async cameOnline(): Promise<void> {
    if (this.token === null) return;
    if (this._status === 'offline') await this.refresh();
    else await this.syncNow();
  }

  private setStatus(status: AccountStatus, force = false): void {
    if (this._status === status && !force) return;
    this._status = status;
    this.notifyListeners();
  }

  private persistAccount(): void {
    if (this._user) this.prefs.setString(kUser, JSON.stringify(this._user));
    else this.prefs.remove(kUser);
    if (this._settings) this.prefs.setString(kSettings, JSON.stringify(this._settings));
    else this.prefs.remove(kSettings);
    this.prefs.setString(kCounts, JSON.stringify(this._counts));
  }

  /** The session is gone (expired, or the account deleted elsewhere). */
  private forgetSession(): void {
    this.prefs.remove(kToken);
    this.prefs.remove(kPush);
    this._streak = null;
    this._user = null;
    this._settings = null;
    this._counts = { friends: 0, pendingRequests: 0 };
    this.prefs.remove(kUser);
    this.prefs.remove(kSettings);
    this.prefs.remove(kCounts);
    this.setStatus('signedOut', true);
  }

  /**
   * Runs a call for a screen. A dropped connection marks the account
   * offline; an answer brings it back; an expired session signs out. The
   * error is thrown on for the screen to show.
   */
  private async call<T>(run: () => Promise<T>): Promise<T> {
    try {
      const value = await run();
      if (this._status === 'offline' && this._user !== null) {
        this.setStatus('signedIn');
        void this.flush();
      }
      return value;
    } catch (error) {
      if (error instanceof NetworkError) {
        if (this._user !== null && this._status === 'signedIn') this.setStatus('offline');
      } else if (error instanceof ApiError && error.code === 'unauthorized') {
        this.forgetSession();
      }
      throw error;
    }
  }

  // ------------------------------------------------------------------ auth

  async register(input: { username: string; password: string; displayName?: string; email?: string; inviteCode?: string }): Promise<User> {
    const { user, token } = await this.api.register({
      username: input.username.trim().toLowerCase(),
      password: input.password,
      displayName: input.displayName?.trim() || undefined,
      email: input.email?.trim() || undefined,
      inviteCode: input.inviteCode?.trim() || undefined,
    });
    await this.signedInAs(user, token);
    return user;
  }

  /** `username` may be the username or the email address. */
  async login(username: string, password: string): Promise<User> {
    const { user, token } = await this.api.login(username.trim(), password);
    await this.signedInAs(user, token);
    return user;
  }

  private async signedInAs(user: User, token: string): Promise<void> {
    const before = readJson<User>(this.prefs.getString(kUser)) ?? readJson<{ id: string }>(this.prefs.getString('account.lastUser'));
    if (!before || before.id !== user.id) {
      // Someone else's account: what was queued and what was told belong
      // to the other one.
      this.queue = [];
      this.persistQueue();
      this.shadow = null;
      this.prefs.remove(kShadow);
      this.prefs.remove(kBackupAt);
      this.prefs.remove(kSyncedAt);
    }
    this.prefs.setString(kToken, token);
    this.prefs.setString('account.lastUser', JSON.stringify({ id: user.id }));
    this._user = user;
    this._settings ??= { reminderTime: null, reminderTz: null, reminderDays: everyDay, reminderOnlyIfUndone: true, friendReminders: true };
    this.persistAccount();
    this.setStatus('signedIn', true);
    // Settings, counts and the server's streak, then everything this
    // device knows that the account does not.
    await this.refresh();
    if (this._settings && this._settings.reminderTz === null) {
      const tz = localTimeZone();
      // Reminders are in the reader's own time; the server needs the zone.
      if (tz && this._status === 'signedIn') await this.patchSettings({ reminderTz: tz }).catch(() => undefined);
    }
  }

  /** Signs out of this device. What is waiting is sent first if it can be. */
  async logout(): Promise<void> {
    if (this.pushEnabled) await this.disablePush().catch(() => undefined);
    await this.syncNow().catch(() => undefined);
    try {
      await this.api.logout();
    } catch {
      // Signing out works offline too; the server's session will expire.
    }
    this.forgetSession();
  }

  async changePassword(current: string, next: string): Promise<void> {
    await this.call(() => this.api.changePassword(current, next));
  }

  /** Deletes the account on the server. What is on this device stays. */
  async deleteAccount(password: string): Promise<void> {
    await this.call(() => this.api.deleteAccount(password));
    this.queue = [];
    this.persistQueue();
    this.shadow = null;
    this.prefs.remove(kShadow);
    this.prefs.remove(kBackupAt);
    this.prefs.remove(kSyncedAt);
    this.prefs.remove('account.lastUser');
    this.forgetSession();
  }

  // --------------------------------------------------------------- profile

  async updateProfile(patch: ProfilePatch): Promise<User> {
    const { user, settings } = await this.call(() => this.api.updateMe(patch));
    this._user = user;
    this._settings = settings;
    this.persistAccount();
    this.notifyListeners();
    return user;
  }

  /**
   * Sets the profile photo. The picture is cut square and brought down to
   * 512 pixels as a JPEG on the device first, so a phone does not send
   * eight megabytes of camera roll.
   */
  async uploadAvatar(file: Blob): Promise<void> {
    const image = await resizeImage(file, 512);
    const { avatarVersion, avatarUrl } = await this.call(() => this.api.uploadAvatar(image));
    if (this._user) {
      this._user = { ...this._user, avatarVersion, avatarUrl };
      this.persistAccount();
      this.notifyListeners();
    }
  }

  async removeAvatar(): Promise<void> {
    await this.call(() => this.api.removeAvatar());
    if (this._user) {
      this._user = { ...this._user, avatarVersion: 0, avatarUrl: null };
      this.persistAccount();
      this.notifyListeners();
    }
  }

  // ------------------------------------------------------------- reminders

  /**
   * Sets when and whether reminders come. The time is the reader's local
   * time, so the device's time zone goes with it.
   */
  async setReminders(patch: ReminderPatch): Promise<Settings> {
    return this.patchSettings({ ...patch, reminderTz: localTimeZone() ?? this._settings?.reminderTz ?? null });
  }

  private async patchSettings(patch: ReminderPatch & { reminderTz?: string | null }): Promise<Settings> {
    const before = this._settings;
    if (before) {
      // Shown at once; put back if the server will not have it.
      this._settings = { ...before, ...definedOnly(patch) };
      this.notifyListeners();
    }
    try {
      const { user, settings } = await this.call(() => this.api.updateMe(patch));
      this._user = user;
      this._settings = settings;
      this.persistAccount();
      this.notifyListeners();
      return settings;
    } catch (error) {
      this._settings = before;
      this.notifyListeners();
      throw error;
    }
  }

  /**
   * Subscribes this browser to push and registers the subscription with
   * the account, asking for permission if it has not been given. Call it
   * from a tap.
   */
  async enablePush(): Promise<PushOutcome> {
    const push = await import('../pwa/notifications');
    if (!push.pushSupported()) return 'unsupported';
    try {
      const key = await this.call(() => this.api.vapidKey());
      const subscription = await push.subscribeToPush(key);
      if (!subscription || !subscription.endpoint) {
        return push.notificationPermission() === 'denied' ? 'denied' : 'failed';
      }
      await this.call(() => this.api.subscribePush(subscription));
      this.prefs.setString(kPush, subscription.endpoint);
      this.notifyListeners();
      return 'enabled';
    } catch (error) {
      console.warn('OpenWord: could not turn push on', error);
      return 'failed';
    }
  }

  /** Stops reminders reaching this browser. */
  async disablePush(): Promise<void> {
    const push = await import('../pwa/notifications');
    const endpoint = (await push.currentPushSubscription())?.endpoint ?? this.prefs.getString(kPush);
    this.prefs.remove(kPush);
    this.notifyListeners();
    if (endpoint) await this.api.unsubscribePush(endpoint).catch(() => undefined);
    await push.unsubscribeFromPush();
  }

  /** Asks the server to push a test notification; answers how many it sent. */
  sendTestPush(): Promise<number> {
    return this.call(() => this.api.testPush());
  }

  // ---------------------------------------------------------------- backup

  /** Puts the same JSON the clipboard backup makes on the account. */
  async uploadBackup(): Promise<Date> {
    const document: unknown = JSON.parse(this.reading.export());
    const info = await this.call(() => this.api.putBackup(document));
    const at = readDate(info.updatedAt) ?? new Date();
    this.prefs.setString(kBackupAt, at.toISOString());
    this.notifyListeners();
    return at;
  }

  /**
   * Fetches the account's backup and merges it into what is here, as
   * importing a backup always does: nothing on the device is dropped.
   * Null when the account has no backup.
   */
  async downloadBackup(): Promise<ImportResult | null> {
    const stored = await this.call(() => this.api.getBackup());
    if (stored === null) return null;
    return this.reading.import(JSON.stringify(stored.document));
  }

  /** When the account's backup was stored, or null when there is none. */
  async backupStoredAt(): Promise<Date | null> {
    const stored = await this.call(() => this.api.getBackup());
    return stored ? readDate(stored.updatedAt) : null;
  }

  // --------------------------------------------------------------- friends

  searchUsers(q: string): Promise<SearchResult[]> {
    return this.call(() => this.api.searchUsers(q));
  }

  profile(username: string): Promise<Profile> {
    return this.call(() => this.api.profile(username));
  }

  async friends(): Promise<FriendEntry[]> {
    const friends = await this.call(() => this.api.friends());
    this.setCounts({ friends: friends.length });
    return friends;
  }

  async requests(): Promise<Requests> {
    const requests = await this.call(() => this.api.requests());
    this.setCounts({ pendingRequests: requests.incoming.length });
    return requests;
  }

  /** Asks someone to be a friend. If they had asked already, you are friends at once. */
  async sendRequest(username: string, message?: string): Promise<RequestOutcome> {
    const outcome = await this.call(() => this.api.sendRequest(username, message?.trim() || undefined));
    if (outcome.friend) {
      this.setCounts({ friends: this._counts.friends + 1, pendingRequests: Math.max(0, this._counts.pendingRequests - 1) });
    }
    return outcome;
  }

  async acceptRequest(id: string): Promise<FriendEntry> {
    const friend = await this.call(() => this.api.acceptRequest(id));
    this.setCounts({ friends: this._counts.friends + 1, pendingRequests: Math.max(0, this._counts.pendingRequests - 1) });
    return friend;
  }

  async declineRequest(id: string): Promise<void> {
    await this.call(() => this.api.declineRequest(id));
    this.setCounts({ pendingRequests: Math.max(0, this._counts.pendingRequests - 1) });
  }

  cancelRequest(id: string): Promise<void> {
    return this.call(() => this.api.cancelRequest(id));
  }

  async unfriend(userId: string): Promise<void> {
    await this.call(() => this.api.unfriend(userId));
    this.setCounts({ friends: Math.max(0, this._counts.friends - 1) });
  }

  private setCounts(changes: Partial<AccountCounts>): void {
    const next = { ...this._counts, ...changes };
    if (next.friends === this._counts.friends && next.pendingRequests === this._counts.pendingRequests) return;
    this._counts = next;
    this.prefs.setString(kCounts, JSON.stringify(next));
    this.notifyListeners();
  }

  // ------------------------------------------------------------------ feed

  feed(before?: string | null): Promise<FeedPage> {
    return this.call(() => this.api.feed(before));
  }

  cheer(id: string): Promise<Cheers> {
    return this.call(() => this.api.cheer(id));
  }

  uncheer(id: string): Promise<Cheers> {
    return this.call(() => this.api.uncheer(id));
  }

  /** Your streak as friends see it, and the streak you share with each of them. */
  async streaks(): Promise<Streaks> {
    const streaks = await this.call(() => this.api.streaks());
    this._streak = streaks.streak;
    return streaks;
  }

  // ------------------------------------------------------------- recording

  /**
   * Tells the account something was done on `day` (today, by the reader's
   * own calendar, when left out). Once a day per kind is all the server
   * needs. For the screens that know what `reading` cannot show: the quiz
   * screen when a round finishes (`quiz`), read-aloud when a chapter has
   * been heard (`listen`). Learning, reading and plan ticks are noticed
   * from `reading` without being told.
   */
  recordActivity(kind: ActivityKind, day?: Date | string): void {
    if (!this.hasAccount) return;
    const shadow = this.ensureShadow();
    if (this.queueActivity(shadow, kind, typeof day === 'string' ? day : this.dayOf(day ?? this.reading.today))) {
      this.persistShadow();
      void this.flush();
    }
  }

  /**
   * Posts something for the feed. `key` is unique per person: posting it
   * twice is posting it once.
   */
  recordAchievement(record: AchievementRecord): void {
    if (!this.hasAccount) return;
    const shadow = this.ensureShadow();
    if (shadow.keys.includes(record.key)) return;
    shadow.keys.push(record.key);
    this.queueAchievements([
      {
        key: record.key,
        kind: record.kind,
        title: record.title,
        detail: record.detail ?? '',
        earnedAt: record.earnedAt === undefined ? this.reading.today.toISOString() : typeof record.earnedAt === 'string' ? record.earnedAt : record.earnedAt.toISOString(),
      },
    ]);
    this.persistShadow();
    void this.flush();
  }

  // ------------------------------------------------------------------ sync

  /** Whether there is an account to mirror to, reachable or not. */
  private get hasAccount(): boolean {
    return this.token !== null && this._user !== null;
  }

  private schedule(): void {
    if (!this.hasAccount) return;
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = null;
      void this.syncNow();
    }, this.debounceMs);
  }

  /**
   * Works out what `reading` holds that the account has not been told,
   * queues it, and sends the queue. What the debounce runs; a test calls
   * it to skip the wait.
   */
  async syncNow(): Promise<void> {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    if (!this.hasAccount) return;
    this.derive();
    await this.flush();
  }

  private dayOf(moment: Date): string {
    return LocalDate.format(LocalDate.only(moment));
  }

  private ensureShadow(): Shadow {
    return (this.shadow ??= this.baseline());
  }

  /**
   * Where a new account starts from. The reading position, the plan ticks
   * and the perfect rounds are taken as they stand, since nothing says on
   * which day they were made; the days of points, the badges and the rest
   * are left for `derive` to send, each with its own day.
   */
  private baseline(): Shadow {
    const position = this.reading.lastPosition;
    return {
      streak: null,
      done: [],
      readChapter: position ? `${position.bookCode}/${position.chapter}` : null,
      planSlots: this.reading.plans.reduce((sum, plan) => sum + plan.slotsDone, 0),
      perfectRounds: this.reading.progress.perfectRounds,
      // Only the level reached is news; the ones passed on the way are not.
      level: this.reading.progress.level - 1,
      keys: [],
    };
  }

  /** Turns the difference between `reading` and the shadow into queued calls. */
  private derive(): void {
    const reading = this.reading;
    const now = reading.today;
    const today = this.dayOf(now);
    const todayDate = LocalDate.only(now);
    const shadow = this.ensureShadow();
    const progress = reading.progress;
    const streak = reading.streak;
    const earned: AchievementInput[] = [];
    const earn = (key: string, kind: AchievementKind, title: string, detail: string, at: Date) => {
      if (shadow.keys.includes(key)) return;
      shadow.keys.push(key);
      // No two alike, so the feed's paging never drops one.
      earned.push({ key, kind, title, detail, earnedAt: new Date(at.getTime() + earned.length).toISOString() });
    };
    /** A moment for something earned on `day`: now if that is today, else that day's noon. */
    const momentOn = (day: Date | null | undefined): Date => {
      if (day == null || day.getTime() >= todayDate.getTime()) return now;
      return new Date(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate(), 12, 0, 0, 0);
    };

    // (a) The streak, as it stands today.
    if (streak.last !== null) {
      const input: StreakInput = {
        current: streak.currentOn(now),
        best: streak.best,
        freezes: streak.freezes,
        lastDay: LocalDate.format(streak.last),
      };
      const signature = JSON.stringify(input);
      if (signature !== shadow.streak) {
        shadow.streak = signature;
        this.enqueue('PUT', '/streak', input, (call) => call.method === 'PUT' && call.path === '/streak');
      }
    }

    // (b) The days something was done. Learning: every day with points,
    // and the streak's last day, so a day learnt while signed out or
    // offline still counts towards a streak with a friend.
    const learnt = new Set<number>();
    for (const [day, points] of progress.daily) if (points > 0) learnt.add(day);
    if (streak.last !== null) learnt.add(streak.last.getTime());
    for (const day of [...learnt].sort((a, b) => a - b)) {
      const behind = LocalDate.daysBetween(todayDate, new Date(day));
      if (behind < 0 || behind > oldestDayBehind) continue;
      this.queueActivity(shadow, 'learn', LocalDate.format(new Date(day)));
    }

    // Reading: the position moved to another chapter.
    const position = reading.lastPosition;
    const chapter = position ? `${position.bookCode}/${position.chapter}` : null;
    if (chapter !== shadow.readChapter) {
      shadow.readChapter = chapter;
      if (chapter !== null) this.queueActivity(shadow, 'read', today);
    }

    // A plan: a chapter ticked.
    const slots = reading.plans.reduce((sum, plan) => sum + plan.slotsDone, 0);
    if (slots > shadow.planSlots) this.queueActivity(shadow, 'plan', today);
    shadow.planSlots = slots;

    // A round with every answer right is a round finished.
    if (progress.perfectRounds > shadow.perfectRounds) {
      this.queueActivity(shadow, 'quiz', today);
      earn(`quiz:perfect:${today}`, 'quiz', 'Perfect round', 'A whole round without a miss.', now);
    }
    shadow.perfectRounds = progress.perfectRounds;

    // (c) Things worth a cheer.
    for (const badge of Badge.values) {
      const day = progress.badges.get(badge.id);
      if (day === undefined) continue;
      earn(badge.id, 'badge', badge.title, badge.description, momentOn(day));
    }
    const level = progress.level;
    if (level > shadow.level) {
      for (let n = Math.max(shadow.level + 1, 2); n <= level; n++) {
        earn(`level:${n}`, 'level', `Level ${n}`, `${progress.xp} points so far.`, now);
      }
    }
    shadow.level = Math.max(shadow.level, level);
    for (const milestone of streakMilestones) {
      if (streak.best >= milestone || streak.count >= milestone) {
        earn(`streak:${milestone}`, 'streak', `${milestone}-day streak`, streakDetail(milestone), streak.count === milestone ? momentOn(streak.last) : now);
      }
    }
    for (const plan of reading.plans) {
      if (plan.isComplete && plan.plan.slotCount > 0) {
        earn(`plan:${plan.plan.id}`, 'plan', `Finished ${plan.plan.name}`, `${plan.plan.length} days of reading.`, plan.updated.getTime() > 0 && plan.updated.getTime() < now.getTime() ? plan.updated : now);
      }
    }
    for (const verse of reading.memoryVerses) {
      if (verse.isLearnt) {
        earn(`memory:${verse.reference.encode()}`, 'memory', `${verse.reference.label} by heart`, 'Recalled after a month away.', now);
      }
    }
    if (earned.length > 0) this.queueAchievements(earned);

    this.persistShadow();
  }

  /** Queues an activity unless that day and kind is already told. Answers whether it was queued. */
  private queueActivity(shadow: Shadow, kind: ActivityKind, day: string): boolean {
    const mark = `${kind}:${day}`;
    if (shadow.done.includes(mark)) return false;
    shadow.done.push(mark);
    if (shadow.done.length > doneKept) shadow.done = shadow.done.slice(shadow.done.length - doneKept);
    this.enqueue('POST', '/activity', { day, kind });
    return true;
  }

  /** Queues achievements, on to a batch already waiting where there is one. */
  private queueAchievements(inputs: AchievementInput[]): void {
    const waiting = this.queue.find(
      (call) => call.path === '/achievements/batch' && isBatch(call.body) && call.body.achievements.length + inputs.length <= 500,
    );
    if (waiting && isBatch(waiting.body)) {
      waiting.body.achievements.push(...inputs);
      this.persistQueue();
      this.notifyListeners();
      return;
    }
    for (let i = 0; i < inputs.length; i += 500) {
      this.enqueue('POST', '/achievements/batch', { achievements: inputs.slice(i, i + 500) });
    }
  }

  /** Adds a call to the queue, in place of any waiting call `replaces` matches. */
  private enqueue(method: QueuedCall['method'], path: string, body: unknown, replaces?: (call: QueuedCall) => boolean): void {
    if (replaces) this.queue = this.queue.filter((call) => !replaces(call));
    this.queue.push({ id: this.nextQueueId++, method, path, body });
    this.persistQueue();
    this.notifyListeners();
  }

  private persistQueue(): void {
    if (this.queue.length === 0) this.prefs.remove(kQueue);
    else this.prefs.setString(kQueue, JSON.stringify(this.queue));
  }

  private persistShadow(): void {
    if (this.shadow) this.prefs.setString(kShadow, JSON.stringify(this.shadow));
  }

  /**
   * Sends what is waiting, oldest first, each call taken off the queue
   * only once the server has answered it. Stops at the first call that
   * cannot be delivered for now and leaves it, and the rest, for later.
   */
  flush(): Promise<void> {
    if (this.flushing) return this.flushing;
    this.flushing = this.runFlush().finally(() => {
      this.flushing = null;
    });
    return this.flushing;
  }

  private async runFlush(): Promise<void> {
    if (!this.hasAccount) return;
    let sent = false;
    while (this.queue.length > 0 && this.hasAccount) {
      const call = this.queue[0];
      try {
        const answer = await this.api.send(call.method, call.path, call.body);
        if (call.path === '/streak' && isRecord(answer) && isRecord(answer['streak'])) {
          this._streak = answer['streak'] as unknown as StreakSnapshot;
        }
        sent = true;
      } catch (error) {
        if (error instanceof ApiError && error.status === 401) {
          // The session is gone; what is queued waits for the next sign-in.
          this.forgetSession();
          return;
        }
        if (error instanceof ApiError && error.status >= 400 && error.status < 500 && error.status !== 429 && error.status !== 408) {
          // The server will never take this one; holding it would hold
          // everything behind it.
          console.warn(`OpenWord: the server refused ${call.method} ${call.path}: ${error.message}`);
        } else {
          if (error instanceof NetworkError && this._status === 'signedIn') this.setStatus('offline');
          this.retryLater();
          return;
        }
      }
      // Whatever was added while this one was in the air stays; only this
      // call comes off.
      this.queue = this.queue.filter((c) => c.id !== call.id);
      this.persistQueue();
    }
    if (this.queue.length === 0 && this.hasAccount) {
      if (sent) this.prefs.setString(kSyncedAt, new Date().toISOString());
      if (this._status === 'offline' && sent) this._status = 'signedIn';
      this.notifyListeners();
    }
  }

  /** Tries again in a while; the `online` event usually gets there first. */
  private retryLater(): void {
    if (this.retryTimer || typeof window === 'undefined') return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      void this.cameOnline();
    }, 60_000);
  }
}

function streakDetail(days: number): string {
  switch (days) {
    case 7:
      return 'A week of learning every day.';
    case 30:
      return 'A month of learning every day.';
    case 100:
      return 'A hundred days of learning.';
    case 365:
      return 'A year of learning every day.';
    default:
      return `${days} days of learning.`;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isBatch(body: unknown): body is { achievements: AchievementInput[] } {
  return isRecord(body) && Array.isArray(body['achievements']);
}

function readJson<T>(raw: string | null): T | null {
  if (raw === null) return null;
  try {
    const parsed: unknown = JSON.parse(raw);
    return parsed === null || typeof parsed !== 'object' ? null : (parsed as T);
  } catch {
    return null;
  }
}

function readDate(raw: string | null | undefined): Date | null {
  if (!raw) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? null : date;
}

function definedOnly<T extends object>(patch: T): Partial<T> {
  const out: Partial<T> = {};
  for (const [key, value] of Object.entries(patch)) {
    if (value !== undefined) (out as Record<string, unknown>)[key] = value;
  }
  return out;
}

/**
 * A picture cut to a centred square and brought down to at most `size`
 * pixels a side, as a JPEG. Where the browser cannot (no canvas, a format
 * it does not read) the file is answered as it came, and the server, which
 * crops and resizes anyway, has the last word.
 */
export async function resizeImage(file: Blob, size = 512): Promise<Blob> {
  if (typeof document === 'undefined') return file;
  try {
    const source = await decodeImage(file);
    const side = Math.min(source.width, source.height);
    if (side <= 0) return file;
    const target = Math.min(size, side);
    const canvas = document.createElement('canvas');
    canvas.width = target;
    canvas.height = target;
    const context = canvas.getContext('2d');
    if (!context) return file;
    context.imageSmoothingQuality = 'high';
    context.drawImage(source.image, (source.width - side) / 2, (source.height - side) / 2, side, side, 0, 0, target, target);
    source.close();
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.86));
    return blob ?? file;
  } catch (error) {
    console.warn('OpenWord: could not resize the photo; sending it as it is', error);
    return file;
  }
}

async function decodeImage(file: Blob): Promise<{ image: CanvasImageSource; width: number; height: number; close: () => void }> {
  if (typeof createImageBitmap === 'function') {
    try {
      // Phones record how the camera was held rather than turning the pixels.
      const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
      return { image: bitmap, width: bitmap.width, height: bitmap.height, close: () => bitmap.close() };
    } catch {
      // Fall through to an <img>, which reads a few formats bitmaps do not.
    }
  }
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    await new Promise<void>((resolve, reject) => {
      img.onload = () => resolve();
      img.onerror = () => reject(new Error('not an image'));
      img.src = url;
    });
    return { image: img, width: img.naturalWidth, height: img.naturalHeight, close: () => undefined };
  } finally {
    URL.revokeObjectURL(url);
  }
}
