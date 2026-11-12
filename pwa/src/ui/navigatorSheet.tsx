import { useLayoutEffect, useRef, useState } from 'preact/hooks';
import type { ReadingStore } from '../data/marks';
import { ReferenceSearch } from '../data/referenceSearch';
import { BookOrder, bookOrderLabel, type Settings } from '../data/settings';
import { useNotifier } from '../infra/changeNotifier';
import { type Book, Reference } from '../model/bible';
import { bookDivisionLabel } from '../model/bookMeta';
import { compareCodeUnits } from '../model/searchIndex';
import { Icon, IconButton, ListTile, SegmentedButton, SheetHandle, TextButton, showSheet, useOverlay } from './m3';
import './sheets.css';
import './navigatorSheet.css';

/** Opens the navigator and resolves to the chosen place, or undefined. */
export function showBibleNavigator(options: {
  books: readonly Book[];
  settings: Settings;
  reading: ReadingStore;
  current?: Reference | null;
}): Promise<Reference | undefined> {
  return showSheet<Reference>(
    <NavigatorSheet books={options.books} settings={options.settings} reading={options.reading} current={options.current ?? null} />,
    { class: 'ow-sheet--h92', name: 'navigator' },
  );
}

enum Step {
  books,
  chapters,
  verses,
}

/**
 * Book, chapter and verse navigation in one sheet.
 *
 * The field at the top does double duty: it filters the book list as you
 * type, and if what you typed reads as a reference — `jn 3:16`, `1 co 13`,
 * `psalm 23` — it offers to jump straight there.
 */
function NavigatorSheet({
  books,
  settings,
  reading,
  current,
}: {
  books: readonly Book[];
  settings: Settings;
  reading: ReadingStore;
  current: Reference | null;
}) {
  const overlay = useOverlay();
  useNotifier(settings);
  const field = useRef<HTMLInputElement>(null);

  const [query, setQuery] = useState('');
  const [step, setStep] = useState(Step.books);
  const [book, setBook] = useState<Book | null>(() =>
    current === null ? null : (books.find((candidate) => candidate.code === current.bookCode) ?? books[0] ?? null),
  );
  const [chapter, setChapter] = useState(current?.chapter ?? 1);

  const text = query.trim();
  const parsed = text.length === 0 ? null : ReferenceSearch.parse(text, books);

  /**
   * Books matching what was typed, ignoring any chapter and verse, so that
   * `jn 3:16` still lists John underneath the jump button.
   */
  const matches = ReferenceSearch.matchBooks(ReferenceSearch.split(text).name, books);

  const pop = (reference: Reference) => overlay.close(reference);

  const chooseBook = (chosen: Book) => {
    if (chosen.chapterCount === 1) {
      pop(new Reference(chosen.code, 1));
      return;
    }
    field.current?.blur();
    setBook(chosen);
    setStep(Step.chapters);
    setQuery('');
  };

  const chooseChapter = (number: number) => {
    setChapter(number);
    setStep(Step.verses);
  };

  const back = () => setStep(step === Step.verses ? Step.chapters : Step.books);

  const title = step === Step.books ? 'Go to' : step === Step.chapters ? (book?.name ?? '') : `${book?.name ?? ''} ${chapter}`;

  const marked = reading.markedBookCodes;
  const bookTile = (candidate: Book) => {
    const selected = candidate.code === current?.bookCode;
    return (
      <ListTile
        key={candidate.code}
        dense
        class="ow-nav__book"
        selected={selected}
        leading={<BookBadge abbrev={candidate.abbrev} selected={selected} />}
        title={candidate.name}
        subtitle={candidate.chapterCount === 1 ? '1 chapter' : `${candidate.chapterCount} chapters`}
        trailing={marked.has(candidate.code) ? <Icon name="bookmark" size={16} class="m3-primary" /> : undefined}
        onClick={() => chooseBook(candidate)}
      />
    );
  };

  const bookList = () => {
    if (matches.length === 0) {
      return (
        <div class="ow-nav__empty m3-body-large m3-on-surface-variant">
          No book matches “{ReferenceSearch.split(text).name.trim()}”
        </div>
      );
    }

    // While filtering, a flat ranked list is what the reader wants to see.
    if (text.length > 0) {
      return (
        <div class="ow-nav__list" key="filtered">
          {matches.map(bookTile)}
        </div>
      );
    }

    const alphabetical = settings.bookOrder === BookOrder.alphabetical;
    const ordered = alphabetical
      ? [...matches].sort((a, b) => compareCodeUnits(a.meta.sortName.toLowerCase(), b.meta.sortName.toLowerCase()))
      : matches;

    const children = [];
    let group: string | null = null;
    for (const candidate of ordered) {
      const heading = alphabetical ? candidate.meta.initial : bookDivisionLabel[candidate.meta.division];
      if (heading !== group) {
        group = heading;
        children.push(
          <div class="ow-nav__group" key={`group-${heading}`}>
            {heading}
          </div>,
        );
      }
      children.push(bookTile(candidate));
    }

    return (
      <div class="ow-nav__list" key={alphabetical ? 'a-z' : 'canon'}>
        <div class="ow-nav__order">
          <SegmentedButton
            class="ow-nav__order-buttons"
            options={[BookOrder.canonical, BookOrder.alphabetical].map((order) => ({ value: order, label: bookOrderLabel[order] }))}
            selected={settings.bookOrder}
            onSelect={(order) => (settings.bookOrder = order)}
          />
        </div>
        {children}
      </div>
    );
  };

  const chapterGrid = () => {
    if (book === null) return null;
    return (
      <NumberGrid
        key={`chapters-${book.code}`}
        count={book.chapterCount}
        current={book.code === current?.bookCode ? (current?.chapter ?? null) : null}
        marked={reading.markedChaptersIn(book.code)}
        onSelected={chooseChapter}
      />
    );
  };

  const verseGrid = () => {
    if (book === null) return null;
    // From the outline, so picking a verse does not unpack the book the
    // reader may yet decide not to open.
    const verses = book.verseCountAt(chapter);
    if (verses === 0) return null;
    return (
      <NumberGrid
        key={`verses-${book.code}-${chapter}`}
        count={verses}
        current={book.code === current?.bookCode && chapter === current?.chapter ? (current?.verse ?? null) : null}
        marked={reading.flaggedVersesIn(book.code, chapter)}
        onSelected={(verse) => pop(new Reference(book.code, chapter, verse))}
      />
    );
  };

  return (
    <>
      <SheetHandle />
      <div class="ow-sheet-fill ow-nav">
        <div class="ow-nav__header">
          {step === Step.books ? <span style="width:12px" /> : <IconButton icon="arrow_back" label="Back" onClick={back} />}
          <span class="ow-nav__title m3-title-large">{title}</span>
          {step === Step.chapters && book !== null && (
            <TextButton onClick={() => pop(new Reference(book.code, chapter))}>Keep reading</TextButton>
          )}
          {step === Step.verses && book !== null && (
            <TextButton onClick={() => pop(new Reference(book.code, chapter))}>Whole chapter</TextButton>
          )}
        </div>
        {step === Step.books && (
          <div class="ow-nav__search">
            <label class="ow-nav__field">
              <Icon name="search" />
              <input
                ref={field}
                type="text"
                enterkeyhint="go"
                autocapitalize="words"
                autocomplete="off"
                autocorrect="off"
                spellcheck={false}
                placeholder="Book, or a reference like Jn 3:16"
                aria-label="Book, or a reference like Jn 3:16"
                value={query}
                onInput={(event) => setQuery((event.currentTarget as HTMLInputElement).value)}
                onKeyDown={(event) => {
                  if (event.key !== 'Enter') return;
                  event.preventDefault();
                  if (parsed !== null) pop(parsed);
                  else if (matches.length === 1) chooseBook(matches[0]);
                }}
              />
              {text.length > 0 && <IconButton icon="close" label="Clear" onClick={() => setQuery('')} />}
            </label>
            {parsed !== null && (
              <button type="button" class="ow-nav__go m3-interactive" onClick={() => pop(parsed)}>
                <Icon name="arrow_forward" />
                <span>Go to {parsed.label}</span>
              </button>
            )}
          </div>
        )}
        <div class="ow-nav__body" key={step}>
          {step === Step.books ? bookList() : step === Step.chapters ? chapterGrid() : verseGrid()}
        </div>
      </div>
    </>
  );
}

/**
 * A book's short form — Gen, Exo, 1Sa — beside its name in the list, the
 * way it is written in references and typed into the search.
 */
function BookBadge({ abbrev, selected }: { abbrev: string; selected: boolean }) {
  return <span class={`ow-nav__badge${selected ? ' ow-nav__badge--selected' : ''}`}>{abbrev}</span>;
}

const maxTileExtent = 76;
const spacing = 8;
const aspectRatio = 1.15;
const padding = { left: 16, top: 4, right: 16, bottom: 32 };

/**
 * A grid of numbers, used for both chapters and verses.
 *
 * Opening Psalm 119 and reaching for its chapter list used to start at
 * chapter 1 with the one you were reading far below the fold, so the grid
 * starts scrolled to whatever is current.
 */
function NumberGrid({
  count,
  onSelected,
  current = null,
  marked,
}: {
  count: number;
  onSelected: (number: number) => void;
  current?: number | null;
  marked: ReadonlySet<number>;
}) {
  const scroller = useRef<HTMLDivElement>(null);
  const [columns, setColumns] = useState(0);
  const placed = useRef(false);

  /** As many columns as tiles of at most `maxTileExtent` across need. */
  const columnsFor = (width: number): number =>
    Math.min(Math.max(Math.ceil((width - padding.left - padding.right) / (maxTileExtent + spacing)), 1), Math.max(count, 1));

  useLayoutEffect(() => {
    const element = scroller.current;
    if (element === null) return;
    const measure = () => setColumns(columnsFor(element.clientWidth));
    measure();
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(measure);
    observer?.observe(element);
    return () => observer?.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [count]);

  /**
   * Where the grid should start so that `current` is on screen, roughly
   * centred, without running past either end.
   */
  useLayoutEffect(() => {
    const element = scroller.current;
    if (element === null || columns === 0 || placed.current) return;
    placed.current = true;
    if (current === null || current < 1) return;

    const width = element.clientWidth - padding.left - padding.right;
    const tileWidth = (width - (columns - 1) * spacing) / columns;
    const rowStride = tileWidth / aspectRatio + spacing;
    const rows = Math.ceil(count / columns);
    const contentHeight = rows * rowStride - spacing + padding.top + padding.bottom;
    const viewport = element.clientHeight;
    if (contentHeight <= viewport) return;

    const row = Math.trunc((current - 1) / columns);
    const target = padding.top + row * rowStride - (viewport - rowStride) / 2;
    element.scrollTop = Math.min(Math.max(target, 0), contentHeight - viewport);
  }, [columns, count, current]);

  const tiles = [];
  for (let number = 1; number <= count; number++) {
    const isCurrent = number === current;
    tiles.push(
      <button
        type="button"
        class={`ow-nav__tile m3-interactive${isCurrent ? ' ow-nav__tile--current' : ''}`}
        aria-current={isCurrent ? 'true' : undefined}
        onClick={() => {
          navigator.vibrate?.(1);
          onSelected(number);
        }}
      >
        {number}
        {marked.has(number) && <Icon name="bookmark" size={11} class="ow-nav__tile-mark" />}
      </button>,
    );
  }

  return (
    <div class="ow-nav__grid-scroll" ref={scroller}>
      <div class="ow-nav__grid" style={columns > 0 ? `grid-template-columns:repeat(${columns},1fr)` : 'visibility:hidden'}>
        {tiles}
      </div>
    </div>
  );
}

