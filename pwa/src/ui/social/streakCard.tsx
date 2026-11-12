import { useEffect, useState } from 'preact/hooks';
import { useAppScope } from '../../app/scope';
import type { AccountController } from '../../data/account';
import type { FriendStreakEntry } from '../../data/api';
import type { ReadingStore } from '../../data/marks';
import { useNotifier } from '../../infra/changeNotifier';
import { Card, Icon, TextButton, TonalButton } from '../m3';
import { Avatar } from './avatar';
import { Pill } from './parts';
import { relativeTime } from './relativeTime';
import { openSocial } from './socialScreen';
import './social.css';

/** Where the mirror of the streak stands, in a line. */
export function syncLine(account: AccountController, now: Date = new Date()): { icon: string; text: string } {
  switch (account.syncState) {
    case 'offline':
      return { icon: 'cloud_off', text: account.pendingCount > 0 ? 'Offline. Your streak is safe here and will be backed up when you’re back.' : 'Offline. Showing what was saved.' };
    case 'pending':
      return { icon: 'sync', text: 'Backing up…' };
    case 'synced': {
      const at = account.lastSyncedAt;
      return { icon: 'cloud_done', text: at ? `Backed up ${relativeTime(at, now)}` : 'Backed up to your account' };
    }
    default:
      return { icon: 'cloud_off', text: 'Kept on this device only' };
  }
}

/** The reader's own streak: the run, the best, the freezes in hand. The device's count is the true one. */
export function OwnStreak({ reading }: { reading: ReadingStore }) {
  const streak = reading.streak;
  const today = reading.today;
  const days = streak.currentOn(today);
  const done = streak.practisedOn(today);
  return (
    <div class="ow-streak-card__row">
      <div class={`ow-streak-card__flame${days > 0 ? '' : ' ow-streak-card__flame--out'}`}>
        <Icon name="local_fire_department" />
      </div>
      <div style="min-width:0">
        <div class="ow-streak-card__count">{days === 1 ? '1 day' : `${days} days`}</div>
        <div class="ow-streak-card__facts">
          <span>Best {streak.best}</span>
          {streak.freezes > 0 && (
            <span>
              <Icon name="ac_unit" /> {streak.freezes} {streak.freezes === 1 ? 'freeze' : 'freezes'}
            </span>
          )}
          <span>{done ? 'Done for today' : days > 0 ? 'Today still to do' : 'Learn today to start one'}</span>
        </div>
      </div>
    </div>
  );
}

/**
 * Your streak and the ones you share with friends, for the Library's
 * Progress tab. Nothing at all for a reader with no account, unless
 * `showInvite` asks for the invitation to make one.
 */
export function FriendStreaksCard({ showInvite = false, limit = 4 }: { showInvite?: boolean; limit?: number }) {
  const { account, reading } = useAppScope();
  useNotifier(account, reading);
  const [streaks, setStreaks] = useState<FriendStreakEntry[] | null>(null);
  const signedIn = account.isSignedIn;
  const userId = account.user?.id;
  const friendCount = account.counts.friends;
  const learnt = reading.streak.last?.getTime() ?? 0;

  useEffect(() => {
    if (!signedIn) {
      setStreaks(null);
      return;
    }
    let live = true;
    account.streaks().then(
      (loaded) => live && setStreaks(loaded.friendStreaks),
      () => undefined,
    );
    return () => {
      live = false;
    };
    // A day learnt changes every shared streak; so does a friend made.
  }, [account, signedIn, userId, friendCount, learnt, account.lastSyncedAt?.getTime()]);

  if (!signedIn) {
    if (!showInvite || account.status === 'loading') return null;
    return (
      <Card variant="outlined" class="ow-streak-card">
        <div class="ow-streak-card__row">
          <div class="ow-streak-card__flame">
            <Icon name="diversity_3" />
          </div>
          <div style="flex:1;min-width:0">
            <div class="m3-title-medium">Keep a streak with a friend</div>
            <div class="m3-body-medium ow-social-muted">Make a free account to share streaks and cheer each other on. It’s optional.</div>
          </div>
        </div>
        <div class="ow-friend-streaks__more">
          <TonalButton icon="person_add" onClick={() => void openSocial('account')}>
            Find friends
          </TonalButton>
        </div>
      </Card>
    );
  }

  const sync = syncLine(account);
  const sorted = streaks === null ? null : [...streaks].sort((a, b) => Number(b.atRisk) - Number(a.atRisk) || b.current - a.current);
  const shown = sorted?.slice(0, limit) ?? null;
  return (
    <Card variant="outlined" class="ow-streak-card">
      <OwnStreak reading={reading} />
      {shown !== null && shown.length > 0 && (
        <div class="ow-friend-streaks">
          {shown.map((entry) => (
            <button type="button" class="ow-friend-streak m3-interactive" key={entry.user.id} onClick={() => void openSocial('friends')}>
              <Avatar user={entry.user} size={32} />
              <span class="ow-friend-streak__name">{entry.user.displayName}</span>
              {entry.atRisk ? (
                <Pill kind="risk" icon="local_fire_department">
                  {entry.current} · today still to do
                </Pill>
              ) : entry.current > 0 ? (
                <Pill kind="together" icon="local_fire_department">
                  {entry.current} together
                </Pill>
              ) : (
                <Pill>No streak yet</Pill>
              )}
            </button>
          ))}
        </div>
      )}
      {sorted !== null && sorted.length === 0 ? (
        <div class="ow-streak-card__sync" style="justify-content:space-between">
          <span>Streaks are better shared.</span>
          <TonalButton icon="person_add" onClick={() => void openSocial('friends')}>
            Find friends
          </TonalButton>
        </div>
      ) : (
        <div class="ow-streak-card__sync">
          <Icon name={sync.icon} />
          <span style="flex:1">{sync.text}</span>
          {sorted !== null && sorted.length > limit && <TextButton onClick={() => void openSocial('friends')}>All {sorted.length}</TextButton>}
        </div>
      )}
    </Card>
  );
}
