import type { ComponentChildren, JSX, RefObject } from 'preact';

export interface TextFieldProps {
  value: string;
  onInput: (value: string) => void;
  onSubmit?: () => void;
  label?: string;
  placeholder?: string;
  supporting?: ComponentChildren;
  error?: boolean;
  leading?: ComponentChildren;
  trailing?: ComponentChildren;
  variant?: 'outlined' | 'filled';
  multiline?: boolean;
  rows?: number;
  type?: string;
  autoFocus?: boolean;
  autocomplete?: string;
  inputMode?: JSX.HTMLAttributes<HTMLInputElement>['inputMode'];
  maxLength?: number;
  disabled?: boolean;
  inputRef?: RefObject<HTMLInputElement | HTMLTextAreaElement>;
  class?: string;
  name?: string;
  enterKeyHint?: 'enter' | 'done' | 'go' | 'next' | 'previous' | 'search' | 'send';
}

/** Material's text field, outlined by default. */
export function TextField(p: TextFieldProps) {
  const common = {
    class: 'm3-text-field__input',
    value: p.value,
    placeholder: p.placeholder,
    disabled: p.disabled,
    autofocus: p.autoFocus,
    autocomplete: p.autocomplete,
    maxLength: p.maxLength,
    name: p.name,
    'aria-label': p.label ?? p.placeholder,
    onInput: (e: Event) => p.onInput((e.currentTarget as HTMLInputElement).value),
    onKeyDown: (e: KeyboardEvent) => {
      if (e.key === 'Enter' && !p.multiline && p.onSubmit) {
        e.preventDefault();
        p.onSubmit();
      }
    },
  };
  return (
    <label class={`m3-text-field${p.variant === 'filled' ? ' m3-text-field--filled' : ''}${p.error ? ' m3-text-field--error' : ''}${p.class ? ` ${p.class}` : ''}`}>
      <span class="m3-text-field__box">
        {p.label && <span class="m3-text-field__label">{p.label}</span>}
        {p.leading && <span class="m3-text-field__icon">{p.leading}</span>}
        {p.multiline ? (
          <textarea ref={p.inputRef as RefObject<HTMLTextAreaElement>} rows={p.rows ?? 3} {...common} />
        ) : (
          <input
            ref={p.inputRef as RefObject<HTMLInputElement>}
            type={p.type ?? 'text'}
            inputMode={p.inputMode}
            enterkeyhint={p.enterKeyHint}
            {...common}
          />
        )}
        {p.trailing && <span class="m3-text-field__icon">{p.trailing}</span>}
      </span>
      {p.supporting && <span class="m3-text-field__support">{p.supporting}</span>}
    </label>
  );
}
