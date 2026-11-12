import { type Settings, ReadingFont, readingFontLabel } from '../data/settings';
import { Translations } from '../data/translations';
import type { TranslationInfo } from '../model/bible';
import { useNotifier } from '../infra/changeNotifier';
import { Chip, Divider, ListTile, SegmentedButton, Sheet, Slider, Switch, showSheet } from './m3';
import './displaySheet.css';

/** Opens the display sheet over the reader. */
export function showDisplaySheet(options: { settings: Settings; current: TranslationInfo }): Promise<void> {
  return showSheet(<DisplaySheet settings={options.settings} current={options.current} />, { name: 'display' }).then(() => undefined);
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}

/**
 * Quick reading controls, reachable from the reader without leaving the page,
 * plus the picker for reading two translations side by side.
 */
export function DisplaySheet({
  settings,
  current,
}: {
  settings: Settings;

  /** The translation being read, so it is not offered as its own comparison. */
  current: TranslationInfo;
}) {
  useNotifier(settings);

  const nudge = (delta: number) => {
    settings.fontScale = clamp(settings.fontScale + delta, 0.8, 2.0);
  };

  return (
    <Sheet class="ow-display">
      <div class="m3-title-large">Display</div>
      <div class="ow-display__size">
        <button
          type="button"
          class="m3-icon-button m3-icon-button--tonal m3-interactive"
          aria-label="Smaller text"
          title="Smaller text"
          disabled={!(settings.fontScale > 0.8)}
          onClick={() => nudge(-0.1)}
        >
          <span style="font-size:13px">A</span>
        </button>
        <Slider
          value={clamp(settings.fontScale, 0.8, 2.0)}
          min={0.8}
          max={2.0}
          step={0.1}
          label={`Text size, ${Math.round(settings.fontScale * 100)}%`}
          onChange={(value) => (settings.fontScale = value)}
        />
        <button
          type="button"
          class="m3-icon-button m3-icon-button--tonal m3-interactive"
          aria-label="Larger text"
          title="Larger text"
          disabled={!(settings.fontScale < 2.0)}
          onClick={() => nudge(0.1)}
        >
          <span style="font-size:21px">A</span>
        </button>
      </div>
      <div class="ow-display__slider-head">
        <span class="m3-body-large">Line spacing</span>
        <span class="m3-label-large">{settings.lineHeight.toFixed(1)}</span>
      </div>
      <Slider
        value={clamp(settings.lineHeight, 1.2, 2.4)}
        min={1.2}
        max={2.4}
        step={0.1}
        label="Line spacing"
        onChange={(value) => (settings.lineHeight = value)}
      />
      <div style="height:8px" />
      <SegmentedButton
        class="ow-display__fonts"
        options={[ReadingFont.serif, ReadingFont.sans].map((font) => ({ value: font, label: readingFontLabel[font] }))}
        selected={settings.readingFont}
        onSelect={(font) => (settings.readingFont = font)}
      />
      <div style="height:4px" />
      <ListTile
        class="ow-display__switch"
        title="Paragraph layout"
        trailing={<Switch value={settings.paragraphLayout} onChange={(value) => (settings.paragraphLayout = value)} label="Paragraph layout" />}
        onClick={() => (settings.paragraphLayout = !settings.paragraphLayout)}
      />
      <ListTile
        class="ow-display__switch"
        title="Verse numbers"
        trailing={<Switch value={settings.showVerseNumbers} onChange={(value) => (settings.showVerseNumbers = value)} label="Verse numbers" />}
        onClick={() => (settings.showVerseNumbers = !settings.showVerseNumbers)}
      />
      <ListTile
        class="ow-display__switch"
        title="Words of Jesus in red"
        trailing={<Switch value={settings.redLetter} onChange={(value) => (settings.redLetter = value)} label="Words of Jesus in red" />}
        onClick={() => (settings.redLetter = !settings.redLetter)}
      />
      <ListTile
        class="ow-display__switch"
        title="Footnotes"
        trailing={<Switch value={settings.showFootnotes} onChange={(value) => (settings.showFootnotes = value)} label="Footnotes" />}
        onClick={() => (settings.showFootnotes = !settings.showFootnotes)}
      />
      <Divider class="ow-display__divider" />
      <div class="m3-title-medium">Compare with</div>
      <div class="m3-body-small m3-on-surface-variant" style="margin-top:4px">
        Shows a second translation verse by verse.
      </div>
      <div class="ow-display__compare">
        <Chip
          variant="choice"
          label="Off"
          selected={settings.compareTranslationId === null}
          onClick={() => (settings.compareTranslationId = null)}
        />
        {Translations.all
          .filter((translation) => translation.id !== current.id)
          .map((translation) => (
            <Chip
              variant="choice"
              label={translation.abbreviation}
              selected={settings.compareTranslationId === translation.id}
              onClick={() => (settings.compareTranslationId = translation.id)}
            />
          ))}
      </div>
    </Sheet>
  );
}
