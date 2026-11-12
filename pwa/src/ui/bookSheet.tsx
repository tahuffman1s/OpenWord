import { useState } from 'preact/hooks';
import { BookIntro, BookIntros, type IntroSection } from '../data/bookIntros';
import { type BookNote, bookNotes } from '../data/bookNotes';
import type { Book } from '../model/bible';
import { bookDivisionLabel, bookSectionLabel } from '../model/bookMeta';
import { useAsync } from './hooks';
import { CircularProgress, Icon, SheetHandle } from './m3';
import { openSheet } from './overlaySettle';
import { SimpleMarkdown } from './optionalScreens';
import './sheets.css';
import './bookSheet.css';

/**
 * A background sheet for the book being read: where it sits in the canon,
 * how big it is, and an introduction to it.
 */
export function showBookSheet(book: Book, options: { intros?: BookIntros | null } = {}): void {
  void openSheet(<BookSheet book={book} intros={options.intros ?? null} />, { class: 'ow-sheet--h88', name: 'book' });
}

function BookSheet({ book, intros }: { book: Book; intros: BookIntros | null }) {
  const note = bookNotes.get(book.code) ?? null;
  const verses = book.verseCount;
  return (
    <>
      <SheetHandle />
      <div class="ow-sheet-scroll ow-book-sheet">
        <div class="m3-headline-small">{book.name}</div>
        <div class="m3-body-medium m3-primary" style="margin-top:4px">
          {bookDivisionLabel[book.meta.division]} • {bookSectionLabel[book.section]}
        </div>
        <div class="ow-book-sheet__facts">
          <Fact label={book.chapterCount === 1 ? 'chapter' : 'chapters'} value={`${book.chapterCount}`} />
          <Fact label="verses" value={`${verses}`} />
          {note !== null && <Fact label="" value={note.genre} />}
        </div>
        <Introduction book={book} intros={intros} fallback={note} />
      </div>
    </>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return <span class="ow-book-sheet__fact">{label.length === 0 ? value : `${value} ${label}`}</span>;
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div style="padding-bottom:10px">
      <div class="ow-book-sheet__row-label">{label.toUpperCase()}</div>
      <div class="m3-body-medium" style="margin-top:2px">
        {value}
      </div>
    </div>
  );
}

/**
 * Prose from the introductions. Set by the app's Markdown widget where it
 * is there, and as plain paragraphs where it is not yet.
 */
function Prose({ source, baseStyle }: { source: string; baseStyle: string }) {
  if (SimpleMarkdown !== null) {
    return (
      <div class={baseStyle}>
        <SimpleMarkdown source={source} baseStyle={baseStyle} />
      </div>
    );
  }
  return (
    <div class={baseStyle}>
      {source
        .split(/\n\s*\n/)
        .map((paragraph) => paragraph.trim())
        .filter((paragraph) => paragraph.length > 0)
        .map((paragraph) => (
          <p class="ow-book-sheet__paragraph">{paragraph.replace(/\s*\n\s*/g, ' ').replace(/[*_#`]/g, '')}</p>
        ))}
    </div>
  );
}

/**
 * The bundled introduction for a book, or the app's own short note where
 * there is none — the deuterocanonical books are not covered by the
 * introductions resource.
 */
function Introduction({ book, intros, fallback }: { book: Book; intros: BookIntros | null; fallback: BookNote | null }) {
  const alreadyLoaded = intros?.loaded(book.code) ?? null;
  const loading = useAsync(
    () => (intros === null || alreadyLoaded !== null ? Promise.resolve(alreadyLoaded) : intros.forBook(book.code)),
    [intros, book.code],
  );

  if (intros === null) return <Fallback note={fallback} />;
  if (alreadyLoaded !== null) return <Intro markdown={alreadyLoaded} fallback={fallback} />;
  if (loading.loading) {
    return (
      <div class="ow-center" style="padding:24px 0">
        <CircularProgress />
      </div>
    );
  }
  const markdown = loading.value ?? null;
  if (markdown === null || markdown.length === 0) return <Fallback note={fallback} />;
  return <Intro markdown={markdown} fallback={fallback} />;
}

function Intro({ markdown, fallback }: { markdown: string; fallback: BookNote | null }) {
  const intro = BookIntro.parse(markdown);
  if (intro.isEmpty) return <Fallback note={fallback} />;
  return (
    <div>
      {intro.lead.length > 0 && <Prose source={intro.lead} baseStyle="m3-body-large" />}
      {intro.sections.length > 0 && (
        <div style="margin-top:8px">
          {intro.sections.map((section, i) => (
            <div style="padding-bottom:8px">
              {/* Where there is a lead, it is already the summary and the
                  sections below it are an outline to choose from; where
                  there is not, the first section is opened so the sheet
                  does not read as a row of shut doors. */}
              <Section section={section} initiallyExpanded={i === 0 && intro.lead.length === 0} />
            </div>
          ))}
        </div>
      )}
      <div class="ow-sheet-note" style="margin-top:12px">
        {BookIntros.attribution}
      </div>
    </div>
  );
}

function Fallback({ note }: { note: BookNote | null }) {
  if (note === null) {
    return <div class="m3-body-medium m3-on-surface-variant">No background note for this book yet.</div>;
  }
  return (
    <div>
      <div class="m3-body-large">{note.summary}</div>
      <div style="height:18px" />
      <Row label="Ascribed to" value={note.attribution} />
      <Row label="Setting" value={note.setting} />
      <div style="height:18px" />
      <div class="ow-sheet-note">
        A brief editorial summary written for this app, not a commentary. Traditional authorship is noted as tradition; scholarly
        views on authorship and dating differ.
      </div>
    </div>
  );
}

/** One section of an introduction, folded away until it is wanted. */
function Section({ section, initiallyExpanded = false }: { section: IntroSection; initiallyExpanded?: boolean }) {
  const [open, setOpen] = useState(initiallyExpanded);
  return (
    <div class="ow-book-sheet__section">
      <button
        type="button"
        class={`ow-book-sheet__section-title m3-interactive${open ? ' ow-book-sheet__section-title--open' : ''}`}
        aria-expanded={open}
        onClick={() => setOpen(!open)}
      >
        <span style="flex:1">{section.title}</span>
        <Icon name="expand_more" />
      </button>
      {open && (
        <div class="ow-book-sheet__section-body">
          <Prose source={section.body} baseStyle="m3-body-medium" />
        </div>
      )}
    </div>
  );
}
