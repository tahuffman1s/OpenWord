import 'dart:typed_data';

import '../model/bib_file.dart';
import '../model/strongs_codec.dart';
import '../model/strongs_scope.dart';
import '../model/xref_codec.dart';

/// What a saved copy is to carry: the app's own assets, as they are stored.
///
/// Either may be left out. Both are the gzipped asset bytes, which is the
/// shape the chunks store them in, so nothing is re-encoded on the way.
class StudyLayers {
  const StudyLayers({this.crossReferences, this.originals});

  final Uint8List? crossReferences;
  final Uint8List? originals;

  bool get isEmpty => crossReferences == null && originals == null;
}

/// What came of writing them in.
class AttachedLayers {
  const AttachedLayers({
    required this.bytes,
    required this.references,
    required this.verses,
    required this.entries,
  });

  final Uint8List bytes;

  /// How many verses of cross-references went in, and how many verses and
  /// dictionary entries of Hebrew and Greek. Zero for a layer left out.
  final int references;
  final int verses;
  final int entries;
}

/// Rewrites a `.bib` with the study layers inside it.
///
/// A translation carrying its own is better off than one leaning on the
/// app's assets in every way that matters: they travel with the file, so
/// any reader of the format has them without a 4 MB download, and they are
/// stored against the numbering of the very Bible they sit in. This is the
/// work the `tool/attach_*.dart` scripts do, which the app had no way of
/// doing for a reader who wanted a copy to hand on.
///
/// Top-level, and taking nothing but bytes, because [compute] cannot carry
/// a Bible across an isolate: a book of a version 2 file inflates when it
/// is first read, which is a closure, and a closure does not cross.
AttachedLayers attachStudyLayers((Uint8List file, StudyLayers layers) work) {
  final (file, layers) = work;
  if (layers.isEmpty) {
    throw const BibFormatException('there is nothing to write in');
  }

  // Read what is being written before touching the file: a bad asset
  // should cost nothing.
  var references = 0;
  final crossReferences = layers.crossReferences;
  if (crossReferences != null) {
    references = XrefCodec.unpack(crossReferences).length;
    if (references == 0) {
      throw const BibFormatException('there are no references in that set');
    }
  }

  final bible = BibFile.decode(file, verify: true);
  final carry = {...bible.extras};
  if (crossReferences != null) {
    carry[XrefCodec.chunkTag] = crossReferences;
  }

  var verses = 0;
  var entries = 0;
  if (layers.originals != null) {
    // Cut to the verses this Bible actually has. The bundled layer covers
    // the whole Protestant canon, and writing all of it into a New
    // Testament would more than treble the file for nothing: the verses
    // that are not there are dead weight, and so is every dictionary entry
    // only they reached.
    final source = StrongsCodec.unpack(layers.originals!);
    final trimmed = trimOriginalsTo(source, originalsKeysOf(bible));
    final read = StrongsReader.parse(trimmed);
    verses = read.verseCount;
    entries = read.entryCount;
    if (verses == 0) {
      throw const BibFormatException(
        'none of this Bible has Hebrew or Greek behind it',
      );
    }
    carry[StrongsCodec.chunkTag] = StrongsCodec.deflate(trimmed);
  }

  // Whatever chunks the file came with are kept: a rewrite that dropped a
  // translation's own layers would be the worst kind of bug.
  final out = BibFile.encode(bible, carry: carry);

  // Read it back before handing it over, the way the tools do. Encoding is
  // deterministic, so this either holds always or never — but a file
  // written for someone else to read should be read once first.
  final check = BibFile.decode(out, verify: true);
  if (crossReferences != null) {
    final attached = check.extras[XrefCodec.chunkTag];
    if (attached == null || XrefCodec.unpack(attached).length != references) {
      throw const BibFormatException(
        'the references did not survive the write',
      );
    }
  }
  if (layers.originals != null) {
    final attached = check.extras[StrongsCodec.chunkTag];
    if (attached == null ||
        StrongsCodec.unpack(attached).verseCount != verses) {
      throw const BibFormatException(
        'the Hebrew and Greek did not survive the write',
      );
    }
  }

  return AttachedLayers(
    bytes: out,
    references: references,
    verses: verses,
    entries: entries,
  );
}
