import { useRef, useState } from 'preact/hooks';
import type { LibraryController } from '../data/library';
import type { Settings } from '../data/settings';
import type { Shelf, ShelfResult } from '../data/shelf';
import { Versification, type Bible } from '../model/bible';
import { BookSection } from '../model/bookMeta';
import { VersificationCheck } from '../model/versificationCheck';
import { CircularProgress, FilledButton, Icon, SheetHandle, TextButton, showSheet, useOverlay } from './m3';
import './shared.css';
import './importSheet.css';

/**
 * Brings a translation in from a file: a `.bib`, or an EPUB to convert.
 *
 * The conversion is the interesting part, so the sheet shows its work — what
 * it found, and what it could not place — rather than reporting "done".
 */
export function showImportSheet(options: { shelf: Shelf; library: LibraryController; settings: Settings }): Promise<void> {
  return showSheet<void>(<ImportSheet {...options} />, { class: 'ow-import-sheet', name: 'import' }).then(() => undefined);
}

type Stage = 'waiting' | 'reading' | 'done' | 'failed';

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function ImportSheet({ shelf, library, settings }: { shelf: Shelf; library: LibraryController; settings: Settings }) {
  const overlay = useOverlay();
  const input = useRef<HTMLInputElement>(null);
  const [stage, setStage] = useState<Stage>('waiting');
  const [what, setWhat] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<ShelfResult | null>(null);

  /** Asks the browser for a file: its picker is the input's own. */
  const pick = (): void => {
    const field = input.current;
    if (field === null) {
      setStage('failed');
      setError('The file picker would not open.');
      return;
    }
    // The same file chosen twice in a row would not say it had changed.
    field.value = '';
    try {
      field.click();
    } catch (problem) {
      setStage('failed');
      setError(`The file picker would not open: ${errorText(problem)}`);
    }
  };

  const chosen = async (file: File | undefined): Promise<void> => {
    if (file === undefined) return;
    setStage('reading');
    setWhat(file.name);
    setError(null);

    let bytes: Uint8Array;
    try {
      bytes = new Uint8Array(await file.arrayBuffer());
    } catch (problem) {
      setStage('failed');
      setError(`That file could not be read: ${errorText(problem)}`);
      return;
    }

    const added = await shelf.add(bytes, file.name);
    if (added.ok) {
      setResult(added);
      setStage('done');
    } else {
      setError(added.failure);
      setStage('failed');
    }
  };

  const readNow = (added: ShelfResult): void => {
    const id = added.bible!.translation.id;
    settings.translationId = id;
    void library.load(id);
    overlay.close();
  };

  return (
    <>
      <SheetHandle />
      <div class="ow-import">
        <div class="m3-headline-small">Add a translation</div>
        <div class="m3-body-medium ow-muted ow-import__lead">An EPUB of a Bible, or a .bib file — the format this app converts them to.</div>
        <input
          ref={input}
          type="file"
          class="ow-import__input"
          accept=".epub,.bib,application/epub+zip"
          aria-label="Choose a Bible to import"
          onChange={(event) => void chosen((event.currentTarget as HTMLInputElement).files?.[0])}
        />
        <div class={`ow-import__body${stage === 'reading' ? ' ow-import__body--centred' : ''}`}>
          {stage === 'reading' ? (
            <>
              <CircularProgress />
              <div class="m3-body-medium ow-import__reading" role="status">
                Reading {what}…
              </div>
              <div class="m3-body-small ow-muted">A whole Bible takes a few seconds.</div>
            </>
          ) : stage === 'failed' ? (
            <>
              <div class="m3-body-medium m3-error" role="alert">
                {error ?? 'That file could not be read.'}
              </div>
              <div class="m3-body-small ow-muted ow-import__why">
                An EPUB can be read when its headings name the books of the Bible and its verses are numbered — as a
                superscript, in a span of their own, or as a number at the head of each paragraph. Anything else is a
                book, not a Bible, and the app would only be guessing.
              </div>
            </>
          ) : stage === 'done' && result !== null ? (
            <Summary result={result} />
          ) : (
            <>
              <Point
                icon="menu_book"
                title="EPUB"
                body="Converted to .bib as it is read: the books, chapters and verses are found from the markup, and poetry, headings and italics are kept."
              />
              <Point icon="inventory_2" title=".bib" body="A whole translation in one file — the app’s own format. Copied onto the shelf as it is." />
              <Point
                icon="wifi_off"
                title="Nothing leaves the device"
                body="The file is read where it sits. Once imported, the translation reads, searches, compares and takes bookmarks like the ones that ship with the app."
              />
            </>
          )}
        </div>
        <div class="ow-import__actions">
          {stage === 'reading' ? null : stage === 'done' && result !== null ? (
            <>
              <FilledButton icon="auto_stories" onClick={() => readNow(result)}>
                Read it now
              </FilledButton>
              <TextButton onClick={() => overlay.close()}>Later</TextButton>
            </>
          ) : (
            <FilledButton icon="folder_open" onClick={pick}>
              {stage === 'failed' ? 'Choose another file' : 'Choose a file'}
            </FilledButton>
          )}
        </div>
      </div>
    </>
  );
}

/**
 * Which parts of the canon came through, since an EPUB is often only a
 * Testament or a single book.
 */
export function coverage(bible: Bible): string {
  const codes = new Set(bible.books.map((book) => book.code));
  const old = bible.books.filter((book) => book.section === BookSection.oldTestament).length;
  const newer = bible.books.filter((book) => book.section === BookSection.newTestament).length;
  const deutero = codes.size - old - newer;

  const parts = [
    ...(old > 0 ? [`${old} of the 39 books of the Old Testament`] : []),
    ...(newer > 0 ? [`${newer} of the 27 of the New`] : []),
    ...(deutero > 0 ? [`${deutero} deuterocanonical`] : []),
  ];
  if (parts.length === 0) return 'Nothing of the canon was recognised.';
  return `Found ${parts.join(', ')}.`;
}

/**
 * How the translation numbers its verses against the bundled study
 * layers, where the file says: what Settings says of it afterwards, said
 * here first, with a few of the chapters that differ.
 */
export function numberingVerdict(bible: Bible): { text: string; examples: readonly string[] } | null {
  const versification = bible.translation.versification;
  if (versification === Versification.english) {
    return { text: 'Numbers its verses the usual English way, so cross-references and the Hebrew and Greek are offered for it.', examples: [] };
  }
  if (!Versification.mayAnchorEnglish(versification)) {
    return {
      text: 'Numbers its verses differently, so cross-references and the Hebrew and Greek are not offered for it.',
      examples: VersificationCheck.against(bible).examples.slice(0, 3),
    };
  }
  return null;
}

/** What the import found, in the terms the reader cares about. */
function Summary({ result }: { result: ShelfResult }) {
  const bible = result.bible!;
  const books = bible.books.length;
  const verses = bible.verseCount;
  const verdict = numberingVerdict(bible);

  return (
    <>
      <div class="m3-title-large">{bible.translation.name}</div>
      <div class="m3-body-small ow-muted ow-import__licence">
        {bible.translation.abbreviation} • {bible.translation.license}
      </div>
      <div class="ow-import__facts">
        <Fact value={`${books}`} label={books === 1 ? 'book' : 'books'} />
        <Fact value={`${verses}`} label="verses" />
        {result.translation !== null && <Fact value={result.translation.readableSize} label="on disk" />}
      </div>
      <div class="m3-body-medium">{coverage(bible)}</div>
      {verdict !== null && (
        <div class="m3-body-small ow-muted ow-import__verdict">
          {verdict.text}
          {verdict.examples.map((example) => (
            <div key={example}>• {example}</div>
          ))}
        </div>
      )}
      {result.warnings.length > 0 && (
        <div class="ow-import__warnings">
          <div class="m3-label-large">
            {result.warnings.length === 1 ? 'One thing could not be placed:' : `${result.warnings.length} things could not be placed:`}
          </div>
          {result.warnings.slice(0, 12).map((warning) => (
            <div class="m3-body-small ow-muted ow-import__warning">• {warning}</div>
          ))}
        </div>
      )}
    </>
  );
}

function Fact({ value, label }: { value: string; label: string }) {
  return (
    <span class="ow-import__fact m3-label-large">
      {value} {label}
    </span>
  );
}

function Point({ icon, title, body }: { icon: string; title: string; body: string }) {
  return (
    <div class="ow-import__point">
      <Icon name={icon} class="m3-primary" />
      <div class="ow-import__point-text">
        <div class="m3-title-small">{title}</div>
        <div class="m3-body-small ow-muted">{body}</div>
      </div>
    </div>
  );
}
