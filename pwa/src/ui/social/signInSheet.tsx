import { useState } from 'preact/hooks';
import { useAppScope } from '../../app/scope';
import { FilledButton, Icon, IconButton, SegmentedButton, Sheet, TextField, showSheet, showSnackBar, useOverlay } from '../m3';
import { fieldOf, messageOf } from './errors';
import './social.css';

export type SignInMode = 'login' | 'register';

const usernameRule = /^[a-z0-9_]{3,24}$/;

/**
 * Sign in, or make an account. Answers true once signed in.
 *
 * The rules are checked here first so a slip is caught without a round
 * trip, and whatever the server then says is shown under the field it is
 * about. The invite code is asked for only if the server wants one.
 */
export function showSignIn(mode: SignInMode = 'login'): Promise<boolean> {
  return showSheet<boolean>(<SignInSheet initial={mode} />, { full: true }).then((done) => done === true);
}

export function SignInSheet({ initial = 'login' }: { initial?: SignInMode }) {
  const { account } = useAppScope();
  const overlay = useOverlay();
  const [mode, setMode] = useState<SignInMode>(initial);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [email, setEmail] = useState('');
  const [inviteCode, setInviteCode] = useState('');
  const [needsInvite, setNeedsInvite] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [busy, setBusy] = useState(false);
  /** What is wrong, by field; `form` for what belongs to no field. */
  const [errors, setErrors] = useState<Record<string, string>>({});

  const registering = mode === 'register';
  const clear = (field: string) => setErrors((e) => (e[field] || e['form'] ? { ...e, [field]: '', form: '' } : e));

  const check = (): Record<string, string> => {
    const found: Record<string, string> = {};
    const name = username.trim();
    if (registering) {
      if (!usernameRule.test(name.toLowerCase())) found['username'] = '3–24 characters: a–z, 0–9 and _ only.';
      if (password.length < 8) found['password'] = 'At least 8 characters.';
      if (displayName.trim().length > 40) found['displayName'] = 'At most 40 characters.';
      if (email.trim().length > 0 && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) found['email'] = 'That doesn’t look like an email address.';
      if (needsInvite && inviteCode.trim().length === 0) found['inviteCode'] = 'This server needs an invite code to join.';
    } else {
      if (name.length === 0) found['username'] = 'Enter your username or email.';
      if (password.length === 0) found['password'] = 'Enter your password.';
    }
    return found;
  };

  const submit = async () => {
    if (busy) return;
    const found = check();
    setErrors(found);
    if (Object.keys(found).length > 0) return;
    setBusy(true);
    try {
      if (registering) {
        await account.register({ username, password, displayName, email, inviteCode: needsInvite ? inviteCode : undefined });
        showSnackBar('Welcome to OpenWord. Your account is ready.');
      } else {
        const user = await account.login(username, password);
        showSnackBar(`Signed in as ${user.displayName}`);
      }
      overlay.close(true);
    } catch (error) {
      const field = fieldOf(error);
      if (field === 'inviteCode') setNeedsInvite(true);
      const known = field !== null && ['username', 'password', 'displayName', 'email', 'inviteCode'].includes(field);
      // A wrong password could as well be a wrong username: say it once, under both.
      setErrors(known && !(field === 'password' && !registering) ? { [field]: messageOf(error) } : { form: messageOf(error) });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet title={registering ? 'Create account' : 'Sign in'}>
      <form
        class="ow-form"
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        <SegmentedButton
          options={[
            { value: 'login' as SignInMode, label: 'Sign in' },
            { value: 'register' as SignInMode, label: 'Create account' },
          ]}
          selected={mode}
          onSelect={(next) => {
            setMode(next);
            setErrors({});
          }}
        />
        {registering && (
          <div class="ow-form__note">
            An account is optional. It lets you share streaks with friends, cheer each other on, get reminders and keep a backup.
          </div>
        )}
        <TextField
          label={registering ? 'Username' : 'Username or email'}
          name="username"
          autocomplete="username"
          value={username}
          onInput={(v) => {
            setUsername(registering ? v.toLowerCase() : v);
            clear('username');
          }}
          error={!!errors['username']}
          supporting={errors['username'] || (registering ? 'What friends search for. 3–24 characters: a–z, 0–9 and _.' : undefined)}
          maxLength={registering ? 24 : 254}
          autoFocus
          enterKeyHint="next"
        />
        {registering && (
          <TextField
            label="Display name"
            name="name"
            autocomplete="name"
            value={displayName}
            onInput={(v) => {
              setDisplayName(v);
              clear('displayName');
            }}
            error={!!errors['displayName']}
            supporting={errors['displayName'] || 'The name friends see. Your username if left empty.'}
            maxLength={40}
            enterKeyHint="next"
          />
        )}
        <TextField
          label="Password"
          name="password"
          type={showPassword ? 'text' : 'password'}
          autocomplete={registering ? 'new-password' : 'current-password'}
          value={password}
          onInput={(v) => {
            setPassword(v);
            clear('password');
          }}
          onSubmit={() => void submit()}
          error={!!errors['password']}
          supporting={errors['password'] || (registering ? 'At least 8 characters.' : undefined)}
          trailing={
            <IconButton
              icon={showPassword ? 'visibility_off' : 'visibility'}
              label={showPassword ? 'Hide password' : 'Show password'}
              size="small"
              onClick={() => setShowPassword(!showPassword)}
            />
          }
          enterKeyHint={registering ? 'next' : 'go'}
        />
        {registering && (
          <TextField
            label="Email (optional)"
            name="email"
            type="email"
            inputMode="email"
            autocomplete="email"
            value={email}
            onInput={(v) => {
              setEmail(v);
              clear('email');
            }}
            onSubmit={() => void submit()}
            error={!!errors['email']}
            supporting={errors['email'] || 'For reminders and password help. Never shown to anyone.'}
            enterKeyHint={needsInvite ? 'next' : 'go'}
          />
        )}
        {registering && needsInvite && (
          <TextField
            label="Invite code"
            name="invite"
            autocomplete="off"
            value={inviteCode}
            onInput={(v) => {
              setInviteCode(v);
              clear('inviteCode');
            }}
            onSubmit={() => void submit()}
            error={!!errors['inviteCode']}
            supporting={errors['inviteCode'] || 'Ask whoever runs this server for the code.'}
            enterKeyHint="go"
          />
        )}
        {errors['form'] && (
          <div class="ow-form__error" role="alert">
            <Icon name="error_outline" />
            <span>{errors['form']}</span>
          </div>
        )}
        <div class="ow-form__actions">
          <FilledButton type="submit" disabled={busy}>
            {busy ? 'One moment…' : registering ? 'Create account' : 'Sign in'}
          </FilledButton>
        </div>
      </form>
    </Sheet>
  );
}
