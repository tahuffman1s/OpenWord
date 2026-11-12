import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AccountController, reminderDueNow, weekdayBit, type QueuedCall } from '../src/data/account';
import { Api, ApiError, NetworkError, avatarUrl, type AchievementInput, type Settings } from '../src/data/api';
import { ReadingStore } from '../src/data/marks';
import { MockServer } from '../src/dev/mockApi';
import { Prefs } from '../src/infra/prefs';
import { Reference } from '../src/model/bible';
import { LocalDate } from '../src/model/localDate';
import { MemoryVerse } from '../src/model/memoryVerse';
import { ReadingPlans } from '../src/model/readingPlan';

/** Monday 28 September 2026, half past nine in the morning. */
const monday = new Date(2026, 8, 28, 9, 30);
const mondayString = '2026-09-28';
const days = (n: number) => new Date(monday.getTime() + n * 86_400_000);

interface World {
  server: MockServer;
  prefs: Prefs;
  reading: ReadingStore;
  account: AccountController;
  /** The app closed and opened again: the same Prefs, new stores. */
  restart(): Promise<AccountController>;
  setNow(to: Date): void;
}

async function world(options: { signedIn?: boolean } = {}): Promise<World> {
  let now = monday;
  const server = new MockServer();
  server.now = () => now;
  const prefs = Prefs.memory();
  const reading = await ReadingStore.load({ prefs, clock: () => now });
  const make = (store: ReadingStore) => new AccountController({ prefs, reading: store, fetch: server.fetch, debounceMs: 5 });
  const w: World = {
    server,
    prefs,
    reading,
    account: make(reading),
    async restart() {
      w.account.dispose();
      w.reading = await ReadingStore.load({ prefs, clock: () => now });
      w.account = make(w.reading);
      await w.account.start();
      return w.account;
    },
    setNow(to: Date) {
      now = to;
    },
  };
  await w.account.start();
  if (options.signedIn ?? true) {
    await w.account.register({ username: 'Alice', password: 'correct horse', displayName: 'Alice' });
    server.log.length = 0;
  }
  return w;
}

const posted = (server: MockServer, method: string, path: string) => server.log.filter((c) => c.method === method && c.path === path && c.status < 300);
const activities = (server: MockServer) => posted(server, 'POST', '/activity').map((c) => `${(c.body as { kind: string }).kind}:${(c.body as { day: string }).day}`);
const achievementKeys = (server: MockServer) => [...server.byUsername('alice')!.achievements].map((a) => a.key).sort();

let warn: ReturnType<typeof vi.spyOn>;
beforeEach(() => {
  warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
});
afterEach(() => {
  warn.mockRestore();
});

describe('the API client', () => {
  it('sends the bearer token and reads an error as status, code and message', async () => {
    const server = new MockServer();
    const user = server.addUser({ username: 'alice', password: 'correct horse' });
    let token: string | null = null;
    const api = new Api({ fetch: server.fetch, token: () => token });

    const unauthorized = await api.me().catch((e: unknown) => e);
    expect(unauthorized).toBeInstanceOf(ApiError);
    expect(unauthorized).toMatchObject({ status: 401, code: 'unauthorized' });

    const wrong = await api.login('alice', 'nope').catch((e: unknown) => e);
    expect(wrong).toMatchObject({ status: 401, code: 'bad_credentials' });
    expect((wrong as ApiError).message.length).toBeGreaterThan(0);

    const session = await api.login('alice', 'correct horse');
    token = session.token;
    expect(session.user.id).toBe(user.id);
    const me = await api.me();
    expect(me.user.username).toBe('alice');
    expect(me.counts).toEqual({ friends: 0, pendingRequests: 0 });

    const taken = await api.register({ username: 'alice', password: 'longenough' }).catch((e: unknown) => e);
    expect(taken).toMatchObject({ status: 409, code: 'username_taken' });
    server.inviteCode = 'friends-only';
    const invite = await api.register({ username: 'bob', password: 'longenough' }).catch((e: unknown) => e);
    expect(invite).toMatchObject({ status: 403, code: 'invite_required' });
    expect((await api.register({ username: 'bob', password: 'longenough', inviteCode: 'friends-only' })).user.username).toBe('bob');
  });

  it('a request that gets no answer is a NetworkError', async () => {
    const server = new MockServer();
    server.offline = true;
    const api = new Api({ fetch: server.fetch });
    await expect(api.me()).rejects.toBeInstanceOf(NetworkError);
  });

  it('answers null for a backup that is not there, and the document when it is', async () => {
    const server = new MockServer();
    const user = server.addUser({ username: 'alice' });
    const token = server.tokenFor(user);
    const api = new Api({ fetch: server.fetch, token: () => token });
    expect(await api.getBackup()).toBeNull();
    const info = await api.putBackup({ app: 'openword', marks: [] });
    expect(info.sizeBytes).toBeGreaterThan(0);
    expect(await api.getBackup()).toEqual({ document: { app: 'openword', marks: [] }, updatedAt: info.updatedAt });
  });

  it('builds the avatar URL from the user, with its version', () => {
    expect(avatarUrl({ id: 'u1', avatarVersion: 0, avatarUrl: null })).toBeNull();
    expect(avatarUrl({ id: 'u1', avatarVersion: 3, avatarUrl: '/api/users/u1/avatar?v=3' })).toBe('/api/users/u1/avatar?v=3');
    expect(avatarUrl({ id: 'u1', avatarVersion: 2, avatarUrl: null })).toBe('/api/users/u1/avatar?v=2');
    expect(avatarUrl(null)).toBeNull();
  });
});

describe('starting', () => {
  it('asks nothing of the server when nobody has signed in here', async () => {
    const w = await world({ signedIn: false });
    expect(w.account.status).toBe('signedOut');
    expect(w.account.isSignedIn).toBe(false);
    expect(w.server.log).toEqual([]);
  });

  it('restores the session, with settings and counts', async () => {
    const w = await world();
    const bob = w.server.addUser({ username: 'bob' });
    w.server.request(bob, w.server.byUsername('alice')!, 'hello');
    const account = await w.restart();
    expect(account.status).toBe('signedIn');
    expect(account.user?.username).toBe('alice');
    expect(account.counts).toEqual({ friends: 0, pendingRequests: 1 });
    expect(account.settings?.reminderDays).toBe(127);
  });

  it('offline, still shows who is signed in from the copy kept', async () => {
    const w = await world();
    w.server.offline = true;
    const account = await w.restart();
    expect(account.status).toBe('offline');
    expect(account.isSignedIn).toBe(true);
    expect(account.user?.displayName).toBe('Alice');
    expect(account.syncState).toBe('offline');
  });

  it('signs out when the server no longer knows the session', async () => {
    const w = await world();
    w.server.sessions.clear();
    const account = await w.restart();
    expect(account.status).toBe('signedOut');
    expect(account.user).toBeNull();
  });
});

describe('mirroring the reader’s learning', () => {
  it('sends the streak, the day and the first badge after a first answer', async () => {
    const w = await world();
    const won = w.reading.recordLearning({ xp: 10, right: true });
    expect(won.map((b) => b.id)).toEqual(['first_step']);
    await w.account.syncNow();

    const streak = posted(w.server, 'PUT', '/streak');
    expect(streak).toHaveLength(1);
    expect(streak[0].body).toEqual({ current: 1, best: 1, freezes: 0, lastDay: mondayString });
    expect(activities(w.server)).toEqual([`learn:${mondayString}`]);
    expect(achievementKeys(w.server)).toEqual(['first_step']);
    const badge = w.server.byUsername('alice')!.achievements[0];
    expect(badge).toMatchObject({ kind: 'badge', title: 'First step', detail: 'Earned your first points.' });
    expect(w.account.streak).toMatchObject({ current: 1, best: 1, lastDay: mondayString });
    expect(w.account.pendingCount).toBe(0);
    expect(w.account.syncState).toBe('synced');
  });

  it('tells the server nothing twice', async () => {
    const w = await world();
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.syncNow();
    const calls = w.server.log.length;
    await w.account.syncNow();
    w.reading.recordLearning({ xp: 5, right: true });
    await w.account.syncNow();
    expect(w.server.log.length).toBe(calls);
  });

  it('syncs by itself a moment after the store changes', async () => {
    const w = await world();
    w.reading.recordLearning({ xp: 10, right: true });
    expect(w.server.log).toEqual([]);
    await vi.waitFor(() => expect(activities(w.server)).toEqual([`learn:${mondayString}`]));
  });

  it('posts a level reached, a perfect round, and a quiz day', async () => {
    const w = await world();
    w.reading.recordLearning({ xp: 60, right: true, perfectRound: true });
    await w.account.syncNow();
    expect(achievementKeys(w.server)).toEqual(['first_step', 'level:2', 'perfect_round', `quiz:perfect:${mondayString}`]);
    expect(activities(w.server).sort()).toEqual([`learn:${mondayString}`, `quiz:${mondayString}`]);
    const level = w.server.byUsername('alice')!.achievements.find((a) => a.key === 'level:2')!;
    expect(level).toMatchObject({ kind: 'level', title: 'Level 2' });
    // No two share a moment, so the feed's paging never skips one.
    const times = w.server.byUsername('alice')!.achievements.map((a) => a.earnedAt);
    expect(new Set(times).size).toBe(times.length);
  });

  it('posts each level passed once signed in, and a week’s streak when it comes', async () => {
    const w = await world();
    for (let day = 0; day < 7; day++) {
      w.setNow(days(day));
      w.reading.recordLearning({ xp: 100, right: true });
      await w.account.syncNow();
    }
    const keys = achievementKeys(w.server);
    expect(keys).toContain('streak:7');
    expect(keys).toContain('week_of_fire');
    expect(keys).not.toContain('streak:30');
    // 700 points is level 5: 25·5·4 = 500, and level 6 starts at 750.
    expect(keys.filter((k) => k.startsWith('level:'))).toEqual(['level:2', 'level:3', 'level:4', 'level:5']);
    expect(keys).toContain('level_five');
    expect(activities(w.server).filter((a) => a.startsWith('learn:'))).toHaveLength(7);
    expect(w.server.byUsername('alice')!.streak).toMatchObject({ current: 7, best: 7, freezes: 1 });
    expect(w.server.byUsername('alice')!.achievements.find((a) => a.key === 'streak:7')).toMatchObject({ kind: 'streak', title: '7-day streak' });
  });

  it('tells the server when the streak has lapsed', async () => {
    const w = await world();
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.syncNow();
    w.setNow(days(5));
    await w.account.syncNow();
    expect(w.server.byUsername('alice')!.streak).toMatchObject({ current: 0, best: 1, lastDay: mondayString });
  });

  it('counts a chapter read once a day', async () => {
    const w = await world();
    await w.reading.savePosition(new Reference('JHN', 3, 16));
    await w.account.syncNow();
    await w.reading.savePosition(new Reference('JHN', 4));
    await w.account.syncNow();
    // The same chapter, another verse: nothing moved.
    await w.reading.savePosition(new Reference('JHN', 4, 7));
    await w.account.syncNow();
    expect(activities(w.server)).toEqual([`read:${mondayString}`]);
    w.setNow(days(1));
    await w.reading.savePosition(new Reference('JHN', 5));
    await w.account.syncNow();
    expect(activities(w.server)).toEqual([`read:${mondayString}`, `read:${LocalDate.format(LocalDate.only(days(1)))}`]);
  });

  it('counts a plan chapter ticked, and posts the plan when it is finished', async () => {
    const w = await world();
    const plan = ReadingPlans.proverbsMonth;
    w.reading.startPlan(plan);
    await w.account.syncNow();
    expect(activities(w.server)).toEqual([]);
    w.reading.setPlanSlot(plan.id, 0, true);
    await w.account.syncNow();
    expect(activities(w.server)).toEqual([`plan:${mondayString}`]);
    expect(achievementKeys(w.server)).toEqual([]);
    for (const day of plan.days) w.reading.setPlanDay(plan.id, day, true);
    await w.account.syncNow();
    expect(achievementKeys(w.server)).toEqual([`plan:${plan.id}`]);
    expect(w.server.byUsername('alice')!.achievements[0]).toMatchObject({ kind: 'plan', title: `Finished ${plan.name}` });
  });

  it('posts a verse known by heart', async () => {
    const w = await world();
    const reference = new Reference('JHN', 3, 16);
    w.reading.restoreMemory(new MemoryVerse({ reference, added: LocalDate.only(days(-60)), due: LocalDate.only(days(30)), updated: monday, rung: 2, recalled: 2 }));
    await w.account.syncNow();
    expect(achievementKeys(w.server)).toEqual([]);
    w.reading.restoreMemory(new MemoryVerse({ reference, added: LocalDate.only(days(-60)), due: LocalDate.only(days(30)), updated: monday, rung: MemoryVerse.learntRung, recalled: 6 }));
    await w.account.syncNow();
    expect(achievementKeys(w.server)).toEqual(['memory:JHN/3/16']);
    expect(w.server.byUsername('alice')!.achievements[0]).toMatchObject({ kind: 'memory', title: 'John 3:16 by heart' });
  });

  it('takes what the screens tell it: a round finished, a chapter heard', async () => {
    const w = await world();
    w.account.recordActivity('quiz');
    w.account.recordActivity('listen');
    w.account.recordActivity('listen');
    w.account.recordAchievement({ key: 'friend:first', kind: 'friend', title: 'First friend' });
    w.account.recordAchievement({ key: 'friend:first', kind: 'friend', title: 'First friend' });
    await w.account.flush();
    expect(activities(w.server).sort()).toEqual([`listen:${mondayString}`, `quiz:${mondayString}`]);
    expect(achievementKeys(w.server)).toEqual(['friend:first']);
  });

  it('does nothing at all while signed out', async () => {
    const w = await world({ signedIn: false });
    w.reading.recordLearning({ xp: 10, right: true });
    w.account.recordActivity('quiz');
    await w.account.syncNow();
    expect(w.server.log).toEqual([]);
    expect(w.account.pendingCount).toBe(0);
  });

  it('brings a new account up to date with what was learnt before it', async () => {
    const w = await world({ signedIn: false });
    for (let day = 0; day < 3; day++) {
      w.setNow(days(day));
      w.reading.recordLearning({ xp: 30, right: true });
    }
    await w.reading.savePosition(new Reference('MRK', 1));
    await w.account.register({ username: 'alice', password: 'correct horse' });
    const alice = w.server.byUsername('alice')!;
    // Every day with points counts towards a streak with a friend.
    expect([...alice.activity.keys()].sort()).toEqual(['2026-09-28', '2026-09-29', '2026-09-30']);
    expect(alice.streak).toMatchObject({ current: 3, best: 3 });
    // The level reached is news; the ones on the way are not. Where the
    // reader happened to be reading is not a chapter read today.
    expect(achievementKeys(w.server)).toEqual(['first_step', 'level:2']);
    expect([...alice.activity.values()].every((kinds) => kinds.read === undefined)).toBe(true);
    // A badge keeps the day it was won.
    expect(alice.achievements.find((a) => a.key === 'first_step')!.earnedAt.startsWith('2026-09-28')).toBe(true);
  });
});

describe('the offline queue', () => {
  it('keeps what could not be sent and sends it when the app is next opened', async () => {
    const w = await world();
    w.server.offline = true;
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.syncNow();
    expect(w.account.status).toBe('offline');
    expect(w.account.pendingCount).toBe(3);
    expect(w.account.pending.map((c) => `${c.method} ${c.path}`)).toEqual(['PUT /streak', 'POST /activity', 'POST /achievements/batch']);
    const kept = JSON.parse(w.prefs.getString('account.queue')!) as QueuedCall[];
    expect(kept).toHaveLength(3);

    // The next day, still offline: the day before is not forgotten.
    w.setNow(days(1));
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.syncNow();
    // One streak call, the latest; one activity a day.
    expect(w.account.pending.map((c) => `${c.method} ${c.path}`)).toEqual(['POST /activity', 'POST /achievements/batch', 'PUT /streak', 'POST /activity']);

    w.server.offline = false;
    const account = await w.restart();
    expect(account.status).toBe('signedIn');
    expect(account.pendingCount).toBe(0);
    expect(w.prefs.getString('account.queue')).toBeNull();
    const alice = w.server.byUsername('alice')!;
    expect([...alice.activity.keys()].sort()).toEqual(['2026-09-28', '2026-09-29']);
    expect(alice.streak).toMatchObject({ current: 2, best: 2, lastDay: '2026-09-29' });
    expect(alice.achievements.map((a) => a.key)).toEqual(['first_step']);
    expect(account.lastSyncedAt).not.toBeNull();
  });

  it('adds to a batch of achievements already waiting', async () => {
    const w = await world();
    w.server.offline = true;
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.syncNow();
    w.reading.recordLearning({ xp: 60, right: true, perfectRound: true });
    await w.account.syncNow();
    const batches = w.account.pending.filter((c) => c.path === '/achievements/batch');
    expect(batches).toHaveLength(1);
    const keys = (batches[0].body as { achievements: AchievementInput[] }).achievements.map((a) => a.key);
    expect(keys).toEqual(['first_step', `quiz:perfect:${mondayString}`, 'perfect_round', 'level:2']);
  });

  it('sends when the connection comes back', async () => {
    const w = await world();
    w.server.offline = true;
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.syncNow();
    expect(w.account.pendingCount).toBe(3);
    w.server.offline = false;
    await w.account.refresh();
    expect(w.account.status).toBe('signedIn');
    expect(w.account.pendingCount).toBe(0);
    expect(activities(w.server)).toEqual([`learn:${mondayString}`]);
  });

  it('waits out a server in trouble, and lets go of a call the server refuses', async () => {
    const w = await world();
    w.server.failWith = 500;
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.syncNow();
    expect(w.account.pendingCount).toBe(3);
    expect(w.account.status).toBe('signedIn');

    w.server.failWith = null;
    // A day the server will never take, ahead of good ones.
    w.account.recordActivity('listen', '1999-01-01');
    await w.account.flush();
    expect(w.account.pendingCount).toBe(0);
    expect(activities(w.server)).toEqual([`learn:${mondayString}`]);
    expect(w.server.log.some((c) => c.status === 400)).toBe(true);
  });

  it('keeps the queue for the same person signing back in, and drops it for another', async () => {
    const w = await world();
    w.server.offline = true;
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.syncNow();
    await w.account.logout();
    expect(w.account.status).toBe('signedOut');
    expect(w.account.pendingCount).toBe(3);

    w.server.offline = false;
    await w.account.login('alice', 'correct horse');
    expect(w.account.pendingCount).toBe(0);
    expect(achievementKeys(w.server)).toEqual(['first_step']);

    // Someone else on the same device: the first account's mirror is not theirs.
    await w.account.logout();
    await w.account.register({ username: 'bob', password: 'longenough' });
    const bob = w.server.byUsername('bob')!;
    // What is on the device is theirs now, and is told afresh.
    expect(bob.achievements.map((a) => a.key)).toEqual(['first_step']);
    expect(bob.streak).toMatchObject({ current: 1 });
  });
});

describe('the account', () => {
  it('registers, surfaces the server’s refusals, signs out and in', async () => {
    const w = await world({ signedIn: false });
    await expect(w.account.register({ username: 'a', password: 'correct horse' })).rejects.toMatchObject({ code: 'validation' });
    await expect(w.account.register({ username: 'alice', password: 'short' })).rejects.toMatchObject({ code: 'validation' });
    expect(w.account.status).toBe('signedOut');
    const user = await w.account.register({ username: 'Alice', password: 'correct horse', displayName: ' Alice W ', email: 'alice@example.com' });
    expect(user).toMatchObject({ username: 'alice', displayName: 'Alice W', email: 'alice@example.com' });
    expect(w.account.isSignedIn).toBe(true);
    expect(w.prefs.getString('account.token')).not.toBeNull();
    // The reader's time zone goes with the account, for reminders.
    await vi.waitFor(() => expect(w.server.byUsername('alice')!.settings.reminderTz).not.toBeNull());

    await w.account.logout();
    expect(w.account.isSignedIn).toBe(false);
    expect(w.prefs.getString('account.token')).toBeNull();
    await expect(w.account.login('alice', 'wrong')).rejects.toMatchObject({ code: 'bad_credentials' });
    await w.account.login('alice@example.com', 'correct horse');
    expect(w.account.user?.username).toBe('alice');
  });

  it('edits the profile and the reminders', async () => {
    const w = await world();
    await w.account.updateProfile({ displayName: 'Alice W', bio: 'Reading through Mark' });
    expect(w.account.user).toMatchObject({ displayName: 'Alice W', bio: 'Reading through Mark' });
    const settings = await w.account.setReminders({ reminderTime: '07:30', reminderDays: 31, friendReminders: false });
    expect(settings).toMatchObject({ reminderTime: '07:30', reminderDays: 31, friendReminders: false, reminderOnlyIfUndone: true });
    expect(settings.reminderTz).toBeTruthy();
    expect(w.account.settings).toEqual(settings);
    // A refusal puts the screen back as it was.
    await expect(w.account.setReminders({ reminderTime: '25:00' })).rejects.toMatchObject({ code: 'validation' });
    expect(w.account.settings?.reminderTime).toBe('07:30');
    await w.account.setReminders({ reminderTime: null });
    expect(w.account.settings?.reminderTime).toBeNull();
    // Kept for the next launch, offline or not.
    w.server.offline = true;
    const account = await w.restart();
    expect(account.settings?.reminderDays).toBe(31);
  });

  it('makes friends and keeps the counts', async () => {
    const w = await world();
    const bob = w.server.addUser({ username: 'bob', displayName: 'Bob' });
    const carol = w.server.addUser({ username: 'carol', displayName: 'Carol' });
    const alice = w.server.byUsername('alice')!;
    const incoming = w.server.request(carol, alice, 'It’s Carol from church');

    expect((await w.account.searchUsers('bo')).map((u) => [u.username, u.relation])).toEqual([['bob', 'none']]);
    const sent = await w.account.sendRequest('bob', 'hello');
    expect(sent.request?.to.username).toBe('bob');
    await expect(w.account.sendRequest('bob')).rejects.toMatchObject({ code: 'already_requested' });

    const requests = await w.account.requests();
    expect(requests.incoming.map((r) => r.from.username)).toEqual(['carol']);
    expect(requests.outgoing.map((r) => r.to.username)).toEqual(['bob']);
    expect(w.account.counts.pendingRequests).toBe(1);

    const friend = await w.account.acceptRequest(incoming.id);
    expect(friend.user.username).toBe('carol');
    expect(w.account.counts).toEqual({ friends: 1, pendingRequests: 0 });
    await w.account.cancelRequest(sent.request!.id);
    expect((await w.account.requests()).outgoing).toEqual([]);

    // A request to someone who has already asked makes friends at once.
    w.server.request(bob, alice);
    const outcome = await w.account.sendRequest('bob');
    expect(outcome.friend?.user.username).toBe('bob');
    expect((await w.account.friends()).map((f) => f.user.username)).toEqual(['bob', 'carol']);
    await w.account.unfriend(bob.id);
    expect(w.account.counts.friends).toBe(1);
  });

  it('shares a streak with a friend who learnt the same days, and cheers', async () => {
    const w = await world();
    const bob = w.server.addUser({ username: 'bob', displayName: 'Bob' });
    w.server.befriend(w.server.byUsername('alice')!, bob);
    w.server.learn(bob, 0, 1, 2);
    w.server.achieve(bob, 'badge', 'first_step', 'First step', '', days(-1));
    w.setNow(days(-1));
    w.reading.recordLearning({ xp: 10, right: true });
    w.setNow(monday);
    await w.account.syncNow();
    let streaks = await w.account.streaks();
    expect(streaks.friendStreaks[0]).toMatchObject({ current: 1, atRisk: true });
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.syncNow();
    streaks = await w.account.streaks();
    expect(streaks.friendStreaks[0]).toMatchObject({ current: 2, best: 2, atRisk: false, lastDay: mondayString });
    expect(streaks.streak).toMatchObject({ current: 2 });

    const feed = await w.account.feed();
    expect(feed.items.map((i) => [i.user.username, i.key, i.mine])).toContainEqual(['bob', 'first_step', false]);
    const item = feed.items.find((i) => i.user.username === 'bob')!;
    expect(await w.account.cheer(item.id)).toEqual({ cheers: 1, cheered: true });
    expect(await w.account.uncheer(item.id)).toEqual({ cheers: 0, cheered: false });
    const profile = await w.account.profile('bob');
    expect(profile.relation).toBe('friend');
    expect(profile.friendStreak).toMatchObject({ current: 2 });
  });

  it('backs up to the account and restores by merging', async () => {
    const w = await world();
    const verse = new Reference('JHN', 3, 16);
    w.reading.toggleBookmark(verse);
    w.reading.recordLearning({ xp: 10, right: true });
    expect(w.account.lastBackupAt).toBeNull();
    await w.account.uploadBackup();
    expect(w.account.lastBackupAt).not.toBeNull();
    expect(w.server.byUsername('alice')!.backup!.document).toMatchObject({ app: 'openword', version: 1 });

    // A new device: nothing here but one mark of its own.
    const prefs = Prefs.memory();
    const reading = await ReadingStore.load({ prefs, clock: () => monday });
    const other = new Reference('PSA', 23, 1);
    reading.toggleBookmark(other);
    const account = new AccountController({ prefs, reading, fetch: w.server.fetch });
    await account.start();
    await account.login('alice', 'correct horse');
    const result = await account.downloadBackup();
    expect(result?.ok).toBe(true);
    expect(reading.isBookmarked(verse)).toBe(true);
    expect(reading.isBookmarked(other)).toBe(true);
    expect(reading.streak.count).toBe(1);

    await w.account.api.deleteBackup();
    expect(await account.downloadBackup()).toBeNull();
  });

  it('changes the password and deletes the account', async () => {
    const w = await world();
    await expect(w.account.changePassword('wrong', 'another one')).rejects.toMatchObject({ code: 'bad_credentials' });
    await w.account.changePassword('correct horse', 'another one');
    await expect(w.account.deleteAccount('correct horse')).rejects.toMatchObject({ code: 'bad_credentials' });
    expect(w.account.isSignedIn).toBe(true);
    w.reading.recordLearning({ xp: 10, right: true });
    await w.account.deleteAccount('another one');
    expect(w.account.status).toBe('signedOut');
    expect(w.server.byUsername('alice')).toBeUndefined();
    // What is on the device stays.
    expect(w.reading.streak.count).toBe(1);
    expect(w.prefs.getString('account.shadow')).toBeNull();
  });
});

describe('the reminder nudge', () => {
  const settings = (changes: Partial<Settings> = {}): Settings => ({ reminderTime: '07:30', reminderTz: 'Europe/London', reminderDays: 127, reminderOnlyIfUndone: true, friendReminders: true, ...changes });

  it('is due once the time has passed and nothing is learnt today', async () => {
    const reading = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => monday });
    expect(reminderDueNow(settings(), reading, monday)).toBe(true);
    expect(reminderDueNow(settings(), reading, new Date(2026, 8, 28, 7, 29))).toBe(false);
    expect(reminderDueNow(settings({ reminderTime: null }), reading, monday)).toBe(false);
    expect(reminderDueNow(null, reading, monday)).toBe(false);
    reading.recordPractice();
    expect(reminderDueNow(settings(), reading, monday)).toBe(false);
    // The next day it is due again.
    expect(reminderDueNow(settings(), reading, days(1))).toBe(true);
  });

  it('keeps to the days chosen', async () => {
    const reading = await ReadingStore.load({ prefs: Prefs.memory(), clock: () => monday });
    expect(weekdayBit(monday)).toBe(1);
    expect(weekdayBit(days(6))).toBe(64);
    expect(reminderDueNow(settings({ reminderDays: 1 }), reading, monday)).toBe(true);
    expect(reminderDueNow(settings({ reminderDays: 126 }), reading, monday)).toBe(false);
    expect(reminderDueNow(settings({ reminderDays: 64 }), reading, days(6))).toBe(true);
  });
});
