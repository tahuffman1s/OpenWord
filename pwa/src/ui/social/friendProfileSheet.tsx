import { useCallback, useEffect, useState } from 'preact/hooks';
import { useAppScope } from '../../app/scope';
import type { Profile } from '../../data/api';
import { FilledButton, Icon, OutlinedButton, SectionHeader, Sheet, TextButton, confirm, showSheet, showSnackBar, useOverlay } from '../m3';
import { Avatar } from './avatar';
import { messageOf } from './errors';
import { AchievementBody, type CheerState } from './feedTab';
import { LoadError, Loading, Pill } from './parts';
import { relativeDay, relativeTime } from './relativeTime';
import './social.css';

/** What the sheet closed with, when it closed itself. */
export type ProfileOutcome = 'removed';

/** Opens someone's profile; settles when it is closed, with `'removed'` if they were unfriended. */
export function showFriendProfile(username: string): Promise<ProfileOutcome | undefined> {
  return showSheet<ProfileOutcome>(<FriendProfileSheet username={username} />, { full: true });
}

/**
 * A friend, larger: their photo, what they say of themselves, their streak
 * and the one you share, and the last things they earned, each of which
 * can be cheered.
 */
export function FriendProfileSheet({ username }: { username: string }) {
  const { account } = useAppScope();
  const overlay = useOverlay();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [error, setError] = useState<string | null>(null);
  /** Cheers by achievement id: the profile does not carry them, the feed does. */
  const [cheers, setCheers] = useState<Record<string, CheerState>>({});
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    try {
      const [loaded, feed] = await Promise.all([account.profile(username), account.feed().catch(() => null)]);
      setProfile(loaded);
      // The profile says how each is cheered; a server from before it did
      // leaves the first page of the feed to fill in what it can.
      const found: Record<string, CheerState> = {};
      if (feed) for (const item of feed.items) found[item.id] = { cheers: item.cheers, cheered: item.cheered };
      for (const item of loaded.achievements) {
        if (item.cheers !== undefined) found[item.id] = { cheers: item.cheers, cheered: item.cheered ?? false };
      }
      setCheers((have) => ({ ...found, ...have }));
    } catch (e) {
      setError(messageOf(e));
    }
  }, [account, username]);

  useEffect(() => {
    void load();
  }, [load]);

  if (profile === null) {
    return <Sheet>{error ? <LoadError message={error} onRetry={() => void load()} /> : <Loading />}</Sheet>;
  }

  const { user, streak, friendStreak, achievements, relation } = profile;
  const now = new Date();

  const remove = async () => {
    const sure = await confirm({
      title: `Remove ${user.displayName}?`,
      body: 'You’ll stop seeing each other’s streaks and achievements, and the streak you share will end. You can add each other again later.',
      confirmLabel: 'Remove',
      destructive: true,
    });
    if (!sure) return;
    setBusy(true);
    try {
      await account.unfriend(user.id);
      showSnackBar(`${user.displayName} is no longer a friend`);
      overlay.close('removed');
    } catch (e) {
      showSnackBar(messageOf(e));
      setBusy(false);
    }
  };

  const add = async () => {
    setBusy(true);
    try {
      const outcome = await account.sendRequest(user.username);
      showSnackBar(outcome.friend ? `You and ${user.displayName} are now friends` : `Request sent to ${user.displayName}`);
      await load();
    } catch (e) {
      showSnackBar(messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet>
      <div class="ow-profile-head">
        <Avatar user={user} size={96} />
        <div class="ow-profile-head__name">{user.displayName}</div>
        <div class="m3-body-medium ow-social-muted">@{user.username}</div>
        {user.bio && <div class="ow-profile-head__bio">{user.bio}</div>}
        {relation !== 'friend' && relation !== 'self' && (
          <div class="ow-profile-head__actions">
            {relation === 'none' && <FilledButton icon="person_add" disabled={busy} onClick={() => void add()}>Add friend</FilledButton>}
            {relation === 'incoming' && <FilledButton icon="check" disabled={busy} onClick={() => void add()}>Accept request</FilledButton>}
            {relation === 'requested' && <OutlinedButton disabled>Requested</OutlinedButton>}
          </div>
        )}
      </div>

      <div class="ow-stats">
        <div class="ow-stat">
          <div class="ow-stat__label">{relation === 'self' ? 'Your streak' : 'Their streak'}</div>
          <div class="ow-stat__value">
            <Icon name="local_fire_department" />
            {streak?.current ?? 0}
          </div>
          <div class="ow-stat__note">{streak ? `Best ${streak.best} · last learnt ${relativeDay(streak.lastDay, now)}` : 'Not started yet'}</div>
        </div>
        {relation === 'friend' && (
          <div class="ow-stat ow-stat--together">
            <div class="ow-stat__label">Together</div>
            <div class="ow-stat__value">
              <Icon name="local_fire_department" />
              {friendStreak?.current ?? 0}
            </div>
            <div class="ow-stat__note">
              {friendStreak && friendStreak.best > 0 ? `Best ${friendStreak.best} ${friendStreak.best === 1 ? 'day' : 'days'}` : 'Learn on the same day to start one'}
            </div>
          </div>
        )}
      </div>
      {friendStreak?.atRisk && (
        <div style="padding:0 16px 4px">
          <Pill kind="risk" icon="error_outline">Today still to do — one of you hasn’t learnt yet</Pill>
        </div>
      )}

      <SectionHeader>Recently earned</SectionHeader>
      {achievements.length === 0 ? (
        <div class="ow-social-footnote" style="padding-bottom:16px">Nothing yet. It won’t be long.</div>
      ) : (
        achievements.map((achievement) => (
          <div class="ow-feed-item" key={achievement.id}>
            <div class="ow-feed-item__main">
              <div class="ow-feed-item__head">
                <span class="ow-feed-item__when" style="margin-left:0">{relativeTime(achievement.earnedAt, now)}</span>
              </div>
              <AchievementBody
                achievement={achievement}
                cheer={cheers[achievement.id] ?? null}
                onCheer={(state) => setCheers((have) => ({ ...have, [achievement.id]: state }))}
              />
            </div>
          </div>
        ))
      )}

      {relation === 'friend' && (
        <div style="display:flex;justify-content:center;padding:16px 16px 8px">
          <TextButton destructive icon="person_remove" disabled={busy} onClick={() => void remove()}>
            Remove friend
          </TextButton>
        </div>
      )}
    </Sheet>
  );
}
