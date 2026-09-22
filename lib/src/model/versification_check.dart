import 'bible.dart';
import 'book_meta.dart';
import 'versification_table.dart';

/// How a Bible's verse numbering compares with the one the app's own
/// verse-anchored data assumes.
class VersificationMatch {
  const VersificationMatch({
    required this.compared,
    required this.differing,
    required this.examples,
  });

  /// How many chapters were in both this Bible and the reference.
  final int compared;

  /// How many of those hold a different number of verses.
  final int differing;

  /// A few of them, worded for a reader.
  final List<String> examples;

  double get fraction => compared == 0 ? 0 : differing / compared;

  /// Too little of the Bible overlapped to say anything. A single-book
  /// import, say, or one whose books were not recognised.
  bool get isInconclusive => compared < minimumChapters;

  /// Whether this numbers its verses the way the bundled cross-references
  /// and original-language layer do.
  bool get matchesEnglish => !isInconclusive && fraction <= tolerance;

  /// What to record in the file.
  String get versification => isInconclusive
      ? Versification.unknown
      : matchesEnglish
      ? Versification.english
      : Versification.other;

  /// Below this there is not enough overlap for a proportion to mean
  /// anything; a Bible of one book would match or not on a handful of
  /// chapters.
  static const int minimumChapters = 100;

  /// Where the line sits, and why it sits there.
  ///
  /// Editions of the English Bible disagree with each other a little: the
  /// three bundled here differ over 2 of 1189 chapters, 0.17%, which is
  /// Romans' floating doxology. A different scheme is nothing like that
  /// small — the Masoretic numbering counts a psalm's superscription as
  /// its first verse, which moves something like a hundred chapters of the
  /// Psalms on its own, and the Septuagint's psalm numbering moves more.
  /// 2% is ten times the noise and a fraction of the signal.
  static const double tolerance = 0.02;

  @override
  String toString() =>
      '$differing of $compared chapters differ '
      '(${(fraction * 100).toStringAsFixed(1)}%)';
}

/// Checks a Bible's verse numbering against the English Protestant scheme.
///
/// This exists because everything anchored to a verse — the cross-
/// references, the Hebrew and Greek behind a verse — is anchored to one
/// numbering. Pointed at a Bible that numbers differently, they do not
/// fail; they quietly point at the wrong verse, which is worse. So an
/// import is measured against the scheme they assume, and where it does
/// not match, it is marked and they are withheld.
///
/// Only the sixty-six books of the Protestant canon are compared. The
/// deuterocanonical books are numbered differently by English editions
/// that otherwise agree entirely, so including them would raise a false
/// alarm on an ordinary import.
class VersificationCheck {
  const VersificationCheck._();

  static Map<String, List<int>>? _reference;

  static Map<String, List<int>> get reference =>
      _reference ??= englishVerseCounts.map(
        (code, counts) => MapEntry(code, [
          for (final part in counts.split(' ')) int.parse(part),
        ]),
      );

  static VersificationMatch against(Bible bible) {
    var compared = 0;
    var differing = 0;
    final examples = <String>[];

    for (final book in bible.books) {
      if (book.section == BookSection.deuterocanon) continue;
      final expected = reference[book.code];
      if (expected == null) continue;

      final overlap = book.chapterCount < expected.length
          ? book.chapterCount
          : expected.length;
      for (var c = 1; c <= overlap; c++) {
        compared++;
        final found = book.verseCountAt(c);
        if (found == expected[c - 1]) continue;
        differing++;
        if (examples.length < 5) {
          examples.add(
            '${book.name} $c has $found '
            '${found == 1 ? 'verse' : 'verses'}, not ${expected[c - 1]}',
          );
        }
      }

      // A book of the wrong length is a difference in itself, counted once
      // per chapter that is missing or spare.
      final extra = (book.chapterCount - expected.length).abs();
      if (extra > 0) {
        compared += extra;
        differing += extra;
        if (examples.length < 5) {
          examples.add(
            '${book.name} has ${book.chapterCount} chapters, '
            'not ${expected.length}',
          );
        }
      }
    }

    return VersificationMatch(
      compared: compared,
      differing: differing,
      examples: examples,
    );
  }
}
