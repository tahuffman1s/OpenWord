import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/app_scope.dart';
import 'package:openword/src/data/library.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/data/updates.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/ui/reader_screen.dart';
import 'package:openword/src/ui/widgets/atlas_map.dart';
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
  Harness(this.settings, this.reading, this.library, this.updates);

  final Settings settings;
  final ReadingStore reading;
  final LibraryController library;
  final UpdateService updates;
}

Future<Harness> pumpReader(
  WidgetTester tester, {
  Reference? resume,
  Map<String, Object> prefs = const {},
  Bible? bible,
  FakeUpdateBackend? updateBackend,
}) async {
  SharedPreferences.setMockInitialValues({
    ...prefs,
    if (resume != null) 'lastPosition': resume.encode(),
  });
  final settings = await Settings.load();
  final reading = await ReadingStore.load();
  final library = LibraryController(bundle: FixtureBundle(bible: bible));
  await library.load(testTranslation.id);
  // Never the real backend in a test: that would reach for the network.
  final updates = UpdateService(
    settings: settings,
    backend: updateBackend ?? FakeUpdateBackend(isSupported: false),
    currentVersion: '1.0.0',
  );

  await tester.pumpWidget(
    AppScope(
      settings: settings,
      library: library,
      reading: reading,
      updates: updates,
      child: const MaterialApp(home: ReaderScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(settings, reading, library, updates);
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
    expect(
      find.textContaining('Psalms 1:1', findRichText: true),
      findsOneWidget,
    );
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

  testWidgets('only paragraphs that continue a passage are indented', (
    tester,
  ) async {
    await pumpReader(tester);
    // Genesis 1 in the fixture is: heading, reference, \p, \p, \m, \pi,
    // speaker. Only the second \p continues a passage and indents; the first
    // opens one after the heading, \m is flush by marker and \pi is indented
    // as a block instead.
    final indents = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((box) => (box.width ?? 0) > 15 && (box.height == null))
        .length;
    expect(indents, 1);
  });

  testWidgets('the chapter grid opens at the chapter being read', (
    tester,
  ) async {
    await pumpReader(
      tester,
      bible: parseLongFixture(verses: 4, chapters: 60),
      resume: const Reference('GEN', 55),
    );

    await tester.tap(find.text('Genesis 55'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gen');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genesis').last);
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      grid.controller!.offset,
      greaterThan(100),
      reason: 'chapter 55 would otherwise be far below the fold',
    );
    expect(find.widgetWithText(InkWell, '55'), findsOneWidget);
  });

  testWidgets('a short book still opens its grid at the top', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.text('Genesis 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gen');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genesis').last);
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.controller!.offset, 0);
  });

  testWidgets('a cited passage in a reference line is tappable', (
    tester,
  ) async {
    final harness = await pumpReader(tester);

    // Genesis 1 in the fixture carries a parallel-passage line citing two
    // places; tapping one should take the reader there.
    final link = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Psalms 1:1'),
    );
    expect(link, findsOneWidget);

    // Find the span carrying the citation and fire its tap handler, rather
    // than guessing where the glyphs landed.
    TapGestureRecognizer? recognizer;
    tester.widget<RichText>(link).text.visitChildren((span) {
      if (span is TextSpan && span.text == 'Psalms 1:1') {
        recognizer = span.recognizer as TapGestureRecognizer?;
        return false;
      }
      return true;
    });
    expect(recognizer, isNotNull, reason: 'the citation should be a link');
    recognizer!.onTap!();
    await tester.pumpAndSettle();

    expect(appBarText('Psalms 1'), findsOneWidget);
    expect(harness.reading.lastPosition?.bookCode, 'PSA');
  });

  testWidgets('a footnote opens, with its citations tappable', (tester) async {
    await pumpReader(tester);

    // The footnote marker on Genesis 1:1.
    await tester.tap(find.byIcon(Icons.circle).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Elohim'), findsOneWidget);
  });

  testWidgets('the book name opens a background note', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.text('GENESIS'));
    await tester.pumpAndSettle();

    expect(find.text('Law • Old Testament'), findsOneWidget);
    // The bundled introduction: its lead, then its sections as an outline.
    expect(find.textContaining('book of beginnings'), findsOneWidget);
    expect(find.text('Setting'), findsOneWidget);
    expect(find.text('Author'), findsOneWidget);
    expect(find.textContaining('CC BY-SA 4.0'), findsOneWidget);

    // A section is folded away until it is asked for.
    expect(find.textContaining('Ur of the Chaldees'), findsNothing);
    await tester.tap(find.text('Setting'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ur of the Chaldees'), findsOneWidget);
  });

  testWidgets('a chapter that names places offers its map', (tester) async {
    await pumpReader(tester);

    // The fixture atlas puts one place in Genesis 1 and two in Genesis 2.
    expect(find.text('1 PLACE'), findsOneWidget);

    await tester.tap(find.text('1 PLACE'));
    await tester.pumpAndSettle();

    expect(find.text('Genesis 1'), findsWidgets);
    expect(find.text('One place named here'), findsOneWidget);
    expect(find.byType(AtlasMap), findsOneWidget);
    expect(find.textContaining('OpenBible.info'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Bethel'));
    await tester.pumpAndSettle();

    // What the open data knows about the place, and where the chapter names
    // it.
    expect(find.textContaining('31.930°N'), findsOneWidget);
    expect(find.textContaining('Beitin', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('Beth-el, Luz', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('north of Jerusalem'), findsOneWidget);
    expect(
      find.textContaining('71 verses', findRichText: true),
      findsOneWidget,
    );
    expect(find.widgetWithText(ActionChip, 'verse 1'), findsOneWidget);
  });

  testWidgets('a verse on the map is somewhere to read', (tester) async {
    await pumpReader(tester, resume: const Reference('GEN', 2));

    await tester.tap(find.text('2 PLACES'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bethel'));
    await tester.pumpAndSettle();

    // Bethel is named at verses 2 and 5 of the fixture's second chapter.
    expect(find.widgetWithText(ActionChip, 'verse 2'), findsOneWidget);
    final verse = find.widgetWithText(ActionChip, 'verse 5');
    // The details pane scrolls; on a test-sized window the chips start below
    // its fold.
    await tester.ensureVisible(verse);
    await tester.pumpAndSettle();
    await tester.tap(verse);
    await tester.pumpAndSettle();

    // The map gets out of the way and the chapter is left on screen.
    expect(find.byType(AtlasMap), findsNothing);
    expect(appBarText('Genesis 2'), findsOneWidget);
  });

  testWidgets('a new release is mentioned, not forced', (tester) async {
    final harness = await pumpReader(
      tester,
      updateBackend: FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0')),
    );

    // The text is still what is on screen; the update is a snack bar.
    expect(
      find.textContaining('In the beginning', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('OpenWord 2.0.0 is out'), findsOneWidget);

    await tester.tap(find.text('See what’s new'));
    await tester.pumpAndSettle();
    expect(find.text('You have 1.0.0'), findsOneWidget);
    expect(harness.updates.release!.tag, 'v2.0.0');
  });

  testWidgets('a skipped version is not mentioned again', (tester) async {
    await pumpReader(
      tester,
      prefs: const {'skippedUpdate': '2.0.0'},
      updateBackend: FakeUpdateBackend(body: releaseJson(tag: 'v2.0.0')),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenWord 2.0.0 is out'), findsNothing);
  });

  testWidgets('a verse offers its cross-references, and they lead on', (
    tester,
  ) async {
    await pumpReader(tester);

    // Genesis 1:1 — tapping the verse opens what can be done with it.
    await tester.tap(verseNumber('1').first);
    await tester.pumpAndSettle();
    expect(find.text('2 cross-references'), findsOneWidget);

    await tester.tap(find.text('2 cross-references'));
    await tester.pumpAndSettle();

    // Grouped under the phrase they hang on, each with the words it points
    // at, taken from the translation in hand.
    expect(find.text('\u201cIn the beginning\u201d'), findsOneWidget);
    expect(find.text('Psalms 1:1'), findsOneWidget);
    expect(find.text('Matthew 1:1'), findsOneWidget);
    expect(
      find.textContaining('CrossReferences.org'),
      findsOneWidget,
      reason: 'CC BY asks for attribution where the work is shown',
    );

    await tester.tap(find.text('Matthew 1:1'));
    await tester.pumpAndSettle();

    expect(appBarText('Matthew 1'), findsOneWidget);
  });

  testWidgets('a verse with no cross-references does not offer any', (
    tester,
  ) async {
    await pumpReader(tester);

    await tester.tap(verseNumber('2').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('cross-references'), findsNothing);
    expect(find.text('Bookmark'), findsOneWidget);
  });

  testWidgets('a verse opens its Hebrew, its dictionary and its concordance', (
    tester,
  ) async {
    await pumpReader(tester);

    await tester.tap(verseNumber('1').first);
    await tester.pumpAndSettle();
    expect(find.text('Hebrew'), findsOneWidget);

    await tester.tap(find.text('Hebrew'));
    await tester.pumpAndSettle();

    // The words of the verse, each with its number and how it is said.
    expect(find.text('בְּרֵאשִׁית'), findsOneWidget);
    expect(find.text('אֱלֹהִים'), findsOneWidget);
    expect(find.text('H430'), findsOneWidget);
    expect(find.text('rêʼshîyth'), findsOneWidget);
    expect(find.textContaining('Open Scriptures'), findsOneWidget);

    // Tapping a word opens what Strong's says about it.
    await tester.tap(find.text('אֱלֹהִים'));
    await tester.pumpAndSettle();
    expect(find.textContaining('supreme God'), findsOneWidget);
    expect(find.text('Used in 2 verses'), findsOneWidget);

    // And from there, everywhere else it is used.
    await tester.tap(find.text('Used in 2 verses'));
    await tester.pumpAndSettle();
    expect(find.text('Genesis 1:1'), findsOneWidget);
    expect(find.text('Genesis 1:3'), findsOneWidget);

    await tester.tap(find.text('Genesis 1:3'));
    await tester.pumpAndSettle();
    expect(appBarText('Genesis 1'), findsOneWidget);
  });

  testWidgets('tapping an English word lights the word behind it', (
    tester,
  ) async {
    await pumpReader(tester);
    await tester.tap(verseNumber('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hebrew'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Tap an English word'),
      findsOneWidget,
      reason: 'the sheet should say what can be done with it',
    );

    // The English line renders one tappable Text per word, so an exact
    // finder picks the word and not the chapter behind the sheet.
    await tester.tap(find.text('God '));
    await tester.pumpAndSettle();
    expect(find.textContaining('most likely came from'), findsOneWidget);

    // A word with nothing clearly behind it says so rather than guessing.
    await tester.tap(find.text('the ').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('No word of the original'), findsOneWidget);
  });

  testWidgets('a verse with no original behind it does not offer one', (
    tester,
  ) async {
    await pumpReader(tester);

    await tester.tap(verseNumber('2').first);
    await tester.pumpAndSettle();

    expect(find.text('Hebrew'), findsNothing);
    expect(find.text('Greek'), findsNothing);
    expect(find.text('Bookmark'), findsOneWidget);
  });

  testWidgets('saves the position when the chapter changes', (tester) async {
    final harness = await pumpReader(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(harness.reading.lastPosition?.bookCode, 'GEN');
    expect(harness.reading.lastPosition?.chapter, 2);
    expect(harness.reading.history.first.label, 'Genesis 2');
  });

  group('a translation numbered differently', () {
    testWidgets('is not offered the layers that would land on wrong verses', (
      tester,
    ) async {
      final normal = parseFixture();

      // Genesis 1:1 has both a cross-reference and a Hebrew word behind it
      // in the fixtures, so both would be offered but for the marking.
      await pumpReader(
        tester,
        bible: Bible(
          translation: normal.translation.copyWith(
            versification: Versification.other,
          ),
          books: normal.books,
        ),
      );

      await tester.tap(verseNumber('1').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('cross-references'), findsNothing);
      expect(find.text('Hebrew'), findsNothing);
      // Everything that does not depend on the numbering still works.
      expect(find.text('Bookmark'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('one that never said keeps them, as it always had', (
      tester,
    ) async {
      final normal = parseFixture();

      await pumpReader(
        tester,
        bible: Bible(
          translation: normal.translation.copyWith(
            versification: Versification.unknown,
          ),
          books: normal.books,
        ),
      );

      await tester.tap(verseNumber('1').first);
      await tester.pumpAndSettle();

      expect(find.text('2 cross-references'), findsOneWidget);
      expect(find.text('Hebrew'), findsOneWidget);
    });
  });

  group('a translation that runs the other way', () {
    testWidgets('the page follows the direction the file declares', (
      tester,
    ) async {
      final ltr = parseFixture();

      // The same Scripture, said to run right to left — which is what an
      // imported Hebrew or Arabic Bible looks like.
      await pumpReader(
        tester,
        bible: Bible(
          translation: ltr.translation.copyWith(
            direction: ReadingDirection.rtl,
            language: 'he',
            script: 'Hebr',
          ),
          books: ltr.books,
        ),
      );

      final block = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.byType(ScriptureBlock).first,
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(block.textDirection, TextDirection.rtl);
    });

    testWidgets('and left to right where it does not', (tester) async {
      await pumpReader(tester);

      final block = tester.widget<Directionality>(
        find
            .ancestor(
              of: find.byType(ScriptureBlock).first,
              matching: find.byType(Directionality),
            )
            .first,
      );
      expect(block.textDirection, TextDirection.ltr);
    });
  });
}
