import 'dart:typed_data';

import '../model/bib_file.dart';
import '../model/bible.dart';
import '../model/boilerplate.dart';

/// What sweeping a `.bib` would take out of it, and the file that would
/// replace it.
class TidyResult {
  const TidyResult({this.bytes, this.removed = const [], this.failure});

  const TidyResult.failed(String reason) : this(failure: reason);

  /// The rewritten file, or null when there was nothing to take out.
  final Uint8List? bytes;

  /// The lines it would drop, so a reader can say whether they should go.
  final List<String> removed;

  final String? failure;

  bool get foundSomething => bytes != null && removed.isNotEmpty;
}

/// Sweeps an already-imported translation, working from the `.bib` alone.
///
/// This matters more than it looks. An import is a stored file, and
/// updating the app never touches it — so every fix the importer gains is
/// unreachable for a translation already on the shelf, and the reader has
/// no way of knowing that the copy they are reading predates any of them.
/// Re-importing would fix it and needs the EPUB, which the app did not
/// keep. The rule this uses needs no EPUB: it asks only whether a line
/// belongs to no verse and repeats across books, and the `.bib` answers
/// both.
///
/// Top-level, and taking nothing but bytes, because [compute] cannot carry
/// a Bible across an isolate: a book of a version 2 file inflates when it
/// is first read, which is a closure, and a closure does not cross.
TidyResult tidyBib(Uint8List bytes) {
  final Bible bible;
  try {
    bible = BibFile.decode(bytes, verify: true);
  } on Object catch (error) {
    return TidyResult.failed('$error');
  }

  final swept = stripBoilerplate(bible.books);
  if (swept.isEmpty) return const TidyResult();

  try {
    final out = BibFile.encode(
      Bible(
        translation: bible.translation,
        books: swept.books,
        // Whatever the file carried stays with it: a tidy that dropped a
        // translation's own cross-references would be a poor trade.
        extras: bible.extras,
      ),
    );
    // Read it back before offering to replace anything.
    BibFile.decode(out, verify: true);
    return TidyResult(bytes: out, removed: swept.removed);
  } on Object catch (error) {
    return TidyResult.failed('$error');
  }
}
