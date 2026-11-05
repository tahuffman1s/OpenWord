import type { ComponentChildren } from 'preact';
import { useRef } from 'preact/hooks';
import { IconButton, type IconButtonProps } from './buttons';
import { Icon, type IconName } from './icon';
import { showMenu, useOverlay } from './overlay';

export interface MenuItemProps {
  icon?: IconName | string;
  label: ComponentChildren;
  /** The value the menu settles with when this is chosen. */
  value?: unknown;
  onClick?: () => void;
  disabled?: boolean;
  checked?: boolean;
  destructive?: boolean;
}

/** One line of a menu; choosing it closes the menu with `value`. */
export function MenuItem({ icon, label, value, onClick, disabled, checked, destructive }: MenuItemProps) {
  const overlay = useOverlay();
  return (
    <button
      type="button"
      role="menuitem"
      disabled={disabled}
      class={`m3-menu-item m3-interactive${checked ? ' m3-menu-item--checked' : ''}`}
      style={destructive ? 'color:var(--md-sys-color-error)' : undefined}
      onClick={() => {
        onClick?.();
        overlay.close(value);
      }}
    >
      {checked !== undefined ? <Icon name={checked ? 'check' : ''} /> : icon ? <Icon name={icon} /> : null}
      {label}
    </button>
  );
}

export function MenuDivider() {
  return <hr class="m3-divider" style="margin:8px 0" />;
}

export interface PopupMenuButtonProps extends Omit<IconButtonProps, 'onClick' | 'icon'> {
  icon?: IconName | string;
  /** The menu's items, built when it opens. */
  items: () => ComponentChildren;
  onSelected?: (value: unknown) => void;
}

/** Flutter's PopupMenuButton: an icon button that drops a menu. */
export function PopupMenuButton({ icon = 'more_vert', items, onSelected, ...rest }: PopupMenuButtonProps) {
  const ref = useRef<HTMLButtonElement>(null);
  return (
    <IconButton
      elementRef={ref}
      icon={icon}
      {...rest}
      onClick={async () => {
        const value = await showMenu<unknown>(<>{items()}</>, ref.current!);
        if (value !== undefined) onSelected?.(value);
      }}
    />
  );
}
