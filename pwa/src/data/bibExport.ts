import { BibFile, BibFormatException } from '../model/bibFile';
import { StrongsCodec, StrongsReader, trimOriginalsTo } from '../model/strongsCodec';
import { originalsKeysOf } from '../model/strongsScope';
import { XrefCodec } from '../model/xrefCodec';

/**
 * What a saved copy is to carry: the app's own assets, as they are stored.
 *
 * Either may be left out. Both are the gzipped asset bytes, which is the
 * shape the chunks store them in, so nothing is re-encoded on the way.
 */
export class StudyLayers {
  readonly crossReferences: Uint8Array | null;
  readonly originals: Uint8Array | null;

  constructor(init: { crossReferences?: Uint8Array | null; originals?: Uint8Array | null } = {}) {
    this.crossReferences = init.crossReferences ?? null;
    this.originals = init.originals ?? null;
  }

  get isEmpty(): boolean {
    return this.crossReferences === null && this.originals === null;
  }
}

/** What came of writing them in. */
export class AttachedLayers {
  readonly bytes: Uint8Array;

  /**
   * How many verses of cross-references went in, and how many verses and
   * dictionary entries of Hebrew and Greek. Zero for a layer left out.
   */
  readonly references: number;
  readonly verses: number;
  readonly entries: number;

  constructor(init: { bytes: Uint8Array; references: number; verses: number; entries: number }) {
    this.bytes = init.bytes;
    this.references = init.references;
    this.verses = init.verses;
    this.entries = init.entries;
  }
}

/**
 * Rewrites a `.bib` with the study layers inside it.
 *
 * A translation carrying its own is better off than one leaning on the
 * app's assets in every way that matters: they travel with the file, so
 * any reader of the format has them without a 4 MB download, and they are
 * stored against the numbering of the very Bible they sit in. This is the
 * work the `tool/attach_*.dart` scripts do, which the app had no way of
 * doing for a reader who wanted a copy to hand on.
 *
 * Top-level, and taking nothing but bytes, because a worker cannot carry
 * a Bible across: a book of a version 2 file inflates when it is first
 * read, which is a closure, and a closure does not cross.
 */
export function attachStudyLayers(file: Uint8Array, layers: StudyLayers): AttachedLayers {
  if (layers.isEmpty) {
    throw new BibFormatException('there is nothing to write in');
  }

  // Read what is being written before touching the file: a bad asset
  // should cost nothing.
  let references = 0;
  const crossReferences = layers.crossReferences;
  if (crossReferences !== null) {
    references = XrefCodec.unpack(crossReferences).length;
    if (references === 0) {
      throw new BibFormatException('there are no references in that set');
    }
  }

  const bible = BibFile.decode(file, true);
  const carry = new Map<string, Uint8Array>(bible.extras);
  if (crossReferences !== null) {
    carry.set(XrefCodec.chunkTag, crossReferences);
  }

  let verses = 0;
  let entries = 0;
  if (layers.originals !== null) {
    // Cut to the verses this Bible actually has. The bundled layer covers
    // the whole Protestant canon, and writing all of it into a New
    // Testament would more than treble the file for nothing: the verses
    // that are not there are dead weight, and so is every dictionary entry
    // only they reached.
    const source = StrongsCodec.unpack(layers.originals);
    const trimmed = trimOriginalsTo(source, originalsKeysOf(bible));
    const read = StrongsReader.parse(trimmed);
    verses = read.verseCount;
    entries = read.entryCount;
    if (verses === 0) {
      throw new BibFormatException('none of this Bible has Hebrew or Greek behind it');
    }
    carry.set(StrongsCodec.chunkTag, StrongsCodec.deflate(trimmed));
  }

  // Whatever chunks the file came with are kept: a rewrite that dropped a
  // translation's own layers would be the worst kind of bug.
  const out = BibFile.encode(bible, { carry });

  // Read it back before handing it over, the way the tools do. Encoding is
  // deterministic, so this either holds always or never — but a file
  // written for someone else to read should be read once first.
  const check = BibFile.decode(out, true);
  if (crossReferences !== null) {
    const attached = check.extras.get(XrefCodec.chunkTag);
    if (attached === undefined || XrefCodec.unpack(attached).length !== references) {
      throw new BibFormatException('the references did not survive the write');
    }
  }
  if (layers.originals !== null) {
    const attached = check.extras.get(StrongsCodec.chunkTag);
    if (attached === undefined || StrongsCodec.unpack(attached).verseCount !== verses) {
      throw new BibFormatException('the Hebrew and Greek did not survive the write');
    }
  }

  return new AttachedLayers({ bytes: out, references, verses, entries });
}
