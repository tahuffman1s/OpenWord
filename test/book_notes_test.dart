import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/book_notes.dart';
import 'package:openword/src/model/book_meta.dart';

void main() {
  test('every book in the canon table has a note', () {
    final missing = [
      for (final book in BookMeta.all)
        if (!bookNotes.containsKey(book.code)) book.code,
    ];
    expect(missing, isEmpty, reason: 'books without a background note');
  });

  test('no note is written for a book that does not exist', () {
    for (final code in bookNotes.keys) {
      expect(BookMeta.lookup(code), isNotNull, reason: 'unknown book $code');
    }
  });

  test('notes are filled in and short enough to read in a sheet', () {
    for (final entry in bookNotes.entries) {
      final note = entry.value;
      expect(note.genre.trim(), isNotEmpty, reason: entry.key);
      expect(note.attribution.trim(), isNotEmpty, reason: entry.key);
      expect(note.setting.trim(), isNotEmpty, reason: entry.key);
      expect(note.summary.trim().length, greaterThan(40), reason: entry.key);
      expect(note.summary.trim().length, lessThan(400), reason: entry.key);
    }
  });

  test('authorship is hedged where the book is anonymous', () {
    // A claim as firm as "by Moses" would be a scholarly assertion the app
    // has no business making.
    for (final code in ['GEN', 'EXO', 'LEV', 'NUM', 'DEU', 'JOS', 'JDG']) {
      expect(
        bookNotes[code]!.attribution.toLowerCase(),
        contains('traditionally'),
        reason: code,
      );
    }
    expect(bookNotes['HEB']!.attribution.toLowerCase(), contains('unknown'));
  });
}
