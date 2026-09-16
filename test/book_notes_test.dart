import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/book_notes.dart';
import 'package:openword/src/model/book_meta.dart';

void main() {
  test('covers exactly the books the bundled introductions do not', () {
    // The Protestant canon is covered by the Aquifer introductions; these
    // notes exist for the deuterocanonical books alone.
    final deuterocanon = [
      for (final book in BookMeta.all)
        if (book.section == BookSection.deuterocanon) book.code,
    ];
    expect(bookNotes.keys.toSet(), deuterocanon.toSet());
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

  test('authorship is hedged rather than asserted', () {
    // A claim as firm as "by Solomon" would be a scholarly assertion the app
    // has no business making. Sirach is the exception the rule allows for: it
    // names its own author, so saying so is reporting the book, not taking a
    // side.
    for (final entry in bookNotes.entries) {
      final attribution = entry.value.attribution.toLowerCase();
      expect(
        attribution.contains('anonymous') ||
            attribution.contains('ascribed') ||
            attribution.contains('presented as') ||
            attribution.contains('voice') ||
            attribution.contains('adaptation') ||
            attribution.contains('abridgement') ||
            attribution.contains('names himself'),
        isTrue,
        reason: '${entry.key}: "${entry.value.attribution}"',
      );
    }
  });
}
