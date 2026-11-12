import { unzipSync } from 'fflate';
import {
  Bible,
  Block,
  BlockAlign,
  BlockStyle,
  Book,
  Chapter,
  Markup,
  parseIntStrict,
  TranslationInfo,
  Versification,
  type VerseSegment,
} from '../model/bible';
import { stripBoilerplate } from '../model/boilerplate';
import { BookMeta, BookSection } from '../model/bookMeta';
import { ScriptureText } from '../model/textNormal';
import { VersificationCheck } from '../model/versificationCheck';
import { ReferenceSearch } from './referenceSearch';
import {
  childrenOf,
  findAllElements,
  findElements,
  getAttribute,
  innerText,
  isElement,
  isTextNode,
  localName,
  parseXhtml,
  parseXml,
  rootElement,
  textOf,
  type XmlDocument,
  type XmlElement,
  type XmlNode,
} from './xmlDom';

/**
 * What came of reading an EPUB: a Bible, or the reason there is not one,
 * and whatever the conversion had to guess at along the way.
 */
export class ImportResult {
  readonly bible: Bible | null;

  /**
   * Null when it worked; otherwise why it did not, in words a reader can do
   * something with.
   */
  readonly failure: string | null;

  /**
   * Books that were found but had nothing in them, chapters that came out
   * empty, and so on. Worth showing: a Bible that is missing Obadiah should
   * say so rather than look complete.
   */
  readonly warnings: readonly string[];

  constructor(init: { bible?: Bible | null; failure?: string | null; warnings?: readonly string[] } = {}) {
    this.bible = init.bible ?? null;
    this.failure = init.failure ?? null;
    this.warnings = init.warnings ?? [];
  }

  static failed(reason: string): ImportResult {
    return new ImportResult({ failure: reason });
  }

  get ok(): boolean {
    return this.bible !== null;
  }
}

/** One file out of the EPUB's zip. */
interface ArchiveFile {
  readonly name: string;
  readonly content: Uint8Array;
}

/**
 * Turns a Bible in EPUB form into the app's own model.
 *
 * There is no standard for how a Bible is marked up in an EPUB, so this
 * reads the three shapes that cover nearly all of them:
 *
 *  - numbered elements: `<sup>3</sup>`, `<span class="verse">3</span>`, or
 *    an `id` like `V3` — the usual output of Bible publishing tools;
 *  - a number at the head of a paragraph, where each paragraph is a verse;
 *  - `3:16` at the head of a paragraph, the shape Project Gutenberg's texts
 *    take, which carries the chapter as well.
 *
 * Books and chapters are recognised by their headings. Anything that cannot
 * be placed is left out and reported rather than guessed at: a Bible with
 * invented verse numbers would be worse than no Bible at all.
 */
export class EpubImport {
  private constructor() {}

  /** Verse numbers above this are not verse numbers. */
  static readonly maxVerse = 176;

  /** Nor are chapter numbers above this. */
  static readonly maxChapter = 150;

  static convert(bytes: Uint8Array, fileName = 'import'): ImportResult {
    // An EPUB is a zip, and a zip starts 'PK'. Without this the decoder makes
    // an empty archive of anything at all and the failure reads as a broken
    // EPUB rather than as the text file it is.
    if (bytes.length < 4 || bytes[0] !== 0x50 || bytes[1] !== 0x4b) {
      return ImportResult.failed('That file is not an EPUB.');
    }

    let unzipped: Record<string, Uint8Array>;
    try {
      unzipped = unzipSync(bytes);
    } catch (error) {
      return ImportResult.failed(`That file is not an EPUB (${describeError(error)}).`);
    }

    const files = new Map<string, ArchiveFile>();
    for (const [name, content] of Object.entries(unzipped)) {
      // A directory entry ends in a slash and holds nothing.
      if (name.endsWith('/')) continue;
      files.set(normalisePath(name), { name, content });
    }

    const opfPath = findOpf(files);
    if (opfPath === null) {
      return ImportResult.failed('That EPUB has no package file, so there is no telling what is in it.');
    }

    let opf: XmlDocument;
    try {
      opf = parseXml(text(files.get(opfPath)!));
    } catch (error) {
      return ImportResult.failed(`The EPUB package file is broken (${describeError(error)}).`);
    }

    const base = directoryOf(opfPath);
    // The table of contents is in the spine of most EPUBs, and it is not
    // Scripture: read as one it puts a list of every book of the Bible in
    // whatever chapter happened to be open. The manifest says which file
    // it is, so there is nothing to guess at.
    const navigation = navigationPaths(opf, base);
    const documents = spineDocuments(opf, files, base)
      .filter((file) => !navigation.has(normalisePath(file.name)))
      // An edition that files a book's footnotes and cross-references as
      // documents of their own puts them in the reading order too. They
      // are apparatus about the text rather than the text, and reading
      // them as Scripture had every reference in them counted as a
      // verse of chapter 1 of the book they annotate.
      .filter((file) => !isApparatus(file.name));
    if (documents.length === 0) {
      return ImportResult.failed('That EPUB has no readable chapters in it.');
    }

    const labels = tocLabels(files, opf, base);
    const builder = new BibleBuilder();
    for (const document of documents) {
      try {
        builder.read(parseXhtml(repair(text(document))), document.name, labels.get(normalisePath(document.name)));
      } catch (error) {
        builder.warn(`Skipped ${document.name}: ${describeError(error)}`);
      }
    }

    let books = builder.finish();

    // Take out the furniture the edition prints around every book. Every
    // rule above this one reads the markup and can be defeated by an
    // edition that marks its navigation up some other way; this one reads
    // only the text, and asks a question no single paragraph can answer.
    const swept = stripBoilerplate(books);
    if (!swept.isEmpty) {
      books = [...swept.books];
      builder.warn(
        `Dropped ${swept.removed.length} ${swept.removed.length === 1 ? 'line' : 'lines'} the edition ` +
          `repeats around every book, belonging to no verse: ${quoted(swept.removed)}.`,
      );
    }

    if (books.length === 0) {
      return new ImportResult({
        failure:
          'No books of the Bible could be found in that EPUB. The headings ' +
          'have to name the books — "Genesis", "1 Corinthians" — and the ' +
          'verses have to be numbered.',
        warnings: builder.warnings,
      });
    }

    // Which verse numbering this follows decides whether the bundled
    // cross-references and the original-language layer can be pointed at
    // it. They do not fail against a Bible numbered differently; they
    // quietly land on the wrong verse, so this is measured rather than
    // assumed.
    const described = new Bible({ translation: describe(opf, fileName), books });
    const match = VersificationCheck.against(described);
    if (match.versification === Versification.other) {
      builder.warn(
        'This Bible numbers its verses differently from the ones bundled ' +
          `with the app — ${match.differing} of ${match.compared} chapters ` +
          'are a different length. Cross-references and the Hebrew and Greek ' +
          'are not offered for it, because they would point at the wrong ' +
          'verses. Everything else works.',
      );
      for (const example of match.examples) {
        builder.warn(example);
      }
    }

    return new ImportResult({
      bible: new Bible({
        translation: described.translation.copyWith({ versification: match.versification }),
        books,
      }),
      warnings: builder.warnings,
    });
  }
}

function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** What to call the translation this EPUB holds. */
function describe(opf: XmlDocument, fileName: string): TranslationInfo {
  const metadata = (name: string): string => {
    for (const element of findAllElements(opf, name)) {
      const value = innerText(element).trim();
      if (value.length > 0) return value;
    }
    return '';
  };

  const title = metadata('title');
  const name = title.length === 0 ? stem(fileName) : title;
  const rights = metadata('rights');
  const publisher = metadata('publisher');

  return new TranslationInfo({
    id: identifier(name, metadata('identifier')),
    name,
    abbreviation: abbreviate(name),
    license: rights.length === 0 ? 'Imported — licence not stated in the file' : rights,
    sourceUrl: publisher.length === 0 ? fileName : `${publisher} · ${fileName}`,
  });
}

/**
 * A stable id for the translation, so that re-importing the same EPUB
 * replaces it rather than making a second copy.
 */
function identifier(name: string, identifier: string): string {
  const seed = identifier.length === 0 ? name : identifier;
  let hash = 0x811c9dc5;
  for (const unit of new TextEncoder().encode(seed)) {
    // The low 32 bits of the product, which is what Dart's `& 0xffffffff`
    // kept; a plain multiply here would lose bits past 2^53.
    hash = Math.imul(hash ^ unit, 0x01000193) >>> 0;
  }
  const slug = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  const short = slug.length > 24 ? slug.substring(0, 24) : slug;
  return `import-${short.length === 0 ? 'bible' : short}-${hash.toString(16).padStart(8, '0')}`;
}

/**
 * Initials, which is what most translations use: "World English Bible"
 * becomes WEB.
 */
function abbreviate(name: string): string {
  const words = name
    .split(/\s+/)
    .filter((word) => word.length > 0)
    .filter((word) => !smallWords.has(word.toLowerCase()));
  if (words.length === 0) return 'BIB';
  const letters = words
    .slice(0, 4)
    .map((word) => word[0].toUpperCase())
    .join('');
  return letters.length < 2 ? words[0].substring(0, Math.min(Math.max(words[0].length, 0), 3)).toUpperCase() : letters;
}

const smallWords = new Set(['the', 'a', 'an', 'of', 'in', 'and', 'holy']);

function stem(fileName: string): string {
  const parts = fileName.split('/');
  const base = parts[parts.length - 1];
  const dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

function normalisePath(path: string): string {
  const parts: string[] = [];
  for (const part of path.split('/')) {
    if (part.length === 0 || part === '.') continue;
    if (part === '..') {
      if (parts.length > 0) parts.pop();
      continue;
    }
    parts.push(part);
  }
  return parts.join('/');
}

function directoryOf(path: string): string {
  const slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

function resolve(base: string, href: string): string {
  const target = decodePercent(href.split('#')[0]);
  return normalisePath(base.length === 0 ? target : `${base}/${target}`);
}

/** Dart's `Uri.decodeFull`: percent-encodings undone, a bad one left as it is. */
function decodePercent(text: string): string {
  try {
    return decodeURIComponent(text);
  } catch {
    return text;
  }
}

function findOpf(files: Map<string, ArchiveFile>): string | null {
  const container = files.get('META-INF/container.xml');
  if (container !== undefined) {
    try {
      const document = parseXml(text(container));
      for (const rootfile of findAllElements(document, 'rootfile')) {
        const path = getAttribute(rootfile, 'full-path');
        if (path !== null && files.has(normalisePath(path))) {
          return normalisePath(path);
        }
      }
    } catch {
      // Fall through to looking for it.
    }
  }
  for (const path of files.keys()) {
    if (path.toLowerCase().endsWith('.opf')) return path;
  }
  return null;
}

/**
 * Whether a document's name says it holds a book's apparatus rather
 * than the book: `b03.00.Leviticus.crossrefs.xhtml`.
 */
function isApparatus(path: string): boolean {
  const parts = path.split('/');
  let stem = parts[parts.length - 1];
  const dot = stem.lastIndexOf('.');
  if (dot > 0) stem = stem.substring(0, dot);
  const pieces = stem.split('.');
  if (pieces.length < 2) return false;
  return apparatusDocuments.has(pieces[pieces.length - 1].toLowerCase());
}

const apparatusDocuments = new Set(['footnotes', 'crossrefs', 'crossreferences', 'notes']);

/** The reading order: the spine, resolved through the manifest. */
function spineDocuments(opf: XmlDocument, files: Map<string, ArchiveFile>, base: string): ArchiveFile[] {
  const hrefById = new Map<string, string>();
  for (const item of findAllElements(opf, 'item')) {
    const id = getAttribute(item, 'id');
    const href = getAttribute(item, 'href');
    if (id !== null && href !== null) hrefById.set(id, href);
  }

  const documents: ArchiveFile[] = [];
  for (const ref of findAllElements(opf, 'itemref')) {
    const id = getAttribute(ref, 'idref');
    const href = id === null ? undefined : hrefById.get(id);
    if (href === undefined) continue;
    const file = files.get(resolve(base, href));
    if (file !== undefined) documents.push(file);
  }

  if (documents.length === 0) {
    // No usable spine: fall back to every XHTML file, in name order, which
    // is how most of them are laid out anyway.
    const paths = [...files.keys()]
      .filter((path) => path.endsWith('.xhtml') || path.endsWith('.html') || path.endsWith('.htm'))
      .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    for (const path of paths) {
      documents.push(files.get(path)!);
    }
  }
  return documents;
}

/**
 * The EPUB's own navigation documents: the EPUB 3 nav, which the
 * manifest marks `properties="nav"`, and the EPUB 2 `toc.ncx`.
 */
function navigationPaths(opf: XmlDocument, base: string): Set<string> {
  const paths = new Set<string>();
  for (const item of findAllElements(opf, 'item')) {
    const href = getAttribute(item, 'href');
    if (href === null) continue;
    const properties = getAttribute(item, 'properties') ?? '';
    const mediaType = getAttribute(item, 'media-type') ?? '';
    if (properties.split(/\s+/).includes('nav') || mediaType.includes('x-dtbncx')) {
      paths.add(resolve(base, href));
    }
  }
  return paths;
}

/**
 * What the table of contents calls each document — the EPUB 3 nav, or
 * the EPUB 2 `toc.ncx`. A Bible whose chapter files carry no book title
 * of their own is still named here.
 */
function tocLabels(files: Map<string, ArchiveFile>, opf: XmlDocument, base: string): Map<string, string> {
  const labels = new Map<string, string>();

  const note = (href: string | null, label: string | null): void => {
    if (href === null || label === null) return;
    const value = label.replace(/\s+/g, ' ').trim();
    if (value.length === 0) return;
    const key = resolve(base, href);
    if (!labels.has(key)) labels.set(key, value);
  };

  for (const item of findAllElements(opf, 'item')) {
    const href = getAttribute(item, 'href');
    const properties = getAttribute(item, 'properties') ?? '';
    const mediaType = getAttribute(item, 'media-type') ?? '';
    if (href === null) continue;
    const isNav = properties.split(/\s+/).includes('nav');
    const isNcx = mediaType.includes('x-dtbncx');
    if (!isNav && !isNcx) continue;

    const file = files.get(resolve(base, href));
    if (file === undefined) continue;
    let document: XmlDocument;
    try {
      // The NCX is XML; the nav document is XHTML, and read as such.
      document = isNcx ? parseXml(repair(text(file))) : parseXhtml(repair(text(file)));
    } catch {
      continue;
    }

    // EPUB 2: navPoint → navLabel/text plus content/@src.
    for (const point of findAllElements(document, 'navPoint')) {
      const content = findElements(point, 'content')[0];
      const label = findElements(point, 'navLabel')[0];
      note(content === undefined ? null : getAttribute(content, 'src'), label === undefined ? null : innerText(label));
    }

    // EPUB 3: the nav document is a list of links.
    for (const link of findAllElements(document, 'a')) {
      note(getAttribute(link, 'href'), innerText(link));
    }
  }
  return labels;
}

/**
 * The first few of a list, quoted, so a warning names what it dropped
 * without running to a page of it.
 */
function quoted(lines: readonly string[]): string {
  const shown = 4;
  const short = (line: string): string => (line.length <= 40 ? line : `${line.substring(0, 39)}…`);
  const quotedLines = lines.slice(0, shown).map((line) => `"${short(line)}"`);
  return lines.length <= shown ? quotedLines.join(', ') : `${quotedLines.join(', ')} and ${lines.length - shown} more`;
}

/**
 * A document's text, composed to NFC.
 *
 * An EPUB may carry its accents decomposed, or two Hebrew points in
 * either order. Either looks right on the page and matches nothing a
 * reader types, so everything is composed once, here, before it is
 * parsed — which covers the Scripture, the headings the books are named
 * from and the footnotes alike.
 */
function text(file: ArchiveFile): string {
  return ScriptureText.normalise(new TextDecoder('utf-8').decode(file.content));
}

/**
 * XHTML is XML, but plenty of EPUBs carry HTML's named entities, which an
 * XML parser has no table for. The five XML entities are left alone.
 */
function repair(xhtml: string): string {
  const withoutDoctype = xhtml.replace(/<!DOCTYPE[^>]*>/gi, '');
  return withoutDoctype.replace(/&([a-zA-Z][a-zA-Z0-9]+);/g, (whole, name: string) => {
    if (xmlEntities.has(name)) return whole;
    return entities[name] ?? ' ';
  });
}

const xmlEntities = new Set(['amp', 'lt', 'gt', 'quot', 'apos']);

const entities: Record<string, string> = {
  nbsp: ' ',
  ensp: ' ',
  emsp: ' ',
  thinsp: ' ',
  mdash: '—',
  ndash: '–',
  hellip: '…',
  lsquo: '‘',
  rsquo: '’',
  ldquo: '“',
  rdquo: '”',
  sect: '§',
  para: '¶',
  middot: '·',
  deg: '°',
  copy: '©',
  reg: '®',
  trade: '™',
  dagger: '†',
  Dagger: '‡',
  bull: '•',
  prime: '′',
  Prime: '″',
  laquo: '«',
  raquo: '»',
  eacute: 'é',
  egrave: 'è',
  agrave: 'à',
  ccedil: 'ç',
  uuml: 'ü',
  ouml: 'ö',
  auml: 'ä',
};

/** A book a name or heading resolved to, and the chapter where it carried one. */
interface NamedBook {
  code: string;
  chapter: number | null;
}

/** What chapter — and, where the marker carries it, what verse — a chapter label opens. */
interface ChapterOpening {
  chapter: number;
  verse: number | null;
}

/** Builds books out of a stream of XHTML documents. */
class BibleBuilder {
  readonly warnings: string[] = [];

  private readonly _blocks = new Map<string, Map<number, Block[]>>();
  private readonly _notes = new Map<string, Map<number, string[]>>();

  private _book: string | null = null;
  private _chapter = 0;
  private _verse = 0;

  /**
   * Headings wait here until there is Scripture under them.
   *
   * A section heading belongs to what follows, and what follows is often
   * the next chapter — "The Flood Subsides" is printed before Genesis 8:1,
   * while the reader is still in chapter 7. Holding it until the next verse
   * opens puts it at the head of the chapter it introduces instead of
   * stranding it at the foot of the one before.
   * Each held block with the chapter that was open when it was gathered,
   * so one that turns out to open a different chapter can be stripped of
   * the verse number it would otherwise claim from the chapter before.
   */
  private readonly _pending: { block: Block; chapter: number }[] = [];

  private static readonly chapterHeading = /^(?:chapter|psalm|chap\.?)?\s*(\d{1,3})\s*$/i;
  private static readonly leadingVerse = /^\s*(\d{1,3})[.\s ]+/;
  private static readonly leadingChapterVerse = /^\s*(\d{1,3}):(\d{1,3})[.\s ]+/;

  /**
   * Project Gutenberg's Bibles number every verse from the book up:
   * `41:001:001` is Mark 1:1. Read as chapter and verse it would put the
   * whole Gospel into a chapter 41 that does not exist.
   */
  private static readonly leadingBookChapterVerse = /^\s*(\d{1,3}):(\d{1,3}):(\d{1,3})[.\s]+/;

  /**
   * The sixty-six books of the Protestant canon in order, which is how
   * Project Gutenberg numbers them.
   */
  private static readonly canonicalOrder: readonly string[] = BookMeta.all
    .filter((meta) => meta.section !== BookSection.deuterocanon)
    .map((meta) => meta.code);
  private static readonly digits = /^\s*(\d{1,3})[.:\s ]*$/;
  private static readonly whitespace = /\s+/g;
  private static readonly anyNumber = /\d{1,3}/;
  private static readonly romanHeading = /^(?:chapter|psalm|chap\.?)?\s*([ivxlc]+)\s*$/i;

  /**
   * The first number in a string, for a chapter label in a language whose
   * word for "chapter" this app has never heard of.
   */
  private static numberIn(text: string): number | null {
    const match = BibleBuilder.anyNumber.exec(text);
    return match === null ? null : Number.parseInt(match[0], 10);
  }

  /** Roman numerals, as far as a chapter number ever reaches. */
  private static roman(text: string): number | null {
    const values: Record<string, number> = { i: 1, v: 5, x: 10, l: 50, c: 100 };
    const letters = text.toLowerCase();
    let total = 0;
    let previous = 0;
    for (let i = letters.length - 1; i >= 0; i--) {
      const value = values[letters[i]];
      if (value === undefined) return null;
      if (value < previous) {
        total -= value;
      } else {
        total += value;
        previous = value;
      }
    }
    return total >= 1 && total <= EpubImport.maxChapter ? total : null;
  }

  warn(message: string): void {
    if (this.warnings.length < 40) this.warnings.push(message);
  }

  /**
   * Reads one document of the spine.
   *
   * `path` and `tocLabel` are what the EPUB says this file is, and are used
   * only when nothing inside it names a book: a file called `GEN.xhtml`, or
   * one the table of contents calls "Genesis", is Genesis even when the
   * markup never says so.
   */
  read(document: XmlDocument, path?: string, tocLabel?: string): void {
    const named = this.bookFromName(path) ?? this.bookHeading(tocLabel ?? '');
    if (named !== null && named.code !== this._book) {
      this._book = named.code;
      this._chapter = 0;
      this._verse = 0;
      if (named.chapter !== null) this.startChapter(named.chapter);
    }

    // Nothing in this document has been numbered yet. A file that numbers
    // nothing at all — a preface, a copyright page, an index, a table of
    // contents — used to have every paragraph read as a continuation of the
    // last verse of the last chapter left open, because the open verse
    // carried across the file boundary. Text ahead of a document's own
    // first verse marker belongs to no verse, and text belonging to no
    // verse is dropped.
    //
    // The open verse itself is kept, because it is the one signal that a
    // chapter has begun in an edition that heads none: a file whose numbers
    // run 1, 2, 3 after a file that ended at 31 has started a new chapter.
    this._numberedHere = false;
    this._inNavigation = false;

    const body = findAllElements(document, 'body')[0];
    const root = body ?? rootElement(document);
    if (root === null) return;
    this.walk(root, BlockStyle.paragraph, 0);
  }

  /**
   * A book named by a file name: `GEN.xhtml`, `01_Genesis.xhtml`,
   * `PSA119.xhtml`.
   */
  private bookFromName(path: string | undefined): NamedBook | null {
    if (path === undefined) return null;
    const pieces = path.split('/');
    let stem = pieces[pieces.length - 1];
    const dot = stem.lastIndexOf('.');
    if (dot > 0) stem = stem.substring(0, dot);

    // An edition that files its books as `b62.00.1-John.text.xhtml` puts
    // three things in one name: where the file sorts, what book it holds,
    // and which part of that book's apparatus it is. Only the middle one
    // names a book, and leaving the other two in is how "1-John" came to
    // be read as John — which put the whole of 1, 2 and 3 John inside the
    // Gospel, silently.
    const parts = stem.split('.');
    if (parts.length > 1) {
      while (parts.length > 1 && BibleBuilder.orderPrefix.test(parts[0])) {
        parts.shift();
      }
      while (parts.length > 1 && BibleBuilder.apparatusName.has(parts[parts.length - 1].toLowerCase())) {
        parts.pop();
      }
      stem = parts.join(' ');
    }

    stem = stem
      // "GEN01" is a book and a chapter; "1CO" is one book.
      .replace(/([A-Za-z])(\d)/g, (_match, letter: string, digit: string) => `${letter} ${digit}`)
      .replace(/[_\-.]+/g, ' ')
      .trim();
    if (stem.length === 0) return null;

    // As written first. A leading number is only a file-order number if
    // the name does not read as a book with it — "1 John" is a book and
    // stripping its 1 made it John, which put three whole epistles inside
    // the Gospel.
    const asWritten = this.bookHeading(stem);
    if (asWritten !== null) return asWritten;

    const withoutOrder = stem.replace(/^\s*\d{1,3}\s+/, '').trim();
    if (withoutOrder.length === 0 || withoutOrder === stem) return null;
    return this.bookHeading(withoutOrder);
  }

  /**
   * A file-name component that says where the file sorts rather than what
   * is in it: `b62`, `00`, `019`.
   */
  private static readonly orderPrefix = /^[A-Za-z]?\d{1,3}$/;

  /**
   * A file-name component naming a part of a book's apparatus rather than
   * the book.
   */
  private static readonly apparatusName = new Set([
    'text',
    'main',
    'footnotes',
    'crossrefs',
    'notes',
    'intro',
    'introduction',
  ]);

  /** Walks the tree, emitting a block for each block-level element. */
  private walk(node: XmlElement, style: BlockStyle, indent: number): void {
    for (const child of childrenOf(node)) {
      if (!isElement(child)) continue;
      const name = localName(child).toLowerCase();
      const classes = (getAttribute(child, 'class') ?? '').toLowerCase();

      if (this.skip(child)) continue;

      if (this.isHeading(name, classes)) {
        this.heading(innerText(child), name, this.isChapterLabel(classes), BibleBuilder.headingLevel(name, classes));
        continue;
      }

      if (this.isBlock(name, classes)) {
        // A row of links is navigation, not Scripture.
        if (this.isNavigation(child)) {
          this._inNavigation = true;
          continue;
        }
        const blockStyle = this.styleFor(name, classes, style);
        const level = this.poetryLevel(classes);
        // A row holds cells, which are not blocks: the row is read whole
        // however many cells it has, or each name of a genealogy would
        // become a paragraph of its own.
        if (this.hasBlockChildren(child) && blockStyle !== BlockStyle.tableRow) {
          this.walk(child, blockStyle, level ?? indent + (name === 'blockquote' ? 1 : 0));
        } else {
          this.paragraph(
            child,
            blockStyle,
            level ?? (blockStyle === BlockStyle.listItem ? this._listDepth : indent + (name === 'blockquote' ? 1 : 0)),
          );
        }
        continue;
      }

      // How deep a list is nested is the level of the items inside it.
      if (name === 'ol' || name === 'ul') {
        this._listDepth++;
        this.walk(child, style, indent);
        this._listDepth--;
        continue;
      }

      this.walk(child, style, indent);
    }
  }

  private static readonly blockChildNames = new Set([
    'p',
    'div',
    'blockquote',
    'ul',
    'ol',
    'li',
    'table',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
  ]);

  private hasBlockChildren(element: XmlElement): boolean {
    return childrenOf(element).some(
      (child) => isElement(child) && BibleBuilder.blockChildNames.has(localName(child).toLowerCase()),
    );
  }

  private static readonly skippedNames = new Set([
    'script',
    'style',
    'head',
    'nav',
    'figure',
    'img',
    // A footnote proper, kept at the end of the file.
    'aside',
    // The machinery of a pop-up note.
    'input',
  ]);

  /**
   * Classes whose contents are apparatus rather than Scripture.
   *
   * `note` matters as much as `footnote`: haiola writes each footnote
   * inline as `<span class='note'>…</span>`, so without this the note's
   * text lands in the middle of the verse it annotates.
   */
  private static readonly skippedClasses = new Set([
    'footnote',
    'note',
    'noteref',
    'notemark',
    // Hidden by the edition's own stylesheet.
    'hide',
    'hidden',
    // Navigation the edition draws around the text.
    'nav',
    'navheader',
    'poplink',
    'toclink',
    'index',
    'link',
    'bookname',
    'notebackref',
    'ntlbl',
    'popnote',
    'ftxt',
    'crossref',
    'xref',
    'copyright',
    'toc',
  ]);

  /**
   * Whether a block is a row of links rather than a word of Scripture.
   *
   * A book's landing page lists the chapters under it — "1 John 1 · 1 John
   * 2 · …" — and an edition that puts one in the reading order had that
   * read as the first verse of the book: a paragraph opening with a number
   * is one of the ways an edition numbers a verse, so the "1" of "1 John
   * 1" was taken for verse 1 and the rest of the line for its text.
   *
   * Scripture is not made of links and navigation is, which is the whole
   * test. Measured on how much of the text sits inside a link rather than
   * on how many links there are, so a verse carrying one or two of them —
   * a footnote marker, a reference — is not mistaken for a menu. Two links
   * at least, because a single one is as likely to be a citation as a
   * list, and a heading is never judged this way: plenty of editions make
   * a chapter's own heading a link to itself.
   */
  private isNavigation(element: XmlElement): boolean {
    let links = 0;
    let linked = 0;
    let total = 0;
    // A block that numbers a verse is Scripture whatever else is in it.
    // Some editions hang a link on every verse — to a commentary, to a
    // note — and without this a verse wrapped in one end to end would be
    // read as a menu item and dropped.
    let numbered = false;

    const measure = (node: XmlNode, inLink: boolean): void => {
      if (isTextNode(node)) {
        const length = textOf(node).trim().length;
        total += length;
        if (inLink) linked += length;
        return;
      }
      if (!isElement(node)) return;
      // Apparatus is not counted either way: a verse with three footnote
      // markers in it is still a verse.
      if (this.skip(node)) return;
      const classes = BibleBuilder.classesOf(node);
      if (
        this.isChapterLabel(classes) ||
        this.verseNumber(localName(node).toLowerCase(), classes, getAttribute(node, 'id') ?? '', innerText(node)) !==
          null
      ) {
        numbered = true;
        return;
      }
      const isLink = localName(node).toLowerCase() === 'a' && (getAttribute(node, 'href') ?? '').length > 0;
      if (isLink && !inLink) links++;
      for (const child of childrenOf(node)) {
        measure(child, inLink || isLink);
      }
    };

    for (const child of childrenOf(element)) {
      measure(child, false);
    }
    if (numbered || links < 1 || total === 0) return false;
    const fraction = linked / total;
    // A block that is nothing but a link is navigation however many links
    // it has: an edition's footer puts each of "ESV", "The Old Testament"
    // and "Show Last Hilite" in a paragraph of its own, and one link each
    // is all they are. A verse is never a link end to end.
    if (fraction >= 0.95) return true;
    // Below that it takes more than one, because a single link inside a
    // run of text is as likely to be a citation as a list.
    return links >= 2 && fraction >= 0.6;
  }

  private skip(element: XmlElement): boolean {
    const name = localName(element).toLowerCase();
    if (BibleBuilder.skippedNames.has(name)) return true;

    // What the edition hides from its own reader is not Scripture. The
    // ESV keeps its whole navigation apparatus — every book of the Bible,
    // every chapter of each, and the template text around them — in a
    // `<div class="hide">` at the foot of every book's file. Nothing is
    // more authoritative about that than the file saying so itself.
    if (getAttribute(element, 'hidden') !== null) return true;
    const style = (getAttribute(element, 'style') ?? '').toLowerCase().replace(/ /g, '');
    if (style.includes('display:none') || style.includes('visibility:hidden')) {
      return true;
    }

    const classes = (getAttribute(element, 'class') ?? '').toLowerCase();
    if (BibleBuilder.classWords(classes).some((word) => BibleBuilder.skippedClasses.has(word))) {
      return true;
    }

    // EPUB 3 says what a thing is in its own attribute, whatever it is
    // classed as.
    const type = (getAttribute(element, 'type', true) ?? '').toLowerCase();
    return type.includes('footnote') || type.includes('noteref') || type.includes('endnote');
  }

  private static readonly titleClass = /^(mt|ms)\d?$/;

  /**
   * Classes for a paragraph an edition sets flush to the margin. Space
   * above it — which "line-space" asks for — is a different thing from a
   * line of verse, and reading it as one turned three hundred paragraphs
   * of prose into poetry.
   */
  private static readonly flushClasses = new Set(['noindent', 'noindentlinespace', 'nofirstlineindent', 'flush']);

  /** How an edition marks what Jesus says. */
  private static readonly wordsOfChrist = new Set(['woc', 'wj', 'wordsofchrist', 'wordsofjesus', 'redletter']);

  /**
   * Classes that mark an element as the label opening a chapter. haiola —
   * which generates the EPUBs on ebible.org, and so most of the freely
   * available ones — writes every chapter label as `psalmlabel`, Psalms or
   * not, so this is the difference between reading those Bibles and
   * refusing them.
   */
  private static readonly chapterClasses = new Set([
    'chapterlabel',
    'psalmlabel',
    'chapternum',
    'chapternumber',
    // USFM's own marker for a chapter label. Not bare "c", which as often
    // as not means centred.
    'cl',
  ]);

  private isChapterLabel(classes: string): boolean {
    return BibleBuilder.classWords(classes).some((word) => BibleBuilder.chapterClasses.has(word));
  }

  private static readonly headingNames = new Set(['h1', 'h2', 'h3', 'h4', 'h5', 'h6']);

  private isHeading(name: string, classes: string): boolean {
    return (
      BibleBuilder.headingNames.has(name) ||
      this.isChapterLabel(classes) ||
      BibleBuilder.classWords(classes).some((word) => BibleBuilder.titleClass.test(word))
    );
  }

  private static readonly blockNames = new Set(['p', 'div', 'blockquote', 'li', 'tr']);

  private isBlock(name: string, _classes: string): boolean {
    return BibleBuilder.blockNames.has(name);
  }

  private _listDepth = 0;
  private _cellsInRow = 0;

  /** Whether a verse marker has been seen in the document being read. */
  private _numberedHere = false;

  /**
   * Whether this document has reached its navigation.
   *
   * A footer is not one block. Between the links an edition writes plain
   * labels — "ESV · The Old Testament" heads the list of the books under
   * it — which carry no link to give them away and would otherwise be
   * appended to the last verse of the book, as the links themselves used
   * to be. Once a document is into its navigation, everything that
   * follows is navigation until something numbers a verse again.
   */
  private _inNavigation = false;

  /**
   * What was last placed, which is how a line carrying nothing but an
   * indent is read: after a line of verse it is another line of verse.
   */
  private _lastStyle: BlockStyle | null = null;

  /** What a verse is printed as, by the verse it is stored under. */
  private readonly _labels = new Map<string, Map<number, Map<number, string>>>();

  /** The labels of the chapter being read. */
  private readonly _verseLabels = new Map<number, string>();

  /**
   * Every verse a chapter numbers, so one numbered and left empty can be
   * told from one that was never there.
   */
  private readonly _seen = new Map<string, Map<number, Set<number>>>();
  private readonly _versesSeenHere = new Set<number>();

  /** A bridged verse as the edition prints it: "1-2", "1,2", "1–3". */
  private static printedVerse(text: string): string | null {
    const match = BibleBuilder.bridgedVerses.exec(text.trim());
    return match === null ? null : match[0].trim();
  }

  /**
   * A cell of a table. Not a block of its own: a row is the block, and
   * its cells are parted inside it, or a genealogy comes out as one
   * paragraph per name.
   */
  private static isCell(name: string): boolean {
    return name === 'td' || name === 'th';
  }

  /** Where the markup sets a block across the column. */
  private static alignFor(classes: string, style: string): BlockAlign {
    const flattened = style.replace(/ /g, '');
    if (flattened.includes('text-align:center')) return BlockAlign.center;
    if (flattened.includes('text-align:right')) return BlockAlign.end;
    for (const word of BibleBuilder.classWords(classes)) {
      if (word === 'center' || word === 'centre' || word === 'centered' || word === 'qc' || word === 'pc') {
        return BlockAlign.center;
      }
      if (word === 'right' || word === 'qr' || word === 'pr' || word === 'colophon') {
        return BlockAlign.end;
      }
    }
    return BlockAlign.start;
  }

  /**
   * What a section heading is called. USFM says `s1`; the editions that
   * were not generated from USFM spell it out.
   */
  private static readonly headingClasses = new Set([
    's',
    's1',
    's2',
    's3',
    'section',
    'sectionhead',
    'sectionheading',
    'subhead',
    'subheading',
    'heading',
    'head',
  ]);

  /**
   * How deep a poetry line is indented, where the markup says so: `q2`,
   * `line2`, `indent-2`. Without it every line of a psalm sits at the same
   * depth and the couplets stop reading as couplets.
   */
  private static readonly levelClass = /^(?:q|iq|li|pi|line|indent)-?([1-4])$/;

  /**
   * A class that says a line is indented and nothing else: `indent`,
   * `indent2`, `block-indent`.
   */
  private static readonly indentClass = /^(?:block|line)?indent([1-4])?$/;

  static classesOf(element: XmlElement): string {
    return (getAttribute(element, 'class') ?? '').toLowerCase();
  }

  /**
   * The class names in an attribute, with the punctuation publishers vary
   * on taken out.
   *
   * `chapter-num`, `chapternum` and `chapter_num` are one class spelled
   * three ways, and all three turn up; the sets below used to have to
   * carry every spelling, and a spelling nobody had thought of — a
   * hyphenated `psalm-title` — simply did not match.
   */
  private static classWords(classes: string): string[] {
    return classes
      .split(/[\s]+/)
      .map((word) => word.replace(/[-_]/g, ''))
      .filter((word) => word.length > 0);
  }

  /**
   * How major a heading is, where the markup says. An EPUB spells it
   * either in the tag — `h1` above `h2` — or in a class, `s1` above `s2`.
   */
  private static headingLevel(name: string, classes: string): number {
    for (const word of BibleBuilder.classWords(classes)) {
      if (word === 'ms' || word === 'ms1' || word === 'majorsection') return 1;
      if (word === 's' || word === 's1') return 2;
      if (word === 's2' || word === 's3' || word === 's4') return 3;
    }
    switch (name) {
      case 'h1':
      case 'h2':
        return 2;
      case 'h3':
        return 2;
      case 'h4':
      case 'h5':
      case 'h6':
        return 3;
      default:
        return 0;
    }
  }

  /**
   * Text a publisher sets in small capitals, which in Scripture means the
   * divine name. Spelled as a class, or in a style attribute.
   */
  private static isDivineName(name: string, classes: string, style: string): boolean {
    if (name === 'abbr') return false;
    for (const word of BibleBuilder.classWords(classes)) {
      if (
        word === 'nd' ||
        word === 'divine' ||
        word === 'divinename' ||
        word === 'sc' ||
        word === 'smallcap' ||
        word === 'smallcaps'
      ) {
        return true;
      }
    }
    return style.replace(/ /g, '').includes('font-variant:small-caps');
  }

  private poetryLevel(classes: string): number | null {
    for (const word of BibleBuilder.classWords(classes)) {
      const match = BibleBuilder.levelClass.exec(word);
      if (match !== null) return Number.parseInt(match[1], 10);
      // An indent with no depth on it is one step in from the line above.
      if (BibleBuilder.indentClass.test(word)) return 2;
    }
    return null;
  }

  private styleFor(name: string, classes: string, inherited: BlockStyle): BlockStyle {
    if (name === 'blockquote') return BlockStyle.poetry;
    const words = BibleBuilder.classWords(classes);
    // Before the poetry test below: "qa" begins with a q and is not a
    // line of verse but the letter an acrostic stanza runs on.
    if (words.some((c) => c === 'qa' || c === 'acrostic')) {
      return BlockStyle.acrostic;
    }
    if (words.some((c) => c === 'sp' || c === 'speaker')) {
      return BlockStyle.speaker;
    }
    if (
      words.some(
        (c) =>
          c.startsWith('q') ||
          c === 'poetry' ||
          c === 'line' ||
          c === 'poem' ||
          c === 'iq' ||
          // A stanza, and a stanza opening under a heading.
          c === 'linegroup' ||
          c === 'linegroupafterheading' ||
          c === 'lineindent',
      )
    ) {
      return BlockStyle.poetry;
    }
    // A line that says nothing about itself but how far it is indented,
    // coming straight after a line of verse, is the next line of the same
    // stanza — which is how the ESV sets the second line of a couplet.
    // Read as prose it took a paragraph's first-line indent and wrapped
    // back to the margin, so a couplet came out looking like a poetry line
    // that had lost its indent. Only after verse: an indented paragraph of
    // prose is a common thing in its own right.
    if (this._lastStyle === BlockStyle.poetry && words.some((word) => BibleBuilder.indentClass.test(word))) {
      return BlockStyle.poetry;
    }
    if (words.some((c) => c === 'psalmacrostictitle' || c === 'acrostictitle')) {
      return BlockStyle.acrostic;
    }
    if (
      words.some(
        (c) => c === 'd' || c === 'psalmtitle' || c === 'psalmref' || c === 'superscription' || c === 'descriptivetitle',
      )
    ) {
      return BlockStyle.descriptiveTitle;
    }
    if (words.some((word) => BibleBuilder.headingClasses.has(word))) {
      return BlockStyle.heading;
    }
    if (name === 'li') return BlockStyle.listItem;
    if (name === 'tr') return BlockStyle.tableRow;
    return inherited === BlockStyle.poetry ? BlockStyle.poetry : BlockStyle.paragraph;
  }

  /**
   * A heading either names a book, numbers a chapter, or belongs to the text
   * as a section heading.
   */
  private heading(rawText: string, tag: string, labelsChapter = false, level = 0): void {
    const text = rawText.replace(BibleBuilder.whitespace, ' ').trim();
    if (text.length === 0) return;

    // An element the markup itself calls a chapter label is one, whatever
    // language it is labelled in: "Chapter 3", "Kapitel 3", "Psalm 23", or
    // bare "3". Only the number has to be found.
    if (labelsChapter) {
      const number = BibleBuilder.numberIn(text);
      if (number !== null && number <= EpubImport.maxChapter) {
        this.startChapter(number);
      }
      return;
    }

    const book = this.bookHeading(text);
    if (book !== null) {
      // Whatever was waiting belonged to the book that just ended, so it
      // is placed there rather than thrown away: the Song of Songs ends
      // with a speaker's label and nothing follows it to flush it out.
      this.flushPending();
      this._book = book.code;
      this._chapter = 0;
      this._verse = 0;
      // "John 3" names the book and opens the chapter in one line.
      if (book.chapter !== null) this.startChapter(book.chapter);
      return;
    }

    const chapter = BibleBuilder.chapterHeading.exec(text);
    if (chapter !== null) {
      const number = Number.parseInt(chapter[1], 10);
      if (number >= 1 && number <= EpubImport.maxChapter) {
        this.startChapter(number);
        return;
      }
    }

    // "CHAPTER XXIII", the way older editions number them.
    const roman = BibleBuilder.romanHeading.exec(text);
    if (roman !== null) {
      const number = BibleBuilder.roman(roman[1]);
      if (number !== null) {
        this.startChapter(number);
        return;
      }
    }

    // Anything else is a heading inside the text, worth keeping as one.
    if (this._book !== null && tag !== 'h1') {
      this.hold(
        new Block({
          style: BlockStyle.heading,
          level,
          segments: [{ verse: this._verse, startsVerse: false, text }],
        }),
      );
    }
  }

  private startChapter(number: number): void {
    this.stashChapter();
    this._chapter = number;
    this._verse = 0;
    if (this._book !== null) {
      const blocks = getOrPut(this._blocks, this._book, () => new Map<number, Block[]>());
      if (!blocks.has(number)) blocks.set(number, []);
      const notes = getOrPut(this._notes, this._book, () => new Map<number, string[]>());
      if (!notes.has(number)) notes.set(number, []);
    }
  }

  /** Puts away what was gathered about the chapter just left. */
  private stashChapter(): void {
    const book = this._book;
    if (book === null || this._chapter === 0) return;
    if (this._verseLabels.size > 0) {
      const chapters = getOrPut(this._labels, book, () => new Map<number, Map<number, string>>());
      const labels = getOrPut(chapters, this._chapter, () => new Map<number, string>());
      for (const [verse, label] of this._verseLabels) labels.set(verse, label);
    }
    if (this._versesSeenHere.size > 0) {
      const chapters = getOrPut(this._seen, book, () => new Map<number, Set<number>>());
      const seen = getOrPut(chapters, this._chapter, () => new Set<number>());
      for (const verse of this._versesSeenHere) seen.add(verse);
    }
    this._verseLabels.clear();
    this._versesSeenHere.clear();
  }

  /**
   * The block styles that stand above a chapter's first verse rather than
   * belonging to a verse of their own.
   */
  private static readonly opensChapter = new Set<BlockStyle>([
    BlockStyle.heading,
    BlockStyle.descriptiveTitle,
    BlockStyle.acrostic,
    BlockStyle.speaker,
  ]);

  /** Everything inside one block-level element, cut into verses. */
  private paragraph(element: XmlElement, style: BlockStyle, indent: number): void {
    this._cellsInRow = 0;
    // An edition that anchors each paragraph with a packed reference says
    // which book it is in every one of them. Believing that beats
    // believing a file name.
    this.followBook(getAttribute(element, 'id') ?? '');
    const align = BibleBuilder.alignFor(
      (getAttribute(element, 'class') ?? '').toLowerCase(),
      (getAttribute(element, 'style') ?? '').toLowerCase(),
    );
    const segments: VerseSegment[] = [];
    let buffer = '';
    let startsVerse = false;
    // Until this document numbers something, its text belongs to no verse.
    let verse = this._numberedHere ? this._verse : 0;
    // Set when a chapter opened partway through this block without saying
    // which verse it opened on, which makes the text that follows verse 1.
    let impliesFirstVerse = false;

    const flush = (): void => {
      const text = buffer.replace(BibleBuilder.whitespace, ' ');
      if (text.trim().length === 0 && !startsVerse) {
        buffer = '';
        return;
      }
      segments.push({ verse, startsVerse, text });
      buffer = '';
      startsVerse = false;
    };

    /**
     * Opens a chapter partway through a block.
     *
     * Anything buffered ahead of it precedes the new chapter's first verse,
     * so it is a label — the book's name as a running head — and is marked
     * as belonging to no verse so that it is dropped below. Text that has
     * already been placed in a verse is left as it is.
     */
    const startChapterHere = (number: number): void => {
      if (segments.length === 0 && !startsVerse) verse = 0;
      flush();
      this.startChapter(number);
    };

    const openVerse = (number: number, printed: string | null = null): void => {
      impliesFirstVerse = false;
      flush();
      // "1-2" for a bridged verse: the text is stored under the first and
      // printed as the edition prints it.
      if (printed !== null && printed !== `${number}`) {
        this._verseLabels.set(number, printed);
      }
      // Obadiah, Philemon, 2 and 3 John and Jude have one chapter, and many
      // editions give them no chapter heading at all. A numbered verse under
      // a book heading opens chapter 1 rather than being thrown away.
      if (this._chapter === 0 && this._book !== null) {
        this.startChapter(1);
      } else if (number < this._verse && this._book !== null) {
        // The numbering has gone backwards, so a chapter began and nothing
        // said so. This is the one signal that does not depend on knowing
        // how a particular edition marks its chapters.
        this.startChapter(this._chapter + 1);
      }
      verse = number;
      startsVerse = true;
      this._verse = number;
      this._numberedHere = true;
      // Scripture again: whatever navigation there was is behind us.
      this._inNavigation = false;
      this._versesSeenHere.add(number);
    };

    const write = (node: XmlNode): void => {
      if (isTextNode(node)) {
        let text = textOf(node);
        if (impliesFirstVerse && text.trim().length > 0) {
          openVerse(1);
        }
        if (buffer.length === 0 && segments.length === 0) {
          // "3:16 For God so loved…" and "16 For God so loved…" are both
          // ways of numbering a paragraph that is a verse.
          // Book, chapter and verse, before chapter and verse: "41:001:001"
          // must not be read as chapter 41.
          const numbered = BibleBuilder.leadingBookChapterVerse.exec(text);
          if (numbered !== null) {
            const book = Number.parseInt(numbered[1], 10);
            const chapter = Number.parseInt(numbered[2], 10);
            const number = Number.parseInt(numbered[3], 10);
            if (
              book >= 1 &&
              book <= BibleBuilder.canonicalOrder.length &&
              chapter >= 1 &&
              chapter <= EpubImport.maxChapter &&
              number >= 1 &&
              number <= EpubImport.maxVerse
            ) {
              const code = BibleBuilder.canonicalOrder[book - 1];
              if (code !== this._book) {
                this._book = code;
                this._chapter = 0;
                this._verse = 0;
              }
              if (chapter !== this._chapter) startChapterHere(chapter);
              openVerse(number);
              buffer += text.substring(numbered[0].length);
              return;
            }
          }

          const both = BibleBuilder.leadingChapterVerse.exec(text);
          if (both !== null) {
            const chapter = Number.parseInt(both[1], 10);
            const number = Number.parseInt(both[2], 10);
            if (chapter <= EpubImport.maxChapter && number <= EpubImport.maxVerse) {
              if (chapter !== this._chapter) startChapterHere(chapter);
              openVerse(number);
              text = text.substring(both[0].length);
            }
          } else {
            const single = BibleBuilder.leadingVerse.exec(text);
            if (single !== null) {
              const number = Number.parseInt(single[1], 10);
              // Only where it carries on from the verse before: a paragraph
              // opening "20 years later" is not verse 20.
              if (number <= EpubImport.maxVerse && (number === this._verse + 1 || (number === 1 && this._verse === 0))) {
                openVerse(number);
                text = text.substring(single[0].length);
              }
            }
          }
        }
        buffer += text;
        return;
      }
      if (!isElement(node)) return;

      const name = localName(node).toLowerCase();
      const classes = (getAttribute(node, 'class') ?? '').toLowerCase();
      const id = getAttribute(node, 'id') ?? '';

      if (this.skip(node)) return;

      // A chapter number printed inside the paragraph rather than above it.
      // The ESV and others open each chapter with
      // `<b class="chapter-num" id="v43001001-1">1:1&nbsp;</b>`, which is the
      // chapter and its first verse in one marker.
      if (this.isChapterLabel(classes)) {
        // The id on a chapter marker often carries the book as well, and
        // it is better evidence than a file name: `v62001001` is 1 John
        // whatever the file is called. Believing it is what stops a book
        // being poured into the wrong one.
        this.followBook(id);
        const opened = this.chapterAt(innerText(node), id);
        if (opened !== null) {
          if (opened.chapter !== this._chapter) startChapterHere(opened.chapter);
          if (opened.verse !== null) {
            openVerse(opened.verse);
          } else {
            // A printed Bible does not repeat the 1 of a chapter's first
            // verse: the chapter number stands for it. So whatever follows
            // this marker is verse 1, unless a verse marker gets in first.
            impliesFirstVerse = true;
          }
        }
        // Either way the marker is a number, not Scripture.
        return;
      }

      const number = this.verseNumber(name, classes, id, innerText(node));
      if (number !== null) {
        openVerse(number, BibleBuilder.printedVerse(innerText(node)));
        return;
      }

      if (name === 'br') {
        buffer += ' ';
        return;
      }

      // A cell boundary inside a row, so the row can be laid out as one.
      if (BibleBuilder.isCell(name)) {
        if (this._cellsInRow > 0) buffer += Markup.cell;
        this._cellsInRow++;
        for (const child of childrenOf(node)) {
          write(child);
        }
        return;
      }

      // What Jesus says, which a red-letter edition sets apart. The
      // marker has been in the format from the start and the EPUB
      // importer never wrote one, so an imported Bible had no red
      // letters however the edition marked them.
      if (BibleBuilder.classWords(classes).some((word) => BibleBuilder.wordsOfChrist.has(word))) {
        buffer += Markup.wjStart;
        for (const child of childrenOf(node)) {
          write(child);
        }
        buffer += Markup.wjEnd;
        return;
      }

      // "Selah", which is a direction rather than a word of the psalm.
      if (BibleBuilder.classWords(classes).includes('selah')) {
        buffer += Markup.selahStart;
        for (const child of childrenOf(node)) {
          write(child);
        }
        buffer += Markup.selahEnd;
        return;
      }

      // Words quoted from elsewhere in Scripture. Not the same thing as a
      // translator's addition, though both used to be stored as one.
      if (name === 'q' || BibleBuilder.classWords(classes).includes('qt')) {
        buffer += Markup.quotationStart;
        for (const child of childrenOf(node)) {
          write(child);
        }
        buffer += Markup.quotationEnd;
        return;
      }

      // The divine name, which an edition sets in small capitals — as a
      // class, or in a style attribute. Every printed Bible distinguishes
      // it from "Lord" as a title, and the marker is what lets this one.
      if (BibleBuilder.isDivineName(name, classes, (getAttribute(node, 'style') ?? '').toLowerCase())) {
        buffer += Markup.divineStart;
        for (const child of childrenOf(node)) {
          write(child);
        }
        buffer += Markup.divineEnd;
        return;
      }

      if (name === 'i' || name === 'em') {
        buffer += Markup.addStart;
        for (const child of childrenOf(node)) {
          write(child);
        }
        buffer += Markup.addEnd;
        return;
      }

      for (const child of childrenOf(node)) {
        write(child);
      }
    };

    for (const child of childrenOf(element)) {
      write(child);
    }
    flush();

    if (segments.length === 0) return;
    if (this._book === null) return;
    // Text before any chapter heading is a preface, not Scripture — but
    // what stands above a first verse is held rather than dropped, or
    // every book would lose the heading over its opening chapter. The ESV
    // prints that heading before the paragraph the chapter number is in,
    // so the chapter is not open yet when it arrives.
    if (this._chapter === 0 && !BibleBuilder.opensChapter.has(style)) return;

    // A heading, a psalm's superscription, the letter of an acrostic stanza
    // and a speaker's label all stand above a chapter's first verse. In an
    // edition that prints the chapter number inside that verse's own
    // paragraph — the ESV does — they arrive before anything has said the
    // chapter changed, so they are held and placed once it is known which
    // chapter they open. Without this, a psalm's heading and superscription
    // were committed to the end of the psalm before it.
    if (BibleBuilder.opensChapter.has(style)) {
      this.hold(
        new Block({
          style,
          level:
            style === BlockStyle.heading
              ? BibleBuilder.headingLevel(localName(element).toLowerCase(), BibleBuilder.classesOf(element))
              : 0,
          align,
          segments,
        }),
      );
      return;
    }

    // Once a document is into its footer, a block that numbers nothing is
    // part of that footer rather than the end of the book.
    if (this._inNavigation && !segments.some((segment) => segment.startsVerse)) {
      return;
    }

    // Text sitting before the chapter's first verse is a label, not
    // Scripture — the book's name repeated as a running head, which the
    // ESV prints inside the opening paragraph. Every word of Scripture
    // belongs to a verse.
    while (segments.length > 0 && segments[0].verse === 0 && !segments[0].startsVerse) {
      segments.shift();
    }
    if (segments.length === 0) return;

    // Whatever headings were waiting belong above this, in whatever chapter
    // this turned out to be.
    this.flushPending();
    this.add(
      new Block({
        style,
        indent:
          style === BlockStyle.poetry
            ? indent < 1
              ? 1
              : indent
            : // How deep the list was nested.
              style === BlockStyle.listItem
              ? indent < 1
                ? 1
                : indent
              : 0,
        // "no-indent" says what it means: a paragraph the edition sets
        // flush to the margin. Indenting it would misrepresent the text.
        indentFirstLine:
          style === BlockStyle.paragraph &&
          !BibleBuilder.classesOf(element)
            .split(/\s+/)
            .map((word) => word.replace(/[-_]/g, ''))
            .some((word) => BibleBuilder.flushClasses.has(word)),
        align,
        segments,
      }),
    );
  }

  private static readonly verseClasses = new Set(['v', 'vn', 'verse', 'versenum', 'versenumber', 'vnumber']);

  private static readonly verseId = /^V\d/i;
  private static readonly bridgedVerses = /^\s*(\d{1,3})\s*[-‐-―]\s*\d{1,3}[.:\s ]*$/;
  private static readonly lastNumber = /(\d{1,3})\D*$/;

  private static readonly chapterAndVerse = /(\d{1,3})\s*[:.]\s*(\d{1,3})/;

  /**
   * `v43001001-1` — book, chapter and verse in one id, the scheme Crossway
   * and several others number their anchors with.
   */
  private static readonly packedId = /^v(\d{2})(\d{3})(\d{3})/;

  /** Moves to the book a packed id names, where it names a different one. */
  private followBook(id: string): void {
    const named = BibleBuilder.bookAt(id);
    if (named === null || named === this._book) return;
    this.stashChapter();
    this.flushPending();
    this._book = named;
    this._chapter = 0;
    this._verse = 0;
  }

  /**
   * The book a packed id names, where it names one: `v62001001` is the
   * sixty-second book of the canon, which is 1 John.
   */
  private static bookAt(id: string): string | null {
    const packed = BibleBuilder.packedId.exec(id);
    if (packed === null) return null;
    const book = Number.parseInt(packed[1], 10);
    if (book < 1 || book > BibleBuilder.canonicalOrder.length) return null;
    return BibleBuilder.canonicalOrder[book - 1];
  }

  /**
   * What chapter — and, where the marker carries it, what verse — an
   * element that the markup calls a chapter number opens.
   */
  private chapterAt(text: string, id: string): ChapterOpening | null {
    // The id, where it carries the whole reference: `v01002001-1`.
    let packed: { chapter: number; verse: number } | null = null;
    const match = BibleBuilder.packedId.exec(id);
    if (match !== null) {
      const chapter = Number.parseInt(match[2], 10);
      const verse = Number.parseInt(match[3], 10);
      if (chapter >= 1 && chapter <= EpubImport.maxChapter && verse >= 1 && verse <= EpubImport.maxVerse) {
        packed = { chapter, verse };
      }
    }

    const both = BibleBuilder.chapterAndVerse.exec(text);
    if (both !== null) {
      const chapter = Number.parseInt(both[1], 10);
      const verse = Number.parseInt(both[2], 10);
      if (chapter >= 1 && chapter <= EpubImport.maxChapter && verse >= 1 && verse <= EpubImport.maxVerse) {
        return { chapter, verse };
      }
    }

    const number = BibleBuilder.numberIn(text);
    if (number !== null && number >= 1 && number <= EpubImport.maxChapter) {
      // A chapter opening prints its number and not the 1 of its first
      // verse, which the id holds. Without reading it the chapter opened
      // with no verse open and the whole of verse 1 was dropped as a
      // running head.
      return {
        chapter: number,
        verse: packed !== null && packed.chapter === number ? packed.verse : null,
      };
    }

    // Nothing printed: the id is all there is to go on.
    if (packed !== null) return packed;
    return null;
  }

  /**
   * Whether an element is a verse number rather than part of the text.
   *
   * Some editions print the number, others hold it in an `id` and draw it
   * with a stylesheet — `<a id="V3"/>` with nothing inside. The marker is
   * still a marker; the number just has to be read from somewhere else.
   */
  private verseNumber(name: string, classes: string, id: string, text: string): number | null {
    const words = BibleBuilder.classWords(classes);
    const marked =
      name === 'sup' || words.some((word) => BibleBuilder.verseClasses.has(word)) || BibleBuilder.verseId.test(id);
    if (!marked) return null;

    // "3" or, where an edition bridges two verses, "3-4".
    const digits = BibleBuilder.digits.exec(text) ?? BibleBuilder.bridgedVerses.exec(text);
    if (digits !== null) {
      const number = Number.parseInt(digits[1], 10);
      return number >= 1 && number <= EpubImport.maxVerse ? number : null;
    }

    // Nothing printed: take the number the id ends with, which is the verse
    // in every scheme going — "V3", "Gen.1.3", "GEN3_16".
    if (text.trim().length > 0) return null;
    const tail = BibleBuilder.lastNumber.exec(id);
    if (tail === null) return null;
    const number = Number.parseInt(tail[1], 10);
    return number >= 1 && number <= EpubImport.maxVerse ? number : null;
  }

  /** Holds a block that belongs above the next chapter's first verse. */
  private hold(block: Block): void {
    this._pending.push({ block, chapter: this._chapter });
  }

  private flushPending(): void {
    if (this._pending.length === 0) return;
    const held = [...this._pending];
    this._pending.length = 0;
    for (const entry of held) {
      // A block held across a chapter boundary was gathered while a verse
      // of the chapter before was still open, and must not carry that
      // verse into the chapter it opens: it stands above the first verse
      // and belongs to none.
      this.add(entry.chapter === this._chapter ? entry.block : entry.block.withoutVerses());
    }
  }

  private add(block: Block): void {
    const book = this._book;
    if (book === null || this._chapter === 0) return;
    const chapters = getOrPut(this._blocks, book, () => new Map<number, Block[]>());
    getOrPut(chapters, this._chapter, () => []).push(block);
    this._lastStyle = block.style;
  }

  /**
   * Reads a heading as the name of a book, and the chapter number where it
   * carries one ("John 3"). Headings name books in every style going — "The
   * Gospel According to John", "THE REVELATION OF ST. JOHN THE DIVINE", "The
   * First Epistle of Paul the Apostle to the Corinthians" — so the words
   * that carry no information are dropped and what is left is looked up.
   */
  private bookHeading(text: string): NamedBook | null {
    if (text.length > 60) return null;

    let words = text
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter((word) => word.length > 0);
    if (words.length === 0) return null;

    // A number at the end is the chapter, not part of the name.
    let chapter: number | null = null;
    if (words.length > 1) {
      const last = parseIntStrict(words[words.length - 1]);
      if (last !== null && last >= 1 && last <= EpubImport.maxChapter) {
        chapter = last;
        words = words.slice(0, words.length - 1);
      }
    }

    let numeral: string | null = null;
    const ordered: string[] = [];
    for (const word of words) {
      const number = BibleBuilder.numerals[word] ?? (parseIntStrict(word) !== null ? word : null);
      if (number !== null && numeral === null && ordered.length === 0) {
        numeral = number;
        continue;
      }
      if (BibleBuilder.noiseWords.has(word)) continue;
      ordered.push(word);
    }
    if (ordered.length === 0) return null;

    const prefix = numeral ?? '';
    for (const candidate of [ordered.join(''), ...ordered]) {
      const code = BibleBuilder.lookup(`${prefix}${candidate}`) ?? BibleBuilder.lookup(candidate);
      if (code !== null) return { code, chapter };
    }
    return null;
  }

  private static readonly numerals: Record<string, string> = {
    first: '1',
    second: '2',
    third: '3',
    i: '1',
    ii: '2',
    iii: '3',
  };

  /** Words that decorate a book's name without naming it. */
  private static readonly noiseWords = new Set([
    'the',
    'of',
    'to',
    'book',
    'books',
    'gospel',
    'according',
    'epistle',
    'epistles',
    'letter',
    'general',
    'st',
    'saint',
    'apostle',
    'paul',
    'holy',
    'divine',
    'prophet',
    'chapter',
  ]);

  private static lookup(key: string): string | null {
    const needle = ReferenceSearch.normalise(key);
    if (needle.length === 0) return null;
    for (const meta of BookMeta.all) {
      if (
        ReferenceSearch.normalise(meta.name) === needle ||
        ReferenceSearch.normalise(meta.abbrev) === needle ||
        meta.code.toLowerCase() === needle
      ) {
        return meta.code;
      }
    }
    return ReferenceSearch.aliases[needle] ?? null;
  }

  /** Enough text that it cannot really be a single verse. */
  private static isLong(chapter: Chapter): boolean {
    let length = 0;
    for (const block of chapter.blocks) {
      for (const segment of block.segments) {
        length += segment.text.length;
      }
      if (length > 200) return true;
    }
    return false;
  }

  finish(): Book[] {
    // Nothing is coming to flush out what is still being held, and a
    // heading or a speaker's label at the end of the last book is no less
    // part of it for being last.
    this.flushPending();
    // The chapter last read has not been put away yet.
    this.stashChapter();
    const books: Book[] = [];
    for (const [code, byNumber] of this._blocks) {
      const meta = BookMeta.lookup(code);
      if (meta === undefined) continue;

      const numbers = [...byNumber.keys()].sort((a, b) => a - b);
      const chapters: Chapter[] = [];
      for (const number of numbers) {
        const blocks = byNumber.get(number)!.filter((block) => !block.isEmpty);
        if (blocks.length === 0) continue;
        // A verse the chapter numbered and never gave text to is left out
        // on purpose, the way the critical texts drop Matthew 17:21.
        const withText = new Set<number>();
        for (const block of blocks) {
          for (const segment of block.segments) {
            if (segment.text.trim().length > 0) withText.add(segment.verse);
          }
        }
        const seen = this._seen.get(code)?.get(number) ?? new Set<number>();
        // A verse the chapter numbers and gives no text to is omitted on
        // purpose — Matthew 17:21 and the rest the critical texts leave
        // out. A number past the end of the chapter is not that: it is a
        // number this reading picked up somewhere it should not have, and
        // claiming the chapter deliberately leaves out its verse 38 when
        // it has seventeen would be a worse answer than saying nothing.
        let highest = 0;
        for (const block of blocks) {
          for (const segment of block.segments) {
            if (segment.verse > highest) highest = segment.verse;
          }
        }
        const omitted = new Set<number>();
        for (const verse of seen) {
          if (verse <= highest && !withText.has(verse)) omitted.add(verse);
        }
        const chapter = new Chapter({
          // Chapters are read by position, so they have to run 1, 2, 3 with
          // no gaps. Where the source skipped one, the shift is reported
          // rather than left for the reader to notice.
          number: chapters.length + 1,
          blocks,
          notes: this._notes.get(code)?.get(number) ?? [],
          labels: this._labels.get(code)?.get(number) ?? new Map(),
          omitted,
        });
        if (chapter.verseCount === 0) {
          this.warn(`${meta.name} ${number} has no numbered verses; left out.`);
          continue;
        }
        if (chapter.number !== number) {
          this.warn(
            `${meta.name} ${number} follows a chapter that was not found, so it is numbered ${chapter.number} here.`,
          );
        }
        if (chapter.verseCount === 1 && BibleBuilder.isLong(chapter)) {
          this.warn(`${meta.name} ${number} came through as one long verse; its verse numbers were not recognised.`);
        }
        chapters.push(chapter);
      }

      if (chapters.length === 0) {
        this.warn(`${meta.name} was found but held no verses; left out.`);
        continue;
      }
      books.push(Book.of(meta, chapters));
    }
    return books;
  }
}

/** Dart's `map[key] ??= make()`. */
function getOrPut<K, V>(map: Map<K, V>, key: K, make: () => V): V {
  let value = map.get(key);
  if (value === undefined) {
    value = make();
    map.set(key, value);
  }
  return value;
}
