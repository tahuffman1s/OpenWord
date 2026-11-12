import { useEffect, useMemo, useState } from 'preact/hooks';
import type { LibraryController } from '../data/library';
import type { Settings } from '../data/settings';
import { type Bible, type Chapter, ReadingDirection, type Reference, type TranslationInfo } from '../model/bible';
import { comparable, differingWords, markedRuns, wordsOf } from '../model/verseCompare';
import { VerseSelection } from '../model/verseSelection';
import { useNotifier } from '../infra/changeNotifier';
import { Chip, IconButton, MenuItem, PopupMenuButton, Sheet, currentScheme, redLetter, showSnackBar, useOverlay } from './m3';
import { openSheet } from './overlaySettle';
import { copyText } from './verseShare';
import { MarkedVerse } from './widgets/markedVerse';
import './compareSheet.css';

/**
 * A verse, or a few, set beside itself in every translation on the shelf.
 *
 * The translation being read comes first and the others under it, each
 * with the words it does not share with the first marked, so that the
 * eye goes to where they part and passes over where they agree. The
 * arrows step to the verse before and after without closing anything:
 * comparing is usually a run of verses, not one.
 */
export interface CompareSheetProps {
  library: LibraryController;
  settings: Settings;
  /** The chapter, as the translation being read has it. */
  chapter: Reference;
  /** The verses to begin on, of that chapter. */
  verses: readonly number[];
  /** Goes to read `translationId` at `verse`. */
  onRead: (translationId: string, verse: number) => void;
  /** Sets `translationId` beside the one being read, verse by verse down the chapter. */
  onSideBySide: (translationId: string) => void;
}

/** What a translation has been found to hold: its text, or that it could not be read. */
type Opened = Bible | 'failed';

/**
 * The translations on the shelf, opened as they are wanted. The one being
 * read is to hand at once; the rest arrive one by one.
 */
export function useOpened(library: LibraryController, ids: readonly string[]): ReadonlyMap<string, Opened> {
  const [opened, setOpened] = useState<ReadonlyMap<string, Opened>>(() => new Map());
  const wanted = ids.join('\n');
  useEffect(() => {
    let live = true;
    for (const id of ids) {
      if (opened.has(id)) continue;
      library.open(id).then(
        (bible) => live && setOpened((before) => new Map(before).set(id, bible)),
        () => live && setOpened((before) => new Map(before).set(id, 'failed')),
      );
    }
    return () => {
      live = false;
    };
  }, [library, wanted]);
  return opened;
}

/** The words of each verse of the translation the others are held against. */
function baseWords(chapter: Chapter | null, verses: readonly number[]): Map<number, string[]> {
  const words = new Map<number, string[]>();
  if (chapter === null) return words;
  for (const verse of verses) words.set(verse, wordsOf(markedRuns(chapter.verseMarked(verse))));
  return words;
}

export function CompareSheet({ library, settings, chapter, verses: initial, onRead, onSideBySide }: CompareSheetProps) {
  const overlay = useOverlay();
  useNotifier(settings, library);
  const [verses, setVerses] = useState<readonly number[]>(() => [...initial].sort((a, b) => a - b));
  const reading = library.translation;
  const others = library.available.filter((translation) => translation.id !== reading.id);
  const hidden = settings.compareHidden;
  const shown = others.filter((translation) => !hidden.has(translation.id));
  const opened = useOpened(library, [reading.id, ...shown.map((translation) => translation.id)]);

  const mine = library.bible?.bookByCode(chapter.bookCode)?.chapter(chapter.chapter) ?? null;
  const base = useMemo(() => baseWords(mine, verses), [mine, verses]);
  const single = verses.length === 1;
  const last = mine?.verseCount ?? 0;
  const step = (delta: number) => {
    const next = verses[0] + delta;
    if (next >= 1 && next <= last) setVerses([next]);
  };

  const differences = settings.compareDifferences;
  // Marking differences says something only where some other translation
  // is in the language of the one being read.
  const canDiffer = shown.some((translation) => comparable(translation.language, reading.language));
  const citation = VerseSelection.citation(chapter, verses);
  const wjColor = redLetter(currentScheme().brightness);

  const card = (translation: TranslationInfo, isReading: boolean) => {
    const bible = opened.get(translation.id);
    const theirs = bible === undefined || bible === 'failed' ? null : (bible.bookByCode(chapter.bookCode)?.chapter(chapter.chapter) ?? null);
    const mark = !isReading && differences && comparable(translation.language, reading.language);
    let body;
    if (bible === undefined) {
      body = <div class="ow-compare-card__waiting" aria-label="Opening" />;
    } else if (bible === 'failed') {
      body = <div class="ow-compare-card__absent">This translation could not be opened.</div>;
    } else if (theirs === null || verses.every((verse) => theirs.verseMarked(verse).length === 0)) {
      body = (
        <div class="ow-compare-card__absent">
          {theirs !== null && verses.some((verse) => theirs.isOmitted(verse))
            ? 'Not in this translation: it follows manuscripts that do not have the verse.'
            : `${translation.abbreviation} does not have ${single ? 'this verse' : 'these verses'}.`}
        </div>
      );
    } else {
      body = (
        <div class="ow-sb ow-compare-card__text" dir={translation.direction === ReadingDirection.rtl ? 'rtl' : 'ltr'}>
          {verses.map((verse, i) => {
            const marked = theirs.verseMarked(verse);
            if (marked.length === 0) return null;
            const differing = mark ? differingWords(base.get(verse) ?? [], wordsOf(markedRuns(marked))) : undefined;
            return (
              <>
                {i > 0 && ' '}
                {!single && <span class="ow-vn">{theirs.labelFor(verse)}</span>}
                <MarkedVerse marked={marked} redLetter={settings.redLetter} wjColor={wjColor} differing={differing} />
              </>
            );
          })}
        </div>
      );
    }
    const text = theirs === null ? '' : VerseSelection.text(theirs, verses);
    return (
      <section class={`ow-compare-card${isReading ? ' ow-compare-card--reading' : ''}`} key={translation.id} data-translation={translation.id}>
        <header class="ow-compare-card__head">
          <span class="ow-compare-card__abbr">{translation.abbreviation}</span>
          <span class="ow-compare-card__name ow-truncate">{isReading ? 'Reading now' : translation.name}</span>
          <PopupMenuButton
            label={`More for ${translation.abbreviation}`}
            size="small"
            items={() => (
              <>
                {!isReading && <MenuItem icon="menu_book" label={`Read in ${translation.abbreviation}`} value="read" />}
                {!isReading && <MenuItem icon="compare_arrows" label="Read side by side" value="beside" />}
                <MenuItem icon="content_copy" label="Copy" value="copy" disabled={text.length === 0} />
                {!isReading && <MenuItem icon="visibility_off" label="Leave out of comparisons" value="hide" />}
              </>
            )}
            onSelected={async (value) => {
              if (value === 'read') {
                overlay.close();
                onRead(translation.id, verses[0]);
              } else if (value === 'beside') {
                overlay.close();
                onSideBySide(translation.id);
              } else if (value === 'copy') {
                await copyText(`${citation} (${translation.abbreviation}) — ${text}`);
                showSnackBar(`Copied ${citation} from ${translation.abbreviation}`);
              } else if (value === 'hide') {
                settings.setCompareHidden(translation.id, true);
              }
            }}
          />
        </header>
        {body}
      </section>
    );
  };

  return (
    <Sheet class="ow-compare-sheet">
      <div class="ow-compare-sheet__head">
        {single && <IconButton icon="chevron_left" label="Previous verse" disabled={verses[0] <= 1} onClick={() => step(-1)} />}
        <div class="m3-title-medium ow-compare-sheet__title" role="status">
          {citation}
        </div>
        {single && <IconButton icon="chevron_right" label="Next verse" disabled={verses[0] >= last} onClick={() => step(1)} />}
      </div>
      {card(reading, true)}
      {canDiffer && (
        <div class="ow-compare-sheet__differences">
          <Chip
            variant="filter"
            label="Mark what differs"
            selected={differences}
            onClick={() => (settings.compareDifferences = !differences)}
          />
          {differences && (
            <span class="m3-body-small m3-on-surface-variant">
              <mark class="ow-diff">Marked</mark> words are not in {reading.abbreviation}.
            </span>
          )}
        </div>
      )}
      {shown.map((translation) => card(translation, false))}
      {others.length === 0 && (
        <div class="m3-body-medium m3-on-surface-variant ow-compare-sheet__none">
          There is no other translation on this device to compare with.
        </div>
      )}
      {others.length > shown.length && (
        <div class="ow-compare-sheet__hidden">
          <div class="m3-label-medium m3-on-surface-variant">Left out</div>
          <div class="ow-compare-sheet__chips">
            {others
              .filter((translation) => hidden.has(translation.id))
              .map((translation) => (
                <Chip
                  variant="assist"
                  icon="add"
                  label={translation.abbreviation}
                  aria-label={`Show ${translation.name}`}
                  onClick={() => settings.setCompareHidden(translation.id, false)}
                />
              ))}
          </div>
        </div>
      )}
    </Sheet>
  );
}

export function showCompareSheet(props: CompareSheetProps): Promise<void | undefined> {
  return openSheet(<CompareSheet {...props} />, { name: 'compare' });
}
