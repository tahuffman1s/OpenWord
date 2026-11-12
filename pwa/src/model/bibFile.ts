import { gunzipSync, gzipSync } from 'fflate';
import { Bible, Book, type ChapterOutline, readingDirectionFromKey, TranslationInfo, Versification } from './bible';
import { BibleCodec } from './bibleCodec';
import { BookMeta } from './bookMeta';
import { ByteReader, ByteWriter, utf8 } from './byteIo';
import { crc32 } from './crc32';
import { SearchIndex } from './searchIndex';
import { sha256Hex } from './sha256';

/**
 * The `.bib` file: one translation, whole, in one file.
 *
 * ## Version 2
 *
 * A fixed six-byte header and then a stream of chunks, each of which says
 * how long it is and what it is, so a reader can walk past what it does not
 * understand:
 *
 *     offset  size  meaning
 *     0       3     'BIB'
 *     3       1     format version, 2
 *     4       2     reserved, zero
 *     then, until the end of the file:
 *       4     tag, four ASCII letters
 *       4     payload length, big-endian
 *       4     CRC-32 of the payload, big-endian
 *       …     payload
 *
 * Critical chunks are named in upper case and a reader that does not
 * understand one must refuse the file; ancillary chunks are lower case and
 * may be skipped. See `docs/bib-format.md`.
 *
 * ## Version 1
 *
 * A fixed header — `BIB`, version, a gzip flag, a two-byte metadata length,
 * JSON, then one gzip stream of the whole Bible. Still read.
 */
export class BibFormatException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'BibFormatException';
  }
  override toString(): string {
    return this.message;
  }
}

const headerLength = 6;
const chunkHeaderLength = 12;
const stored = 0;
const gzip = 1;

export interface EncodeOptions {
  compress?: boolean;
  created?: Date | null;
  searchable?: boolean;
  carry?: ReadonlyMap<string, Uint8Array> | null;
}

export const BibFile = {
  extension: '.bib',
  magic: [0x42, 0x49, 0x42] as const, // 'BIB'
  /** What `encode` writes. */
  version: 2,
  /** The oldest version still read. */
  oldestVersion: 1,
  /** Metadata: UTF-8 JSON. Critical. */
  tagMeta: 'META',
  /** The Scripture, one compressed member per book. Critical. */
  tagText: 'TEXT',
  /** Which books each word is in. Ancillary. */
  tagSearch: 'srch',
  /** Tags reserved for what a `.bib` file may come to carry. All ancillary. */
  reservedTags: new Set(['xref', 'strg', 'sign']),
  /** Version 1 wrote the metadata length in two bytes, so this was its ceiling. */
  maxMetadataLength: 0xffff,
  /** How much of a file to read to be sure of finding out what it holds. */
  maxHeaderLength: headerLength + chunkHeaderLength + 0xffff,
  /** What `encode` writes inside the TEXT chunk. */
  textEncoding: 2,
  /** Stamped into every file this writes. */
  generator: 'OpenWord',

  // ---------------------------------------------------------------- writing

  /** Packs a whole Bible. See the Dart original for what each option does. */
  encode(bible: Bible, options: EncodeOptions = {}): Uint8Array {
    const compress = options.compress ?? true;
    const searchable = options.searchable ?? true;
    const text = encodeText(bible, compress);
    const metadata = utf8.encode(
      JSON.stringify(
        metadataOf(bible.translation, {
          books: bible.books.length,
          verses: bible.verseCount,
          contentHash: `sha256:${sha256Hex(text)}`,
          created: options.created ?? null,
        }),
      ),
    );
    const out = new ByteWriter().bytes(BibFile.magic).byte(BibFile.version).byte(0).byte(0);
    writeChunk(out, BibFile.tagMeta, metadata);
    writeChunk(out, BibFile.tagText, text);
    if (searchable) {
      const index = SearchIndex.build(bible, crc32(text));
      writeChunk(out, BibFile.tagSearch, compress ? gzipSync(index, { level: 9 }) : index);
    }
    const carry = options.carry === undefined ? bible.extras : options.carry;
    if (carry) for (const [tag, payload] of carry) writeChunk(out, tag, payload);
    return out.takeCopy();
  },

  // ---------------------------------------------------------------- reading

  /** True where the bytes begin like a `.bib` file. */
  looksLikeBib(bytes: Uint8Array): boolean {
    if (bytes.length < 4) return false;
    for (let i = 0; i < BibFile.magic.length; i++) if (bytes[i] !== BibFile.magic[i]) return false;
    return true;
  },

  /** What the file says it holds, read from its metadata alone. */
  readInfo(bytes: Uint8Array): TranslationInfo {
    const fileVersion = versionOf(bytes);
    const metadata = fileVersion === 1 ? metadataV1(bytes) : metadataV2(bytes);
    return infoFrom(metadata);
  },

  /**
   * The whole Bible — or rather, the shape of it. The books unpack
   * themselves as they are read. Pass `verify` to check every chunk's CRC.
   */
  decode(bytes: Uint8Array, verify = false): Bible {
    const fileVersion = versionOf(bytes);
    if (fileVersion === 1) return decodeV1(bytes);
    const chunks = readChunks(bytes, verify);
    const meta = chunks.get(BibFile.tagMeta);
    const text = chunks.get(BibFile.tagText);
    if (!meta) throw new BibFormatException('the file says nothing about itself');
    if (!text) throw new BibFormatException('the file carries no Scripture');
    const info = infoFrom(decodeMetadata(meta));
    const search = chunks.get(BibFile.tagSearch);
    const extras = new Map<string, Uint8Array>();
    for (const [tag, payload] of chunks) {
      if (tag !== BibFile.tagMeta && tag !== BibFile.tagText && tag !== BibFile.tagSearch) extras.set(tag, payload);
    }
    return decodeText(info, text, search ? () => SearchIndex.parse(gunzipped(search), crc32(text)) : null, extras);
  },

  /** Any chunk of a v2 file, by tag. Null where the file does not carry one. */
  chunk(bytes: Uint8Array, tag: string): Uint8Array | null {
    return versionOf(bytes) === 1 ? null : (readChunks(bytes).get(tag) ?? null);
  },

  /** Every tag the file carries, in the order they appear. */
  tags(bytes: Uint8Array): string[] {
    return versionOf(bytes) === 1 ? [] : [...readChunks(bytes).keys()];
  },
};

function writeChunk(out: ByteWriter, tag: string, payload: Uint8Array): void {
  out.bytes(utf8.encode(tag)).uint32(payload.length).uint32(crc32(payload)).bytes(payload);
}

/**
 * The TEXT chunk: an outline of every book, then one compressed member per
 * book in the same order.
 */
function encodeText(bible: Bible, compress: boolean): Uint8Array {
  const bodies: Uint8Array[] = [];
  for (const book of bible.books) {
    const raw = BibleCodec.encodeChapters(book.chapters);
    bodies.push(compress ? gzipSync(raw, { level: 9 }) : raw);
  }
  const out = new ByteWriter().byte(BibFile.textEncoding).byte(compress ? gzip : stored).varint(bible.books.length);
  for (let i = 0; i < bible.books.length; i++) {
    const book = bible.books[i];
    out.string(book.code).varint(book.outline.length);
    for (const chapter of book.outline) out.varint(chapter.number).varint(chapter.verseCount);
    out.varint(bodies[i].length);
  }
  for (const body of bodies) out.bytes(body);
  return out.takeCopy();
}

function versionOf(bytes: Uint8Array): number {
  if (!BibFile.looksLikeBib(bytes)) throw new BibFormatException('this is not a .bib file');
  const fileVersion = bytes[3];
  if (fileVersion < BibFile.oldestVersion || fileVersion > BibFile.version) {
    throw new BibFormatException(
      `this .bib file is version ${fileVersion}, and this app reads version ${BibFile.oldestVersion} to ${BibFile.version}`,
    );
  }
  return fileVersion;
}

function tagAt(bytes: Uint8Array, at: number): string {
  return String.fromCharCode(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]);
}

/** Walks the chunk stream. A later chunk of the same tag wins. */
function readChunks(bytes: Uint8Array, verify = false): Map<string, Uint8Array> {
  const found = new Map<string, Uint8Array>();
  let at = headerLength;
  while (at < bytes.length) {
    if (at + chunkHeaderLength > bytes.length) throw new BibFormatException('the file stops inside a chunk header');
    const tag = tagAt(bytes, at);
    const reader = new ByteReader(bytes, at + 4);
    const length = reader.uint32();
    const crc = reader.uint32();
    const start = at + chunkHeaderLength;
    if (start + length > bytes.length) throw new BibFormatException(`the ${tag} chunk runs off the end`);
    const payload = bytes.subarray(start, start + length);
    if (verify && crc32(payload) !== crc) throw new BibFormatException(`the ${tag} chunk is damaged`);
    if (!isKnownTag(tag) && isCritical(tag)) {
      throw new BibFormatException(`this file needs a ${tag} chunk, which this app does not know`);
    }
    found.set(tag, payload);
    at = start + length;
  }
  return found;
}

/** Upper case means a reader must understand it; lower case means it may be skipped. */
function isCritical(tag: string): boolean {
  const first = tag.charCodeAt(0);
  return first >= 0x41 && first <= 0x5a;
}

function isKnownTag(tag: string): boolean {
  return tag === BibFile.tagMeta || tag === BibFile.tagText || tag === BibFile.tagSearch || BibFile.reservedTags.has(tag);
}

/** Unpacks a chunk that may or may not be gzipped. */
function gunzipped(payload: Uint8Array): Uint8Array {
  if (payload.length < 2 || payload[0] !== 0x1f || payload[1] !== 0x8b) return payload;
  return gunzipSync(payload);
}

function decodeText(
  info: TranslationInfo,
  text: Uint8Array,
  search: (() => SearchIndex | null) | null,
  extras: Map<string, Uint8Array>,
): Bible {
  const input = new ByteReader(text);
  const encoding = input.byte();
  if (encoding < 1 || encoding > BibFile.textEncoding) {
    throw new BibFormatException(
      `the Scripture inside is written in a way this app does not know (text encoding ${encoding})`,
    );
  }
  const rich = encoding >= 2;
  const compression = input.byte();
  if (compression !== stored && compression !== gzip) {
    throw new BibFormatException(
      `the Scripture inside is compressed in a way this app does not know (method ${compression})`,
    );
  }
  const bookCount = input.varint();
  const codes: string[] = [];
  const outlines: ChapterOutline[][] = [];
  const lengths: number[] = [];
  for (let b = 0; b < bookCount; b++) {
    codes.push(input.string());
    const chapterCount = input.varint();
    const outline: ChapterOutline[] = [];
    for (let c = 0; c < chapterCount; c++) {
      const number = input.varint();
      const verseCount = input.varint();
      outline.push({ number, verseCount });
    }
    outlines.push(outline);
    lengths.push(input.varint());
  }
  let at = input.offset;
  const books: Book[] = [];
  for (let b = 0; b < bookCount; b++) {
    const start = at;
    const length = lengths[b];
    at += length;
    if (at > text.length) throw new BibFormatException(`${codes[b]} runs off the end of the file`);
    const meta = BookMeta.lookup(codes[b]);
    if (!meta) continue;
    books.push(
      Book.deferred(meta, outlines[b], () => {
        const body = text.subarray(start, start + length);
        const raw = compression === gzip ? gunzipSync(body) : body;
        return BibleCodec.decodeChapters(raw, rich);
      }),
    );
  }
  if (books.length === 0) throw new BibFormatException('the file carries no books');
  return new Bible({
    translation: info,
    books,
    extras,
    searchIndex: search
      ? () => {
          const index = search();
          return index !== null && index.bookCount === bookCount ? index : null;
        }
      : null,
  });
}

// ------------------------------------------------------------- version 1

function decodeV1(bytes: Uint8Array): Bible {
  if (bytes.length < 7) throw new BibFormatException('the file stops inside its header');
  const flags = bytes[4];
  const metadataLength = (bytes[5] << 8) | bytes[6];
  const start = 7 + metadataLength;
  if (start > bytes.length) throw new BibFormatException('the file stops before its Scripture');
  const payload = bytes.subarray(start);
  try {
    const raw = (flags & 0x01) !== 0 ? gunzipSync(payload) : payload;
    return BibleCodec.decode(raw);
  } catch (error) {
    throw new BibFormatException(`the Scripture inside is unreadable: ${(error as Error).message ?? error}`);
  }
}

function metadataV1(bytes: Uint8Array): Record<string, unknown> {
  if (bytes.length < 7) throw new BibFormatException('the file stops inside its header');
  const length = (bytes[5] << 8) | bytes[6];
  const end = 7 + length;
  if (end > bytes.length) throw new BibFormatException('the header runs off the end');
  return decodeMetadata(bytes.subarray(7, end));
}

// -------------------------------------------------------------- metadata

function metadataV2(bytes: Uint8Array): Record<string, unknown> {
  const meta = findChunk(bytes, BibFile.tagMeta);
  if (!meta) throw new BibFormatException('the file says nothing about itself');
  return decodeMetadata(meta);
}

/**
 * Finds one chunk without needing the rest of the file, so a shelf can be
 * listed from the first few hundred bytes of each.
 */
function findChunk(bytes: Uint8Array, wanted: string): Uint8Array | null {
  let at = headerLength;
  while (at + chunkHeaderLength <= bytes.length) {
    const tag = tagAt(bytes, at);
    const length = new ByteReader(bytes, at + 4).uint32();
    const start = at + chunkHeaderLength;
    if (tag === wanted) {
      if (start + length > bytes.length) throw new BibFormatException(`the ${tag} chunk runs off the end`);
      return bytes.subarray(start, start + length);
    }
    if (start + length > bytes.length) return null;
    at = start + length;
  }
  return null;
}

function decodeMetadata(payload: Uint8Array): Record<string, unknown> {
  let decoded: unknown;
  try {
    decoded = JSON.parse(utf8.decode(payload));
  } catch (error) {
    throw new BibFormatException(`the metadata is unreadable: ${(error as Error).message ?? error}`);
  }
  if (decoded === null || typeof decoded !== 'object' || Array.isArray(decoded)) {
    throw new BibFormatException('the metadata is not a record');
  }
  return decoded as Record<string, unknown>;
}

function metadataOf(
  info: TranslationInfo,
  extra: { books: number; verses: number; contentHash: string; created: Date | null },
): Record<string, unknown> {
  const m: Record<string, unknown> = {
    id: info.id,
    name: info.name,
    abbreviation: info.abbreviation,
    license: info.license,
    source: info.sourceUrl,
    language: info.language,
  };
  if (info.script.length > 0) m.script = info.script;
  m.direction = info.direction;
  m.versification = info.versification;
  if (info.attribution.length > 0) m.attribution = info.attribution;
  m.books = extra.books;
  m.verses = extra.verses;
  m.contentHash = extra.contentHash;
  m.generator = BibFile.generator;
  if (extra.created) m.created = extra.created.toISOString();
  return m;
}

function infoFrom(metadata: Record<string, unknown>): TranslationInfo {
  return new TranslationInfo({
    id: str(metadata, 'id'),
    name: str(metadata, 'name'),
    abbreviation: str(metadata, 'abbreviation'),
    license: str(metadata, 'license'),
    sourceUrl: str(metadata, 'source'),
    language: str(metadata, 'language', 'en'),
    script: str(metadata, 'script'),
    direction: readingDirectionFromKey(str(metadata, 'direction')),
    versification: str(metadata, 'versification', Versification.unknown),
    attribution: str(metadata, 'attribution'),
  });
}

function str(metadata: Record<string, unknown>, key: string, fallback = ''): string {
  const value = metadata[key];
  return typeof value === 'string' && value.length > 0 ? value : fallback;
}
