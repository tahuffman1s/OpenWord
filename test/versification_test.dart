import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/epub_import.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/book_meta.dart';
import 'package:openword/src/model/versification_check.dart';

import 'epub_import_test.dart' show epub;

/// A Bible of [books], each chapter holding [verses] verses.
Bible _bible(Map<String, List<int>> books) => Bible(
  translation: const TranslationInfo(
    id: 'x',
    name: 'X',
    abbreviation: 'X',
    license: '',
    sourceUrl: '',
  ),
  books: [
    for (final entry in books.entries)
      Book(
        meta: BookMeta.lookup(entry.key)!,
        chapters: [
          for (var c = 0; c < entry.value.length; c++)
            Chapter(
              number: c + 1,
              blocks: [
                Block(
                  style: BlockStyle.paragraph,
                  segments: [
                    for (var v = 1; v <= entry.value[c]; v++)
                      VerseSegment(verse: v, startsVerse: true, text: 'x'),
                  ],
                ),
              ],
              notes: const [],
            ),
        ],
      ),
  ],
);

/// The reference itself, which must of course match.
Map<String, List<int>> get _english => VersificationCheck.reference;

void main() {
  group('measuring a Bible against the English numbering', () {
    test('the reference matches itself exactly', () {
      final match = VersificationCheck.against(_bible(_english));

      expect(match.differing, 0);
      expect(match.compared, 1189);
      expect(match.matchesEnglish, isTrue);
      expect(match.versification, Versification.english);
    });

    test('an ordinary English edition matches', () {
      // Editions differ over Romans' floating doxology and little else.
      final nearly = {
        ..._english,
        'ROM': [..._english['ROM']!],
      };
      nearly['ROM']![13] = 26;
      nearly['ROM']![15] = 25;

      final match = VersificationCheck.against(_bible(nearly));

      expect(match.differing, 2);
      expect(match.fraction, lessThan(VersificationMatch.tolerance));
      expect(match.versification, Versification.english);
    });

    test('a Bible that counts psalm superscriptions does not', () {
      // What the Masoretic numbering does: the superscription is verse 1,
      // so most of the Psalms run one longer.
      final masoretic = {
        ..._english,
        'PSA': [..._english['PSA']!],
      };
      for (var i = 0; i < masoretic['PSA']!.length; i++) {
        masoretic['PSA']![i] += 1;
      }

      final match = VersificationCheck.against(_bible(masoretic));

      expect(match.differing, 150);
      expect(match.fraction, greaterThan(VersificationMatch.tolerance));
      expect(match.matchesEnglish, isFalse);
      expect(match.versification, Versification.other);
      expect(match.examples.first, contains('Psalms'));
    });

    test('a book of the wrong length counts against it', () {
      // Joel is 3 chapters in English and 4 in Hebrew.
      final joel = {
        ..._english,
        'JOL': [..._english['JOL']!, 21],
      };

      final match = VersificationCheck.against(_bible(joel));

      expect(match.differing, 1);
      expect(match.examples.single, contains('chapters'));
    });

    test('too small a Bible says nothing rather than guessing', () {
      final match = VersificationCheck.against(
        _bible({'JHN': _english['JHN']!}),
      );

      expect(match.isInconclusive, isTrue);
      expect(match.matchesEnglish, isFalse);
      expect(match.versification, Versification.unknown);
    });

    test('the deuterocanon is left out of the comparison', () {
      // English editions disagree over these while agreeing entirely about
      // the rest, so counting them would raise a false alarm.
      final withExtra = {
        ..._english,
        'TOB': [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
      };

      final match = VersificationCheck.against(_bible(withExtra));

      expect(match.compared, 1189);
      expect(match.differing, 0);
      expect(match.versification, Versification.english);
    });
  });

  group('what the app does with the answer', () {
    test('only a measured mismatch withholds the verse-anchored layers', () {
      expect(Versification.mayAnchorEnglish(Versification.english), isTrue);
      // Every file written before this was checked says nothing, and must
      // keep working as it did.
      expect(Versification.mayAnchorEnglish(Versification.unknown), isTrue);
      expect(Versification.mayAnchorEnglish(Versification.other), isFalse);
    });

    test('it survives a round trip through a .bib file', () {
      final bible = Bible(
        translation: _bible(const {}).translation
            .copyWith(versification: Versification.other),
        books: _bible({'GEN': _english['GEN']!}).books,
      );

      final info = BibFile.readInfo(BibFile.encode(bible));
      expect(info.versification, Versification.other);
      expect(Versification.mayAnchorEnglish(info.versification), isFalse);
    });
  });

  group('the shipped table', () {
    test('covers the Protestant canon and nothing else', () {
      expect(VersificationCheck.reference, hasLength(66));
      for (final code in VersificationCheck.reference.keys) {
        final meta = BookMeta.lookup(code);
        expect(meta, isNotNull, reason: '$code is not a book');
        expect(meta!.section, isNot(BookSection.deuterocanon));
      }
      final chapters = VersificationCheck.reference.values.fold<int>(
        0,
        (sum, counts) => sum + counts.length,
      );
      expect(chapters, 1189);
    });

    test('every translation the app ships matches it', () {
      for (final id in const ['eng-web', 'eng-bsb', 'eng-gb-webbe']) {
        final file = File('assets/bible/$id.bib');
        if (!file.existsSync()) continue;
        final bible = BibFile.decode(
          Uint8List.fromList(file.readAsBytesSync()),
        );
        final match = VersificationCheck.against(bible);
        expect(
          match.versification,
          Versification.english,
          reason: '$id: $match',
        );
      }
    });
  });

  group('an EPUB is measured as it comes in', () {
    /// An EPUB of [books], each chapter holding that many numbered verses.
    Uint8List asEpub(Map<String, List<int>> books) {
      final documents = <(String, String)>[];
      for (final entry in books.entries) {
        final name = BookMeta.lookup(entry.key)!.name;
        final body = StringBuffer('<h1>$name</h1>');
        for (var c = 0; c < entry.value.length; c++) {
          body.write('<h2>${c + 1}</h2><p>');
          for (var v = 1; v <= entry.value[c]; v++) {
            body.write('<sup>$v</sup>Word. ');
          }
          body.write('</p>');
        }
        documents.add(('${entry.key.toLowerCase()}.xhtml', body.toString()));
      }
      return epub(documents: documents);
    }

    // Two books are enough to clear the minimum and to carry the Psalms,
    // which is where a difference in scheme shows most.
    Map<String, List<int>> sample() => {
      'GEN': _english['GEN']!,
      'PSA': _english['PSA']!,
    };

    test('one that numbers as the app does is marked so', () {
      final result = EpubImport.convert(
        asEpub(sample()),
        fileName: 'ordinary.epub',
      );

      expect(result.bible, isNotNull);
      expect(result.bible!.translation.versification, Versification.english);
      expect(
        result.warnings.where((w) => w.contains('numbers its verses')),
        isEmpty,
      );
    });

    test('one that does not is marked, and says why', () {
      final shifted = sample();
      shifted['PSA'] = [for (final n in shifted['PSA']!) n + 1];

      final result = EpubImport.convert(
        asEpub(shifted),
        fileName: 'masoretic.epub',
      );

      expect(result.bible, isNotNull);
      expect(result.bible!.translation.versification, Versification.other);
      expect(
        result.warnings.any((w) => w.contains('numbers its verses')),
        isTrue,
        reason: 'the reader should be told, not left to notice',
      );
      expect(
        result.warnings.any((w) => w.contains('Psalms')),
        isTrue,
        reason: 'and told where it differs',
      );
    });

    test('the mark is kept in the .bib the import writes', () {
      final shifted = sample();
      shifted['PSA'] = [for (final n in shifted['PSA']!) n + 1];
      final result = EpubImport.convert(
        asEpub(shifted),
        fileName: 'masoretic.epub',
      );

      final info = BibFile.readInfo(BibFile.encode(result.bible!));
      expect(info.versification, Versification.other);
    });
  });
}
