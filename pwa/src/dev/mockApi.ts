/**
 * The account server of `docs/api.md`, in memory, behind a `fetch`.
 *
 * For the social demo page (`social-demo.html`), which swaps it in for
 * `window.fetch`, and for the tests of the client and the account
 * controller, which hand `server.fetch` to them. It keeps to the contract
 * closely enough that a screen written against it works against the real
 * server: the same paths, statuses, error codes and shapes, friend
 * streaks worked out from shared learn days, and a feed that pages.
 */
import type {
  Achievement,
  AchievementKind,
  ActivityKind,
  FeedItem,
  FriendEntry,
  FriendStreak,
  PublicUser,
  Relation,
  Settings,
  StreakSnapshot,
  User,
} from '../data/api';

interface MockUser {
  id: string;
  username: string;
  displayName: string;
  bio: string;
  email: string | null;
  password: string;
  avatarVersion: number;
  /** A data: URL in the mock, since an `<img>` cannot be intercepted. */
  avatarData: string | null;
  createdAt: string;
  settings: Settings;
  streak: StreakSnapshot | null;
  /** day → kind → count */
  activity: Map<string, Partial<Record<ActivityKind, number>>>;
  achievements: Achievement[];
  backup: { document: unknown; updatedAt: string; sizeBytes: number } | null;
  subscriptions: string[];
}

interface MockRequest {
  id: string;
  from: string;
  to: string;
  message: string;
  createdAt: string;
}

export interface LoggedCall {
  method: string;
  path: string;
  body: unknown;
  status: number;
}

const kinds: readonly ActivityKind[] = ['learn', 'read', 'plan', 'quiz', 'listen'];
const achievementKinds: readonly AchievementKind[] = ['badge', 'level', 'streak', 'plan', 'quiz', 'memory', 'friend'];

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

const pad = (n: number, width = 2) => String(n).padStart(width, '0');
const dayString = (d: Date) => `${pad(d.getFullYear(), 4)}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

export class MockServer {
  readonly users = new Map<string, MockUser>();
  readonly sessions = new Map<string, string>();
  /** `a|b` (ids sorted) → since */
  readonly friendships = new Map<string, string>();
  requests: MockRequest[] = [];
  /** achievement id → user ids who cheered */
  readonly cheers = new Map<string, Set<string>>();
  /** Set to make registration need it. */
  inviteCode: string | null = null;
  /** While true every request fails as a dropped connection does. */
  offline = false;
  /** While set, every request is answered with this status. */
  failWith: number | null = null;
  /** Milliseconds each answer takes; the demo sets a little so spinners show. */
  latency = 0;
  /** Every request answered, in order. */
  readonly log: LoggedCall[] = [];
  now: () => Date = () => new Date();
  private counter = 0;

  /** A `fetch` that answers from this server. Anything outside `/api` goes to `passthrough`. */
  fetch: typeof fetch = async (input, init) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url, 'http://openword.test');
    if (!url.pathname.startsWith('/api/')) {
      if (this.passthrough) return this.passthrough(input, init);
      return new Response('not found', { status: 404 });
    }
    if (this.latency > 0) await new Promise((resolve) => setTimeout(resolve, this.latency));
    if (this.offline) throw new TypeError('Failed to fetch');
    const method = (init?.method ?? 'GET').toUpperCase();
    const path = url.pathname.substring(4);
    let body: unknown = undefined;
    const rawBody = init?.body;
    if (typeof rawBody === 'string') {
      try {
        body = JSON.parse(rawBody);
      } catch {
        body = Symbol.for('bad json');
      }
    } else if (rawBody != null) {
      body = rawBody;
    }
    const headers = new Headers(init?.headers);
    let response: Response;
    try {
      if (this.failWith !== null) throw new HttpError(this.failWith, this.failWith === 429 ? 'rate_limited' : 'internal', 'The mock was told to fail.');
      if (body === Symbol.for('bad json')) throw new HttpError(400, 'validation', 'Malformed JSON.');
      response = await this.route(method, path, url.searchParams, body, headers);
    } catch (error) {
      if (!(error instanceof HttpError)) throw error;
      response = json(error.status, { error: error.code, message: error.message });
    }
    this.log.push({ method, path, body: typeof rawBody === 'string' ? body : rawBody == null ? undefined : '[binary]', status: response.status });
    return response;
  };

  /** Where requests outside `/api` go: the real `fetch`, in the demo. */
  passthrough: typeof fetch | null = null;

  // --------------------------------------------------------------- seeding

  private id(prefix: string): string {
    this.counter++;
    return `${prefix}-${pad(this.counter, 4)}-${Math.floor(this.counter * 2654435761 % 0xffffff).toString(16)}`;
  }

  addUser(init: { username: string; displayName?: string; password?: string; bio?: string; email?: string | null; avatar?: string | null; createdAt?: Date }): MockUser {
    const user: MockUser = {
      id: this.id('u'),
      username: init.username,
      displayName: init.displayName ?? init.username,
      bio: init.bio ?? '',
      email: init.email ?? null,
      password: init.password ?? 'password1',
      avatarVersion: init.avatar ? 1 : 0,
      avatarData: init.avatar ?? null,
      createdAt: (init.createdAt ?? this.now()).toISOString(),
      settings: { reminderTime: null, reminderTz: null, reminderDays: 127, reminderOnlyIfUndone: true, friendReminders: true },
      streak: null,
      activity: new Map(),
      achievements: [],
      backup: null,
      subscriptions: [],
    };
    this.users.set(user.id, user);
    return user;
  }

  byUsername(username: string): MockUser | undefined {
    const wanted = username.toLowerCase();
    for (const user of this.users.values()) if (user.username === wanted) return user;
    return undefined;
  }

  /** A session for `user`, as logging in gives. */
  tokenFor(user: MockUser): string {
    const token = `tok_${user.username}_${this.sessions.size + 1}`;
    this.sessions.set(token, user.id);
    return token;
  }

  befriend(a: MockUser, b: MockUser, since: Date = this.now()): void {
    this.friendships.set(pairKey(a.id, b.id), since.toISOString());
  }

  request(from: MockUser, to: MockUser, message = '', at: Date = this.now()): MockRequest {
    const request = { id: this.id('r'), from: from.id, to: to.id, message, createdAt: at.toISOString() };
    this.requests.unshift(request);
    return request;
  }

  /** Marks `user` as having learnt on each of the `daysAgo` (0 is today). */
  learn(user: MockUser, ...daysAgo: number[]): void {
    for (const ago of daysAgo) {
      const day = dayString(new Date(this.now().getTime() - ago * 86_400_000));
      user.activity.set(day, { ...user.activity.get(day), learn: 1 });
    }
  }

  setStreak(user: MockUser, current: number, best = current, freezes = 0, lastDayAgo = 0): void {
    const at = new Date(this.now().getTime() - lastDayAgo * 86_400_000);
    user.streak = { current, best, freezes, lastDay: dayString(at), updatedAt: at.toISOString() };
  }

  achieve(user: MockUser, kind: AchievementKind, key: string, title: string, detail = '', at: Date = this.now(), cheeredBy: MockUser[] = []): Achievement {
    const achievement: Achievement = { id: this.id('a'), kind, key, title, detail, earnedAt: at.toISOString() };
    user.achievements.push(achievement);
    if (cheeredBy.length > 0) this.cheers.set(achievement.id, new Set(cheeredBy.map((u) => u.id)));
    return achievement;
  }

  // ---------------------------------------------------------------- shapes

  private publicUser(user: MockUser): PublicUser {
    return {
      id: user.id,
      username: user.username,
      displayName: user.displayName,
      bio: user.bio,
      avatarVersion: user.avatarVersion,
      avatarUrl: user.avatarVersion > 0 ? (user.avatarData ?? `/api/users/${user.id}/avatar?v=${user.avatarVersion}`) : null,
      createdAt: user.createdAt,
    };
  }

  private ownUser(user: MockUser): User {
    return { ...this.publicUser(user), email: user.email };
  }

  private areFriends(a: string, b: string): boolean {
    return this.friendships.has(pairKey(a, b));
  }

  private friendsOf(user: MockUser): MockUser[] {
    const out: MockUser[] = [];
    for (const key of this.friendships.keys()) {
      const [a, b] = key.split('|');
      if (a === user.id) out.push(this.users.get(b)!);
      else if (b === user.id) out.push(this.users.get(a)!);
    }
    return out.filter(Boolean).sort((x, y) => x.displayName.localeCompare(y.displayName) || x.username.localeCompare(y.username));
  }

  private relation(me: MockUser, other: MockUser): Relation {
    if (me.id === other.id) return 'self';
    if (this.areFriends(me.id, other.id)) return 'friend';
    if (this.requests.some((r) => r.from === me.id && r.to === other.id)) return 'requested';
    if (this.requests.some((r) => r.from === other.id && r.to === me.id)) return 'incoming';
    return 'none';
  }

  /** The friend streak definition of the contract, word for word. */
  friendStreak(me: MockUser, friend: MockUser): FriendStreak {
    const shared = (ago: number): boolean => {
      const day = dayString(new Date(this.now().getTime() - ago * 86_400_000));
      return (me.activity.get(day)?.learn ?? 0) > 0 && (friend.activity.get(day)?.learn ?? 0) > 0;
    };
    const start = shared(0) ? 0 : shared(1) ? 1 : -1;
    let current = 0;
    if (start >= 0) for (let ago = start; ago < 400 && shared(ago); ago++) current++;
    let best = 0;
    let run = 0;
    for (let ago = 399; ago >= 0; ago--) {
      run = shared(ago) ? run + 1 : 0;
      if (run > best) best = run;
    }
    return {
      current,
      best,
      lastDay: start >= 0 ? dayString(new Date(this.now().getTime() - start * 86_400_000)) : '',
      atRisk: current > 0 && start === 1,
    };
  }

  private everShared(me: MockUser, friend: MockUser): boolean {
    for (const [day, kindsDone] of me.activity) {
      if ((kindsDone.learn ?? 0) > 0 && (friend.activity.get(day)?.learn ?? 0) > 0) return true;
    }
    return false;
  }

  private friendEntry(me: MockUser, friend: MockUser): FriendEntry {
    const streak = this.friendStreak(me, friend);
    let lastActiveDay: string | null = null;
    for (const day of friend.activity.keys()) if (lastActiveDay === null || day > lastActiveDay) lastActiveDay = day;
    return {
      user: this.publicUser(friend),
      since: this.friendships.get(pairKey(me.id, friend.id)) ?? this.now().toISOString(),
      streak: friend.streak,
      friendStreak: this.everShared(me, friend) ? { current: streak.current, best: streak.best, lastDay: streak.lastDay } : null,
      lastActiveDay,
    };
  }

  private feedItem(me: MockUser, owner: MockUser, achievement: Achievement): FeedItem {
    const cheers = this.cheers.get(achievement.id);
    return { ...achievement, user: this.publicUser(owner), cheers: cheers?.size ?? 0, cheered: cheers?.has(me.id) ?? false, mine: owner.id === me.id };
  }

  private findAchievement(me: MockUser, id: string): { owner: MockUser; achievement: Achievement } {
    for (const owner of [me, ...this.friendsOf(me)]) {
      const achievement = owner.achievements.find((a) => a.id === id);
      if (achievement) return { owner, achievement };
    }
    throw new HttpError(404, 'not_found', 'No such achievement.');
  }

  // --------------------------------------------------------------- routing

  private auth(headers: Headers): MockUser {
    const header = headers.get('Authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.substring(7) : '';
    const id = this.sessions.get(token);
    const user = id ? this.users.get(id) : undefined;
    if (!user) throw new HttpError(401, 'unauthorized', 'Please sign in.');
    return user;
  }

  private async route(method: string, path: string, query: URLSearchParams, body: unknown, headers: Headers): Promise<Response> {
    const b = isRecord(body) ? body : {};
    const seg = path.split('/').filter((s) => s.length > 0).map(decodeURIComponent);
    const at = `${method} /${seg.join('/')}`;

    // ---- public
    if (at === 'POST /auth/register') return this.register(b);
    if (at === 'POST /auth/login') {
      const name = String(b['username'] ?? '').toLowerCase();
      const user = [...this.users.values()].find((u) => u.username === name || (u.email !== null && u.email === name));
      if (!user || user.password !== b['password']) throw new HttpError(401, 'bad_credentials', 'Wrong username or password.');
      return json(200, { user: this.ownUser(user), token: this.tokenFor(user) });
    }
    if (at === 'POST /auth/logout') {
      const header = headers.get('Authorization') ?? '';
      if (header.startsWith('Bearer ')) this.sessions.delete(header.substring(7));
      return empty();
    }
    if (at === 'GET /push/vapid') return json(200, { publicKey: 'BNQWuzcweRYwVRYm1udMRg3Z3_0BN8YwxgJsrEQJaOY3uSZ9mock' });
    if (method === 'GET' && seg[0] === 'users' && seg[2] === 'avatar') {
      const user = this.users.get(seg[1]);
      if (!user || user.avatarVersion === 0) throw new HttpError(404, 'not_found', 'No photo.');
      return new Response('jpeg', { status: 200, headers: { 'Content-Type': 'image/jpeg', ETag: `"${user.avatarVersion}"` } });
    }

    const me = this.auth(headers);

    // ---- me
    if (at === 'GET /me') {
      return json(200, {
        user: this.ownUser(me),
        settings: me.settings,
        streak: me.streak,
        counts: { friends: this.friendsOf(me).length, pendingRequests: this.requests.filter((r) => r.to === me.id).length },
      });
    }
    if (at === 'PATCH /me') return this.patchMe(me, b);
    if (at === 'POST /me/password') {
      if (b['current'] !== me.password) throw new HttpError(401, 'bad_credentials', 'That is not your current password.');
      if (typeof b['next'] !== 'string' || b['next'].length < 8) throw new HttpError(400, 'validation', 'next: must be at least 8 characters.');
      me.password = b['next'];
      return empty();
    }
    if (at === 'PUT /me/avatar') {
      const type = headers.get('Content-Type') ?? '';
      if (!type.startsWith('image/')) throw new HttpError(400, 'validation', 'body: not an image.');
      const blob = body instanceof Blob ? body : null;
      if (blob && blob.size > 4 * 1024 * 1024) throw new HttpError(413, 'too_large', 'The photo is over 4 MB.');
      me.avatarVersion++;
      me.avatarData = blob ? await blobToDataUrl(blob, type) : null;
      const pub = this.publicUser(me);
      return json(200, { avatarVersion: pub.avatarVersion, avatarUrl: pub.avatarUrl });
    }
    if (at === 'DELETE /me/avatar') {
      me.avatarVersion = 0;
      me.avatarData = null;
      return empty();
    }
    if (at === 'DELETE /me') {
      if (b['password'] !== me.password) throw new HttpError(401, 'bad_credentials', 'That is not your password.');
      this.users.delete(me.id);
      for (const key of [...this.friendships.keys()]) if (key.split('|').includes(me.id)) this.friendships.delete(key);
      this.requests = this.requests.filter((r) => r.from !== me.id && r.to !== me.id);
      for (const [token, id] of [...this.sessions]) if (id === me.id) this.sessions.delete(token);
      return empty();
    }
    if (at === 'PUT /me/backup') {
      const sizeBytes = JSON.stringify(body).length;
      if (sizeBytes > 4 * 1024 * 1024) throw new HttpError(413, 'too_large', 'The backup is over 4 MB.');
      me.backup = { document: body, updatedAt: this.now().toISOString(), sizeBytes };
      return json(200, { updatedAt: me.backup.updatedAt, sizeBytes });
    }
    if (at === 'GET /me/backup') {
      if (!me.backup) throw new HttpError(404, 'not_found', 'No backup is stored.');
      return json(200, me.backup.document, { 'X-Backup-Updated-At': me.backup.updatedAt });
    }
    if (at === 'DELETE /me/backup') {
      me.backup = null;
      return empty();
    }

    // ---- users
    if (at === 'GET /users/search') {
      const q = (query.get('q') ?? '').trim().toLowerCase();
      if (q.length === 0 || q.length > 64) throw new HttpError(400, 'validation', 'q: must be 1–64 characters.');
      const prefix: MockUser[] = [];
      const rest: MockUser[] = [];
      for (const user of this.users.values()) {
        if (user.id === me.id) continue;
        if (user.username.startsWith(q)) prefix.push(user);
        else if (user.displayName.toLowerCase().includes(q)) rest.push(user);
      }
      return json(200, { users: [...prefix, ...rest].slice(0, 20).map((u) => ({ ...this.publicUser(u), relation: this.relation(me, u) })) });
    }
    if (method === 'GET' && seg[0] === 'users' && seg.length === 2) {
      const user = this.byUsername(seg[1]);
      if (!user) throw new HttpError(404, 'not_found', 'No such user.');
      const relation = this.relation(me, user);
      return json(200, {
        user: this.publicUser(user),
        streak: user.streak,
        friendStreak: relation === 'friend' ? this.friendStreak(me, user) : null,
        achievements: [...user.achievements].sort(newestFirst).slice(0, 20),
        relation,
      });
    }

    // ---- friends
    if (at === 'GET /friends') return json(200, { friends: this.friendsOf(me).map((f) => this.friendEntry(me, f)) });
    if (at === 'GET /friends/requests') {
      return json(200, {
        incoming: this.requests.filter((r) => r.to === me.id).map((r) => ({ id: r.id, from: this.publicUser(this.users.get(r.from)!), message: r.message, createdAt: r.createdAt })),
        outgoing: this.requests.filter((r) => r.from === me.id).map((r) => ({ id: r.id, to: this.publicUser(this.users.get(r.to)!), message: r.message, createdAt: r.createdAt })),
      });
    }
    if (at === 'POST /friends/requests') {
      const other = this.byUsername(String(b['username'] ?? ''));
      if (!other) throw new HttpError(404, 'not_found', 'No such user.');
      if (other.id === me.id) throw new HttpError(400, 'validation', 'username: that is you.');
      const message = typeof b['message'] === 'string' ? b['message'] : '';
      if (message.length > 200) throw new HttpError(400, 'validation', 'message: at most 200 characters.');
      if (this.areFriends(me.id, other.id)) throw new HttpError(409, 'already_friends', 'You are already friends.');
      if (this.requests.some((r) => r.from === me.id && r.to === other.id)) throw new HttpError(409, 'already_requested', 'You have already asked.');
      const theirs = this.requests.find((r) => r.from === other.id && r.to === me.id);
      if (theirs) {
        this.requests = this.requests.filter((r) => r !== theirs);
        this.befriend(me, other);
        return json(200, { friend: this.friendEntry(me, other) });
      }
      const request = this.request(me, other, message);
      return json(201, { request: { id: request.id, to: this.publicUser(other), message, createdAt: request.createdAt } });
    }
    if (method === 'POST' && seg[0] === 'friends' && seg[1] === 'requests' && (seg[3] === 'accept' || seg[3] === 'decline')) {
      const request = this.requests.find((r) => r.id === seg[2] && r.to === me.id);
      if (!request) throw new HttpError(404, 'not_found', 'No such request.');
      this.requests = this.requests.filter((r) => r !== request);
      if (seg[3] === 'decline') return empty();
      const other = this.users.get(request.from)!;
      this.befriend(me, other);
      return json(200, { friend: this.friendEntry(me, other) });
    }
    if (method === 'DELETE' && seg[0] === 'friends' && seg[1] === 'requests' && seg.length === 3) {
      const request = this.requests.find((r) => r.id === seg[2] && r.from === me.id);
      if (!request) throw new HttpError(404, 'not_found', 'No such request.');
      this.requests = this.requests.filter((r) => r !== request);
      return empty();
    }
    if (method === 'DELETE' && seg[0] === 'friends' && seg.length === 2) {
      if (!this.friendships.delete(pairKey(me.id, seg[1]))) throw new HttpError(404, 'not_found', 'You were not friends.');
      return empty();
    }

    // ---- activity and streaks
    if (at === 'POST /activity') {
      const day = b['day'];
      const kind = b['kind'] as ActivityKind;
      const count = b['count'] === undefined ? 1 : b['count'];
      if (!isDay(day)) throw new HttpError(400, 'validation', 'day: must be YYYY-MM-DD.');
      if (!kinds.includes(kind)) throw new HttpError(400, 'validation', 'kind: unknown.');
      if (typeof count !== 'number' || !Number.isInteger(count) || count < 0 || count > 10000) throw new HttpError(400, 'validation', 'count: must be 0–10000.');
      const behind = Math.round((Date.parse(`${dayString(this.now())}T00:00:00Z`) - Date.parse(`${day}T00:00:00Z`)) / 86_400_000);
      if (behind > 400 || behind < -3) throw new HttpError(400, 'validation', 'day: too far from today.');
      const have = me.activity.get(day) ?? {};
      have[kind] = Math.max(have[kind] ?? 0, count);
      me.activity.set(day, have);
      return json(200, { day, kind, count: have[kind] });
    }
    if (at === 'GET /activity') {
      const to = query.get('to') ?? dayString(this.now());
      const from = query.get('from') ?? dayString(new Date(Date.parse(`${to}T12:00:00`) - 90 * 86_400_000));
      const days = [...me.activity.entries()]
        .filter(([day]) => day >= from && day <= to)
        .sort(([a], [c]) => (a < c ? -1 : 1))
        .map(([day, kindsDone]) => ({ day, kinds: kindsDone }));
      return json(200, { from, to, days });
    }
    if (at === 'PUT /streak') {
      const current = b['current'];
      const best = b['best'];
      const freezes = b['freezes'];
      if (![current, best, freezes].every((n) => typeof n === 'number' && Number.isInteger(n) && n >= 0)) throw new HttpError(400, 'validation', 'current, best, freezes: must be whole numbers.');
      if (!isDay(b['lastDay'])) throw new HttpError(400, 'validation', 'lastDay: must be YYYY-MM-DD.');
      me.streak = {
        current: current as number,
        best: Math.max(best as number, current as number),
        freezes: freezes as number,
        lastDay: b['lastDay'],
        updatedAt: this.now().toISOString(),
      };
      return json(200, { streak: me.streak });
    }
    if (at === 'GET /streaks') {
      return json(200, {
        streak: me.streak,
        friendStreaks: this.friendsOf(me).map((f) => ({ user: this.publicUser(f), ...this.friendStreak(me, f) })),
      });
    }

    // ---- achievements and the feed
    if (at === 'POST /achievements') {
      const { created, achievement } = this.addAchievement(me, b);
      return json(created ? 201 : 200, { achievement });
    }
    if (at === 'POST /achievements/batch') {
      const list = b['achievements'];
      if (!Array.isArray(list) || list.length > 500) throw new HttpError(400, 'validation', 'achievements: a list of at most 500.');
      for (const entry of list) this.validateAchievement(isRecord(entry) ? entry : {});
      let created = 0;
      for (const entry of list) if (this.addAchievement(me, entry as Record<string, unknown>).created) created++;
      return json(200, { created });
    }
    if (at === 'GET /feed') {
      const limit = Math.min(Math.max(Number(query.get('limit') ?? 30) || 30, 1), 100);
      const before = query.get('before');
      const beforeTime = before ? Date.parse(before) : Infinity;
      const all: FeedItem[] = [];
      for (const owner of [me, ...this.friendsOf(me)]) {
        for (const achievement of owner.achievements) {
          if (Date.parse(achievement.earnedAt) < beforeTime) all.push(this.feedItem(me, owner, achievement));
        }
      }
      all.sort(newestFirst);
      const items = all.slice(0, limit);
      return json(200, { items, nextBefore: all.length > limit ? items[items.length - 1].earnedAt : null });
    }
    if (seg[0] === 'feed' && seg[2] === 'cheer' && (method === 'POST' || method === 'DELETE')) {
      const { achievement } = this.findAchievement(me, seg[1]);
      const set = this.cheers.get(achievement.id) ?? new Set<string>();
      if (method === 'POST') set.add(me.id);
      else set.delete(me.id);
      this.cheers.set(achievement.id, set);
      return json(200, { cheers: set.size, cheered: set.has(me.id) });
    }

    // ---- push
    if (at === 'POST /push/subscriptions') {
      if (typeof b['endpoint'] !== 'string' || !isRecord(b['keys'])) throw new HttpError(400, 'validation', 'endpoint and keys are required.');
      for (const user of this.users.values()) user.subscriptions = user.subscriptions.filter((e) => e !== b['endpoint']);
      me.subscriptions.push(b['endpoint']);
      return json(201, { id: this.id('p'), createdAt: this.now().toISOString() });
    }
    if (at === 'DELETE /push/subscriptions') {
      me.subscriptions = me.subscriptions.filter((e) => e !== b['endpoint']);
      return empty();
    }
    if (at === 'POST /push/test') return json(200, { sent: me.subscriptions.length });

    throw new HttpError(404, 'not_found', `No route for ${at}.`);
  }

  private register(b: Record<string, unknown>): Response {
    const username = String(b['username'] ?? '').toLowerCase();
    const password = b['password'];
    if (!/^[a-z0-9_]{3,24}$/.test(username)) throw new HttpError(400, 'validation', 'username: 3–24 characters of a–z, 0–9 and _.');
    if (typeof password !== 'string' || password.length < 8) throw new HttpError(400, 'validation', 'password: must be at least 8 characters.');
    const displayName = typeof b['displayName'] === 'string' && b['displayName'].trim().length > 0 ? b['displayName'].trim() : username;
    if (displayName.length > 40) throw new HttpError(400, 'validation', 'displayName: at most 40 characters.');
    const email = typeof b['email'] === 'string' && b['email'].length > 0 ? b['email'].toLowerCase() : null;
    if (email !== null && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new HttpError(400, 'validation', 'email: not a valid address.');
    if (this.inviteCode !== null && b['inviteCode'] !== this.inviteCode) throw new HttpError(403, 'invite_required', 'This server needs an invite code.');
    if (this.byUsername(username)) throw new HttpError(409, 'username_taken', 'That username is taken.');
    if (email !== null && [...this.users.values()].some((u) => u.email === email)) throw new HttpError(409, 'email_taken', 'That email is already in use.');
    const user = this.addUser({ username, displayName, password, email });
    return json(201, { user: this.ownUser(user), token: this.tokenFor(user) });
  }

  private patchMe(me: MockUser, b: Record<string, unknown>): Response {
    if ('displayName' in b) {
      const name = typeof b['displayName'] === 'string' ? b['displayName'].trim() : '';
      if (name.length < 1 || name.length > 40) throw new HttpError(400, 'validation', 'displayName: 1–40 characters.');
      me.displayName = name;
    }
    if ('bio' in b) {
      if (typeof b['bio'] !== 'string' || b['bio'].length > 160) throw new HttpError(400, 'validation', 'bio: at most 160 characters.');
      me.bio = b['bio'];
    }
    if ('email' in b) {
      const email = b['email'] === null || b['email'] === '' ? null : String(b['email']).toLowerCase();
      if (email !== null && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new HttpError(400, 'validation', 'email: not a valid address.');
      if (email !== null && [...this.users.values()].some((u) => u.email === email && u.id !== me.id)) throw new HttpError(409, 'email_taken', 'That email is already in use.');
      me.email = email;
    }
    if ('reminderTime' in b) {
      const time = b['reminderTime'] === null || b['reminderTime'] === '' ? null : String(b['reminderTime']);
      if (time !== null && !/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) throw new HttpError(400, 'validation', 'reminderTime: must be HH:MM.');
      me.settings = { ...me.settings, reminderTime: time };
    }
    if ('reminderTz' in b) me.settings = { ...me.settings, reminderTz: b['reminderTz'] === null || b['reminderTz'] === '' ? null : String(b['reminderTz']) };
    if ('reminderDays' in b) {
      const days = b['reminderDays'];
      if (typeof days !== 'number' || !Number.isInteger(days) || days < 0 || days > 127) throw new HttpError(400, 'validation', 'reminderDays: must be 0–127.');
      me.settings = { ...me.settings, reminderDays: days };
    }
    if (typeof b['reminderOnlyIfUndone'] === 'boolean') me.settings = { ...me.settings, reminderOnlyIfUndone: b['reminderOnlyIfUndone'] };
    if (typeof b['friendReminders'] === 'boolean') me.settings = { ...me.settings, friendReminders: b['friendReminders'] };
    return json(200, { user: this.ownUser(me), settings: me.settings });
  }

  private validateAchievement(b: Record<string, unknown>): void {
    if (typeof b['key'] !== 'string' || b['key'].length === 0 || b['key'].length > 80) throw new HttpError(400, 'validation', 'key: 1–80 characters.');
    if (!achievementKinds.includes(b['kind'] as AchievementKind)) throw new HttpError(400, 'validation', 'kind: unknown.');
    if (typeof b['title'] !== 'string' || b['title'].length === 0) throw new HttpError(400, 'validation', 'title: required.');
    if (b['detail'] !== undefined && (typeof b['detail'] !== 'string' || b['detail'].length > 400)) throw new HttpError(400, 'validation', 'detail: at most 400 characters.');
    if (b['earnedAt'] !== undefined) {
      const at = typeof b['earnedAt'] === 'string' ? Date.parse(b['earnedAt']) : NaN;
      if (Number.isNaN(at) || at > this.now().getTime() + 86_400_000) throw new HttpError(400, 'validation', 'earnedAt: not a time, or too far ahead.');
    }
  }

  private addAchievement(me: MockUser, b: Record<string, unknown>): { created: boolean; achievement: Achievement } {
    this.validateAchievement(b);
    const existing = me.achievements.find((a) => a.key === b['key']);
    if (existing) return { created: false, achievement: existing };
    const achievement: Achievement = {
      id: this.id('a'),
      kind: b['kind'] as AchievementKind,
      key: b['key'] as string,
      title: b['title'] as string,
      detail: typeof b['detail'] === 'string' ? b['detail'] : '',
      earnedAt: typeof b['earnedAt'] === 'string' ? new Date(b['earnedAt']).toISOString() : this.now().toISOString(),
    };
    me.achievements.push(achievement);
    return { created: true, achievement };
  }
}

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...headers } });
}

function empty(): Response {
  return new Response(null, { status: 204 });
}

function pairKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) && !(typeof Blob !== 'undefined' && value instanceof Blob);
}

function isDay(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const at = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(at.getTime()) && at.toISOString().startsWith(value);
}

function newestFirst(a: { earnedAt: string }, b: { earnedAt: string }): number {
  return Date.parse(b.earnedAt) - Date.parse(a.earnedAt);
}

async function blobToDataUrl(blob: Blob, type: string): Promise<string> {
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return `data:${type};base64,${btoa(binary)}`;
}
