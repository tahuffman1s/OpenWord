import 'dart:typed_data';

import '../model/bib_file.dart';
import '../model/xref_codec.dart';

/// Rewrites a `.bib` with a set of cross-references inside it.
///
/// A translation carrying its own references is better off than one leaning
/// on the app's bundled set in every way that matters: they travel with the
/// file, so any reader of the format has them, and they are stored against
/// the numbering of the very Bible they sit in. This is the same work
/// `tool/attach_xrefs.dart` does from a terminal, which the app had no way
/// of doing for a reader who wanted a copy to hand on.
///
/// Top-level, and taking nothing but bytes, because [compute] cannot carry
/// a [Bible] across an isolate: a book of a version 2 file inflates when it
/// is first read, which is a closure, and a closure does not cross.
Uint8List attachCrossReferences((Uint8List file, Uint8List references) work) {
  final (file, references) = work;

  // Read the references first: a bad set should cost nothing.
  final count = XrefCodec.unpack(references).length;
  if (count == 0) {
    throw const BibFormatException('there are no references in that set');
  }

  final bible = BibFile.decode(file, verify: true);
  final out = BibFile.encode(
    bible,
    // Whatever chunks the file came with are kept: a rewrite that dropped
    // a translation's own references would be the worst kind of bug.
    carry: {...bible.extras, XrefCodec.chunkTag: references},
  );

  // Read it back before handing it over, the way the tool does. Encoding is
  // deterministic, so this either holds always or never, but a file written
  // for someone else to read should be read once first.
  final check = BibFile.decode(out, verify: true);
  final attached = check.extras[XrefCodec.chunkTag];
  if (attached == null || XrefCodec.unpack(attached).length != count) {
    throw const BibFormatException('the references did not survive the write');
  }
  return out;
}
