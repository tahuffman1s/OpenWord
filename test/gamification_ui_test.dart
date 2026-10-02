import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/read_aloud.dart';
import 'package:openword/src/model/achievements.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/learn_progress.dart';
import 'package:openword/src/model/memory_exercise.dart';
import 'package:openword/src/model/quiz.dart';
import 'package:openword/src/ui/learn_progress_card.dart';
import 'package:openword/src/ui/widgets/confetti.dart';

import 'memory_ui_test.dart' show arrange, libraryButton, openPractice, reveal;
import 'quiz_ui_test.dart' show pushQuiz;
import 'read_aloud_test.dart' show FakeSpeech;
import 'reader_screen_test.dart' show pumpReader;

const verse = Reference('GEN', 1, 3);
const text = 'God said, "Let there be light."';

void main() {
  final original = createSpeechEngine;
  setUp(() => createSpeechEngine = () => FakeSpeech(available: false));
  tearDown(() => createSpeechEngine = original);

  testWidgets('the Learn tab shows level, goal, badges, and sets the goal', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();

    expect(find.byType(LearnProgressCard), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('of 40 XP'), findsOneWidget);
    expect(find.text('Today’s goal: steady'), findsOneWidget);
    expect(find.text('0 XP · 50 to level 2'), findsOneWidget);
    expect(
      find.text('Badges · 0 of ${Achievement.values.length}'),
      findsOneWidget,
    );
    expect(
      find.byType(AchievementIcon),
      findsNWidgets(Achievement.values.length),
    );

    await tester.tap(find.byKey(const Key('goal')));
    await tester.pumpAndSettle();
    expect(find.text('Daily goal'), findsOneWidget);
    await tester.tap(find.text('Gentle · 20 XP'));
    await tester.pumpAndSettle();
    expect(harness.reading.progress.goal, DailyGoal.gentle);
    expect(find.text('of 20 XP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('badges')));
    await tester.pumpAndSettle();
    expect(find.text('First step'), findsOneWidget);
    expect(find.text('Earned your first points.'), findsOneWidget);
  });

  testWidgets('a session earns points, meets the goal, and wins a badge', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    harness.reading.setDailyGoal(DailyGoal.gentle);
    harness.reading.toggleMemorise(verse);
    harness.reading.toggleMemorise(const Reference('GEN', 1, 2));
    await openPractice(tester, verse);

    // The first right answer: 10 XP, shown on the verdict.
    await arrange(tester, text);
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('+10 XP'), findsOneWidget);
    expect(harness.reading.progress.xp, 10);
    expect(harness.reading.progress.badges.keys, ['first_step']);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // The second: another 10, and the gentle goal of 20 is met.
    await arrange(tester, 'The earth was formless and empty.');
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('+10 XP'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // The summary: what it earned, the goal met, the badge won, confetti.
    expect(find.text('That’s all 2 for today'), findsOneWidget);
    expect(find.text('+20 XP'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('2 in a row'), findsOneWidget);
    expect(find.text('Today’s goal met: 20 XP.'), findsOneWidget);
    expect(find.text('Badge won: First step'), findsOneWidget);
    expect(tester.widget<Confetti>(find.byType(Confetti)).play, isTrue);
    expect(find.text('1-day streak'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Today’s goal met'), up: true);
    expect(
      find.text('Badges · 1 of ${Achievement.values.length}'),
      findsOneWidget,
    );
    expect(find.text('20 XP · 30 to level 2'), findsOneWidget);
  });

  testWidgets('a wrong answer earns nothing and breaks the run', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    await openPractice(tester, verse);
    for (final tile in VerseTiles.of(text).reversed) {
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('bank')),
          matching: find.text(tile),
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('Not quite.'), findsOneWidget);
    expect(find.textContaining(' XP'), findsNothing);
    expect(harness.reading.progress.xp, 0);
    expect(harness.reading.progress.wrong, 1);
    expect(harness.reading.progress.badges, isEmpty);
    // Wrong or not, today counts for the streak.
    expect(harness.reading.streak.count, 1);
  });

  testWidgets('a perfect round earns its bonus and badge', (tester) async {
    final harness = await pumpReader(tester);
    await pushQuiz(tester, QuizKind.bookOrder);
    var asked = 0;
    while (find.textContaining('Question ').evaluate().isNotEmpty) {
      asked++;
      final stem = tester.widget<Text>(
        find.textContaining('Which book comes').first,
      );
      final about = RegExp(r'(after|before) (.+)\?').firstMatch(stem.data!)!;
      const order = ['Genesis', 'Psalms', 'Matthew'];
      final at = order.indexOf(about.group(2)!);
      await tester.tap(
        find.text(order[about.group(1) == 'after' ? at + 1 : at - 1]).last,
      );
      await tester.pumpAndSettle();
      // Five a question, with the run's bonus on the third.
      expect(
        find.text('+${Xp.quizRight + Xp.comboBonus(asked)} XP'),
        findsOneWidget,
      );
      final last = find.text('Finish').evaluate().isNotEmpty;
      await tester.tap(find.text(last ? 'Finish' : 'Next'));
      await tester.pumpAndSettle();
    }
    var earned = Xp.perfectRound;
    for (var i = 1; i <= asked; i++) {
      earned += Xp.quizRight + Xp.comboBonus(i);
    }
    expect(find.text('+$earned XP'), findsOneWidget);
    expect(find.text('Perfect round: +20 XP on top.'), findsOneWidget);
    expect(find.text('Badge won: Perfect round'), findsOneWidget);
    expect(find.text('Badge won: First step'), findsOneWidget);
    expect(harness.reading.progress.perfectRounds, 1);
    expect(harness.reading.progress.xp, earned);
    await tester.pump(const Duration(seconds: 3));
  });
}
