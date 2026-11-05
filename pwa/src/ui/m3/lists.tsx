import type { ComponentChildren, JSX } from 'preact';
import { Icon, type IconName } from './icon';

export interface ListTileProps extends Omit<JSX.ButtonHTMLAttributes<HTMLButtonElement>, 'title' | 'icon'> {
  leading?: ComponentChildren;
  /** A leading icon by name, for the common case. */
  icon?: IconName | string;
  title: ComponentChildren;
  subtitle?: ComponentChildren;
  trailing?: ComponentChildren;
  selected?: boolean;
  dense?: boolean;
  threeLine?: boolean;
  /** Renders as a plain div rather than a button when there is nothing to tap. */
  static?: boolean;
}

/** Flutter's ListTile. A button when it has an onClick, a div otherwise. */
export function ListTile({ leading, icon, title, subtitle, trailing, selected, dense, threeLine, static: isStatic, class: cls, onClick, ...rest }: ListTileProps) {
  const classes = `m3-list-tile${onClick && !isStatic ? ' m3-interactive' : ''}${selected ? ' m3-list-tile--selected' : ''}${dense ? ' m3-list-tile--dense' : ''}${threeLine ? ' m3-list-tile--three' : ''}${cls ? ` ${cls}` : ''}`;
  const inner = (
    <>
      {(leading || icon) && <span class="m3-list-tile__leading">{leading ?? <Icon name={icon!} />}</span>}
      <span class="m3-list-tile__content">
        <span class="m3-list-tile__title">{title}</span>
        {subtitle && <span class="m3-list-tile__subtitle">{subtitle}</span>}
      </span>
      {trailing && <span class="m3-list-tile__trailing">{trailing}</span>}
    </>
  );
  if (isStatic || !onClick) {
    return (
      <div class={classes} aria-selected={selected} {...(rest as unknown as JSX.HTMLAttributes<HTMLDivElement>)}>
        {inner}
      </div>
    );
  }
  return (
    <button type="button" class={classes} aria-selected={selected} onClick={onClick} {...rest}>
      {inner}
    </button>
  );
}

export function SectionHeader({ children, class: cls }: { children: ComponentChildren; class?: string }) {
  return <div class={`m3-section-header${cls ? ` ${cls}` : ''}`}>{children}</div>;
}

export function Divider({ class: cls, inset }: { class?: string; inset?: boolean }) {
  return <hr class={`m3-divider${cls ? ` ${cls}` : ''}`} style={inset ? 'margin-left:16px' : undefined} />;
}
