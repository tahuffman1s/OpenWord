import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import { useAppScope } from '../../app/scope';
import { everyDay, type AccountController } from '../../data/account';
import { useNotifier } from '../../infra/changeNotifier';
import { isStandalone } from '../../pwa/install';
import { notificationPermission, pushSupported } from '../../pwa/notifications';
import {
  AlertDialog,
  Card,
  Chip,
  ChipRow,
  CircularProgress,
  DialogAction,
  Divider,
  FilledButton,
  Icon,
  IconButton,
  ListTile,
  OutlinedButton,
  SectionHeader,
  Sheet,
  TextButton,
  TextField,
  TonalButton,
  alert,
  confirm,
  showDialog,
  showSheet,
  showSnackBar,
  useOverlay,
} from '../m3';
import { showInstallGuide } from '../tutorial/installGuide';
import { SwitchListTile } from '../widgets/listTiles';
import { Avatar } from './avatar';
import { fieldOf, messageOf } from './errors';
import { Loading, SignedOutInvite } from './parts';
import { relativeTime } from './relativeTime';
import { OwnStreak, syncLine } from './streakCard';
import './social.css';

export { reminderDueNow } from '../../data/account';

/** The reminder time offered when reminders are first turned on. */
const defaultReminderTime = '07:30';

const weekdays: readonly { bit: number; label: string; name: string }[] = [
  { bit: 1, label: 'Mon', name: 'Monday' },
  { bit: 2, label: 'Tue', name: 'Tuesday' },
  { bit: 4, label: 'Wed', name: 'Wednesday' },
  { bit: 8, label: 'Thu', name: 'Thursday' },
  { bit: 16, label: 'Fri', name: 'Friday' },
  { bit: 32, label: 'Sat', name: 'Saturday' },
  { bit: 64, label: 'Sun', name: 'Sunday' },
];

/** "every day", "on weekdays", "on Mon, Wed and Fri". */
export function daysPhrase(mask: number): string {
  const days = mask & everyDay;
  if (days === everyDay) return 'every day';
  if (days === 31) return 'on weekdays';
  if (days === 96) return 'at weekends';
  if (days === 0) return 'on no days yet';
  const names = weekdays.filter((d) => (days & d.bit) !== 0).map((d) => d.label);
  return `on ${names.length === 1 ? names[0] : `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`}`;
}

/** `07:30` → "7:30 am", in the reader's own way of writing the time. */
export function timePhrase(time: string): string {
  const m = /^(\d{1,2}):(\d{2})$/.exec(time);
  if (!m) return time;
  try {
    return new Date(2000, 0, 1, Number(m[1]), Number(m[2])).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  } catch {
    return time;
  }
}

/**
 * "You": the profile, the streak as it is kept, reminders, the backup, and
 * the ways out. For a reader with no account, what one is for.
 */
export function AccountTab() {
  const { account, reading } = useAppScope();
  useNotifier(account, reading);
  if (account.status === 'loading') return <Loading />;
  if (!account.isSignedIn || account.user === null) return <SignedOutInvite title="An account, if you’d like one" />;
  const sync = syncLine(account);
  return (
    <div class="ow-social">
      {account.status === 'offline' && (
        <div class="ow-social-banner">
          <Icon name="cloud_off" />
          You’re offline. Changes here need a connection; your learning is saved on this device as always.
        </div>
      )}
      <ProfileHeader account={account} />

      <Card variant="outlined" class="ow-streak-card">
        <OwnStreak reading={reading} />
        <div class="ow-streak-card__sync">
          <Icon name={sync.icon} />
          <span>{sync.text}</span>
        </div>
      </Card>

      <SectionHeader>Reminders</SectionHeader>
      <Reminders account={account} />

      <SectionHeader>Backup</SectionHeader>
      <Backup account={account} />

      <SectionHeader>Account</SectionHeader>
      <ListTile icon="lock" title="Change password" onClick={() => void showSheet(<ChangePasswordSheet />)} />
      <ListTile
        icon="logout"
        title="Sign out"
        subtitle="Everything you’ve saved stays on this device."
        onClick={async () => {
          const sure = await confirm({
            title: 'Sign out?',
            body: 'Your notes, plans and progress stay on this device. Friends, reminders and backup pause until you sign in again.',
            confirmLabel: 'Sign out',
          });
          if (!sure) return;
          await account.logout();
          showSnackBar('Signed out');
        }}
      />
      <ListTile
        class="ow-danger"
        icon="delete"
        title="Delete account"
        subtitle="Removes your account, friends and backup from the server."
        onClick={async () => {
          const gone = await showDialog<boolean>(<DeleteAccountDialog />, { dismissible: false });
          if (gone) showSnackBar('Your account has been deleted');
        }}
      />
    </div>
  );
}

// --------------------------------------------------------------- profile

function ProfileHeader({ account }: { account: AccountController }) {
  const user = account.user!;
  const input = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  const picked = async (event: Event) => {
    const el = event.currentTarget as HTMLInputElement;
    const file = el.files?.[0];
    // So choosing the same picture again still fires a change.
    el.value = '';
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      showSnackBar('Choose a picture: a photo or an image file.');
      return;
    }
    setUploading(true);
    try {
      await account.uploadAvatar(file);
      showSnackBar('Photo updated');
    } catch (error) {
      showSnackBar(messageOf(error));
    } finally {
      setUploading(false);
    }
  };

  return (
    <div class="ow-profile-head">
      <div class="ow-profile-photo">
        <Avatar user={user} size={96} />
        {uploading && (
          <span class="ow-profile-photo__busy">
            <CircularProgress size={32} />
          </span>
        )}
        <IconButton
          class="ow-profile-photo__edit"
          icon="photo_camera"
          label={user.avatarVersion > 0 ? 'Change photo' : 'Add a photo'}
          variant="tonal"
          size="small"
          disabled={uploading}
          onClick={() => input.current?.click()}
        />
        <input ref={input} type="file" accept="image/*" class="ow-sr-only" tabIndex={-1} aria-hidden="true" onChange={(e) => void picked(e)} />
      </div>
      <div class="ow-profile-head__name">{user.displayName}</div>
      <div class="m3-body-medium ow-social-muted">@{user.username}</div>
      {user.bio && <div class="ow-profile-head__bio">{user.bio}</div>}
      <div class="ow-profile-head__actions">
        <OutlinedButton icon="edit" onClick={() => void showSheet(<EditProfileSheet />)}>
          Edit profile
        </OutlinedButton>
      </div>
    </div>
  );
}

function EditProfileSheet() {
  const { account } = useAppScope();
  useNotifier(account);
  const overlay = useOverlay();
  const user = account.user;
  const [displayName, setDisplayName] = useState(user?.displayName ?? '');
  const [bio, setBio] = useState(user?.bio ?? '');
  const [email, setEmail] = useState(user?.email ?? '');
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  if (!user) return <Sheet title="Edit profile">{null}</Sheet>;

  const save = async () => {
    const found: Record<string, string> = {};
    if (displayName.trim().length === 0) found['displayName'] = 'Your name can’t be empty.';
    if (bio.length > 160) found['bio'] = 'At most 160 characters.';
    if (email.trim().length > 0 && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) found['email'] = 'That doesn’t look like an email address.';
    setErrors(found);
    if (Object.keys(found).length > 0) return;
    setBusy(true);
    try {
      await account.updateProfile({ displayName: displayName.trim(), bio: bio.trim(), email: email.trim().length > 0 ? email.trim() : null });
      showSnackBar('Profile saved');
      overlay.close(true);
    } catch (error) {
      const field = fieldOf(error);
      setErrors(field && ['displayName', 'bio', 'email'].includes(field) ? { [field]: messageOf(error) } : { form: messageOf(error) });
    } finally {
      setBusy(false);
    }
  };

  const removePhoto = async () => {
    const sure = await confirm({ title: 'Remove your photo?', body: 'Friends will see your initials instead.', confirmLabel: 'Remove', destructive: true });
    if (!sure) return;
    try {
      await account.removeAvatar();
      showSnackBar('Photo removed');
    } catch (error) {
      showSnackBar(messageOf(error));
    }
  };

  return (
    <Sheet title="Edit profile">
      <form
        class="ow-form"
        onSubmit={(e) => {
          e.preventDefault();
          void save();
        }}
      >
        <TextField
          label="Display name"
          value={displayName}
          onInput={setDisplayName}
          maxLength={40}
          autocomplete="name"
          error={!!errors['displayName']}
          supporting={errors['displayName'] || 'The name friends see.'}
        />
        <TextField
          label="About you"
          value={bio}
          onInput={setBio}
          multiline
          rows={3}
          maxLength={160}
          error={!!errors['bio']}
          supporting={errors['bio'] || `${bio.length} of 160. What you’re reading, perhaps.`}
        />
        <TextField
          label="Email (optional)"
          type="email"
          inputMode="email"
          autocomplete="email"
          value={email}
          onInput={setEmail}
          error={!!errors['email']}
          supporting={errors['email'] || 'For reminders and password help. Never shown to anyone.'}
        />
        {errors['form'] && (
          <div class="ow-form__error" role="alert">
            <Icon name="error_outline" />
            <span>{errors['form']}</span>
          </div>
        )}
        <div class="ow-form__actions">
          {user.avatarVersion > 0 && (
            <TextButton destructive onClick={() => void removePhoto()}>
              Remove photo
            </TextButton>
          )}
          <span class="ow-spacer" />
          <TextButton onClick={() => overlay.close()}>Cancel</TextButton>
          <FilledButton type="submit" disabled={busy}>
            {busy ? 'Saving…' : 'Save'}
          </FilledButton>
        </div>
      </form>
    </Sheet>
  );
}

// ------------------------------------------------------------- reminders

function Reminders({ account }: { account: AccountController }) {
  const settings = account.settings;
  const [time, setTime] = useState(settings?.reminderTime ?? defaultReminderTime);
  const pending = useRef<ReturnType<typeof setTimeout> | null>(null);
  const serverTime = settings?.reminderTime ?? null;
  // The server's answer wins, unless the reader is in the middle of choosing.
  useEffect(() => {
    if (serverTime !== null && pending.current === null) setTime(serverTime);
  }, [serverTime]);
  useEffect(
    () => () => {
      if (pending.current) clearTimeout(pending.current);
    },
    [],
  );
  if (!settings) return <Loading />;

  const save = (patch: Parameters<AccountController['setReminders']>[0]) => {
    account.setReminders(patch).catch((error) => showSnackBar(messageOf(error)));
  };
  const on = settings.reminderTime !== null;

  const pickTime = (value: string) => {
    setTime(value);
    if (!/^\d{2}:\d{2}$/.test(value)) return;
    // A time picker fires as each wheel settles; save once it rests.
    if (pending.current) clearTimeout(pending.current);
    pending.current = setTimeout(() => {
      pending.current = null;
      save({ reminderTime: value });
    }, 600);
  };

  return (
    <>
      <SwitchListTile
        icon="alarm"
        title="Daily reminder"
        subtitle={on ? `At ${timePhrase(settings.reminderTime!)}, ${daysPhrase(settings.reminderDays)}` : 'Off'}
        value={on}
        onChange={(value) => save({ reminderTime: value ? (/^\d{2}:\d{2}$/.test(time) ? time : defaultReminderTime) : null })}
      />
      {on && (
        <div class="ow-reminder">
          <TextField class="ow-reminder__time" type="time" label="Remind me at" value={time} onInput={pickTime} leading={<Icon name="alarm" />} />
          <ChipRow>
            {weekdays.map((day) => {
              const selected = (settings.reminderDays & day.bit) !== 0;
              return (
                <Chip
                  key={day.bit}
                  label={day.label}
                  aria-label={day.name}
                  selected={selected}
                  onClick={() => save({ reminderDays: selected ? settings.reminderDays & ~day.bit : settings.reminderDays | day.bit })}
                />
              );
            })}
          </ChipRow>
        </div>
      )}
      {on && (
        <SwitchListTile
          title="Only if I haven’t learnt yet"
          subtitle="No reminder on a day you’ve already done."
          value={settings.reminderOnlyIfUndone}
          onChange={(value) => save({ reminderOnlyIfUndone: value })}
        />
      )}
      <SwitchListTile
        icon="diversity_3"
        title="Friend streak reminders"
        subtitle="In the evening, if a streak you share is about to end."
        value={settings.friendReminders}
        onChange={(value) => save({ friendReminders: value })}
      />
      <NotificationState account={account} />
      <div class="ow-social-footnote">
        If a reminder can’t reach you, the Library will show a nudge the next time you open OpenWord after your reminder time.
      </div>
    </>
  );
}

function isIos(): boolean {
  if (typeof navigator === 'undefined') return false;
  return /iPhone|iPad|iPod/.test(navigator.userAgent) || (/Macintosh/.test(navigator.userAgent) && (navigator.maxTouchPoints ?? 0) > 1);
}

/**
 * Whether reminders can reach this device, said plainly, with the one
 * thing to do about it where there is one.
 */
function NotificationState({ account }: { account: AccountController }) {
  const [, bump] = useState(0);
  const [busy, setBusy] = useState(false);
  const supported = pushSupported();
  const permission = notificationPermission();
  const refresh = () => bump((n) => n + 1);

  const allow = async () => {
    setBusy(true);
    try {
      const outcome = await account.enablePush();
      if (outcome === 'enabled') showSnackBar('Notifications are on for this device');
      else if (outcome === 'denied') showSnackBar('Notifications are blocked. Allow them in your browser’s settings for this site.');
      else if (outcome === 'unsupported') showSnackBar('This browser can’t receive notifications.');
      else showSnackBar('Couldn’t turn notifications on. Try again in a moment.');
    } finally {
      setBusy(false);
      refresh();
    }
  };

  const test = async () => {
    setBusy(true);
    try {
      const sent = await account.sendTestPush();
      showSnackBar(sent > 0 ? 'Sent. It should arrive in a moment.' : 'Nothing was sent: no device is set up for notifications yet.');
    } catch (error) {
      showSnackBar(messageOf(error));
    } finally {
      setBusy(false);
    }
  };

  const off = async () => {
    setBusy(true);
    try {
      await account.disablePush();
      showSnackBar('Notifications are off for this device');
    } finally {
      setBusy(false);
      refresh();
    }
  };

  let icon = 'notifications';
  let title: string;
  let body: string;
  let actions: ComponentChildren = null;
  if (!supported) {
    icon = 'notifications_off';
    if (isIos() && !isStandalone()) {
      title = 'Add OpenWord to your Home Screen first';
      body = 'On iPhone and iPad, notifications only reach apps on the Home Screen (iOS 16.4 or later). In Safari, tap Share, then Add to Home Screen, and open OpenWord from there.';
      actions = (
        <TonalButton icon="add_to_home_screen" onClick={() => void showInstallGuide()}>
          Show me how
        </TonalButton>
      );
    } else if (isIos()) {
      title = 'This iPhone can’t show notifications yet';
      body = 'Notifications from Home Screen apps need iOS 16.4 or later. After updating, come back here to allow them.';
    } else {
      title = 'This browser can’t receive notifications';
      body = 'Chrome, Edge and Firefox can, on a computer or an Android phone; so can Safari on a Mac. Sign in there to get reminders on that device.';
    }
  } else if (permission === 'denied') {
    icon = 'notifications_off';
    title = 'Notifications are blocked';
    body = 'Allow notifications for OpenWord in your browser’s site settings, then come back here.';
  } else if (permission === 'granted' && account.pushEnabled) {
    icon = 'notifications_active';
    title = 'Notifications are on for this device';
    body = 'Reminders will arrive here even when OpenWord is closed.';
    actions = (
      <>
        <TonalButton icon="send" disabled={busy} onClick={() => void test()}>
          Send a test
        </TonalButton>
        <TextButton disabled={busy} onClick={() => void off()}>
          Turn off
        </TextButton>
      </>
    );
  } else {
    title = 'Reminders arrive as notifications';
    body = isIos() || !isStandalone()
      ? 'Allow them on this device and a reminder can reach you even when OpenWord is closed.'
      : 'Allow them on this device and a reminder can reach you even when the app is closed.';
    actions = (
      <FilledButton icon="notifications_active" disabled={busy} onClick={() => void allow()}>
        Allow notifications
      </FilledButton>
    );
  }

  return (
    <Card variant="filled" class="ow-notify">
      <div class="ow-notify__head">
        <Icon name={icon} />
        <div>
          <div class="ow-notify__title">{title}</div>
          <div class="ow-notify__body">{body}</div>
        </div>
      </div>
      {actions && <div class="ow-notify__actions">{actions}</div>}
    </Card>
  );
}

// ---------------------------------------------------------------- backup

function Backup({ account }: { account: AccountController }) {
  const { reading } = useAppScope();
  const [busy, setBusy] = useState<'up' | 'down' | null>(null);
  const last = account.lastBackupAt;

  const upload = async () => {
    if (!reading.hasBackupContent) {
      showSnackBar('There’s nothing to back up yet.');
      return;
    }
    setBusy('up');
    try {
      await account.uploadBackup();
      showSnackBar('Backed up to your account');
    } catch (error) {
      showSnackBar(messageOf(error));
    } finally {
      setBusy(null);
    }
  };

  const restore = async () => {
    const sure = await confirm({
      icon: 'cloud_download',
      title: 'Restore from your account?',
      body: 'This adds what’s in your account’s backup to this device. Nothing here is removed; where both have the same thing, the newer is kept.',
      confirmLabel: 'Restore',
    });
    if (!sure) return;
    setBusy('down');
    try {
      const result = await account.downloadBackup();
      if (result === null) {
        await alert('No backup yet', 'Your account has no backup. Use “Back up to my account” on the device that has your notes and progress.');
      } else if (!result.ok) {
        showSnackBar('That backup couldn’t be read.');
      } else if (result.total === 0) {
        showSnackBar('Already up to date. Nothing needed restoring.');
      } else {
        showSnackBar(`Restored: ${result.added} added, ${result.updated} updated`);
      }
    } catch (error) {
      showSnackBar(messageOf(error));
    } finally {
      setBusy(null);
    }
  };

  return (
    <>
      <ListTile
        icon="cloud_upload"
        title="Back up to my account"
        subtitle={busy === 'up' ? 'Backing up…' : last ? `Last backed up ${relativeTime(last)}` : 'Bookmarks, highlights, notes, plans, verses and progress.'}
        disabled={busy !== null}
        onClick={() => void upload()}
      />
      <ListTile
        icon="cloud_download"
        title="Restore from my account"
        subtitle={busy === 'down' ? 'Restoring…' : 'Adds your backup to this device. Nothing here is removed.'}
        disabled={busy !== null}
        onClick={() => void restore()}
      />
      <Divider />
    </>
  );
}

// ------------------------------------------------- password and deletion

function ChangePasswordSheet() {
  const { account } = useAppScope();
  const overlay = useOverlay();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [show, setShow] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);

  const save = async () => {
    const found: Record<string, string> = {};
    if (current.length === 0) found['current'] = 'Enter your current password.';
    if (next.length < 8) found['next'] = 'At least 8 characters.';
    setErrors(found);
    if (Object.keys(found).length > 0) return;
    setBusy(true);
    try {
      await account.changePassword(current, next);
      showSnackBar('Password changed');
      overlay.close(true);
    } catch (error) {
      const field = fieldOf(error);
      setErrors(field === 'password' || field === 'current' ? { current: 'That isn’t your current password.' } : field === 'next' ? { next: messageOf(error) } : { form: messageOf(error) });
    } finally {
      setBusy(false);
    }
  };

  const eye = <IconButton icon={show ? 'visibility_off' : 'visibility'} label={show ? 'Hide passwords' : 'Show passwords'} size="small" onClick={() => setShow(!show)} />;
  return (
    <Sheet title="Change password">
      <form
        class="ow-form"
        onSubmit={(e) => {
          e.preventDefault();
          void save();
        }}
      >
        <TextField
          label="Current password"
          type={show ? 'text' : 'password'}
          autocomplete="current-password"
          value={current}
          onInput={setCurrent}
          error={!!errors['current']}
          supporting={errors['current']}
          trailing={eye}
          autoFocus
        />
        <TextField
          label="New password"
          type={show ? 'text' : 'password'}
          autocomplete="new-password"
          value={next}
          onInput={setNext}
          onSubmit={() => void save()}
          error={!!errors['next']}
          supporting={errors['next'] || 'At least 8 characters. Other devices stay signed in.'}
        />
        {errors['form'] && (
          <div class="ow-form__error" role="alert">
            <Icon name="error_outline" />
            <span>{errors['form']}</span>
          </div>
        )}
        <div class="ow-form__actions">
          <TextButton onClick={() => overlay.close()}>Cancel</TextButton>
          <FilledButton type="submit" disabled={busy}>
            {busy ? 'Saving…' : 'Change password'}
          </FilledButton>
        </div>
      </form>
    </Sheet>
  );
}

function DeleteAccountDialog() {
  const { account } = useAppScope();
  const overlay = useOverlay();
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const remove = async () => {
    if (password.length === 0) {
      setError('Enter your password to confirm.');
      return;
    }
    setBusy(true);
    try {
      await account.deleteAccount(password);
      overlay.close(true);
    } catch (e) {
      setError(fieldOf(e) === 'password' ? 'That isn’t your password.' : messageOf(e));
      setBusy(false);
    }
  };

  return (
    <AlertDialog
      icon="delete"
      title="Delete your account?"
      actions={
        <>
          <DialogAction result={false}>Cancel</DialogAction>
          <TextButton destructive disabled={busy} onClick={() => void remove()}>
            {busy ? 'Deleting…' : 'Delete account'}
          </TextButton>
        </>
      }
    >
      <p style="margin:0 0 16px">
        This removes your account from the server for good: your profile, friends, shared streaks, achievements and backup. What’s on this device stays.
      </p>
      <TextField
        label="Password"
        type="password"
        autocomplete="current-password"
        value={password}
        onInput={(v) => {
          setPassword(v);
          setError(null);
        }}
        onSubmit={() => void remove()}
        error={error !== null}
        supporting={error ?? 'Enter your password to confirm.'}
      />
    </AlertDialog>
  );
}
