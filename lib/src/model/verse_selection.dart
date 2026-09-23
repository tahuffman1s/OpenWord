import 'bible.dart';

/// Several verses of one chapter chosen together, and how they are cited
/// and quoted.
class VerseSelection {
  const VerseSelection._();

  /// The verses as a printed Bible cites them: "16–18, 20".
  ///
  /// Runs of consecutive verses collapse to a range; a gap starts a new
  /// part, so a selection that skips a verse says so rather than claiming
  /// it.
  static String ranges(Iterable<int> verses) {
    final sorted = verses.toSet().toList()..sort();
    final parts = <String>[];
    var i = 0;
    while (i < sorted.length) {
      var j = i;
      while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
        j++;
      }
      parts.add(i == j ? '${sorted[i]}' : '${sorted[i]}–${sorted[j]}');
      i = j + 1;
    }
    return parts.join(', ');
  }

  /// "John 3:16–18, 20".
  static String citation(Reference chapter, Iterable<int> verses) =>
      '${chapter.bookName} ${chapter.chapter}:${ranges(verses)}';

  /// The words of the verses, in order. Where the selection skips a verse
  /// an ellipsis stands for it, as it would in a printed quotation.
  static String text(Chapter chapter, Iterable<int> verses) {
    final sorted = verses.toSet().toList()..sort();
    final buffer = StringBuffer();
    int? previous;
    for (final verse in sorted) {
      final words = chapter.verseText(verse).trim();
      if (words.isEmpty) continue;
      if (previous != null) {
        buffer.write(verse == previous + 1 ? ' ' : ' … ');
      }
      buffer.write(words);
      previous = verse;
    }
    return buffer.toString();
  }

  /// What is copied or shared as text: the words, then where they are
  /// from and in which translation.
  static String quotation({
    required Chapter chapter,
    required Reference reference,
    required Iterable<int> verses,
    required String translation,
  }) {
    final cite = citation(reference, verses);
    return '${text(chapter, verses)}\n\n— $cite ($translation)';
  }
}
