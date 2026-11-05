import { iconData, type IconName } from './iconData';

export type { IconName };

export interface IconProps {
  name: IconName | string;
  size?: number;
  class?: string;
  style?: string | Record<string, string | number>;
  label?: string;
}

/**
 * A Material icon, inline. Names are the Material icon names with the
 * rounded set as the default (`add`), and `outlined`/`filled` variants as
 * `add_outlined` / `add_filled`; the set is generated from icons.txt.
 */
export function Icon({ name, size, class: cls, style, label }: IconProps) {
  const svg = iconData[name] ?? iconData[`${name}_outlined`];
  if (!svg) console.warn(`OpenWord: no icon ${name}`);
  const sizeStyle = size ? { width: `${size}px`, height: `${size}px` } : {};
  const merged = typeof style === 'string' ? style : { ...sizeStyle, ...(style ?? {}) };
  return (
    <span
      class={`m3-icon${cls ? ` ${cls}` : ''}`}
      style={merged}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      dangerouslySetInnerHTML={{
        __html: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">${svg ?? ''}</svg>`,
      }}
    />
  );
}
