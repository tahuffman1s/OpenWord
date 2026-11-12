import type { ComponentChildren, JSX } from 'preact';

export interface CardProps extends Omit<JSX.HTMLAttributes<HTMLDivElement>, 'children'> {
  variant?: 'filled' | 'outlined' | 'elevated' | 'low' | 'primary' | 'secondary' | 'tertiary';
  children?: ComponentChildren;
  onClick?: (e: MouseEvent) => void;
}

/** A card. With `onClick` it is a button. */
export function Card({ variant = 'low', children, class: cls, onClick, ...rest }: CardProps) {
  const classes = `m3-card${variant !== 'low' ? ` m3-card--${variant}` : ''}${onClick ? ' m3-card--clickable m3-interactive' : ''}${cls ? ` ${cls}` : ''}`;
  if (onClick) {
    return (
      <button type="button" class={classes} onClick={onClick} {...(rest as unknown as JSX.ButtonHTMLAttributes<HTMLButtonElement>)}>
        {children}
      </button>
    );
  }
  return (
    <div class={classes} {...rest}>
      {children}
    </div>
  );
}
