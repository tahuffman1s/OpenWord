import { Originals } from '../data/originals';
import type { StrongsNumber } from '../model/strongsCodec';
import { SheetHandle, TonalButton, useOverlay } from './m3';
import { openSheet } from './overlaySettle';
import { scriptureStyle } from './scriptureType';
import './sheets.css';
import './strongsSheet.css';

/**
 * What Strong's says about one word, and the way to everywhere else it is
 * used.
 *
 * Returns the number if the reader asked to see its occurrences.
 */
export function showStrongsEntry(options: {
  number: StrongsNumber;
  originals: Originals;
  morphology?: string;
  surface?: string | null;
}): Promise<StrongsNumber | undefined> {
  return openSheet<StrongsNumber>(
    <StrongsSheet
      number={options.number}
      originals={options.originals}
      morphology={options.morphology ?? ''}
      surface={options.surface ?? null}
    />,
    { class: 'ow-sheet--h85', name: 'strongs' },
  );
}

function StrongsSheet({
  number,
  originals,
  morphology,
  surface,
}: {
  number: StrongsNumber;
  originals: Originals;
  morphology: string;
  /**
   * The word as it stands in the verse, which is often inflected away from
   * the headword.
   */
  surface: string | null;
}) {
  const overlay = useOverlay();
  const entry = originals.entryFor(number);
  const occurrences = originals.occurrenceCount(number);
  const rtl = number.isHebrew;

  if (entry === null) {
    return (
      <>
        <SheetHandle />
        <div class="ow-sheet-fill ow-strongs">
          <div class="m3-body-large">{number.label} is not in the dictionary.</div>
        </div>
      </>
    );
  }

  const said = [entry.transliteration, entry.pronunciation.length > 0 ? `(${entry.pronunciation})` : '']
    .filter((part) => part.length > 0)
    .join('  ');

  return (
    <>
      <SheetHandle />
      <div class="ow-sheet-fill ow-strongs">
        <div class="ow-strongs__head">
          {/* Right-to-left inside the word, but still at the head of
              the column: the transliteration sits directly under it,
              and the two read as one heading rather than drifting to
              opposite margins. */}
          <div class={`m3-headline-medium ow-strongs__lemma ${scriptureStyle({ hebrew: rtl })}`} dir={rtl ? 'rtl' : 'ltr'}>
            {entry.lemma.length === 0 ? (surface ?? '') : entry.lemma}
          </div>
          <span class="ow-strongs__number">{number.label}</span>
        </div>
        {said.length > 0 && <div class={`m3-title-medium m3-primary ${scriptureStyle({ hebrew: false })}`}>{said}</div>}
        {morphology.length > 0 && <div class="m3-body-medium m3-on-surface-variant ow-strongs__morphology">{morphology}</div>}
        <div class="ow-sheet-scroll" style="margin-top:16px">
          {entry.definition.trim().length > 0 && <Section title="Definition" body={entry.definition.trim()} />}
          {entry.derivation.trim().length > 0 && <Section title="Derivation" body={entry.derivation.trim()} />}
          {entry.kjvUsage.trim().length > 0 && <Section title="How the King James renders it" body={entry.kjvUsage.trim()} />}
          <div style="height:8px" />
          {occurrences > 0 && (
            <TonalButton icon="manage_search" class="ow-strongs__uses" onClick={() => overlay.close(number)}>
              {occurrences === 1 ? 'Used in one verse' : `Used in ${occurrences} verses`}
            </TonalButton>
          )}
          <div class="ow-sheet-note" style="margin-top:16px">
            {Originals.attribution}
          </div>
        </div>
      </div>
    </>
  );
}

function Section({ title, body }: { title: string; body: string }) {
  return (
    <div style="padding-bottom:14px">
      <div class="m3-label-large m3-primary">{title}</div>
      <div class={`m3-body-medium ${scriptureStyle({ hebrew: false })}`} style="margin-top:2px">
        {body}
      </div>
    </div>
  );
}
