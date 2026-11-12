import { CrossReferences } from '../data/crossReferences';
import { type Bible, Reference } from '../model/bible';
import { BookMeta } from '../model/bookMeta';
import type { XrefAnchor, XrefRange } from '../model/xrefCodec';
import { ListTile, SheetHandle, useOverlay } from './m3';
import { openSheet } from './overlaySettle';
import './sheets.css';
import './crossReferenceSheet.css';

/**
 * Where else Scripture takes up what this verse says.
 *
 * The references are grouped under the phrase that prompted them, the way
 * the Treasury of Scripture Knowledge sets them out, and each one carries
 * the words it points at so the list can be read without leaving it.
 */
export function showCrossReferences(options: {
  reference: Reference;
  anchors: readonly XrefAnchor[];
  bible: Bible;
}): Promise<Reference | undefined> {
  return openSheet<Reference>(<CrossReferenceSheet {...options} />, { class: 'ow-sheet--h85', name: 'cross-references' });
}

function CrossReferenceSheet({ reference, anchors, bible }: { reference: Reference; anchors: readonly XrefAnchor[]; bible: Bible }) {
  let passages = 0;
  for (const anchor of anchors) passages += anchor.ranges.length;

  return (
    <>
      <SheetHandle />
      <div class="ow-sheet-fill ow-xref">
        <div class="m3-title-large">{reference.label}</div>
        <div class="ow-sheet-note" style="margin-top:2px">
          {passages === 1 ? 'One cross-reference' : `${passages} cross-references`}
        </div>
        <div class="ow-sheet-scroll" style="margin-top:12px">
          {anchors.map((anchor) => (
            <>
              {anchor.phrase.length > 0 && <div class="ow-xref__phrase">“{anchor.phrase}”</div>}
              {anchor.ranges.map((range) => (
                <Passage range={range} bible={bible} />
              ))}
            </>
          ))}
          <div class="ow-sheet-note" style="margin-top:16px">
            {CrossReferences.attribution}
          </div>
        </div>
      </div>
    </>
  );
}

/**
 * One passage: what it is called, and what it says where the translation
 * being read has it.
 */
function Passage({ range, bible }: { range: XrefRange; bible: Bible }) {
  const overlay = useOverlay();
  const code = CrossReferences.bookAt(range.book);
  if (code === null) return null;
  const meta = BookMeta.lookup(code);
  if (meta === undefined) return null;

  const label = `${meta.name} ${range.chapter}:${range.verse}${range.isRange ? `-${range.endVerse}` : ''}`;
  const text = textOf(bible, code, range);

  return (
    <ListTile
      dense
      class="ow-xref__passage"
      title={<span class="m3-label-large">{label}</span>}
      subtitle={
        text === null ? (
          <span class="m3-body-small m3-on-surface-variant">Not in this translation</span>
        ) : (
          <span class="ow-xref__text">{text}</span>
        )
      }
      onClick={() => overlay.close(new Reference(code, range.chapter, range.verse))}
    />
  );
}

/**
 * The verses of the passage, joined, from the translation in hand. A
 * reference into a book this edition does not carry has no text, and says
 * so rather than going blank.
 */
function textOf(bible: Bible, code: string, range: XrefRange): string | null {
  const chapter = bible.bookByCode(code)?.chapter(range.chapter);
  if (chapter === undefined) return null;
  const parts: string[] = [];
  for (let verse = range.verse; verse <= range.endVerse; verse++) {
    const text = chapter.verseText(verse);
    if (text.length > 0) parts.push(text);
  }
  return parts.length === 0 ? null : parts.join(' ');
}
