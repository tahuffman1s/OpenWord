import type { ComponentChildren, JSX } from 'preact';
import { Icon, type IconName } from './icon';

export interface SwitchProps {
  value: boolean;
  onChange: (value: boolean) => void;
  disabled?: boolean;
  label?: string;
}

export function Switch({ value, onChange, disabled, label }: SwitchProps) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={value}
      aria-label={label}
      disabled={disabled}
      class={`m3-switch${value ? ' m3-switch--on' : ''}`}
      onClick={(e) => {
        e.stopPropagation();
        onChange(!value);
      }}
    >
      <span class="m3-switch__thumb">{value && <Icon name="check" />}</span>
    </button>
  );
}

export interface CheckboxProps {
  value: boolean;
  onChange?: (value: boolean) => void;
  disabled?: boolean;
  label?: string;
}

export function Checkbox({ value, onChange, disabled, label }: CheckboxProps) {
  return (
    <button
      type="button"
      role="checkbox"
      aria-checked={value}
      aria-label={label}
      disabled={disabled}
      class={`m3-checkbox m3-interactive${value ? ' m3-checkbox--checked' : ''}`}
      onClick={(e) => {
        e.stopPropagation();
        onChange?.(!value);
      }}
    >
      <span class="m3-checkbox__box">{value && <Icon name="check" />}</span>
    </button>
  );
}

export interface RadioProps {
  checked: boolean;
  onSelect?: () => void;
  disabled?: boolean;
  label?: string;
}

export function Radio({ checked, onSelect, disabled, label }: RadioProps) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      class={`m3-radio m3-interactive${checked ? ' m3-radio--checked' : ''}`}
      onClick={(e) => {
        e.stopPropagation();
        onSelect?.();
      }}
    >
      <span class="m3-radio__dot" />
    </button>
  );
}

export interface SliderProps {
  value: number;
  min: number;
  max: number;
  step?: number;
  onChange: (value: number) => void;
  onChangeEnd?: (value: number) => void;
  label?: string;
  disabled?: boolean;
}

export function Slider({ value, min, max, step, onChange, onChangeEnd, label, disabled }: SliderProps) {
  const fill = `${((value - min) / (max - min)) * 100}%`;
  return (
    <input
      type="range"
      class="m3-slider"
      style={{ '--m3-slider-fill': fill } as unknown as string}
      min={min}
      max={max}
      step={step ?? 'any'}
      value={value}
      aria-label={label}
      disabled={disabled}
      onInput={(e) => onChange(Number((e.currentTarget as HTMLInputElement).value))}
      onChange={(e) => onChangeEnd?.(Number((e.currentTarget as HTMLInputElement).value))}
    />
  );
}

export interface SegmentedOption<T> {
  value: T;
  label: ComponentChildren;
  icon?: IconName | string;
}

export interface SegmentedButtonProps<T> {
  options: SegmentedOption<T>[];
  selected: T;
  onSelect: (value: T) => void;
  class?: string;
}

export function SegmentedButton<T>({ options, selected, onSelect, class: cls }: SegmentedButtonProps<T>) {
  return (
    <div class={`m3-segmented${cls ? ` ${cls}` : ''}`} role="radiogroup">
      {options.map((o) => (
        <button
          type="button"
          role="radio"
          aria-checked={o.value === selected}
          class={`m3-segmented__item m3-interactive${o.value === selected ? ' m3-segmented__item--selected' : ''}`}
          onClick={() => onSelect(o.value)}
        >
          {o.value === selected ? <Icon name="check" /> : o.icon ? <Icon name={o.icon} /> : null}
          {o.label}
        </button>
      ))}
    </div>
  );
}

export interface ChipProps extends Omit<JSX.ButtonHTMLAttributes<HTMLButtonElement>, 'icon' | 'label'> {
  label: ComponentChildren;
  icon?: IconName | string;
  selected?: boolean;
  variant?: 'filter' | 'assist' | 'choice' | 'input' | 'elevated';
  onDelete?: () => void;
}

/** Filter, assist, choice and input chips. */
export function Chip({ label, icon, selected, variant = 'filter', onDelete, class: cls, ...rest }: ChipProps) {
  return (
    <button
      type="button"
      aria-pressed={variant === 'filter' || variant === 'choice' ? !!selected : undefined}
      {...rest}
      class={`m3-chip m3-interactive m3-chip--${variant}${selected ? ' m3-chip--selected' : ''}${cls ? ` ${cls}` : ''}`}
    >
      {selected && variant === 'filter' ? <Icon name="check" /> : icon ? <Icon name={icon} /> : null}
      {label}
      {onDelete && (
        <span
          role="button"
          aria-label="Remove"
          class="m3-icon"
          style="width:18px;height:18px;margin-right:-8px"
          onClick={(e) => {
            e.stopPropagation();
            onDelete();
          }}
        >
          <Icon name="close" size={18} />
        </span>
      )}
    </button>
  );
}

export function ChipRow({ children, scroll, class: cls }: { children: ComponentChildren; scroll?: boolean; class?: string }) {
  return <div class={`m3-chip-row${scroll ? ' m3-chip-row--scroll' : ''}${cls ? ` ${cls}` : ''}`}>{children}</div>;
}
