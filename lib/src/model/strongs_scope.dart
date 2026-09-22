import 'bible.dart';
import 'book_meta.dart';
import 'strongs_codec.dart';

/// The books an original-language layer is keyed against, in the order its
/// verse keys number them.
///
/// The deuterocanon is left out: those books are in neither the Hebrew
/// Bible nor the Greek New Testament as this app carries them, so they
/// have no original behind them to key.
final List<String> originalsCanon = [
  for (final meta in BookMeta.all)
    if (meta.section != BookSection.deuterocanon) meta.code,
];

/// Every verse of a Bible, as the keys an original-language layer uses.
///
/// Free of Flutter so that a tool and an isolate can both work this out,
/// and the one place that knows how a verse of a Bible maps to a key in
/// the layer — getting that wrong would silently hand back the words of
/// some other verse.
Set<int> originalsKeysOf(Bible bible) {
  final keys = <int>{};
  for (final book in bible.books) {
    final index = originalsCanon.indexOf(book.code);
    if (index < 0) continue;
    // From the outline, so working out what a Bible covers does not
    // unpack a word of it. A key that is asked for and is not in the
    // layer costs nothing: only what both have is kept.
    var position = 1;
    for (final number in book.chapterNumbers) {
      final verses = book.verseCountAt(position);
      for (var verse = 1; verse <= verses; verse++) {
        keys.add(StrongsCodec.verseKey(index, number, verse));
      }
      position++;
    }
  }
  return keys;
}
