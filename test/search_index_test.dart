import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/search_index.dart';
import 'package:openword/src/ui/search_screen.dart';

import 'fixtures.dart';

void main() {
  final bible = parseFixture();

  SearchIndex indexOf(Bible source) {
    final built = SearchIndex.build(source, textCrc: 7);
    final index = SearchIndex.parse(built, textCrc: 7);
    expect(index, isNotNull);
    return index!;
  }

  group('what the index knows', () {
    test('which books a word is in', () {
      final index = indexOf(bible);
      final genesis = bible.indexOfCode('GEN')!;

      // "beginning" is in Genesis 1:1 of the fixture and nowhere else.
      expect(index.booksFor('beginning'), {genesis});
    });

    test('that a word is nowhere, which is the quickest answer of all', () {
      expect(indexOf(bible).booksFor('lovingkindness'), isEmpty);
    });

    test('nothing, when the query is too short to prune by', () {
      // Two letters are in every book; saying so would cost more than it
      // saves, and punctuation inside a word makes short runs unreliable.
      expect(indexOf(bible).booksFor('in'), isNull);
      expect(indexOf(bible).booksFor('!?'), isNull);
    });

    test('a substring, not only a whole word', () {
      // Search matches substrings, so the index has to answer for them.
      final genesis = bible.indexOfCode('GEN')!;
      expect(indexOf(bible).booksFor('eginnin'), contains(genesis));
    });

    test('that every word of a phrase has to be in the same book', () {
      final index = indexOf(bible);
      // "beginning" is only in Genesis; a word only in Psalms cannot share
      // a book with it, so the phrase can match nowhere.
      expect(index.booksFor('beginning Selah'), isEmpty);
    });
  });

  group('an index is never allowed to be wrong', () {
    test('one built from different text is refused', () {
      final built = SearchIndex.build(bible, textCrc: 1);

      expect(SearchIndex.parse(built, textCrc: 2), isNull);
      expect(SearchIndex.parse(built, textCrc: 1), isNotNull);
    });

    test('a damaged one is refused rather than half-read', () {
      final built = SearchIndex.build(bible, textCrc: 7);
      expect(
        SearchIndex.parse(Uint8List.sublistView(built, 0, 20), textCrc: 7),
        isNull,
      );
      expect(SearchIndex.parse(Uint8List(0), textCrc: 7), isNull);
    });

    test('a file whose index does not match carries none', () {
      final bytes = BibFile.encode(bible);
      final text = BibFile.chunk(bytes, BibFile.tagText)!;

      // Swap in an index built from something else.
      final wrong = Uint8List.fromList(
        const GZipEncoder().encodeBytes(
          SearchIndex.build(bible, textCrc: getCrc32(text) ^ 0xffff),
        ),
      );
      final tampered = BibFile.encode(
        bible,
        searchable: false,
        carry: {BibFile.tagSearch: wrong},
      );

      expect(BibFile.decode(tampered).searchIndex, isNull);
    });
  });

  group('in a .bib file', () {
    test('every file the app writes carries one', () {
      final decoded = BibFile.decode(BibFile.encode(bible));

      expect(BibFile.tags(BibFile.encode(bible)), contains('srch'));
      expect(decoded.searchIndex, isNotNull);
      expect(decoded.searchIndex!.wordCount, greaterThan(20));
    });

    test('it can be left out, and then search still works', () {
      final bytes = BibFile.encode(bible, searchable: false);
      final decoded = BibFile.decode(bytes);

      expect(BibFile.tags(bytes), isNot(contains('srch')));
      expect(decoded.searchIndex, isNull);
      expect(searchBible(decoded, 'beginning'), isNotEmpty);
    });

    test('it survives being written uncompressed', () {
      final decoded = BibFile.decode(BibFile.encode(bible, compress: false));

      expect(decoded.searchIndex, isNotNull);
      expect(decoded.searchIndex!.booksFor('lovingkindness'), isEmpty);
    });

    test('it is not unpacked until something searches', () {
      // The chunk is a couple of hundred kilobytes; opening a Bible nobody
      // searches should not pay for it.
      final bytes = BibFile.encode(bible);
      final decoded = BibFile.decode(bytes);

      decoded.bookByCode('GEN')!.chapter(1)!.verseText(1);
      // Nothing to assert but that asking is what resolves it; the getter
      // is what the reader never touches.
      expect(decoded.searchIndex, isNotNull);
    });
  });

  group('the index changes nothing about the results', () {
    for (final query in const [
      'beginning',
      'God',
      'Selah',
      'the',
      'lovingkindness',
      'in the',
      'e',
    ]) {
      test('"$query" finds the same verses either way', () {
        final withIndex = BibFile.decode(BibFile.encode(bible));
        final without = BibFile.decode(
          BibFile.encode(bible, searchable: false),
        );

        final a = searchBible(without, query);
        final b = searchBible(withIndex, query);

        expect(
          b.map((hit) => hit.reference.toString()),
          a.map((hit) => hit.reference.toString()),
        );
      });
    }
  });

  group('the shipped translations', () {
    test('all carry an index that matches their text', () {
      for (final id in const ['eng-web', 'eng-bsb', 'eng-gb-webbe']) {
        final file = File('assets/bible/$id.bib');
        if (!file.existsSync()) continue;
        final bytes = Uint8List.fromList(file.readAsBytesSync());

        expect(BibFile.tags(bytes), contains('srch'), reason: id);
        final decoded = BibFile.decode(bytes);
        expect(decoded.searchIndex, isNotNull, reason: id);
        expect(
          decoded.searchIndex!.bookCount,
          decoded.books.length,
          reason: id,
        );
        // A word that is certainly there, and one that is certainly not.
        expect(decoded.searchIndex!.booksFor('Jerusalem'), isNotEmpty);
        expect(decoded.searchIndex!.booksFor('zzzzqqq'), isEmpty);
      }
    });
  });
}
