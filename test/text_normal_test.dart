import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/epub_import.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/text_normal.dart';
import 'package:openword/src/ui/search_screen.dart';

import 'epub_import_test.dart' show epub;

/// "Elohim" with the points written in the other of the two canonical
/// orders, and a Latin word with its accent decomposed.
const String decomposedHebrew = 'אֱלֹהִם';
const String decomposedLatin = 'Crédo';
const String composedLatin = 'Crédo';

void main() {
  group('composing text', () {
    test('a decomposed accent becomes one codepoint', () {
      expect(decomposedLatin.length, composedLatin.length + 1);
      expect(ScriptureText.normalise(decomposedLatin), composedLatin);
    });

    test('text with nothing to compose comes back untouched', () {
      const plain = 'In the beginning God created the heavens.';
      expect(ScriptureText.normalise(plain), same(plain));
    });

    test('Hebrew points are put in canonical order', () {
      // Two marks on one letter, written the wrong way round: the same
      // word, different bytes, and no search would match across them.
      const wrongOrder = 'בְּ';
      final composed = ScriptureText.normalise(wrongOrder);
      expect(ScriptureText.isNormalised(wrongOrder), isFalse);
      expect(ScriptureText.isNormalised(composed), isTrue);
      expect(composed.codeUnits, isNot(wrongOrder.codeUnits));
    });

    test('the check agrees with the composer', () {
      expect(ScriptureText.isNormalised(composedLatin), isTrue);
      expect(ScriptureText.isNormalised(decomposedLatin), isFalse);
      expect(ScriptureText.isNormalised(decomposedHebrew), isTrue);
    });
  });

  group('an EPUB carrying decomposed text', () {
    Uint8List decomposedEpub() => epub(
      documents: [
        (
          'gen.xhtml',
          '<h1>Genesis</h1><h2>1</h2>'
              '<p><sup>1</sup>He said $decomposedLatin to them.</p>'
              '<p><sup>2</sup>And also $decomposedHebrew.</p>',
        ),
      ],
    );

    test('is stored composed', () {
      final result = EpubImport.convert(
        decomposedEpub(),
        fileName: 'decomposed.epub',
      );

      final verse = result.bible!.bookByCode('GEN')!.chapter(1)!.verseText(1);
      expect(verse, contains(composedLatin));
      expect(ScriptureText.isNormalised(verse), isTrue);
    });

    test('can be found by typing what is on the page', () {
      // The point of all of it: before, the text held "Cre" + a combining
      // acute, a reader typed the single codepoint, and nothing matched.
      final bible = BibFile.decode(
        BibFile.encode(
          EpubImport.convert(
            decomposedEpub(),
            fileName: 'decomposed.epub',
          ).bible!,
        ),
      );

      expect(searchBible(bible, composedLatin), isNotEmpty);
      // And typing it the other way round still works, because the query
      // is composed too.
      expect(searchBible(bible, decomposedLatin), isNotEmpty);
    });
  });

  test('every translation the app ships is already composed', () {
    for (final id in const ['eng-web', 'eng-bsb', 'eng-gb-webbe']) {
      final file = File('assets/bible/$id.bib');
      if (!file.existsSync()) continue;
      final bible = BibFile.decode(Uint8List.fromList(file.readAsBytesSync()));
      for (final book in bible.books) {
        for (final chapter in book.chapters) {
          for (final block in chapter.blocks) {
            for (final segment in block.segments) {
              expect(
                ScriptureText.isNormalised(segment.text),
                isTrue,
                reason: '$id ${book.code} ${chapter.number}',
              );
            }
          }
        }
      }
    }
  });
}
