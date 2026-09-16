import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/app_scope.dart';
import 'package:openword/src/data/library.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/ui/reader_screen.dart';
import 'package:openword/src/ui/widgets/scripture_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// The book-and-chapter button lives in the app bar; verse numbers in the
/// text carry the same digits, so finders are scoped.
Finder appBarText(String label) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(label));

Finder verseNumber(String number) => find.descendant(
  of: find.byType(ScriptureBlock),
  matching: find.text(number),
);

class Harness {
  Harness(this.settings, this.reading, this.library);

  final Settings settings;
  final ReadingStore reading;
  final LibraryController library;
}

Future<Harness> pumpReader(
  WidgetTester tester, {
  Reference? resume,
  Map<String, Object> prefs = const {},
  Bible? bible,
}) async {
  SharedPreferences.setMockInitialValues({
    ...prefs,
    if (resume != null) 'lastPosition': resume.encode(),
  });
  final settings = await Settings.load();
  final reading = await ReadingStore.load();
  final library = LibraryController(bundle: FixtureBundle(bible: bible));
  await library.load(testTranslation.id);

  await tester.pumpWidget(
    AppScope(
      settings: settings,
      library: library,
      reading: reading,
      child: const MaterialApp(home: ReaderScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(settings, reading, library);
}

void main() {
  testWidgets('opens at Genesis 1 on a fresh install', (tester) async {
    await pumpReader(tester);
    expect(appBarText('Genesis 1'), findsOneWidget);
    expect(
      find.textContaining('In the beginning', findRichText: true),
      findsOneWidget,
    );
    // The section heading and its parallel reference both render.
    expect(find.text('The Creation'), findsOneWidget);
    expect(find.text('(John 1:1–5)'), findsOneWidget);
  });

  testWidgets('resumes where the reader left off', (tester) async {
    await pumpReader(tester, resume: const Reference('PSA', 1, 2));
    expect(appBarText('Psalms 1'), findsOneWidget);
    expect(
      find.textContaining('Blessed is the man', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('lays poetry out line by line with its indents', (tester) async {
    await pumpReader(tester, resume: const Reference('PSA', 1));
    expect(find.text('BOOK 1'), findsOneWidget);
    expect(find.text('A Psalm by David.'), findsOneWidget);
    final indents = tester
        .widgetList<Padding>(find.byType(Padding))
        .map((padding) => padding.padding.resolve(TextDirection.ltr).left)
        .where((left) => left > 0 && left < 60)
        .toSet();
    // Level 1 poetry sits at 8, level 2 one 18pt step further in.
    expect(indents.contains(8.0), isTrue);
    expect(indents.contains(26.0), isTrue);
  });

  testWidgets('the navigator walks book, chapter and verse', (tester) async {
    final harness = await pumpReader(tester);

    await tester.tap(find.text('Genesis 1'));
    await tester.pumpAndSettle();
    expect(find.text('Go to'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gen');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genesis').last);
    await tester.pumpAndSettle();

    // Chapter step.
    await tester.tap(find.widgetWithText(InkWell, '2').first);
    await tester.pumpAndSettle();
    // Verse step: take the whole chapter.
    await tester.tap(find.text('Whole chapter'));
    await tester.pumpAndSettle();

    expect(appBarText('Genesis 2'), findsOneWidget);
    expect(harness.reading.lastPosition?.chapter, 2);
  });

  testWidgets('a one-chapter book is opened straight away', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.text('Genesis 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'matthew');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matthew').last);
    await tester.pumpAndSettle();

    expect(appBarText('Matthew 1'), findsOneWidget);
  });

  testWidgets('a typed reference offers a direct jump', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.text('Genesis 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gen 2');
    await tester.pumpAndSettle();

    expect(find.text('Go to Genesis 2'), findsOneWidget);
    await tester.tap(find.text('Go to Genesis 2'));
    await tester.pumpAndSettle();

    expect(appBarText('Genesis 2'), findsOneWidget);
    expect(
      find.textContaining('The second chapter', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('tapping a verse can highlight and bookmark it', (tester) async {
    final harness = await pumpReader(tester);
    const verse = Reference('GEN', 1, 2);

    await tester.tap(verseNumber('2'));
    await tester.pumpAndSettle();
    expect(find.text('Genesis 1:2'), findsOneWidget);

    await tester.tap(find.byTooltip('Highlight Green'));
    await tester.pumpAndSettle();
    expect(harness.reading.markFor(verse)?.colorIndex, 1);

    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();
    expect(harness.reading.isBookmarked(verse), isTrue);
  });

  testWidgets('comparing shows a second translation verse by verse', (
    tester,
  ) async {
    final harness = await pumpReader(tester);

    harness.settings.compareTranslationId = otherTranslation.id;
    await tester.pumpAndSettle();

    expect(harness.library.comparison, isNotNull);
    // Once as the app-bar badge and once as the column label.
    expect(find.text('TST'), findsOneWidget);
    expect(find.text('OTH'), findsNWidgets(2));
    expect(
      find.textContaining('In the beginning', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('At the first God made', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('jumping to a verse in another chapter scrolls to it', (
    tester,
  ) async {
    final harness = await pumpReader(tester);

    await tester.tap(find.text('Genesis 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gen 1:3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Genesis 1:3'));
    await tester.pumpAndSettle();

    // The pending verse belongs to the page, so the page change that the
    // jump itself causes must not discard it.
    expect(harness.reading.lastPosition, const Reference('GEN', 1, 3));
    expect(
      find.textContaining('Let there be light', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('filtering keeps working when a reference is typed', (
    tester,
  ) async {
    await pumpReader(tester);
    await tester.tap(find.text('Genesis 1'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'gen 1:3');
    await tester.pumpAndSettle();
    expect(find.text('Go to Genesis 1:3'), findsOneWidget);
    // Genesis is still listed underneath, not "no book matches".
    expect(find.textContaining('No book matches'), findsNothing);
    expect(find.text('Genesis'), findsOneWidget);
  });

  testWidgets('a jump scrolls the chapter down to the verse', (tester) async {
    await pumpReader(tester, bible: parseLongFixture());
    final scroller = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroller.controller!.offset, 0);

    await tester.tap(find.text('Genesis 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gen 1:60');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Genesis 1:60'));
    await tester.pumpAndSettle();

    final after = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      after.controller!.offset,
      greaterThan(200),
      reason: 'the chapter should have scrolled to verse 60',
    );
    expect(
      find.textContaining('Chapter 1 verse 60', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a jump into another chapter scrolls there too', (tester) async {
    await pumpReader(tester, bible: parseLongFixture(chapters: 2));

    await tester.tap(find.text('Genesis 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gen 2:60');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Genesis 2:60'));
    await tester.pumpAndSettle();

    expect(appBarText('Genesis 2'), findsOneWidget);
    final scroller = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scroller.controller!.offset,
      greaterThan(200),
      reason: 'changing chapter must not lose the verse to scroll to',
    );
  });

  testWidgets('a verse inside a paragraph scrolls to that paragraph', (
    tester,
  ) async {
    // Prose keeps many verses in one paragraph, so only some verses are
    // anchors; the rest must fall back to the paragraph holding them.
    await pumpReader(
      tester,
      bible: parseLongFixture(versesPerParagraph: 10),
      resume: const Reference('GEN', 1, 64),
    );
    final scroller = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroller.controller!.offset, greaterThan(200));
  });

  testWidgets('resuming opens at the saved verse, not the top', (tester) async {
    await pumpReader(
      tester,
      bible: parseLongFixture(),
      resume: const Reference('GEN', 1, 55),
    );
    final scroller = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroller.controller!.offset, greaterThan(200));
  });

  testWidgets('saves the position when the chapter changes', (tester) async {
    final harness = await pumpReader(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(harness.reading.lastPosition?.bookCode, 'GEN');
    expect(harness.reading.lastPosition?.chapter, 2);
    expect(harness.reading.history.first.label, 'Genesis 2');
  });
}
