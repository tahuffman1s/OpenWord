import { useState } from 'preact/hooks';
import { Originals } from '../data/originals';
import type { Reference } from '../model/bible';
import type { OriginalWord, StrongsNumber } from '../model/strongsCodec';
import { SheetHandle, showSheet, useOverlay } from './m3';
import { scriptureStyle } from './scriptureType';
import { showStrongsEntry } from './strongsSheet';
import './sheets.css';
import './originalSheet.css';

/**
 * The Hebrew or Greek behind a verse.
 *
 * The English is at the top and the original below it. Tapping an English
 * word lights up the word it most likely came from — Strong's says which
 * English words the King James used for each number, and that is enough to
 * tie most of a verse together. Where it cannot tell, it says so instead of
 * guessing.
 *
 * Answers with a Strong's number if the reader asked to see its
 * concordance.
 */
export function showOriginal(options: {
  reference: Reference;
  english: string;
  words: readonly OriginalWord[];
  originals: Originals;
}): Promise<StrongsNumber | undefined> {
  return showSheet<StrongsNumber>(<OriginalSheet {...options} />, { class: 'ow-sheet--h85', name: 'original' });
}

function OriginalSheet({
  reference,
  english,
  words,
  originals,
}: {
  reference: Reference;
  english: string;
  words: readonly OriginalWord[];
  originals: Originals;
}) {
  const overlay = useOverlay();

  /** Which original words are lit, and which English word lit them. */
  const [highlighted, setHighlighted] = useState<ReadonlySet<number>>(new Set());
  const [tappedEnglish, setTappedEnglish] = useState<string | null>(null);
  const [noMatch, setNoMatch] = useState(false);

  const isHebrew = words.some((word) => word.strongs?.isHebrew ?? false);

  /**
   * How the word is said, from its dictionary entry. Worth the lookup:
   * without it the original is a shape rather than a word.
   */
  const transliterationOf = (word: OriginalWord): string => {
    const number = word.strongs;
    if (number === null) return '';
    return originals.entryFor(number)?.transliteration ?? '';
  };

  const tapEnglish = (word: string) => {
    const matches = originals.matchesFor(words, word);
    if (tappedEnglish === word) {
      setTappedEnglish(null);
      setHighlighted(new Set());
      setNoMatch(false);
      return;
    }
    setTappedEnglish(word);
    setHighlighted(new Set(matches));
    setNoMatch(matches.length === 0);
  };

  const openWord = async (index: number) => {
    const word = words[index];
    const number = word.strongs;
    if (number === null) return;
    setHighlighted(new Set([index]));
    setTappedEnglish(null);
    setNoMatch(false);
    const wanted = await showStrongsEntry({ number, originals, morphology: word.morphology, surface: word.text });
    if (wanted !== undefined) overlay.close(wanted);
  };

  const tagged = words.filter((word) => word.strongs !== null).length;

  return (
    <>
      <SheetHandle />
      <div class="ow-sheet-fill ow-original">
        <div class="ow-original__head">
          <span class="m3-title-large" style="flex:1;min-width:0">
            {reference.label}
          </span>
          <span class="m3-label-large m3-primary">{isHebrew ? 'Hebrew' : 'Greek'}</span>
        </div>
        <div class="ow-sheet-note">{tagged} words</div>
        <div class="ow-sheet-scroll" style="margin-top:12px">
          <EnglishLine text={english} selected={tappedEnglish} onTap={tapEnglish} />
          <div class="ow-sheet-note" style={`margin-top:6px${noMatch ? ';color:var(--md-sys-color-error)' : ''}`}>
            {noMatch
              ? `No word of the original is clearly behind “${tappedEnglish}”.`
              : tappedEnglish !== null
                ? `Lit below: what “${tappedEnglish}” most likely came from.`
                : 'Tap an English word above, or an original word below.'}
          </div>
          <div class="ow-original__words" dir={isHebrew ? 'rtl' : 'ltr'}>
            {words.map((word, i) => (
              <WordCard
                word={word}
                highlighted={highlighted.has(i)}
                rtl={isHebrew}
                transliteration={transliterationOf(word)}
                onTap={() => void openWord(i)}
              />
            ))}
          </div>
          <div class="ow-sheet-note" style="margin-top:18px">
            {Originals.attribution}
          </div>
        </div>
      </div>
    </>
  );
}

function bare(token: string): string {
  return token.replace(/[^A-Za-z'\-]/g, '').toLowerCase();
}

/** The English of the verse, one tappable word at a time. */
function EnglishLine({ text, selected, onTap }: { text: string; selected: string | null; onTap: (word: string) => void }) {
  const tokens = text.split(/\s+/).filter((token) => token.length > 0);
  return (
    <div class="ow-original__english m3-body-large">
      {tokens.map((token) => {
        const word = bare(token);
        return (
          <>
            <span
              class={`ow-original__word${word === selected ? ' ow-original__word--selected' : ''}`}
              role="button"
              tabIndex={0}
              onClick={() => onTap(word)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') onTap(word);
              }}
            >
              {token}
            </span>{' '}
          </>
        );
      })}
    </div>
  );
}

/** One word of the original: the word, how it is said, and its number. */
function WordCard({
  word,
  highlighted,
  rtl,
  transliteration,
  onTap,
}: {
  word: OriginalWord;
  highlighted: boolean;
  rtl: boolean;
  transliteration: string;
  onTap: () => void;
}) {
  const number = word.strongs;
  return (
    <button
      type="button"
      class={`ow-original__card${number !== null ? ' m3-interactive' : ''}${highlighted ? ' ow-original__card--lit' : ''}`}
      disabled={number === null}
      onClick={number === null ? undefined : onTap}
    >
      <span class={`m3-title-large ow-original__text ${scriptureStyle({ hebrew: rtl })}`}>{word.text}</span>
      {transliteration.length > 0 && (
        <span class={`m3-body-small ${scriptureStyle({ hebrew: false })}`} dir="ltr">
          {transliteration}
        </span>
      )}
      {number !== null && (
        <span class="m3-label-small ow-original__number" dir="ltr">
          {number.label}
        </span>
      )}
    </button>
  );
}
