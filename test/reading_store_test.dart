import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/bookmarks.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/model/bible.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('toggles bookmarks and reports them per chapter', () async {
    final store = await ReadingStore.load();
    const john = Reference('JHN', 3, 16);

    expect(store.isBookmarked(john), isFalse);
    expect(store.toggle(john), isTrue);
    expect(store.isBookmarked(john), isTrue);
    expect(store.bookmarkedVerses('JHN', 3), {16});
    expect(store.bookmarkedVerses('JHN', 4), isEmpty);

    expect(store.toggle(john), isFalse);
    expect(store.isBookmarked(john), isFalse);
  });

  test('keeps bookmarks, notes and order across a restart', () async {
    final store = await ReadingStore.load();
    store
      ..toggle(const Reference('GEN', 1, 1))
      ..toggle(const Reference('PSA', 23, 1));
    final psalm = store.bookmarkFor(const Reference('PSA', 23, 1))!;
    store.update(psalm.copyWith(note: 'My shepherd'));

    final reopened = await ReadingStore.load();
    expect(reopened.bookmarks.length, 2);
    // Newest first.
    expect(reopened.bookmarks.first.reference, const Reference('PSA', 23, 1));
    expect(reopened.bookmarks.first.note, 'My shepherd');
    expect(reopened.isBookmarked(const Reference('GEN', 1, 1)), isTrue);
  });

  test('remembers the reading position and recent chapters', () async {
    final store = await ReadingStore.load();
    await store.savePosition(const Reference('MAT', 5, 3));
    await store.savePosition(const Reference('MAT', 5, 9));
    await store.savePosition(const Reference('ROM', 8, 1));

    final reopened = await ReadingStore.load();
    expect(reopened.lastPosition, const Reference('ROM', 8, 1));
    // One history entry per chapter, most recent first.
    expect(reopened.history.map((reference) => reference.label), [
      'Romans 8',
      'Matthew 5',
    ]);
  });

  test('clearing removes every bookmark', () async {
    final store = await ReadingStore.load();
    store.toggle(const Reference('GEN', 1, 1));
    store.clearBookmarks();
    expect(store.bookmarks, isEmpty);
    expect((await ReadingStore.load()).bookmarks, isEmpty);
  });

  test('settings persist and have sensible defaults', () async {
    final settings = await Settings.load();
    expect(settings.useDynamicColor, isTrue);
    expect(settings.paragraphLayout, isTrue);
    expect(settings.showDeuterocanon, isFalse);
    expect(settings.bookOrder, BookOrder.alphabetical);

    settings
      ..fontScale = 1.4
      ..showDeuterocanon = true
      ..bookOrder = BookOrder.canonical;

    final reopened = await Settings.load();
    expect(reopened.fontScale, 1.4);
    expect(reopened.showDeuterocanon, isTrue);
    expect(reopened.bookOrder, BookOrder.canonical);
  });
}
