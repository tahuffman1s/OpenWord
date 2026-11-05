import type { ComponentChildren, JSX, RefObject } from 'preact';
import { Icon, type IconName } from './icon';

export type ButtonVariant = 'filled' | 'tonal' | 'elevated' | 'outlined' | 'text';

export interface ButtonProps extends Omit<JSX.ButtonHTMLAttributes<HTMLButtonElement>, 'icon' | 'size'> {
  variant?: ButtonVariant;
  /** The DOM button, for anchoring a menu to it. */
  elementRef?: RefObject<HTMLButtonElement>;
  icon?: IconName | string;
  /** Tints a text/outlined button in the error colour, for "Delete". */
  destructive?: boolean;
  children?: ComponentChildren;
}

/** Material's five buttons. `variant` defaults to filled; `TextButton` etc. below are shorthands. */
export function Button({ variant = 'filled', icon, destructive, children, class: cls, elementRef, ...rest }: ButtonProps) {
  return (
    <button
      ref={elementRef}
      type="button"
      {...rest}
      class={`m3-button m3-button--${variant} m3-interactive${destructive ? ' m3-button--error' : ''}${cls ? ` ${cls}` : ''}`}
    >
      {icon && <Icon name={icon} />}
      {children}
    </button>
  );
}

export const FilledButton = (p: ButtonProps) => <Button {...p} variant="filled" />;
export const TonalButton = (p: ButtonProps) => <Button {...p} variant="tonal" />;
export const ElevatedButton = (p: ButtonProps) => <Button {...p} variant="elevated" />;
export const OutlinedButton = (p: ButtonProps) => <Button {...p} variant="outlined" />;
export const TextButton = (p: ButtonProps) => <Button {...p} variant="text" />;

export interface IconButtonProps extends Omit<JSX.ButtonHTMLAttributes<HTMLButtonElement>, 'icon' | 'size'> {
  icon: IconName | string;
  /** Required: what the button does, read by screen readers and shown as a tooltip. */
  label: string;
  variant?: 'standard' | 'filled' | 'tonal' | 'outlined';
  selected?: boolean;
  size?: 'small' | 'standard' | 'large';
  iconSize?: number;
  /** The DOM button, for anchoring a menu to it. */
  elementRef?: RefObject<HTMLButtonElement>;
}

export function IconButton({ icon, label, variant = 'standard', selected, size = 'standard', iconSize, class: cls, elementRef, ...rest }: IconButtonProps) {
  return (
    <button
      ref={elementRef}
      type="button"
      aria-label={label}
      title={label}
      aria-pressed={selected}
      {...rest}
      class={`m3-icon-button m3-interactive${variant !== 'standard' ? ` m3-icon-button--${variant}` : ''}${selected ? ' m3-icon-button--selected' : ''}${size !== 'standard' ? ` m3-icon-button--${size}` : ''}${cls ? ` ${cls}` : ''}`}
    >
      <Icon name={icon} size={iconSize} />
    </button>
  );
}

export interface FabProps extends Omit<JSX.ButtonHTMLAttributes<HTMLButtonElement>, 'icon' | 'size'> {
  icon: IconName | string;
  label?: string;
  size?: 'small' | 'standard';
  color?: 'primary' | 'tertiary' | 'surface';
}

/** A floating action button; with `label` it is the extended kind. */
export function Fab({ icon, label, size = 'standard', color = 'primary', class: cls, ...rest }: FabProps) {
  return (
    <button
      type="button"
      aria-label={label}
      {...rest}
      class={`m3-fab m3-interactive${size === 'small' ? ' m3-fab--small' : ''}${color !== 'primary' ? ` m3-fab--${color}` : ''}${cls ? ` ${cls}` : ''}`}
    >
      <Icon name={icon} />
      {label}
    </button>
  );
}
