import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { useAppScope } from '../../app/scope';
import type { FriendEntry, FriendStreakEntry, IncomingRequest, OutgoingRequest, Requests } from '../../data/api';
import { useNotifier } from '../../infra/changeNotifier';
import { Divider, FilledButton, Icon, ListTile, SectionHeader, TextButton, showSnackBar } from '../m3';
import { showAddFriend } from './addFriendSheet';
import { Avatar } from './avatar';
import { messageOf } from './errors';
import { showFriendProfile } from './friendProfileSheet';
import { EmptyState, Flame, LoadError, Loading, Pill } from './parts';
import { relativeDay, relativeTime } from './relativeTime';
import './social.css';

interface Loaded {
  friends: FriendEntry[];
  requests: Requests;
  /** Friend streaks by user id, which carry `atRisk`. */
  shared: Map<string, FriendStreakEntry>;
}

/** "Active today", "Active 3 days ago", or nothing known. */
function activeLine(day: string | null, now: Date): string {
  if (!day) return 'Hasn’t started yet';
  const when = relativeDay(day, now);
  return when === 'today' || when === 'yesterday' || when.endsWith('ago') ? `Active ${when}` : `Last active ${when}`;
}

/**
 * Your friends, each with their own streak and the one you share; requests
 * waiting for an answer above them.
 */
export function FriendsTab({ refreshKey = 0 }: { refreshKey?: number }) {
  const { account } = useAppScope();
  useNotifier(account);
  const [data, setData] = useState<Loaded | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const generation = useRef(0);
  const userId = account.user?.id;

  const load = useCallback(async () => {
    const mine = ++generation.current;
    setError(null);
    try {
      const [friends, requests, streaks] = await Promise.all([account.friends(), account.requests(), account.streaks()]);
      if (mine !== generation.current) return;
      setData({ friends, requests, shared: new Map(streaks.friendStreaks.map((s) => [s.user.id, s])) });
    } catch (e) {
      if (mine !== generation.current) return;
      setError(messageOf(e));
    }
  }, [account]);

  useEffect(() => {
    void load();
  }, [load, refreshKey, userId]);

  const act = async (id: string, run: () => Promise<unknown>, done: string) => {
    setBusy(id);
    try {
      await run();
      showSnackBar(done);
    } catch (e) {
      showSnackBar(messageOf(e));
    } finally {
      setBusy(null);
      await load();
    }
  };

  const open = async (username: string) => {
    await showFriendProfile(username);
    await load();
  };

  if (data === null) return error ? <LoadError message={error} onRetry={() => void load()} /> : <Loading />;

  const { friends, requests, shared } = data;
  const now = new Date();
  const hasRequests = requests.incoming.length + requests.outgoing.length > 0;

  return (
    <div class="ow-social ow-social--fab">
      {error && <div class="ow-social-banner"><Icon name="cloud_off" />{error}</div>}
      {hasRequests && (
        <>
          <SectionHeader>Requests</SectionHeader>
          {requests.incoming.map((request) => (
            <IncomingRow
              key={request.id}
              request={request}
              now={now}
              busy={busy === request.id}
              onAccept={() => void act(request.id, () => account.acceptRequest(request.id), `You and ${request.from.displayName} are now friends`)}
              onDecline={() => void act(request.id, () => account.declineRequest(request.id), 'Request declined')}
            />
          ))}
          {requests.outgoing.map((request) => (
            <OutgoingRow
              key={request.id}
              request={request}
              now={now}
              busy={busy === request.id}
              onCancel={() => void act(request.id, () => account.cancelRequest(request.id), 'Request cancelled')}
            />
          ))}
          <Divider />
        </>
      )}
      {friends.length === 0 ? (
        <EmptyState
          icon="diversity_3"
          title={hasRequests ? 'No friends yet' : 'Add your first friend'}
          actions={
            <FilledButton
              icon="person_add"
              onClick={async () => {
                await showAddFriend();
                await load();
              }}
            >
              Add friend
            </FilledButton>
          }
        >
          Learn on the same days and you’ll build a streak together. They’ll see your streak and what you earn; you’ll see theirs.
        </EmptyState>
      ) : (
        <>
          <SectionHeader>{friends.length === 1 ? '1 friend' : `${friends.length} friends`}</SectionHeader>
          {friends.map((friend) => (
            <FriendRow key={friend.user.id} friend={friend} shared={shared.get(friend.user.id)} now={now} onOpen={() => void open(friend.user.username)} />
          ))}
        </>
      )}
    </div>
  );
}

function FriendRow({ friend, shared, now, onOpen }: { friend: FriendEntry; shared: FriendStreakEntry | undefined; now: Date; onOpen: () => void }) {
  const together = shared?.current ?? friend.friendStreak?.current ?? 0;
  const atRisk = shared?.atRisk ?? false;
  return (
    <ListTile
      leading={<Avatar user={friend.user} size={48} />}
      title={friend.user.displayName}
      subtitle={
        <>
          {activeLine(friend.lastActiveDay, now)}
          {(together > 0 || atRisk) && (
            <span class="ow-pill-row">
              {together > 0 && (
                <Pill kind="together" icon="local_fire_department">
                  {together} together
                </Pill>
              )}
              {atRisk && (
                <Pill kind="risk" icon="error_outline">
                  Today still to do
                </Pill>
              )}
            </span>
          )}
        </>
      }
      trailing={<Flame days={friend.streak?.current ?? 0} label={`${friend.user.displayName}’s streak: ${friend.streak?.current ?? 0} days`} />}
      onClick={onOpen}
    />
  );
}

function IncomingRow({ request, now, busy, onAccept, onDecline }: { request: IncomingRequest; now: Date; busy: boolean; onAccept: () => void; onDecline: () => void }) {
  return (
    <div class="ow-request">
      <Avatar user={request.from} size={48} />
      <div class="ow-request__main">
        <div class="ow-request__name">{request.from.displayName}</div>
        <div class="ow-request__note">
          @{request.from.username} · {relativeTime(request.createdAt, now)}
        </div>
        {request.message && <div class="ow-request__note">“{request.message}”</div>}
        <div class="ow-request__actions">
          <FilledButton disabled={busy} onClick={onAccept}>
            Accept
          </FilledButton>
          <TextButton disabled={busy} onClick={onDecline}>
            Decline
          </TextButton>
        </div>
      </div>
    </div>
  );
}

function OutgoingRow({ request, now, busy, onCancel }: { request: OutgoingRequest; now: Date; busy: boolean; onCancel: () => void }) {
  return (
    <ListTile
      static
      leading={<Avatar user={request.to} size={48} />}
      title={request.to.displayName}
      subtitle={`Asked ${relativeTime(request.createdAt, now)} · waiting for an answer`}
      trailing={
        <TextButton disabled={busy} onClick={onCancel}>
          Cancel
        </TextButton>
      }
    />
  );
}
