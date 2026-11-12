import type { ComponentChildren } from 'preact';
import { CircularProgress, FilledButton, Icon, ListTile, OutlinedButton, TonalButton } from '../m3';
import { showSignIn } from './signInSheet';
import './social.css';

/** The middle of a tab with nothing in it yet: a mark, a line or two, something to do. */
export function EmptyState({ icon, title, children, actions }: { icon: string; title: string; children?: ComponentChildren; actions?: ComponentChildren }) {
  return (
    <div class="ow-social-empty">
      <div class="ow-social-empty__mark">
        <Icon name={icon} />
      </div>
      <div class="ow-social-empty__title">{title}</div>
      {children && <div class="ow-social-empty__body">{children}</div>}
      {actions && <div class="ow-social-empty__actions">{actions}</div>}
    </div>
  );
}

export function Loading() {
  return (
    <div class="ow-social-loading" role="status" aria-label="Loading">
      <CircularProgress />
    </div>
  );
}

/** Something could not be loaded: what, and a way to try again. */
export function LoadError({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <EmptyState icon="cloud_off" title="Couldn’t load this" actions={<TonalButton icon="refresh" onClick={onRetry}>Try again</TonalButton>}>
      {message}
    </EmptyState>
  );
}

/** A flame and a number: a streak in days. Grey when there is none. */
export function Flame({ days, label }: { days: number; label?: string }) {
  return (
    <span class={`ow-flame${days > 0 ? '' : ' ow-flame--out'}`} aria-label={label ?? `${days}-day streak`}>
      <Icon name="local_fire_department" />
      {days}
    </span>
  );
}

/** A small label that is not a button: "You", a shared streak, a warning. */
export function Pill({ kind, icon, children }: { kind?: 'you' | 'together' | 'risk'; icon?: string; children: ComponentChildren }) {
  return (
    <span class={`ow-pill${kind ? ` ow-pill--${kind}` : ''}`}>
      {icon && <Icon name={icon} />}
      {children}
    </span>
  );
}

/**
 * For someone with no account: what one is for, that it is optional, and
 * the two ways in.
 */
export function SignedOutInvite({ title = 'Learn alongside friends' }: { title?: string }) {
  return (
    <div class="ow-social">
      <EmptyState
        icon="diversity_3"
        title={title}
        actions={
          <>
            <FilledButton onClick={() => void showSignIn('register')}>Create account</FilledButton>
            <OutlinedButton onClick={() => void showSignIn('login')}>Sign in</OutlinedButton>
          </>
        }
      >
        OpenWord works without an account, and always will. With one, you can:
      </EmptyState>
      <div class="ow-social-perks">
        <ListTile static icon="local_fire_department" title="Keep a streak with a friend" subtitle="It grows on the days you both learn." />
        <ListTile static icon="thumb_up" title="Cheer each other on" subtitle="See badges and milestones as friends earn them." />
        <ListTile static icon="notifications_active" title="Get a reminder" subtitle="A nudge at the time you choose, before a streak slips." />
        <ListTile static icon="cloud_done" title="Keep a backup" subtitle="Your notes, plans and progress, ready for a new device." />
      </div>
    </div>
  );
}
