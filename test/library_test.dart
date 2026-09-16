import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/library.dart';
import 'package:openword/src/data/translations.dart';

import 'fixtures.dart';

void main() {
  test('every bundled translation has an asset path', () {
    expect(Translations.all, isNotEmpty);
    for (final translation in Translations.all) {
      expect(
        Translations.assetFor(translation.id),
        'assets/bible/${translation.id}.owb.gz',
      );
      expect(translation.license, 'Public Domain');
    }
    expect(Translations.byId('nope').id, Translations.fallback.id);
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
    expect(bundle.loaded, ['assets/bible/${testTranslation.id}.owb.gz']);
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
