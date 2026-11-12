import type { ComponentChildren } from 'preact';
import { Checkbox, Radio, Switch } from '../m3/controls';
import { ListTile } from '../m3/lists';

interface TileText {
  title: ComponentChildren;
  subtitle?: ComponentChildren;
  threeLine?: boolean;
  dense?: boolean;
  class?: string;
}

/** Flutter's `RadioListTile`: the radio leads, and the whole row chooses. */
export function RadioListTile({ checked, onSelect, trailing, ...text }: TileText & { checked: boolean; onSelect: () => void; trailing?: ComponentChildren }) {
  return (
    <ListTile
      {...text}
      leading={<Radio checked={checked} onSelect={onSelect} />}
      trailing={trailing}
      onClick={onSelect}
    />
  );
}

/** Flutter's `CheckboxListTile` with the box trailing. */
export function CheckboxListTile({ value, onChange, ...text }: TileText & { value: boolean; onChange: (value: boolean) => void }) {
  return <ListTile {...text} trailing={<Checkbox value={value} onChange={onChange} />} onClick={() => onChange(!value)} />;
}

/** Flutter's `SwitchListTile`. */
export function SwitchListTile({ value, onChange, icon, ...text }: TileText & { value: boolean; onChange: (value: boolean) => void; icon?: string }) {
  return <ListTile {...text} icon={icon} trailing={<Switch value={value} onChange={onChange} />} onClick={() => onChange(!value)} />;
}
