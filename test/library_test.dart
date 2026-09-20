import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/library.dart';
import 'package:openword/src/data/translations.dart';
import 'package:openword/src/model/bib_file.dart';

import 'fixtures.dart';

void main() {
  test('every bundled translation has an asset path', () {
    expect(Translations.all, isNotEmpty);
    for (final translation in Translations.all) {
      expect(
        Translations.assetFor(translation.id),
        'assets/bible/${translation.id}.bib',
      );
      expect(translation.license, 'Public Domain');
    }
    expect(Translations.byId('nope').id, Translations.fallback.id);
  });

  test('every bundled asset really is the .bib it claims to be', () {
    // Reads the files that ship, not a fixture: a rebuilt asset that went
    // out under the wrong name or the wrong format would pass every other
    // test here.
    for (final translation in Translations.all) {
      final file = File(Translations.assetFor(translation.id));
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');

      final handle = file.openSync();
      final Uint8List head;
      try {
        head = handle.readSync(BibFile.maxHeaderLength);
      } finally {
        handle.closeSync();
      }

      expect(BibFile.looksLikeBib(head), isTrue);
      final info = BibFile.readInfo(head);
      expect(info.id, translation.id);
      expect(info.name, translation.name);
      expect(info.abbreviation, translation.abbreviation);
      expect(info.license, translation.license);
      expect(info.sourceUrl, translation.sourceUrl);
    }
  });

  test('a bundled .bib decodes into the whole translation', () {
    // One of the three, in full: the others are the same code path, and a
    // whole Bible is a second of work.
    final bytes = File(Translations.assetFor(Translations.fallback.id))
        .readAsBytesSync();
    final bible = BibFile.decode(bytes);

    expect(bible.translation.id, Translations.fallback.id);
    expect(bible.books.length, greaterThan(66));
    expect(bible.verseCount, greaterThan(31000));
    expect(
      bible.bookByCode('JHN')!.chapter(3)!.verseText(16),
      contains('God so loved the world'),
    );
  });

  test('loads the bundled Scripture with no network at all', () async {
    final bundle = FixtureBundle();
    final library = LibraryController(bundle: bundle);
    expect(library.status, LibraryStatus.loading);

    await library.load(testTranslation.id);

    expect(library.status, LibraryStatus.ready);
    expect(library.isReady, isTrue);
    expect(library.bible!.books.length, 3);
    expect(library.translation.abbreviation, 'TST');
    expect(bundle.loaded, ['assets/bible/${testTranslation.id}.bib']);
  });

  test(
    'falls back to the default translation when an asset is missing',
    () async {
      final bundle = FixtureBundle();
      final library = LibraryController(bundle: bundle);

      await library.load('eng-gb-webbe'); // not in the fixture bundle

      expect(library.isReady, isTrue);
      expect(library.bible!.translation.id, Translations.fallback.id);
    },
  );

  test('reports failure when even the default cannot be read', () async {
    final library = LibraryController(
      bundle: FixtureBundle(assets: <String, Uint8List>{}),
    );

    await library.load(Translations.fallback.id);

    expect(library.status, LibraryStatus.failed);
    expect(library.isReady, isFalse);
    expect(library.errorMessage, isNotNull);
  });

  test('loads and drops the comparison translation on demand', () async {
    final library = LibraryController(bundle: FixtureBundle());
    await library.load(testTranslation.id);
    expect(library.comparison, isNull);

    await library.loadComparison(otherTranslation.id);
    expect(library.comparison!.translation.abbreviation, 'OTH');
    expect(
      library.comparison!.bookByCode('GEN')!.chapter(1)!.verseText(1),
      'At the first God made the heaven and the earth.',
    );

    library.clearComparison();
    expect(library.comparison, isNull);
  });

  test('comparing with the translation being read is a no-op', () async {
    final library = LibraryController(bundle: FixtureBundle());
    await library.load(testTranslation.id);
    await library.loadComparison(testTranslation.id);
    expect(library.comparison, isNull);
  });

  test('switching translation drops a stale comparison', () async {
    final library = LibraryController(bundle: FixtureBundle());
    await library.load(testTranslation.id);
    await library.loadComparison(otherTranslation.id);
    expect(library.comparison, isNotNull);

    await library.load(otherTranslation.id);
    expect(library.bible!.translation.id, otherTranslation.id);
    expect(library.comparison, isNull);
  });
}
