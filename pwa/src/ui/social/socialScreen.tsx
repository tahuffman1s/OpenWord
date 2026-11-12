import { useEffect, useState } from 'preact/hooks';
import { useAppScope } from '../../app/scope';
import { useNotifier } from '../../infra/changeNotifier';
import { AppBar, Fab, IconButton, NavigationBar, Screen, nav } from '../m3';
import { AccountTab } from './accountTab';
import { showAddFriend } from './addFriendSheet';
import { FeedTab } from './feedTab';
import { showFriendProfile } from './friendProfileSheet';
import { FriendsTab } from './friendsTab';
import { Loading, SignedOutInvite } from './parts';
import './social.css';

export type SocialTab = 'feed' | 'friends' | 'account';

function tabOf(name: string | undefined): SocialTab {
  return name === 'friends' || name === 'account' || name === 'feed' ? name : name === 'you' ? 'account' : 'feed';
}

/**
 * Opens the social screens on a tab: the achievements feed, friends, or
 * the reader's own account. What the reader's menu, the Library's streak
 * card and `openFlow` (`'friends'`, `'account'`) call. Settles when the
 * screen is closed.
 */
export function openSocial(tab?: SocialTab | string): Promise<void> {
  return nav.push<void>(<SocialScreen initial={tabOf(tab)} />, { name: 'social' }).then(() => undefined);
}

export function SocialScreen({ initial = 'feed' }: { initial?: SocialTab }) {
  const { account } = useAppScope();
  useNotifier(account);
  const [tab, setTab] = useState<SocialTab>(initial);
  const [refreshKey, setRefreshKey] = useState(0);
  const [spinning, setSpinning] = useState(false);
  const refresh = () => setRefreshKey((n) => n + 1);
  const signedIn = account.isSignedIn;
  const loading = account.status === 'loading';

  // Coming back to the tab with the app open for a while: ask again who
  // has asked to be a friend, so the badge is right.
  useEffect(() => {
    if (signedIn) void account.refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const reload = async () => {
    setSpinning(true);
    refresh();
    await account.refresh();
    setSpinning(false);
  };

  const addFriend = async () => {
    await showAddFriend();
    refresh();
  };

  const openProfile = async (username: string) => {
    await showFriendProfile(username);
    refresh();
  };

  const title = tab === 'feed' ? 'Friends' : tab === 'friends' ? 'Friends' : 'You';
  return (
    <Screen
      class="ow-social-screen"
      appBar={(scrolled) => (
        <AppBar
          scrolled={scrolled}
          title={title}
          subtitle={account.status === 'offline' && tab !== 'account' ? 'Offline' : undefined}
          actions={
            signedIn && tab !== 'account' ? (
              <IconButton icon="refresh" label="Refresh" disabled={spinning} onClick={() => void reload()} />
            ) : undefined
          }
        />
      )}
      fab={account.status === 'signedIn' && tab === 'friends' && account.counts.friends > 0 ? <Fab icon="person_add" label="Add friend" onClick={() => void addFriend()} /> : undefined}
      bottom={
        <NavigationBar<SocialTab>
          destinations={[
            { value: 'feed', label: 'Feed', icon: 'celebration' },
            { value: 'friends', label: 'Friends', icon: 'group', badge: signedIn ? account.counts.pendingRequests : undefined },
            { value: 'account', label: 'You', icon: 'account_circle' },
          ]}
          selected={tab}
          onSelect={setTab}
        />
      }
    >
      {loading ? (
        <Loading />
      ) : tab === 'account' ? (
        <AccountTab />
      ) : !signedIn ? (
        <SignedOutInvite title={tab === 'feed' ? 'Cheer each other on' : 'Learn alongside friends'} />
      ) : (
        <>
          {tab === 'feed' ? (
            <FeedTab refreshKey={refreshKey} onOpenProfile={(username) => void openProfile(username)} onFindFriends={() => setTab('friends')} />
          ) : (
            <FriendsTab refreshKey={refreshKey} />
          )}
        </>
      )}
    </Screen>
  );
}
