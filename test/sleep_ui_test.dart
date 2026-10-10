import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/read_aloud.dart';
import 'package:openword/src/data/translations.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/learn_progress.dart';
import 'package:openword/src/model/memory_exercise.dart';
import 'package:openword/src/model/memory_verse.dart';
import 'package:openword/src/model/reading_plan.dart';
import 'package:openword/src/model/sleep_policy.dart';
import 'package:openword/src/ui/memory_screen.dart';
import 'package:openword/src/ui/pretest_card.dart';
import 'package:openword/src/ui/quiz_screen.dart';

import 'memory_ui_test.dart' show arrange, libraryButton, openPractice, tapTile;
import 'plans_ui_test.dart' show planPrefs;
import 'read_aloud_test.dart' show FakeSpeech;
import 'reader_screen_test.dart' show pumpReader;

const verse = Reference('GEN', 1, 3);
const text = 'God said, "Let there be light."';
final evening = DateTime(2026, 9, 28, 20, 0);
final nextMorning = DateTime(2026, 9, 29, 7, 0);

Map<String, Object> nights() => {
  'sleep': jsonEncode({'mode': 'nights', 'evening': 19, 'morning': 11}),
};

void main() {
  final original = createSpeechEngine;
  setUp(() => createSpeechEngine = () => FakeSpeech(available: false));
  tearDown(() => createSpeechEngine = original);

  testWidgets('answering from memory asks how sure you are first', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    for (var i = 0; i < 3; i++) {
      harness.reading.reviewMemory(verse, remembered: true);
    }
    await openPractice(tester, verse);
    expect(find.text('From memory'), findsOneWidget);
    expect(find.text('How sure are you?'), findsOneWidget);

    // All the tiles placed, but no word on sureness: nothing to check.
    await arrange(tester, text);
    final check = find.widgetWithText(FilledButton, 'Check');
    expect(tester.widget<FilledButton>(check).onPressed, isNull);
    await tester.tap(find.text('Sure'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(check).onPressed, isNotNull);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.text('Nicely done.'), findsOneWidget);
    expect(harness.reading.progress.calibration(Confidence.sure), 1.0);
    expect(harness.reading.progress.confidentMisses, 0);
  });

  testWidgets('a sure miss is named, counted, and asked again', (tester) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    for (var i = 0; i < 3; i++) {
      harness.reading.reviewMemory(verse, remembered: true);
    }
    await openPractice(tester, verse);
    for (final tile in VerseTiles.of(text).reversed) {
      await tapTile(tester, tile);
    }
    await tester.tap(find.text('Sure'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('Not quite.'), findsOneWidget);
    expect(find.textContaining('You were sure of it.'), findsOneWidget);
    expect(harness.reading.progress.confidentMisses, 1);
    expect(harness.reading.memoryFor(verse)!.confidentMisses, 1);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    // Asked again, as a new verse: shown, so no sureness is asked.
    expect(find.text('Put it together'), findsOneWidget);
    expect(find.text('How sure are you?'), findsNothing);
  });

  testWidgets('a verse learnt at night is asked for next morning, with the '
      'question', (tester) async {
    var now = evening;
    final harness = await pumpReader(tester, prefs: nights(), clock: () => now);
    harness.reading.toggleMemorise(verse);
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    expect(find.text('Learn a new verse tonight'), findsOneWidget);
    expect(find.text('1 new · 5 questions · about 2 minutes'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Put it together'), findsOneWidget);
    await arrange(tester, text);
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Asked for tomorrow morning'), findsOneWidget);
    expect(find.byKey(const Key('slept')), findsNothing);
    expect(harness.reading.memoryFor(verse)!.stage, MemoryStage.introduced);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    // Nothing more tonight; on to the round, and out.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Next morning: the recall, bare, then the question.
    now = nextMorning;
    harness.reading.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Recall last night’s verses'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoryScreen), findsOneWidget);
    expect(find.text('From memory'), findsOneWidget);
    await arrange(tester, text);
    await tester.tap(find.text('Fairly sure'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('slept')), findsOneWidget);
    final go = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(go).onPressed, isNull);
    // Not yet recorded: the question decides what kind of recall it was.
    expect(harness.reading.memoryFor(verse)!.firstRecall, isNull);
    await tester.tap(find.text('Yes, I slept'));
    await tester.pumpAndSettle();
    final learnt = harness.reading.memoryFor(verse)!;
    expect(learnt.firstRecall!.right, isTrue);
    expect(learnt.firstRecall!.slept, isTrue);
    expect(learnt.stage, MemoryStage.onLadder);
    expect(tester.widget<FilledButton>(go).onPressed, isNotNull);
  });

  testWidgets('the Progress tab says how the trial stands', (tester) async {
    final harness = await pumpReader(tester, prefs: nights());
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();
    expect(find.text('Sleeping on it'), findsOneWidget);
    expect(find.textContaining('Too soon to say: 0 of 5'), findsOneWidget);
    harness.reading.setSleepPolicy(const SleepPolicy(mode: SleepMode.off));
    await tester.pumpAndSettle();
    expect(find.textContaining('Switched off.'), findsOneWidget);
  });

  testWidgets('Settings chooses the timing and the hours', (tester) async {
    final harness = await pumpReader(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sleep and new verses'), 200);
    // Brought fully on screen: the tile's middle was just over the edge.
    await tester.ensureVisible(find.text('Sleep and new verses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sleep and new verses'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep and new verses'), findsNWidgets(2));
    await tester.tap(find.text('Nights only'));
    await tester.pumpAndSettle();
    expect(harness.reading.sleepPolicy.mode, SleepMode.nights);
    expect(find.byKey(const Key('evening')), findsOneWidget);
    await tester.tap(find.text('7 pm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9 pm').last);
    await tester.pumpAndSettle();
    expect(harness.reading.sleepPolicy.eveningStart, 21);
  });

  testWidgets('a plan chapter offers a guess before reading, and after', (
    tester,
  ) async {
    // The fixture's verses are too short to finish; the real text is not.
    final web = BibFile.decode(
      File(Translations.assetFor(Translations.fallback.id)).readAsBytesSync(),
    );
    await pumpReader(
      tester,
      bible: web,
      prefs: planPrefs(ReadingPlans.bibleInAYear.id),
    );
    expect(find.byType(PretestCard), findsOneWidget);
    expect(find.text('Guess before you read'), findsOneWidget);
    await tester.tap(find.text('Guess'));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    expect(find.text('Question 1 of 2'), findsOneWidget);
    // Real verses are long: the options and the button may be below the
    // fold, and a list builds only what is in view.
    final list = find.byType(ListView).last;
    for (var i = 0; i < 2; i++) {
      final option = find.byWidgetPredicate(
        (w) => w is InkWell && w.onTap != null,
      );
      await tester.dragUntilVisible(option.first, list, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(option.first);
      await tester.pumpAndSettle();
      final next = find.text(i == 1 ? 'Finish' : 'Next');
      await tester.dragUntilVisible(next, list, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      find.text('Read on; the same questions wait at the end.'),
      findsOneWidget,
    );

    // The page is one scroll view, so the card is built; bring it up.
    await tester.ensureVisible(find.byType(PosttestCard));
    await tester.pumpAndSettle();
    expect(find.textContaining('Answer again now?'), findsOneWidget);
    await tester.tap(find.text('Answer'));
    await tester.pumpAndSettle();
    expect(find.text('After reading'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}
