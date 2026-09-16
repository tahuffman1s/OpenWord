import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/reference_search.dart';
import 'package:openword/src/model/bible.dart';

import 'fixtures.dart';

void main() {
  final bible = parseFixture();
  final books = bible.books;

  Reference? parse(String input) => ReferenceSearch.parse(input, books);

  test('parses book, chapter and verse', () {
    expect(parse('Genesis 1:2'), const Reference('GEN', 1, 2));
    expect(parse('genesis 2'), const Reference('GEN', 2));
    expect(parse('Genesis'), const Reference('GEN', 1));
  });

  test('accepts the spellings people actually type', () {
    expect(parse('gen 1:1'), const Reference('GEN', 1, 1));
    expect(parse('GEN1:1'), const Reference('GEN', 1, 1));
    expect(parse('gen.1.1'), const Reference('GEN', 1, 1));
    expect(parse('gen 1 1'), const Reference('GEN', 1, 1));
    expect(parse('  Gen  1 : 1 '), const Reference('GEN', 1, 1));
    expect(parse('psalm 1'), const Reference('PSA', 1));
    expect(parse('ps 1:2'), const Reference('PSA', 1, 2));
    expect(parse('mat 1'), const Reference('MAT', 1));
  });

  test('clamps out-of-range chapters and verses', () {
    expect(parse('Genesis 99'), const Reference('GEN', 2));
    expect(parse('Genesis 1:99'), const Reference('GEN', 1, 3));
    expect(parse('Genesis 0'), const Reference('GEN', 1));
  });

  test('refuses an ambiguous name', () {
    // Both Genesis and Psalms are loaded, so a bare letter means nothing.
    expect(parse('a'), isNull);
    expect(parse('nonsense 3'), isNull);
    expect(parse(''), isNull);
    expect(parse('12'), isNull);
  });

  test('normalises numbered and roman-numeral book names', () {
    expect(ReferenceSearch.normalise('1 John'), '1john');
    expect(ReferenceSearch.normalise('I John'), '1john');
    expect(ReferenceSearch.normalise('III  john.'), '3john');
    expect(ReferenceSearch.normalise(' Song of Solomon '), 'songofsolomon');
  });

  test('splits a reference into its name and numbers', () {
    expect(ReferenceSearch.split('jn 3:16').name.trim(), 'jn');
    expect(ReferenceSearch.split('jn 3:16').chapter, 3);
    expect(ReferenceSearch.split('jn 3:16').verse, 16);
    expect(ReferenceSearch.split('genesis').name, 'genesis');
    expect(ReferenceSearch.split('genesis').chapter, isNull);
    // A bare number is a book name as far as splitting goes, so "1 John"
    // never loses its numeral.
    expect(ReferenceSearch.split('1').name, '1');
  });

  test('ranks book matches, exact first', () {
    final matches = ReferenceSearch.matchBooks('ge', books);
    expect(matches.first.code, 'GEN');

    expect(ReferenceSearch.matchBooks('psalms', books).first.code, 'PSA');
    expect(ReferenceSearch.matchBooks('', books).length, books.length);
    expect(ReferenceSearch.matchBooks('zzz', books), isEmpty);
  });

  test('matches on abbreviation and code', () {
    expect(ReferenceSearch.matchBooks('psa', books).first.code, 'PSA');
    expect(ReferenceSearch.matchBooks('mat', books).first.code, 'MAT');
  });
}
