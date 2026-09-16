import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/book_meta.dart';

import 'fixtures.dart';

void main() {
  test('survives a JSON round trip', () {
    final original = parseFixture();
    final restored = Bible.fromJson(
      (jsonDecode(jsonEncode(original.toJson())) as Map)
          .cast<String, Object?>(),
    );
    expect(restored, isNotNull);
    expect(restored!.books.length, original.books.length);
    expect(restored.verseCount, original.verseCount);
    expect(
      restored
          .bookByCode('PSA')!
          .chapter(1)!
          .blocks
          .map((block) => '${block.style.key}${block.indent}'),
      original
          .bookByCode('PSA')!
          .chapter(1)!
          .blocks
          .map((block) => '${block.style.key}${block.indent}'),
    );
    expect(restored.bookByCode('GEN')!.chapter(1)!.notes, ['Elohim.']);
  });

  test('rejects a cache written by another format version', () {
    final json = parseFixture().toJson()..['v'] = 999;
    expect(Bible.fromJson(json), isNull);
  });

  test('keeps books in canonical order regardless of input order', () {
    final bible = parseFixture();
    final shuffled = Bible(
      translation: testTranslation,
      books: bible.books.reversed.toList(),
    );
    expect(shuffled.books.map((book) => book.code), ['GEN', 'PSA', 'MAT']);
  });

  test('encodes and decodes references', () {
    const reference = Reference('JHN', 3, 16);
    expect(reference.label, 'John 3:16');
    expect(Reference.decode(reference.encode()), reference);
    expect(Reference.decode('JHN/3/'), const Reference('JHN', 3));
    expect(Reference.decode('nonsense'), isNull);
    expect(Reference.decode(null), isNull);
  });

  test('sorts numbered books under their name', () {
    expect(BookMeta.lookup('1SA')!.sortName, 'Samuel, 1');
    expect(BookMeta.lookup('1SA')!.initial, 'S');
    expect(BookMeta.lookup('JHN')!.initial, 'J');
    expect(BookMeta.lookup('2co')!.name, '2 Corinthians');
  });

  test('assigns traditional divisions', () {
    expect(BookMeta.lookup('GEN')!.division, BookDivision.law);
    expect(BookMeta.lookup('JOS')!.division, BookDivision.history);
    expect(BookMeta.lookup('PSA')!.division, BookDivision.wisdom);
    expect(BookMeta.lookup('ISA')!.division, BookDivision.prophets);
    expect(BookMeta.lookup('LUK')!.division, BookDivision.gospels);
    expect(BookMeta.lookup('ACT')!.division, BookDivision.acts);
    expect(BookMeta.lookup('ROM')!.division, BookDivision.letters);
    expect(BookMeta.lookup('REV')!.division, BookDivision.apocalypse);
    expect(BookMeta.lookup('TOB')!.division, BookDivision.deuterocanon);
  });
}
