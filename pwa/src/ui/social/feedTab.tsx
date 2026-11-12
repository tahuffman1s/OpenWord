import { useCallback, useEffect, useRef, useState } from 'preact/hooks';
import { useAppScope } from '../../app/scope';
import type { Achievement, AchievementKind, FeedItem } from '../../data/api';
import { useNotifier } from '../../infra/changeNotifier';
import { Button, Icon, TonalButton, showSnackBar } from '../m3';
import { Avatar } from './avatar';
import { messageOf } from './errors';
import { EmptyState, LoadError, Loading, Pill } from './parts';
import { relativeTime } from './relativeTime';
import './social.css';

/** The icon that stands for each kind of thing earned. */
export const kindIcon: Record<AchievementKind, string> = {
  badge: 'workspace_premium',
  level: 'trending_up',
  streak: 'local_fire_department',
  plan: 'event_available',
  quiz: 'quiz',
  memory: 'psychology',
  friend: 'handshake',
};

export function iconForKind(kind: string): string {
  return (kindIcon as Record<string, string>)[kind] ?? 'emoji_events';
}

export interface CheerState {
  cheers: number;
  cheered: boolean;
}

/**
 * The thumbs-up under something earned. The count moves the moment it is
 * tapped and is put right, or put back, when the server answers.
 */
export function CheerButton({ id, state, onChange, quiet }: { id: string; state: CheerState | null; onChange: (next: CheerState) => void; quiet?: boolean }) {
  const { account } = useAppScope();
  const busy = useRef(false);
  const cheered = state?.cheered ?? false;
  const cheers = state?.cheers ?? 0;
  const toggle = async () => {
    if (busy.current) return;
    busy.current = true;
    const before: CheerState = { cheers, cheered };
    onChange({ cheered: !cheered, cheers: Math.max(0, cheers + (cheered ? -1 : 1)) });
    try {
      onChange(await (cheered ? account.uncheer(id) : account.cheer(id)));
    } catch (error) {
      onChange(before);
      showSnackBar(messageOf(error));
    } finally {
      busy.current = false;
    }
  };
  return (
    <Button
      variant={cheered ? 'tonal' : 'text'}
      icon={cheered ? 'thumb_up' : 'thumb_up_outlined'}
      aria-pressed={cheered}
      aria-label={cheered ? `Cheered. ${cheers} ${cheers === 1 ? 'cheer' : 'cheers'}` : `Cheer. ${cheers} ${cheers === 1 ? 'cheer' : 'cheers'}`}
      onClick={() => void toggle()}
    >
      {cheers > 0 ? cheers : quiet ? '' : 'Cheer'}
    </Button>
  );
}

/** What was earned: its icon, title, the detail under it, and the cheer. */
export function AchievementBody({ achievement, cheer, onCheer }: { achievement: Achievement; cheer: CheerState | null; onCheer: (next: CheerState) => void }) {
  return (
    <>
      <div class="ow-feed-item__what">
        <Icon name={iconForKind(achievement.kind)} />
        <span>{achievement.title}</span>
      </div>
      {achievement.detail && <div class="ow-feed-item__detail">{achievement.detail}</div>}
      <div class="ow-feed-item__cheer">
        <CheerButton id={achievement.id} state={cheer} onChange={onCheer} />
      </div>
    </>
  );
}

function FeedRow({ item, now, onCheer, onOpen }: { item: FeedItem; now: Date; onCheer: (next: CheerState) => void; onOpen?: (username: string) => void }) {
  const who = <Avatar user={item.user} size={40} />;
  return (
    <div class="ow-feed-item">
      {item.mine || !onOpen ? (
        <span class="ow-feed-item__who">{who}</span>
      ) : (
        <button type="button" class="ow-feed-item__who m3-interactive" aria-label={`${item.user.displayName}’s profile`} onClick={() => onOpen(item.user.username)}>
          {who}
        </button>
      )}
      <div class="ow-feed-item__main">
        <div class="ow-feed-item__head">
          <span class="ow-feed-item__name">{item.user.displayName}</span>
          {item.mine && <Pill kind="you">You</Pill>}
          <span class="ow-feed-item__when">{relativeTime(item.earnedAt, now)}</span>
        </div>
        <AchievementBody achievement={item} cheer={item} onCheer={onCheer} />
      </div>
    </div>
  );
}

/**
 * The achievements feed: what you and your friends have earned, newest
 * first, more loading as the end comes into view.
 */
export function FeedTab({ refreshKey = 0, onOpenProfile, onFindFriends }: { refreshKey?: number; onOpenProfile?: (username: string) => void; onFindFriends?: () => void }) {
  const { account } = useAppScope();
  useNotifier(account);
  const [items, setItems] = useState<FeedItem[] | null>(null);
  const [next, setNext] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [moreFailed, setMoreFailed] = useState(false);
  const generation = useRef(0);
  const sentinel = useRef<HTMLDivElement>(null);
  const userId = account.user?.id;

  const load = useCallback(async () => {
    const mine = ++generation.current;
    setError(null);
    try {
      const page = await account.feed();
      if (mine !== generation.current) return;
      setItems(page.items);
      setNext(page.nextBefore);
      setMoreFailed(false);
      paged.current = false;
    } catch (e) {
      if (mine !== generation.current) return;
      setError(messageOf(e));
    }
  }, [account]);

  useEffect(() => {
    void load();
  }, [load, refreshKey, userId]);

  // What this device has just told the server belongs at the top: when a
  // sync lands, the first page is fetched again — unless the reader has
  // gone further down, where swapping the list would lose their place.
  const syncedAt = account.lastSyncedAt?.getTime() ?? 0;
  const firstSync = useRef(syncedAt);
  const paged = useRef(false);
  useEffect(() => {
    if (syncedAt === firstSync.current) return;
    firstSync.current = syncedAt;
    if (!paged.current) void load();
  }, [syncedAt, load]);

  const more = useCallback(async () => {
    if (next === null || loadingMore) return;
    const mine = generation.current;
    setLoadingMore(true);
    try {
      const page = await account.feed(next);
      if (mine !== generation.current) return;
      setItems((have) => {
        const seen = new Set((have ?? []).map((i) => i.id));
        return [...(have ?? []), ...page.items.filter((i) => !seen.has(i.id))];
      });
      setNext(page.nextBefore);
      setMoreFailed(false);
      paged.current = true;
    } catch {
      if (mine === generation.current) setMoreFailed(true);
    } finally {
      setLoadingMore(false);
    }
  }, [account, next, loadingMore]);

  // The next page is fetched as the end of this one scrolls into view.
  useEffect(() => {
    const el = sentinel.current;
    if (!el || next === null || moreFailed || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) void more();
    }, { rootMargin: '400px' });
    observer.observe(el);
    return () => observer.disconnect();
  }, [more, next, moreFailed, items?.length]);

  const setCheer = (id: string, state: CheerState) => setItems((have) => have?.map((i) => (i.id === id ? { ...i, ...state } : i)) ?? have);

  if (items === null) return error ? <LoadError message={error} onRetry={() => void load()} /> : <Loading />;
  if (items.length === 0) {
    return (
      <div class="ow-social">
        <EmptyState
          icon="celebration"
          title="Nothing to cheer yet"
          actions={onFindFriends && account.counts.friends === 0 ? <TonalButton icon="person_add" onClick={onFindFriends}>Find friends</TonalButton> : undefined}
        >
          Badges, new levels, streaks and finished plans show up here as you and your friends earn them.
        </EmptyState>
      </div>
    );
  }
  const now = new Date();
  return (
    <div class="ow-social">
      {error && <div class="ow-social-banner"><Icon name="cloud_off" />{error}</div>}
      {items.map((item) => (
        <FeedRow key={item.id} item={item} now={now} onCheer={(state) => setCheer(item.id, state)} onOpen={onOpenProfile} />
      ))}
      <div ref={sentinel} />
      {next !== null ? (
        <div class="ow-feed-end">
          {moreFailed ? <TonalButton icon="refresh" onClick={() => void more()}>Load more</TonalButton> : <Loading />}
        </div>
      ) : (
        <div class="ow-feed-end">That’s everything so far.</div>
      )}
    </div>
  );
}
