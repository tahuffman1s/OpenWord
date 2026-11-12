import { useMemo, useRef, useState } from 'preact/hooks';
import type { Originals } from '../data/originals';
import type { Bible, Reference } from '../model/bible';
import { BookMeta } from '../model/bookMeta';
import type { StrongsNumber } from '../model/strongsCodec';
import { AppBar, Chip, ListTile, Screen, nav, useOverlay } from './m3';
import { scriptureStyle } from './scriptureType';
import './concordanceScreen.css';

/**
 * Every verse one Strong's number occurs in.
 *
 * The list is of the original word's occurrences, so it holds whatever
 * translation is being read: the verses are the same verses. Where the
 * translation in hand does not carry a book, the reference still stands
 * and says so.
 */
export function showConcordance(options: {
  number: StrongsNumber;
  originals: Originals;
  bible: Bible;
}): Promise<Reference | undefined> {
  return nav.push<Reference>(<ConcordanceScreen {...options} />, { name: 'concordance' });
}

/** How many verses are laid out at a time; the common words run to thousands. */
const pageSize = 150;

export function ConcordanceScreen({ number, originals, bible }: { number: StrongsNumber; originals: Originals; bible: Bible }) {
  const overlay = useOverlay();
  const body = useRef<HTMLDivElement>(null);
  const all = useMemo(() => originals.occurrences(number), [originals, number]);
  const [book, setBook] = useState<string | null>(null);
  const [limit, setLimit] = useState(pageSize);

  const entry = originals.entryFor(number);
  const shown = book === null ? all : all.filter((reference) => reference.bookCode === book);

  // Which books it turns up in, in canonical order, for the filter.
  const books = useMemo(() => {
    const found: string[] = [];
    for (const reference of all) {
      if (found.length === 0 || found[found.length - 1] !== reference.bookCode) {
        if (!found.includes(reference.bookCode)) found.push(reference.bookCode);
      }
    }
    return found;
  }, [all]);

  const textOf = (reference: Reference): string | null => {
    const verse = reference.verse;
    if (verse === null) return null;
    const text = bible.bookByCode(reference.bookCode)?.chapter(reference.chapter)?.verseText(verse);
    return text === undefined || text.length === 0 ? null : text;
  };

  const choose = (code: string | null) => {
    setBook(code);
    setLimit(pageSize);
  };

  return (
    <Screen
      appBar={(scrolled) => (
        <div class={`ow-concordance__bar${scrolled ? ' ow-concordance__bar--scrolled' : ''}`}>
          <AppBar title={number.label} scrolled={scrolled} />
          <div class="ow-concordance__head">
            {entry !== null && (
              <div class={`m3-title-medium ow-concordance__lemma ${scriptureStyle({ hebrew: number.isHebrew })}`}>
                {entry.lemma}
                {'   '}
                {entry.transliteration}
              </div>
            )}
            <div class="m3-body-small m3-on-surface-variant">
              {all.length} verses in {books.length} {books.length === 1 ? 'book' : 'books'}
            </div>
            <div class="ow-concordance__books">
              <Chip variant="choice" label="All" selected={book === null} onClick={() => choose(null)} />
              {books.map((code) => (
                <Chip
                  variant="choice"
                  label={BookMeta.lookup(code)?.abbrev ?? code}
                  selected={book === code}
                  onClick={() => choose(book === code ? null : code)}
                />
              ))}
            </div>
          </div>
        </div>
      )}
      bodyRef={body}
      onScroll={() => {
        // The list is long and mostly unread: more of it is laid out as
        // the reader nears the end of what there is.
        const element = body.current;
        if (element !== null && limit < shown.length && element.scrollTop + element.clientHeight * 2 >= element.scrollHeight) {
          setLimit((current) => current + pageSize);
        }
      }}
    >
      <div class="ow-content">
        {shown.slice(0, limit).map((reference) => {
          const text = textOf(reference);
          return (
            <ListTile
              key={reference.key}
              dense
              title={<span class="m3-label-large">{reference.label}</span>}
              subtitle={
                <span class={`ow-concordance__text${text === null ? ' m3-on-surface-variant' : ''}`}>
                  {text ?? 'Not in this translation'}
                </span>
              }
              onClick={text === null ? undefined : () => overlay.close(reference)}
            />
          );
        })}
      </div>
    </Screen>
  );
}
