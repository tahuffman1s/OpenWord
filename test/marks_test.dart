import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/model/bible.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const john = Reference('JHN', 3, 16);
  const psalm = Reference('PSA', 23, 1);

  test('bookmarks toggle on and off', () async {
    final store = await ReadingStore.load();
    expect(store.isBookmarked(john), isFalse);
    expect(store.toggleBookmark(john), isTrue);
    expect(store.isBookmarked(john), isTrue);
    expect(store.bookmarks.single.reference, john);
    expect(store.flaggedVersesIn('JHN', 3), {16});

    expect(store.toggleBookmark(john), isFalse);
    expect(store.isBookmarked(john), isFalse);
    expect(store.all, isEmpty);
  });

  test('highlights carry a colour and are listed separately', () async {
    final store = await ReadingStore.load();
    store.setHighlight(john, 2);
    expect(store.highlightsIn('JHN', 3), {16: 2});
    expect(store.highlights.single.colorIndex, 2);
    expect(store.bookmarks, isEmpty);

    store.setHighlight(john, null);
    expect(store.highlightsIn('JHN', 3), isEmpty);
    expect(store.all, isEmpty);
  });

  test('one verse can hold a bookmark, a colour and a note at once', () async {
    final store = await ReadingStore.load();
    store
      ..toggleBookmark(john)
      ..setHighlight(john, 1)
      ..setNote(john, '  God so loved  ');

    final mark = store.markFor(john)!;
    expect(mark.bookmarked, isTrue);
    expect(mark.colorIndex, 1);
    expect(mark.note, 'God so loved');
    expect(store.notes.single.reference, john);
    expect(store.markedChaptersIn('JHN'), {3});
    expect(store.markedBookCodes, {'JHN'});

    // Clearing every part removes the mark.
    store
      ..toggleBookmark(john)
      ..setHighlight(john, null)
      ..setNote(john, '');
    expect(store.markFor(john), isNull);
  });

  test('marks and notes survive a restart, newest first', () async {
    final store = await ReadingStore.load();
    store.toggleBookmark(john);
    store.setNote(psalm, 'My shepherd');

    final reopened = await ReadingStore.load();
    expect(reopened.all.length, 2);
    expect(reopened.all.first.reference, psalm);
    expect(reopened.markFor(psalm)!.note, 'My shepherd');
    expect(reopened.isBookmarked(john), isTrue);
  });

  test('version 1.0 bookmarks are migrated', () async {
    SharedPreferences.setMockInitialValues({
      'bookmarks': jsonEncode([
        {'b': 'JHN', 'c': 3, 'v': 16, 't': 1000, 'n': 'from 1.0'},
        {'b': 'GEN', 'c': 1, 'v': 1, 't': 900},
      ]),
    });
    final store = await ReadingStore.load();
    expect(store.bookmarks.length, 2);
    expect(store.markFor(john)!.bookmarked, isTrue);
    expect(store.markFor(john)!.note, 'from 1.0');
    expect(store.markFor(john)!.highlighted, isFalse);

    // And are written forward, so the legacy key is no longer needed.
    final reopened = await ReadingStore.load();
    expect(reopened.bookmarks.length, 2);
  });

  test('export and import round trip, merging by recency', () async {
    final store = await ReadingStore.load();
    store
      ..toggleBookmark(john)
      ..setHighlight(psalm, 3);
    final backup = store.export();
    expect(backup, contains('"app": "openword"'));

    // A fresh device restores everything.
    SharedPreferences.setMockInitialValues({});
    final fresh = await ReadingStore.load();
    final result = fresh.import(backup);
    expect(result.ok, isTrue);
    expect(result.added, 2);
    expect(fresh.isBookmarked(john), isTrue);
    expect(fresh.highlightsIn('PSA', 23), {1: 3});

    // Importing the same backup again changes nothing.
    final again = fresh.import(backup);
    expect(again.total, 0);
    expect(fresh.all.length, 2);
  });

  test('import keeps the local copy when it is newer', () async {
    final store = await ReadingStore.load();
    store.setNote(john, 'older');
    final backup = store.export();

    store.setNote(john, 'newer');
    final result = store.import(backup);
    expect(result.ok, isTrue);
    expect(result.total, 0);
    expect(store.markFor(john)!.note, 'newer');
  });

  test('rubbish does not import', () async {
    final store = await ReadingStore.load();
    expect(store.import('not json at all').ok, isFalse);
    expect(store.import('{}').ok, isFalse);
    expect(store.all, isEmpty);
  });

  test('position and history are remembered', () async {
    final store = await ReadingStore.load();
    await store.savePosition(const Reference('MAT', 5, 3));
    await store.savePosition(const Reference('MAT', 5, 9));
    await store.savePosition(const Reference('ROM', 8, 1));

    final reopened = await ReadingStore.load();
    expect(reopened.lastPosition, const Reference('ROM', 8, 1));
    expect(reopened.history.map((reference) => reference.label), [
      'Romans 8',
      'Matthew 5',
    ]);

    reopened.clearHistory();
    expect(reopened.history, isEmpty);
  });

  test('settings persist and have sensible defaults', () async {
    final settings = await Settings.load();
    expect(settings.useDynamicColor, isTrue);
    expect(settings.paragraphLayout, isTrue);
    expect(settings.showDeuterocanon, isFalse);
    expect(settings.bookOrder, BookOrder.canonical);
    expect(settings.compareTranslationId, isNull);

    settings
      ..fontScale = 1.4
      ..showDeuterocanon = true
      ..compareTranslationId = 'eng-bsb';

    final reopened = await Settings.load();
    expect(reopened.fontScale, 1.4);
    expect(reopened.showDeuterocanon, isTrue);
    expect(reopened.compareTranslationId, 'eng-bsb');

    reopened.compareTranslationId = null;
    expect(reopened.compareTranslationId, isNull);
  });

  test(
    'comparing against the translation being read means not comparing',
    () async {
      final settings = await Settings.load();
      settings.compareTranslationId = settings.translationId;
      expect(settings.compareTranslationId, isNull);
    },
  );
}
