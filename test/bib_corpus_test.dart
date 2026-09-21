@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';

/// The corpus is the format's fixed point: the same files any other
/// implementation would be judged against, read here by this one. If a
/// change to the reader makes one of these behave differently, either the
/// change is wrong or the spec moved — and the spec moving should be a
/// deliberate act, not a side effect.
///
/// Regenerate with `dart run tool/build_bib_corpus.dart`.
void main() {
  Uint8List load(String name) {
    final file = File('test/corpus/$name');
    expect(
      file.existsSync(),
      isTrue,
      reason: '$name is missing — run tool/build_bib_corpus.dart',
    );
    return Uint8List.fromList(file.readAsBytesSync());
  }

  void expectTheSample(Bible bible, String from) {
    expect(bible.books.map((b) => b.code), ['GEN', 'JHN'], reason: from);
    expect(bible.bookByCode('GEN')!.chapterCount, 2, reason: from);
    expect(bible.verseCount, 5, reason: from);
    expect(
      bible.bookByCode('GEN')!.chapter(1)!.verseText(3),
      'A line, indented.',
      reason: from,
    );
    expect(
      bible.bookByCode('JHN')!.chapter(1)!.verseText(1),
      'In the beginning was the Word.',
      reason: from,
    );
    expect(bible.bookByCode('GEN')!.chapter(1)!.notes, ['A footnote.']);
  }

  group('files a reader must accept', () {
    for (final name in const [
      'valid-v2.bib',
      'valid-v2-stored.bib',
      'valid-v1.bib',
      'ancillary-unknown.bib',
    ]) {
      test('$name holds the sample', () {
        expectTheSample(BibFile.decode(load(name)), name);
      });
    }

    test('every version of the sample holds the very same Scripture', () {
      final v2 = BibFile.decode(load('valid-v2.bib'));
      for (final name in const ['valid-v2-stored.bib', 'valid-v1.bib']) {
        final other = BibFile.decode(load(name));
        for (final book in v2.books) {
          final mirror = other.bookByCode(book.code)!;
          for (var c = 1; c <= book.chapterCount; c++) {
            for (var v = 1; v <= book.verseCountAt(c); v++) {
              expect(
                mirror.chapter(c)!.verseText(v),
                book.chapter(c)!.verseText(v),
                reason: '$name ${book.code} $c:$v',
              );
            }
          }
        }
      }
    });

    test('the metadata survives in version 2 and is absent in version 1', () {
      final v2 = BibFile.readInfo(load('valid-v2.bib'));
      expect(v2.language, 'en');
      expect(v2.script, 'Latn');
      expect(v2.versification, Versification.english);
      expect(v2.attribution, 'Nobody in particular.');

      // Version 1 could not say any of it, so a reader must fall back
      // rather than invent.
      final v1 = BibFile.readInfo(load('valid-v1.bib'));
      expect(v1.id, 'xx-corpus');
      expect(v1.versification, Versification.unknown);
      expect(v1.attribution, isEmpty);
    });

    test('an unknown ancillary chunk is kept, not merely tolerated', () {
      final bytes = load('ancillary-unknown.bib');
      expect(BibFile.tags(bytes), contains('zzzz'));
      expect(BibFile.chunk(bytes, 'zzzz'), isNotNull);
    });
  });

  group('files a reader must refuse', () {
    for (final entry in const {
      'critical-unknown.bib': 'ZZZZ',
      'future-version.bib': 'version',
      'truncated.bib': null,
      'header-only.bib': null,
      'not-a-bib.bib': 'not a .bib',
    }.entries) {
      test('${entry.key} is refused', () {
        expect(
          () => BibFile.decode(load(entry.key)),
          throwsA(
            entry.value == null
                ? isA<BibFormatException>()
                : isA<BibFormatException>().having(
                    (error) => error.message,
                    'message',
                    contains(entry.value!),
                  ),
          ),
        );
      });
    }

    test('damaged-crc.bib passes unchecked and fails when checked', () {
      final bytes = load('damaged-crc.bib');

      // Reading it without asking for a check must not pretend the damage
      // is not there: the Scripture's own compression catches it.
      expect(
        () => BibFile.decode(bytes, verify: true),
        throwsA(
          isA<BibFormatException>().having(
            (error) => error.message,
            'message',
            contains('damaged'),
          ),
        ),
      );
    });
  });

  test('the corpus README lists every file in the corpus', () {
    final readme = File('test/corpus/README.md').readAsStringSync();
    final files = Directory('test/corpus')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.bib'));

    for (final name in files) {
      expect(readme, contains('`$name`'), reason: '$name is undocumented');
    }
  });
}
