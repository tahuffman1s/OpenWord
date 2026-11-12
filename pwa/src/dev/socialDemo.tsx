// A page to try the social screens on their own, against the in-memory
// server of ./mockApi.ts swapped in for `fetch`:
//   npx vite --port 5202   →   http://localhost:5202/social-demo.html
// Query parameters, for screenshots:
//   ?state=out         signed out (the default is signed in as Alice)
//   ?tab=feed|friends|account   opens the social screen on that tab
//   ?open=signin|register|add|profile   opens that sheet over it
//   ?empty=1           an account with no friends and nothing earned
//   ?offline=1         the server cannot be reached after the first load
//   ?invite=1          registration needs the invite code "friends-only"
//   ?risk=1            today's learning not done yet
//   ?dark=1            the dark theme
import { render } from 'preact';
import { useState } from 'preact/hooks';
import '../ui/m3/m3.css';
import { AppScope, setGlobalScope, type AppScopeValue } from '../app/scope';
import { AccountController, reminderDueNow } from '../data/account';
import { ReadingStore } from '../data/marks';
import { useNotifier } from '../infra/changeNotifier';
import { Prefs } from '../infra/prefs';
import { Reference } from '../model/bible';
import { ReadingPlans } from '../model/readingPlan';
import { AppBar, Card, ListTile, OverlayHost, Screen, SectionHeader, Switch, applyScheme, installRipples, schemeFromSeed, showSnackBar } from '../ui/m3';
import { showAddFriend } from '../ui/social/addFriendSheet';
import { showFriendProfile } from '../ui/social/friendProfileSheet';
import { showSignIn } from '../ui/social/signInSheet';
import { openSocial } from '../ui/social/socialScreen';
import { FriendStreaksCard } from '../ui/social/streakCard';
import { MockServer } from './mockApi';

const params = new URLSearchParams(location.search);
const flag = (name: string) => params.get(name) === '1';
applyScheme(schemeFromSeed(0xff1b6c4f, flag('dark') ? 'dark' : 'light'));
installRipples();

const hour = 3_600_000;
const day = 24 * hour;

/** A stand-in for a photo: an `<img>` cannot be answered by a fake `fetch`. */
function portrait(from: string, to: string, skin: string): string {
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">` +
    `<stop offset="0" stop-color="${from}"/><stop offset="1" stop-color="${to}"/></linearGradient></defs>` +
    `<rect width="96" height="96" fill="url(#g)"/><circle cx="48" cy="40" r="17" fill="${skin}"/>` +
    `<path d="M14 96c2-22 16-32 34-32s32 10 34 32z" fill="${skin}"/></svg>`;
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

async function boot() {
  const now = new Date();
  const ago = (ms: number) => new Date(now.getTime() - ms);
  const server = new MockServer();
  if (flag('invite')) server.inviteCode = 'friends-only';

  // ---- the people
  const alice = server.addUser({ username: 'alice', displayName: 'Alice Whitfield', password: 'correct horse', bio: 'Reading through Mark. Slowly.', email: 'alice@example.com', createdAt: ago(90 * day) });
  const ben = server.addUser({ username: 'ben_okafor', displayName: 'Ben Okafor', bio: 'Psalms before breakfast.', avatar: portrait('#2f6f8f', '#8fd0c4', '#6b4a35') });
  const carol = server.addUser({ username: 'carol', displayName: 'Carol Reyes', bio: 'Learning Romans 8 by heart, one verse at a time.' });
  const dan = server.addUser({ username: 'dan', displayName: 'Dan Sørensen', avatar: portrait('#b6562f', '#f0c36a', '#f1d1b5') });
  const esther = server.addUser({ username: 'esther', displayName: 'Esther Adeyemi', avatar: portrait('#6a4c93', '#c9a7eb', '#8a5a44') });
  const femi = server.addUser({ username: 'femi', displayName: 'Femi Balogun' });
  server.addUser({ username: 'grace_lee', displayName: 'Grace Lee', avatar: portrait('#3a7d44', '#b7e4a0', '#e8c39e') });
  server.addUser({ username: 'graham', displayName: 'Graham Pike' });
  server.addUser({ username: 'hannah', displayName: 'Hannah Grant' });

  if (!flag('empty')) {
    server.befriend(alice, ben, ago(60 * day));
    server.befriend(alice, carol, ago(21 * day));
    server.befriend(alice, dan, ago(8 * day));
    server.request(esther, alice, 'It’s Esther from the Tuesday group', ago(2 * hour));
    server.request(alice, femi, '', ago(26 * hour));
    server.befriend(ben, carol);

    // Ben learns every day; Carol has not yet today; Dan has drifted.
    server.learn(ben, ...Array.from({ length: 34 }, (_, i) => i));
    server.setStreak(ben, 34, 41, 2, 0);
    server.learn(carol, 1, 2, 3, 4, 5);
    server.setStreak(carol, 5, 12, 0, 1);
    server.learn(dan, 6, 7);
    server.setStreak(dan, 0, 3, 0, 6);

    // ---- what they have earned
    server.achieve(ben, 'badge', 'goal_week', 'Goal week', 'The daily goal met seven days running.', ago(35 * 60_000), [carol]);
    server.achieve(carol, 'memory', 'memory:ROM/8/1', 'Romans 8:1 by heart', 'Recalled after a month away.', ago(3 * hour), [ben, alice]);
    server.achieve(ben, 'level', 'level:7', 'Level 7', '1,060 points so far.', ago(7 * hour));
    server.achieve(dan, 'friend', 'friend:first', 'First friend', 'Joined friends with Alice.', ago(27 * hour), [alice]);
    server.achieve(carol, 'quiz', 'quiz:perfect:1', 'Perfect round', 'Every answer in a round right.', ago(30 * hour));
    server.achieve(ben, 'streak', 'streak:30', '30-day streak', 'A month of learning every day.', ago(4 * day), [alice, carol, dan]);
    server.achieve(carol, 'plan', 'plan:gospels-30', 'Finished The Gospels in 30 days', '30 days of reading.', ago(6 * day), [ben]);
    const filler: [typeof ben, 'badge' | 'level' | 'memory' | 'quiz', string, string][] = [
      [ben, 'badge', 'Scribe', 'A verse written out right.'],
      [carol, 'level', 'Level 4', '310 points so far.'],
      [dan, 'badge', 'First step', 'Earned your first points.'],
      [ben, 'memory', 'Psalm 23:1 by heart', 'Recalled after a month away.'],
      [carol, 'quiz', 'Perfect round', 'Every answer in a round right.'],
    ];
    for (let i = 0; i < 40; i++) {
      const [who, kind, title, detail] = filler[i % filler.length];
      server.achieve(who, kind, `old:${i}`, title, detail, ago((9 + i * 2) * day + i * 977_000));
    }
  }

  // ---- this device: twelve days of learning, a plan under way, a place in Mark
  const prefs = Prefs.memory();
  let clock = now;
  const reading = await ReadingStore.load({ prefs, clock: () => clock });
  if (!flag('empty')) {
    const from = flag('risk') ? 12 : 11;
    const to = flag('risk') ? 1 : 0;
    for (let back = from; back >= to; back--) {
      clock = ago(back * day);
      reading.recordLearning({ xp: 45, right: true, perfectRound: back === 4, scribed: back === 9 });
    }
    clock = now;
    reading.startPlan(ReadingPlans.gospels);
    reading.setPlanSlot(ReadingPlans.gospels.id, 0, true);
    reading.toggleBookmark(new Reference('MRK', 4, 9));
    await reading.savePosition(new Reference('MRK', 4));
  }

  if (params.get('state') !== 'out') {
    prefs.setString('account.token', server.tokenFor(alice));
    await server.fetch('/api/me', {
      method: 'PATCH',
      headers: { Authorization: `Bearer ${server.tokenFor(alice)}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ reminderTime: '07:30', reminderTz: 'Europe/London', reminderDays: 31 }),
    });
    server.log.length = 0;
  }

  server.passthrough = window.fetch.bind(window);
  window.fetch = server.fetch;

  const account = new AccountController({ prefs, reading });
  await account.start();
  // From here on answers take a moment, so the spinners can be seen.
  server.latency = 120;
  if (flag('offline')) server.offline = true;
  // For poking at from the console, and for the screenshot script.
  Object.assign(window, { demo: { server, account, reading, prefs } });
  return { server, account, reading };
}

function Demo({ server, account, reading }: Awaited<ReturnType<typeof boot>>) {
  useNotifier(account, reading);
  const [offline, setOffline] = useState(server.offline);
  return (
    <Screen appBar={(s) => <AppBar scrolled={s} leading="none" title="Social demo" subtitle={`${account.status}${account.user ? ` · @${account.user.username}` : ''}`} />}>
      <SectionHeader>The Library’s card</SectionHeader>
      <FriendStreaksCard showInvite />
      {reminderDueNow(account.settings, reading, reading.today) && (
        <Card variant="tertiary" style="margin:8px 16px">
          <div class="m3-title-small">Reminder</div>
          <div class="m3-body-medium">Your reminder time has passed and today’s learning is still to do.</div>
        </Card>
      )}
      <SectionHeader>Open</SectionHeader>
      <ListTile icon="celebration" title="Feed" onClick={() => void openSocial('feed')} />
      <ListTile icon="group" title="Friends" onClick={() => void openSocial('friends')} />
      <ListTile icon="account_circle" title="You" onClick={() => void openSocial('account')} />
      <ListTile icon="login" title="Sign in sheet" onClick={() => void showSignIn('login')} />
      <SectionHeader>Pretend</SectionHeader>
      <ListTile
        icon="wifi_off"
        title="Server unreachable"
        subtitle={`${account.pendingCount} waiting to be sent`}
        trailing={
          <Switch
            value={offline}
            onChange={(v) => {
              server.offline = v;
              setOffline(v);
              if (!v) void account.refresh();
            }}
          />
        }
      />
      <ListTile
        icon="school"
        title="Learn something now"
        subtitle="Ten points, as answering a verse right would earn"
        onClick={() => {
          const won = reading.recordLearning({ xp: 10, right: true });
          showSnackBar(won.length > 0 ? `Badge: ${won.map((b) => b.title).join(', ')}` : 'Learnt');
        }}
      />
      <ListTile icon="quiz" title="Finish a quiz round" onClick={() => account.recordActivity('quiz')} />
    </Screen>
  );
}

void boot().then((world) => {
  const scope = { account: world.account, reading: world.reading } as unknown as AppScopeValue;
  setGlobalScope(scope);
  render(
    <AppScope value={scope}>
      <Demo {...world} />
      <OverlayHost />
    </AppScope>,
    document.getElementById('app')!,
  );
  const tab = params.get('tab');
  const open = params.get('open');
  if (tab || open) void openSocial(tab ?? 'feed');
  // After the screen has been pushed, so the sheet sits on top of it.
  setTimeout(() => {
    if (open === 'signin') void showSignIn('login');
    else if (open === 'register') void showSignIn('register');
    else if (open === 'add') void showAddFriend();
    else if (open === 'profile') void showFriendProfile(params.get('user') ?? 'ben_okafor');
  }, 50);
});
