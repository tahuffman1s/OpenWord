import { useRef } from 'preact/hooks';
import type { ReadingStore } from '../data/marks';
import { useNotifier } from '../infra/changeNotifier';
import { SleepMode, sleepModeDescription, sleepModeLabel, sleepModes } from '../model/sleepPolicy';
import { Icon, ListTile, MenuItem, Sheet, showMenu, showSheet } from './m3';
import { RadioListTile } from './widgets/listTiles';
import './shared.css';

/**
 * Choosing how new verses are timed against sleep, and when evening
 * and morning are for this reader.
 */
export function showSleepPolicySheet(reading: ReadingStore): Promise<void> {
  return showSheet<void>(<SleepPolicySheet reading={reading} />, { name: 'sleep' }).then(() => undefined);
}

function SleepPolicySheet({ reading }: { reading: ReadingStore }) {
  useNotifier(reading);
  const policy = reading.sleepPolicy;
  const range = (from: number, to: number): number[] => Array.from({ length: to - from + 1 }, (_, i) => from + i);
  return (
    <Sheet title="Sleep and new verses">
      <p class="ow-sheet-lead">
        A night’s sleep soon after learning helps memory settle: in studies, a verse learnt in the evening and asked for
        next morning is relearnt faster and kept longer. The app can time new verses that way, and measure whether it
        works for you.
      </p>
      <div role="radiogroup">
        {sleepModes.map((mode) => (
          <RadioListTile
            key={mode}
            checked={policy.mode === mode}
            title={sleepModeLabel[mode]}
            subtitle={sleepModeDescription[mode]}
            onSelect={() => reading.setSleepPolicy(policy.copyWith({ mode }))}
          />
        ))}
      </div>
      {policy.mode !== SleepMode.off && (
        <>
          <HourTile
            id="evening"
            title="Evening begins"
            subtitle="Night verses are offered from here."
            hour={policy.eveningStart}
            hours={range(16, 23)}
            onChanged={(h) => reading.setSleepPolicy(policy.copyWith({ eveningStart: h }))}
          />
          <HourTile
            id="morning"
            title="Morning ends"
            subtitle="Last night’s verses are best recalled before."
            hour={policy.morningEnd}
            hours={range(7, 13)}
            onChanged={(h) => reading.setSleepPolicy(policy.copyWith({ morningEnd: h }))}
          />
        </>
      )}
    </Sheet>
  );
}

/** One of the two hours, with the dropdown that changes it. */
function HourTile({ id, title, subtitle, hour, hours, onChanged }: { id: string; title: string; subtitle: string; hour: number; hours: number[]; onChanged: (hour: number) => void }) {
  const button = useRef<HTMLButtonElement>(null);
  const choose = async (): Promise<void> => {
    const anchor = button.current;
    if (anchor === null) return;
    const chosen = await showMenu<number>(
      <>
        {hours.map((h) => (
          <MenuItem key={h} label={hourLabel(h)} value={h} />
        ))}
      </>,
      anchor,
    );
    if (chosen !== undefined) onChanged(chosen);
  };
  return (
    <ListTile
      static
      data-key={id}
      title={title}
      subtitle={subtitle}
      trailing={
        <button ref={button} type="button" class="ow-dropdown m3-interactive" aria-haspopup="menu" aria-label={`${title}: ${hourLabel(hour)}`} onClick={choose}>
          {hourLabel(hour)}
          <Icon name="arrow_drop_down" />
        </button>
      }
    />
  );
}

/** The hour as a reader reads it: "7 pm". */
export function hourLabel(hour: number): string {
  return hour === 0 ? '12 am' : hour < 12 ? `${hour} am` : hour === 12 ? '12 pm' : `${hour - 12} pm`;
}
