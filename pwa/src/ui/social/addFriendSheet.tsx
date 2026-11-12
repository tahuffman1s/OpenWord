import { useEffect, useRef, useState } from 'preact/hooks';
import { useAppScope } from '../../app/scope';
import type { Relation, SearchResult } from '../../data/api';
import { FilledButton, Icon, ListTile, Sheet, TextField, TonalButton, showSheet, showSnackBar } from '../m3';
import { Avatar } from './avatar';
import { messageOf } from './errors';
import { EmptyState, Loading, Pill } from './parts';
import './social.css';

/** Opens the search for someone to add; settles when it is closed. */
export function showAddFriend(): Promise<void> {
  return showSheet<void>(<AddFriendSheet />, { full: true }).then(() => undefined);
}

/** How long after the last keystroke the search runs. */
const searchDelay = 300;

/**
 * Find someone by username or name and ask to be friends, with a line to
 * say who you are if you like.
 */
export function AddFriendSheet() {
  const { account } = useAppScope();
  const [query, setQuery] = useState('');
  const [message, setMessage] = useState('');
  const [results, setResults] = useState<SearchResult[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const latest = useRef(0);

  useEffect(() => {
    const q = query.trim();
    const mine = ++latest.current;
    if (q.length === 0) {
      setResults(null);
      setSearching(false);
      setError(null);
      return;
    }
    setSearching(true);
    const timer = setTimeout(async () => {
      try {
        const found = await account.searchUsers(q);
        if (mine !== latest.current) return;
        setResults(found);
        setError(null);
      } catch (e) {
        if (mine !== latest.current) return;
        setError(messageOf(e));
      } finally {
        if (mine === latest.current) setSearching(false);
      }
    }, searchDelay);
    return () => clearTimeout(timer);
  }, [query, account]);

  const setRelation = (id: string, relation: Relation) => setResults((have) => have?.map((u) => (u.id === id ? { ...u, relation } : u)) ?? have);

  const ask = async (user: SearchResult) => {
    setBusy(user.id);
    try {
      const outcome = await account.sendRequest(user.username, message);
      if (outcome.friend) {
        setRelation(user.id, 'friend');
        showSnackBar(`You and ${user.displayName} are now friends`);
      } else {
        setRelation(user.id, 'requested');
        showSnackBar(`Request sent to ${user.displayName}`);
      }
    } catch (e) {
      showSnackBar(messageOf(e));
    } finally {
      setBusy(null);
    }
  };
  const action = (user: SearchResult) => {
    switch (user.relation) {
      case 'friend':
        return <Pill icon="check">Friends</Pill>;
      case 'requested':
        return <Pill>Requested</Pill>;
      case 'incoming':
        return <FilledButton disabled={busy === user.id} onClick={() => void ask(user)}>Accept</FilledButton>;
      default:
        return <TonalButton icon="person_add" disabled={busy === user.id} onClick={() => void ask(user)}>Add</TonalButton>;
    }
  };

  return (
    <Sheet
      title="Add a friend"
      header={
        <div class="ow-form" style="padding-bottom:12px">
          <TextField
            placeholder="Search by username or name"
            value={query}
            onInput={setQuery}
            leading={<Icon name="search" />}
            autoFocus
            autocomplete="off"
            maxLength={64}
            enterKeyHint="search"
          />
          <TextField
            label="Add a note (optional)"
            value={message}
            onInput={setMessage}
            maxLength={200}
            supporting="Sent with your request, so they know who’s asking."
          />
        </div>
      }
    >
      {query.trim().length === 0 ? (
        <EmptyState icon="person_add" title="Find someone you know">
          Friends see your streak and what you earn, and you see theirs. Nothing else is shared.
        </EmptyState>
      ) : results === null ? (
        error ? <EmptyState icon="cloud_off" title="Couldn’t search">{error}</EmptyState> : <Loading />
      ) : results.length === 0 ? (
        <EmptyState icon="search" title="No one by that name">
          Check the spelling, or ask them for their username.
        </EmptyState>
      ) : (
        <div style={searching ? 'opacity:0.6' : undefined}>
          {results.map((user) => (
            <ListTile
              key={user.id}
              static
              leading={<Avatar user={user} size={40} />}
              title={user.displayName}
              subtitle={`@${user.username}`}
              trailing={action(user)}
            />
          ))}
        </div>
      )}
    </Sheet>
  );
}
