import 'dart:typed_data';

import 'bible.dart';
import 'byte_io.dart';

/// Which books of a translation each of its words occurs in.
///
/// Searching used to mean unpacking every book and reading every verse:
/// 217 ms for the World English Bible, on whatever thread asked. Most words
/// are nowhere near that widespread — the median word of the WEB is in two
/// of its eighty-four books — so this says which books a word is in, and a
/// search reads only those.
///
/// It is a filter and never an answer. The words are indexed, the query may
/// be any substring, and what finally decides a hit is the same pattern
/// match as before; all this does is rule out books that cannot possibly
/// contain the query. So the results are identical, and a file without the
/// index searches exactly as it always did.
///
/// A stale index would quietly lose results, which is the worst way for it
/// to be wrong, so it records the checksum of the text it was built from and
/// is ignored unless the two agree.
class SearchIndex {
  SearchIndex._({
    required this.textCrc,
    required this.bookCount,
    required String blob,
    required List<int> starts,
    required List<List<int>> books,
    // The three are private fields, so they cannot be named parameters.
    // ignore_for_file: prefer_initializing_formals
  }) : _blob = blob,
       _starts = starts,
       _books = books;

  static const int version = 1;

  /// A word shorter than this prunes nothing — "of" is in every book — and
  /// invites trouble with the punctuation inside a word, so the query has
  /// to offer at least one run this long for the index to be consulted.
  static const int minimumToken = 3;

  /// The CRC-32 of the TEXT chunk this was built from.
  final int textCrc;

  final int bookCount;

  /// Every word, in order, joined by newlines — which no word contains, so
  /// a match can never straddle two of them. One scan of a single string
  /// beats fifteen thousand calls to [String.contains] by a wide margin,
  /// and the point of an index is that consulting it should disappear
  /// beside the work it saves.
  final String _blob;

  /// Where each word starts in [_blob], so a match offset can be turned
  /// back into which word matched.
  final List<int> _starts;

  final List<List<int>> _books;

  int get wordCount => _starts.length;

  /// Letters and marks. Deliberately the same rule for building the index
  /// and for reading a query, or the two would disagree about where a word
  /// ends and the index would rule out books that do match.
  static final RegExp _token = RegExp(r'[\p{L}\p{M}]+', unicode: true);

  /// The books a query could possibly match, or null where the index
  /// cannot say and every book must be read.
  Set<int>? booksFor(String query) {
    final tokens = [
      for (final match in _token.allMatches(query.toLowerCase()))
        if (match.group(0)!.length >= minimumToken) match.group(0)!,
    ];
    if (tokens.isEmpty) return null;

    Set<int>? narrowed;
    for (final token in tokens) {
      final forToken = <int>{};
      var at = _blob.indexOf(token);
      while (at >= 0) {
        forToken.addAll(_books[_wordAt(at)]);
        at = _blob.indexOf(token, at + 1);
      }
      // Every word of the query has to be somewhere in the book, so the
      // book has to be in all of their sets.
      narrowed = narrowed == null ? forToken : narrowed.intersection(forToken);
      if (narrowed.isEmpty) return const {};
    }
    return narrowed;
  }

  /// Which word covers this offset in [_blob]: the last one starting at or
  /// before it.
  int _wordAt(int offset) {
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  // ---------------------------------------------------------------- writing

  static Uint8List build(Bible bible, {required int textCrc}) {
    // Sorted, so that the same Bible always writes the same bytes.
    final inBooks = <String, Set<int>>{};
    for (var b = 0; b < bible.books.length; b++) {
      final book = bible.books[b];
      for (final chapter in book.chapters) {
        for (final block in chapter.blocks) {
          for (final segment in block.segments) {
            for (final match in _token.allMatches(segment.text.toLowerCase())) {
              (inBooks[match.group(0)!] ??= <int>{}).add(b);
            }
          }
        }
      }
    }

    final words = inBooks.keys.toList()..sort();
    final out = ByteWriter()
      ..byte(version)
      ..uint32(textCrc)
      ..varint(bible.books.length)
      ..varint(words.length);
    for (final word in words) {
      final books = inBooks[word]!.toList()..sort();
      out
        ..string(word)
        ..varint(books.length);
      var previous = 0;
      for (final book in books) {
        out.varint(book - previous);
        previous = book;
      }
    }
    return out.takeCopy();
  }

  // ---------------------------------------------------------------- reading

  /// Reads an index, or answers null where it cannot be read or was built
  /// from different text. Never throws: an index is an optimisation, and
  /// losing it must cost nothing but speed.
  static SearchIndex? parse(Uint8List bytes, {required int textCrc}) {
    try {
      final input = ByteReader(bytes);
      if (input.byte() != version) return null;
      final crc = input.uint32();
      if (crc != textCrc) return null;
      final bookCount = input.varint();
      final wordCount = input.varint();

      final blob = StringBuffer();
      final starts = List<int>.filled(wordCount, 0);
      final books = List<List<int>>.filled(wordCount, const []);
      var at = 0;
      for (var i = 0; i < wordCount; i++) {
        final word = input.string();
        if (i > 0) {
          blob.write('\n');
          at += 1;
        }
        starts[i] = at;
        blob.write(word);
        at += word.length;
        final count = input.varint();
        final forWord = List<int>.filled(count, 0);
        var previous = 0;
        for (var j = 0; j < count; j++) {
          previous += input.varint();
          forWord[j] = previous;
        }
        books[i] = forWord;
      }
      return SearchIndex._(
        textCrc: crc,
        bookCount: bookCount,
        blob: blob.toString(),
        starts: starts,
        books: books,
      );
    } on Object {
      return null;
    }
  }
}
