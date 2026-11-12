import type { ComponentChildren } from 'preact';
import { IconButton } from './buttons';
import { nav } from './overlay';

export interface AppBarProps {
  title?: ComponentChildren;
  subtitle?: ComponentChildren;
  /** The leading icon button; `back` is the usual, `close` for a full sheet. */
  leading?: 'back' | 'close' | 'none' | ComponentChildren;
  onLeading?: () => void;
  actions?: ComponentChildren;
  centerTitle?: boolean;
  /** True while the body underneath has scrolled, to tint the bar. */
  scrolled?: boolean;
  class?: string;
}

/** Material's top app bar. Pair with `Screen`, which feeds it `scrolled`. */
export function AppBar({ title, subtitle, leading = 'back', onLeading, actions, centerTitle, scrolled, class: cls }: AppBarProps) {
  const lead =
    leading === 'back' ? (
      <IconButton icon="arrow_back" label="Back" onClick={onLeading ?? (() => nav.pop())} />
    ) : leading === 'close' ? (
      <IconButton icon="close" label="Close" onClick={onLeading ?? (() => nav.pop())} />
    ) : leading === 'none' ? (
      <span style="width:12px" />
    ) : (
      leading
    );
  return (
    <header class={`m3-app-bar${scrolled ? ' m3-app-bar--scrolled' : ''}${centerTitle ? ' m3-app-bar--center' : ''}${cls ? ` ${cls}` : ''}`}>
      {lead}
      <div class="m3-app-bar__title">
        {title}
        {subtitle && <span class="m3-app-bar__subtitle">{subtitle}</span>}
      </div>
      <div class="m3-app-bar__actions">{actions}</div>
    </header>
  );
}
