/**
 * The HTTP client for the OpenWord account server: one typed function per
 * endpoint of `docs/api.md`, and nothing else.
 *
 * Requests go to the same origin under `/api` with the session cookie, and
 * with `Authorization: Bearer` as well when a token is in hand — the server
 * takes either, and the bearer survives the cookie being dropped, which an
 * installed web app on iOS is prone to. The caller keeps the token (the
 * account controller puts it in Prefs); this file only sends it.
 *
 * Every failure is an `ApiError` with the server's `status`, `code` and
 * `message`, or a `NetworkError` when the request never got an answer.
 */

export type ActivityKind = 'learn' | 'read' | 'plan' | 'quiz' | 'listen';
export type AchievementKind = 'badge' | 'level' | 'streak' | 'plan' | 'quiz' | 'memory' | 'friend';
export type Relation = 'none' | 'friend' | 'requested' | 'incoming' | 'self';

export const activityKinds: readonly ActivityKind[] = ['learn', 'read', 'plan', 'quiz', 'listen'];
export const achievementKinds: readonly AchievementKind[] = ['badge', 'level', 'streak', 'plan', 'quiz', 'memory', 'friend'];

/** Someone else, as the server shows them to you. */
export interface PublicUser {
  id: string;
  username: string;
  displayName: string;
  bio: string;
  avatarVersion: number;
  /** `/api/users/{id}/avatar?v=N`, or null when there is no photo. */
  avatarUrl: string | null;
  createdAt: string;
}

/** Your own account. */
export interface User extends PublicUser {
  email: string | null;
}

/** The client's own streak, mirrored so friends can see it. */
export interface StreakSnapshot {
  current: number;
  best: number;
  freezes: number;
  lastDay: string;
  updatedAt: string;
}

export interface StreakInput {
  current: number;
  best: number;
  freezes: number;
  lastDay: string;
}

/** Reminder preferences. */
export interface Settings {
  /** `HH:MM` local time, or null for off. */
  reminderTime: string | null;
  /** An IANA zone, or null. */
  reminderTz: string | null;
  /** A bitmask: Mon=1, Tue=2, Wed=4, Thu=8, Fri=16, Sat=32, Sun=64. */
  reminderDays: number;
  reminderOnlyIfUndone: boolean;
  friendReminders: boolean;
}

export interface SettingsPatch {
  displayName?: string;
  bio?: string;
  email?: string | null;
  reminderTime?: string | null;
  reminderTz?: string | null;
  reminderDays?: number;
  reminderOnlyIfUndone?: boolean;
  friendReminders?: boolean;
}

/** Days in a row on which both of you learnt. */
export interface FriendStreak {
  current: number;
  best: number;
  lastDay: string;
  atRisk: boolean;
}

export interface FriendStreakEntry extends FriendStreak {
  user: PublicUser;
}

export interface Achievement {
  id: string;
  kind: AchievementKind;
  key: string;
  title: string;
  detail: string;
  earnedAt: string;
}

export interface AchievementInput {
  key: string;
  kind: AchievementKind;
  title: string;
  detail?: string;
  earnedAt?: string;
}

export interface FeedItem extends Achievement {
  user: PublicUser;
  cheers: number;
  cheered: boolean;
  mine: boolean;
}

export interface FeedPage {
  items: FeedItem[];
  nextBefore: string | null;
}

export interface FriendEntry {
  user: PublicUser;
  since: string;
  streak: StreakSnapshot | null;
  /** Null when the two of you have never shared a learn day. */
  friendStreak: { current: number; best: number; lastDay: string } | null;
  lastActiveDay: string | null;
}

export interface IncomingRequest {
  id: string;
  from: PublicUser;
  message: string;
  createdAt: string;
}

export interface OutgoingRequest {
  id: string;
  to: PublicUser;
  message: string;
  createdAt: string;
}

export interface Requests {
  incoming: IncomingRequest[];
  outgoing: OutgoingRequest[];
}

export interface SearchResult extends PublicUser {
  relation: Relation;
}

export interface Me {
  user: User;
  settings: Settings;
  streak: StreakSnapshot | null;
  counts: { friends: number; pendingRequests: number };
}

export interface Profile {
  user: PublicUser;
  streak: StreakSnapshot | null;
  friendStreak: FriendStreak | null;
  achievements: Achievement[];
  relation: Relation;
}

export interface Streaks {
  streak: StreakSnapshot | null;
  friendStreaks: FriendStreakEntry[];
}

export interface AuthResponse {
  user: User;
  token: string;
}

export interface ActivityDay {
  day: string;
  kinds: Partial<Record<ActivityKind, number>>;
}

export interface BackupInfo {
  updatedAt: string;
  sizeBytes: number;
}

export interface Cheers {
  cheers: number;
  cheered: boolean;
}

/** What `POST /api/friends/requests` answers: a request sent, or a friend made at once. */
export type RequestOutcome = { request: OutgoingRequest; friend?: undefined } | { friend: FriendEntry; request?: undefined };

export type ErrorCode =
  | 'validation'
  | 'unauthorized'
  | 'bad_credentials'
  | 'invite_required'
  | 'not_found'
  | 'username_taken'
  | 'email_taken'
  | 'already_friends'
  | 'already_requested'
  | 'too_large'
  | 'rate_limited'
  | 'internal'
  | string;

/** The server said no. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

/** The request never got an answer: offline, DNS, a dropped connection. */
export class NetworkError extends Error {
  constructor(message = 'Could not reach the server') {
    super(message);
    this.name = 'NetworkError';
  }
}

export function isApiError(error: unknown, code?: ErrorCode): error is ApiError {
  return error instanceof ApiError && (code === undefined || error.code === code);
}

export function isNetworkError(error: unknown): error is NetworkError {
  return error instanceof NetworkError;
}

/**
 * The URL of a user's photo, ready for an `<img>`: the server's path with
 * its `?v=` version, so a new photo is never served from the old cache.
 * Null when they have none.
 */
export function avatarUrl(user: Pick<PublicUser, 'id' | 'avatarVersion' | 'avatarUrl'> | null | undefined, base = ''): string | null {
  if (!user || user.avatarVersion <= 0) return null;
  const path = user.avatarUrl ?? `/api/users/${user.id}/avatar?v=${user.avatarVersion}`;
  return base + path;
}

export interface ApiOptions {
  /** The base path; `/api` by default. */
  base?: string;
  /** The `fetch` to use; the global one by default. A test hands in a fake. */
  fetch?: typeof fetch;
  /** Where the bearer token is, if any. */
  token?: () => string | null;
}

type Json = Record<string, unknown> | unknown[] | string | number | boolean | null;

export class Api {
  readonly base: string;
  private readonly fetchImpl: typeof fetch;
  private readonly readToken: () => string | null;

  constructor(options: ApiOptions = {}) {
    this.base = options.base ?? '/api';
    this.fetchImpl = options.fetch ?? ((input, init) => fetch(input, init));
    this.readToken = options.token ?? (() => null);
  }

  // ------------------------------------------------------------- transport

  private headers(extra: Record<string, string> = {}): Record<string, string> {
    const headers: Record<string, string> = { Accept: 'application/json', ...extra };
    const token = this.readToken();
    if (token) headers['Authorization'] = `Bearer ${token}`;
    return headers;
  }

  /** One request; answers the parsed body (undefined for 204) or throws. */
  private async request<T>(method: string, path: string, options: { json?: unknown; body?: BodyInit; contentType?: string; raw?: boolean } = {}): Promise<T> {
    const headers = this.headers();
    let body: BodyInit | undefined = options.body;
    if (options.json !== undefined) {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify(options.json);
    } else if (options.contentType) {
      headers['Content-Type'] = options.contentType;
    }
    let response: Response;
    try {
      response = await this.fetchImpl(this.base + path, { method, headers, body, credentials: 'include' });
    } catch (error) {
      throw new NetworkError(error instanceof Error ? error.message : String(error));
    }
    if (response.status === 204) return undefined as T;
    const text = await response.text();
    let parsed: unknown = undefined;
    if (text.length > 0) {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = undefined;
      }
    }
    if (!response.ok) {
      const record = isRecord(parsed) ? parsed : {};
      const code = typeof record['error'] === 'string' ? (record['error'] as string) : response.status === 401 ? 'unauthorized' : 'internal';
      const message = typeof record['message'] === 'string' ? (record['message'] as string) : defaultMessage(response.status, code);
      throw new ApiError(response.status, code, message);
    }
    if (options.raw) return { body: parsed, headers: response.headers } as unknown as T;
    return parsed as T;
  }

  private get<T>(path: string): Promise<T> {
    return this.request<T>('GET', path);
  }
  private post<T>(path: string, json?: Json): Promise<T> {
    return this.request<T>('POST', path, json === undefined ? {} : { json });
  }
  private put<T>(path: string, json: Json): Promise<T> {
    return this.request<T>('PUT', path, { json });
  }
  private patch<T>(path: string, json: Json): Promise<T> {
    return this.request<T>('PATCH', path, { json });
  }
  private delete<T>(path: string, json?: Json): Promise<T> {
    return this.request<T>('DELETE', path, json === undefined ? {} : { json });
  }

  // ------------------------------------------------------------------ auth

  register(input: { username: string; password: string; displayName?: string; email?: string; inviteCode?: string }): Promise<AuthResponse> {
    return this.post<AuthResponse>('/auth/register', clean(input));
  }

  login(username: string, password: string): Promise<AuthResponse> {
    return this.post<AuthResponse>('/auth/login', { username, password });
  }

  logout(): Promise<void> {
    return this.post<void>('/auth/logout');
  }

  // -------------------------------------------------------------------- me

  me(): Promise<Me> {
    return this.get<Me>('/me');
  }

  updateMe(patch: SettingsPatch): Promise<{ user: User; settings: Settings }> {
    return this.patch('/me', patch as Record<string, unknown>);
  }

  changePassword(current: string, next: string): Promise<void> {
    return this.post<void>('/me/password', { current, next });
  }

  /** The raw image bytes; the server crops, resizes and stores a JPEG. */
  uploadAvatar(image: Blob): Promise<{ avatarVersion: number; avatarUrl: string }> {
    return this.request('PUT', '/me/avatar', { body: image, contentType: image.type || 'image/jpeg' });
  }

  removeAvatar(): Promise<void> {
    return this.delete<void>('/me/avatar');
  }

  deleteAccount(password: string): Promise<void> {
    return this.delete<void>('/me', { password });
  }

  putBackup(document: unknown): Promise<BackupInfo> {
    return this.request('PUT', '/me/backup', { json: document });
  }

  /** The stored document and when it was stored, or null when there is none. */
  async getBackup(): Promise<{ document: unknown; updatedAt: string | null } | null> {
    try {
      const { body, headers } = await this.request<{ body: unknown; headers: Headers }>('GET', '/me/backup', { raw: true });
      return { document: body, updatedAt: headers.get('X-Backup-Updated-At') };
    } catch (error) {
      if (isApiError(error, 'not_found')) return null;
      throw error;
    }
  }

  deleteBackup(): Promise<void> {
    return this.delete<void>('/me/backup');
  }

  // ----------------------------------------------------------------- users

  async searchUsers(q: string): Promise<SearchResult[]> {
    const { users } = await this.get<{ users: SearchResult[] }>(`/users/search?q=${encodeURIComponent(q)}`);
    return users;
  }

  profile(username: string): Promise<Profile> {
    return this.get<Profile>(`/users/${encodeURIComponent(username)}`);
  }

  // --------------------------------------------------------------- friends

  async friends(): Promise<FriendEntry[]> {
    const { friends } = await this.get<{ friends: FriendEntry[] }>('/friends');
    return friends;
  }

  requests(): Promise<Requests> {
    return this.get<Requests>('/friends/requests');
  }

  sendRequest(username: string, message?: string): Promise<RequestOutcome> {
    return this.post<RequestOutcome>('/friends/requests', clean({ username, message }));
  }

  async acceptRequest(id: string): Promise<FriendEntry> {
    const { friend } = await this.post<{ friend: FriendEntry }>(`/friends/requests/${encodeURIComponent(id)}/accept`);
    return friend;
  }

  declineRequest(id: string): Promise<void> {
    return this.post<void>(`/friends/requests/${encodeURIComponent(id)}/decline`);
  }

  cancelRequest(id: string): Promise<void> {
    return this.delete<void>(`/friends/requests/${encodeURIComponent(id)}`);
  }

  unfriend(userId: string): Promise<void> {
    return this.delete<void>(`/friends/${encodeURIComponent(userId)}`);
  }

  // ------------------------------------------------------------- activity

  recordActivity(day: string, kind: ActivityKind, count = 1): Promise<{ day: string; kind: ActivityKind; count: number }> {
    return this.post('/activity', { day, kind, count });
  }

  activity(from?: string, to?: string): Promise<{ from: string; to: string; days: ActivityDay[] }> {
    const q = new URLSearchParams();
    if (from) q.set('from', from);
    if (to) q.set('to', to);
    const query = q.toString();
    return this.get(`/activity${query ? `?${query}` : ''}`);
  }

  async putStreak(streak: StreakInput): Promise<StreakSnapshot> {
    const { streak: snapshot } = await this.put<{ streak: StreakSnapshot }>('/streak', streak as unknown as Record<string, unknown>);
    return snapshot;
  }

  streaks(): Promise<Streaks> {
    return this.get<Streaks>('/streaks');
  }

  // --------------------------------------------------------- achievements

  async postAchievement(input: AchievementInput): Promise<Achievement> {
    const { achievement } = await this.post<{ achievement: Achievement }>('/achievements', clean(input));
    return achievement;
  }

  async postAchievements(inputs: AchievementInput[]): Promise<number> {
    const { created } = await this.post<{ created: number }>('/achievements/batch', { achievements: inputs.map(clean) });
    return created;
  }

  feed(before?: string | null, limit = 30): Promise<FeedPage> {
    const q = new URLSearchParams();
    if (before) q.set('before', before);
    q.set('limit', String(limit));
    return this.get<FeedPage>(`/feed?${q.toString()}`);
  }

  cheer(id: string): Promise<Cheers> {
    return this.post<Cheers>(`/feed/${encodeURIComponent(id)}/cheer`);
  }

  uncheer(id: string): Promise<Cheers> {
    return this.delete<Cheers>(`/feed/${encodeURIComponent(id)}/cheer`);
  }

  // ------------------------------------------------------------------ push

  async vapidKey(): Promise<string> {
    const { publicKey } = await this.get<{ publicKey: string }>('/push/vapid');
    return publicKey;
  }

  subscribePush(subscription: PushSubscriptionJSON): Promise<{ id: string; createdAt: string }> {
    return this.post('/push/subscriptions', { endpoint: subscription.endpoint, keys: subscription.keys ?? {} });
  }

  unsubscribePush(endpoint: string): Promise<void> {
    return this.delete<void>('/push/subscriptions', { endpoint });
  }

  async testPush(): Promise<number> {
    const { sent } = await this.post<{ sent: number }>('/push/test');
    return sent;
  }

  /**
   * An arbitrary queued call, for the offline queue: `method` and `path`
   * as the contract names them, with a JSON body.
   */
  send(method: string, path: string, json?: unknown): Promise<unknown> {
    return this.request<unknown>(method, path, json === undefined ? {} : { json });
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** Drops undefined fields, so an optional left out is left out of the JSON. */
function clean<T extends object>(input: T): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) if (value !== undefined) out[key] = value;
  return out;
}

function defaultMessage(status: number, code: string): string {
  switch (code) {
    case 'unauthorized':
      return 'Please sign in again.';
    case 'bad_credentials':
      return 'That username or password is not right.';
    case 'rate_limited':
      return 'Too many tries. Wait a minute and try again.';
    case 'not_found':
      return 'Not found.';
    case 'too_large':
      return 'That is too big to send.';
    default:
      return status >= 500 ? 'The server had a problem. Try again later.' : 'The server said no.';
  }
}
