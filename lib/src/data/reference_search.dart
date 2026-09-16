import 'package:flutter/foundation.dart';

import '../model/bible.dart';

/// Matching book names and parsing references typed by hand.
///
/// This is what replaced the alphabet rail: one field where `jn 3:16`,
/// `1 co 13`, `psalm 23` or just `mat` all get you where you are going.
class ReferenceSearch {
  const ReferenceSearch._();

  /// Trailing `12`, `12:3`, `12.3` or `12 3`.
  static final RegExp _trailingNumbers = RegExp(
    r'\s*(\d{1,3})\s*(?:[:.,v]\s*|\s+)?(\d{1,3})?\s*$',
  );

  static final RegExp _romanPrefix = RegExp(r'^(i{1,3})\s+');
  static final RegExp _notAlphanumeric = RegExp(r'[^a-z0-9]');

  /// Spellings people type that are not the book's name or abbreviation.
  static const Map<String, String> aliases = {
    'psalm': 'PSA',
    'psalms': 'PSA',
    'ps': 'PSA',
    'song': 'SNG',
    'songofsongs': 'SNG',
    'songs': 'SNG',
    'canticles': 'SNG',
    'sos': 'SNG',
    'ecc': 'ECC',
    'qoheleth': 'ECC',
    'phlm': 'PHM',
    'philem': 'PHM',
    'phil': 'PHP',
    'philip': 'PHP',
    'jas': 'JAS',
    'jam': 'JAS',
    'rev': 'REV',
    'apocalypse': 'REV',
    'act': 'ACT',
    'mk': 'MRK',
    'mt': 'MAT',
    'lk': 'LUK',
    'jn': 'JHN',
    '1jn': '1JN',
    '2jn': '2JN',
    '3jn': '3JN',
    'jhn': 'JHN',
    'jdg': 'JDG',
    'judg': 'JDG',
    'deut': 'DEU',
    'josh': 'JOS',
    'isa': 'ISA',
    'jer': 'JER',
    'ezek': 'EZK',
    'eze': 'EZK',
    'hab': 'HAB',
    'zech': 'ZEC',
    'zeph': 'ZEP',
    'matt': 'MAT',
    'rom': 'ROM',
    'cor': '1CO',
    'gal': 'GAL',
    'eph': 'EPH',
    'col': 'COL',
    'thess': '1TH',
    'tim': '1TI',
    'heb': 'HEB',
    'pet': '1PE',
  };

  /// Reduces a name to comparable form: `1 John` and `1john.` both become
  /// `1john`, and `I John` is normalised to `1john` as well.
  static String normalise(String value) {
    var text = value.toLowerCase().trim();
    final roman = _romanPrefix.firstMatch(text);
    if (roman != null) {
      text = '${roman.group(1)!.length}${text.substring(roman.end - 1)}';
    }
    return text.replaceAll(_notAlphanumeric, '');
  }

  /// Splits `jn 3:16` into its book name and the numbers after it.
  static ({String name, int? chapter, int? verse}) split(String input) {
    final text = input.trim();
    final numbers = _trailingNumbers.firstMatch(text);
    // Guard against eating the whole input, as in "1" or "2 3".
    if (numbers == null || numbers.start == 0) {
      return (name: text, chapter: null, verse: null);
    }
    return (
      name: text.substring(0, numbers.start),
      chapter: int.tryParse(numbers.group(1)!),
      verse: numbers.group(2) == null ? null : int.tryParse(numbers.group(2)!),
    );
  }

  /// Books matching [query], best first. An empty query matches everything.
  static List<Book> matchBooks(String query, List<Book> books) {
    final needle = normalise(query);
    if (needle.isEmpty) return books;

    final exact = <Book>[];
    final prefix = <Book>[];
    final abbreviation = <Book>[];
    final contains = <Book>[];

    final aliasCode = aliases[needle];
    for (final book in books) {
      final name = normalise(book.name);
      final code = normalise(book.code);
      final abbrev = normalise(book.abbrev);
      if (name == needle ||
          code == needle ||
          abbrev == needle ||
          book.code == aliasCode) {
        exact.add(book);
      } else if (name.startsWith(needle)) {
        prefix.add(book);
      } else if (abbrev.startsWith(needle) || code.startsWith(needle)) {
        abbreviation.add(book);
      } else if (name.contains(needle)) {
        contains.add(book);
      }
    }
    return [...exact, ...prefix, ...abbreviation, ...contains];
  }

  /// Parses something like `jn 3:16` into a reference, clamped to what the
  /// book actually has. Returns null when no single book is meant.
  static Reference? parse(String input, List<Book> books) {
    if (input.trim().isEmpty) return null;
    final (:name, :chapter, :verse) = split(input);
    final text = name;

    final candidates = matchBooks(text, books);
    if (candidates.isEmpty) return null;
    // An ambiguous name is only usable when the matches agree on a book.
    final book = candidates.first;
    if (candidates.length > 1 &&
        normalise(book.name) != normalise(text) &&
        normalise(book.abbrev) != normalise(text) &&
        aliases[normalise(text)] != book.code) {
      return null;
    }

    final targetChapter = (chapter ?? 1).clamp(1, book.chapterCount);
    final chapterData = book.chapter(targetChapter)!;
    final targetVerse = verse?.clamp(
      1,
      chapterData.verseCount == 0 ? 1 : chapterData.verseCount,
    );
    return Reference(book.code, targetChapter, targetVerse);
  }
}

/// One reference found inside a piece of prose.
@immutable
class ReferenceMatch {
  const ReferenceMatch({
    required this.start,
    required this.end,
    required this.reference,
  });

  final int start;
  final int end;
  final Reference reference;
}

/// Finds citations such as `Exodus 30:12` or `2 Kings 23:21` inside footnotes
/// and parallel-passage lines, so they can be tapped.
///
/// Built from the books actually loaded, and matched longest name first, so
/// `2 John 1` is never read as `John 1`. Only a real book name followed by a
/// number matches, which keeps ordinary prose from lighting up.
class ReferenceMatcher {
  ReferenceMatcher(List<Book> books) {
    final names = <String>[];
    for (final book in books) {
      for (final form in {book.name, book.abbrev, book.code}) {
        _codes[form.toLowerCase()] = book.code;
        names.add(form);
      }
      _books[book.code] = book;
    }
    for (final entry in ReferenceSearch.aliases.entries) {
      if (!_books.containsKey(entry.value)) continue;
      _codes[entry.key] = entry.value;
      names.add(entry.key);
    }
    names.sort((a, b) => b.length.compareTo(a.length));
    _pattern = RegExp(
      '(?<![A-Za-z])(${names.map(RegExp.escape).join('|')})'
      r'\.?\s*(\d{1,3})(?:\s*[:.]\s*(\d{1,3}))?',
      caseSensitive: false,
    );
  }

  final Map<String, String> _codes = {};
  final Map<String, Book> _books = {};
  late final RegExp _pattern;

  List<ReferenceMatch> findAll(String text) {
    final found = <ReferenceMatch>[];
    for (final match in _pattern.allMatches(text)) {
      final code = _codes[match.group(1)!.toLowerCase()];
      final book = code == null ? null : _books[code];
      if (book == null) continue;
      final chapter = int.tryParse(match.group(2)!);
      if (chapter == null || chapter < 1 || chapter > book.chapterCount) {
        continue;
      }
      final verse = match.group(3) == null
          ? null
          : int.tryParse(match.group(3)!);
      final verses = book.chapter(chapter)!.verseCount;
      found.add(
        ReferenceMatch(
          start: match.start,
          end: match.end,
          reference: Reference(
            book.code,
            chapter,
            verse?.clamp(1, verses == 0 ? 1 : verses),
          ),
        ),
      );
    }
    return found;
  }
}
