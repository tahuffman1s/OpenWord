import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/read_aloud.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/suggested_verses.dart';
import 'package:openword/src/ui/memory_screen.dart';
import 'package:openword/src/ui/quiz_screen.dart';

import 'fixtures.dart';
import 'memory_ui_test.dart' show arrange, libraryButton;
import 'read_aloud_test.dart' show FakeSpeech;
import 'reader_screen_test.dart' show appBarText, pumpReader;

const verse = Reference('GEN', 1, 3);
const text = 'God said, "Let there be light."';

void main() {
  final original = createSpeechEngine;
  setUp(() => createSpeechEngine = () => FakeSpeech(available: false));
  tearDown(() => createSpeechEngine = original);

  test('suggestions are the ones this translation has, not yet learning', () {
    final bible = parseFixture();
    final all = SuggestedVerse.available(bible);
    expect(all.map((s) => s.reference), [
      const Reference('GEN', 1, 1),
      const Reference('PSA', 1, 1),
    ]);
    final fewer = SuggestedVerse.available(
      bible,
      alreadyLearning: (r) => r == const Reference('GEN', 1, 1),
    );
    expect(fewer.map((s) => s.reference), [const Reference('PSA', 1, 1)]);
    expect(
      SuggestedVerse.all.map((s) => s.reference).toSet().length,
      SuggestedVerse.all.length,
    );
  });

  testWidgets('with nothing to learn, verses worth knowing are offered', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();

    // Learn opens first, with the lesson and the suggestions.
    expect(find.byKey(const Key('lesson')), findsOneWidget);
    expect(find.text('Today’s lesson'), findsOneWidget);
    expect(find.text('5 questions · about 1 minute'), findsOneWidget);
    expect(find.textContaining('start with one of these'), findsOneWidget);
    expect(find.text('Genesis 1:1 · Beginnings'), findsOneWidget);
    expect(find.text('Psalms 1:1 · Guidance'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pumpAndSettle();
    expect(harness.reading.isMemorising(const Reference('GEN', 1, 1)), isTrue);
    // Learning now: the list, with the one added, and Add for the rest.
    expect(find.text('Genesis 1:1'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text('1 new · 5 questions · about 2 minutes'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Verses worth knowing'), findsOneWidget);
    expect(find.text('Guidance'), findsOneWidget);
    await tester.tap(find.text('Psalms 1:1'));
    await tester.pumpAndSettle();
    expect(harness.reading.isMemorising(const Reference('PSA', 1, 1)), isTrue);
  });

  testWidgets('a lesson is the verses due and then a short round', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.byType(MemoryScreen), findsOneWidget);
    await arrange(tester, text);
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Straight on to the round, of at most five.
    expect(find.byType(MemoryScreen), findsNothing);
    expect(find.byType(QuizScreen), findsOneWidget);
    final heading = tester
        .widget<Text>(find.textContaining('Question 1 of'))
        .data!;
    final total = int.parse(heading.split(' ').last);
    expect(total, inInclusiveRange(1, 5));
  });

  testWidgets('a passage opened from a lesson reaches the reader', (
    tester,
  ) async {
    await pumpReader(tester, resume: const Reference('PSA', 1));
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    // Nothing due: the lesson is the round alone.
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    // Answer the first question, wrong or right, and open its passage.
    final option = find.byWidgetPredicate(
      (w) => w is InkWell && w.onTap != null,
    );
    await tester.tap(option.first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithIcon(OutlinedButton, Icons.menu_book_rounded),
    );
    await tester.pumpAndSettle();
    // Back in the reader, at the passage the answer named.
    expect(find.byType(QuizScreen), findsNothing);
    expect(find.text('Library'), findsNothing);
    final shown = [
      'Genesis 1',
      'Genesis 2',
      'Psalms 1',
      'Matthew 1',
    ].where((label) => appBarText(label).evaluate().isNotEmpty).toList();
    expect(shown, hasLength(1));
  });

  testWidgets('Saved holds the marks behind one row of choices', (
    tester,
  ) async {
    final harness = await pumpReader(
      tester,
      resume: const Reference('PSA', 1),
      prefs: {
        'history': ['GEN/2/'],
      },
    );
    harness.reading.toggleBookmark(verse);
    harness.reading.setNote(const Reference('GEN', 1, 2), 'A note');
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('Genesis 1:3'), findsOneWidget);
    expect(find.text('Genesis 1:2'), findsNothing);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Genesis 1:2'), findsOneWidget);
    expect(find.text('A note'), findsOneWidget);
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();
    expect(find.text('Genesis 2'), findsOneWidget);
    await tester.tap(find.text('Genesis 2'));
    await tester.pumpAndSettle();
    expect(appBarText('Genesis 2'), findsOneWidget);
  });
}
