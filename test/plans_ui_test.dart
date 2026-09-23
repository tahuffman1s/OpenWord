import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/reading_plan.dart';
import 'package:openword/src/ui/plans_screen.dart';
import 'package:openword/src/ui/reader_screen.dart';

import 'reader_screen_test.dart' show appBarText, pumpReader;

/// A plan saved as started [daysAgo] days ago, with [done] read.
Map<String, Object> planPrefs(
  String id, {
  int daysAgo = 0,
  List<int> done = const [],
}) {
  final start = DateTime.now().subtract(Duration(days: daysAgo));
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'plans': jsonEncode([
      {
        'id': id,
        'start': '${start.year}-${two(start.month)}-${two(start.day)}',
        't': 1,
        'done': done,
      },
    ]),
  };
}

Finder planButton() => find.byTooltip('Reading plans (P)');

void main() {
  testWidgets('a chapter outside any plan has no plan card', (tester) async {
    await pumpReader(tester);
    expect(find.byType(PlanChapterCard), findsNothing);
  });

  testWidgets('the end of a plan chapter ticks it off and goes on', (
    tester,
  ) async {
    // Day 1 of the Bible in a year is Genesis 1–3; the fixture has 1 and 2.
    final harness = await pumpReader(
      tester,
      prefs: planPrefs(ReadingPlans.bibleInAYear.id),
    );
    final done = find.text('Done — next: Genesis 2');
    await tester.ensureVisible(done);
    await tester.pumpAndSettle();
    await tester.tap(done);
    await tester.pumpAndSettle();

    expect(appBarText('Genesis 2'), findsOneWidget);
    final progress = harness.reading.progressFor(ReadingPlans.bibleInAYear.id)!;
    expect(progress.done, {0});

    // Genesis 3 is not in this translation, so Genesis 2 ends the day here.
    final last = find.text('Done — that’s day 1');
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(harness.reading.progressFor(ReadingPlans.bibleInAYear.id)!.done, {
      0,
      1,
    });
    // Still offered back, after the fact.
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(harness.reading.progressFor(ReadingPlans.bibleInAYear.id)!.done, {
      0,
    });
  });

  testWidgets('finishing a day says so', (tester) async {
    // Proverbs is not in the fixture; the Gospels are, as far as Matthew 1.
    await pumpReader(
      tester,
      resume: const Reference('MAT', 1),
      prefs: planPrefs(
        ReadingPlans.gospels.id,
        // Everything on day 1 but Matthew 1 already read.
        done: [
          for (final slot in ReadingPlans.gospels.days.first.slots)
            if (slot != 0) slot,
        ],
      ),
    );
    final done = find.text('Done — that’s day 1');
    await tester.ensureVisible(done);
    await tester.pumpAndSettle();
    await tester.tap(done);
    await tester.pump();
    expect(find.textContaining('Day 1 done'), findsOneWidget);
  });

  testWidgets('the plan button carries a dot while a reading is due', (
    tester,
  ) async {
    final harness = await pumpReader(
      tester,
      prefs: planPrefs(ReadingPlans.proverbsMonth.id),
    );
    Badge badge() => tester.widget<Badge>(
      find.descendant(of: planButton(), matching: find.byType(Badge)),
    );
    expect(badge().isLabelVisible, isTrue);
    harness.reading.setPlanSlot(ReadingPlans.proverbsMonth.id, 0, read: true);
    await tester.pumpAndSettle();
    expect(badge().isLabelVisible, isFalse);
  });

  testWidgets('starting a plan from the reader, in three taps', (tester) async {
    final harness = await pumpReader(tester);
    await tester.tap(planButton());
    await tester.pumpAndSettle();
    expect(find.text('Good place to start'), findsOneWidget);

    await tester.tap(find.text('The Gospels in 30 days'));
    await tester.pumpAndSettle();
    expect(find.text('Matthew 1–5'), findsOneWidget);
    await tester.tap(find.text('Start today'));
    await tester.pumpAndSettle();

    // Straight to day 1, with the tick waiting at the end of it.
    expect(find.byType(PlansScreen), findsNothing);
    expect(appBarText('Matthew 1'), findsOneWidget);
    expect(harness.reading.progressFor(ReadingPlans.gospels.id), isNotNull);
    expect(find.byType(PlanChapterCard), findsOneWidget);
  });

  testWidgets('today\'s reading is on the plan page, and opens', (
    tester,
  ) async {
    await pumpReader(tester, prefs: planPrefs(ReadingPlans.bibleInAYear.id));
    await tester.tap(planButton());
    await tester.pumpAndSettle();
    expect(find.text('Day 1 of 365'), findsOneWidget);
    expect(find.text('Genesis 1–3'), findsOneWidget);
    expect(find.text('Start reading'), findsOneWidget);
    // A new plan is not behind anything.
    expect(find.text('Pick up from today'), findsNothing);

    await tester.tap(find.text('Start reading'));
    await tester.pumpAndSettle();
    expect(appBarText('Genesis 1'), findsOneWidget);
  });

  testWidgets('falling behind is said gently, once, and fixed in a tap', (
    tester,
  ) async {
    final harness = await pumpReader(
      tester,
      prefs: planPrefs(ReadingPlans.proverbsMonth.id, daysAgo: 5),
    );
    await tester.tap(planButton());
    await tester.pumpAndSettle();
    // Still day 1: nothing piled up while away.
    expect(find.text('Day 1 of 31'), findsOneWidget);
    expect(find.textContaining('5 days behind'), findsOneWidget);

    await tester.tap(find.text('Pick up from today'));
    await tester.pumpAndSettle();
    expect(find.textContaining('behind'), findsNothing);
    final progress = harness.reading.progressFor(
      ReadingPlans.proverbsMonth.id,
    )!;
    expect(progress.slotsDone, 0, reason: 'nothing is marked read for you');
    expect(progress.currentDay!.number, 1);
  });

  testWidgets('a passage can be ticked from the plan page', (tester) async {
    final harness = await pumpReader(
      tester,
      prefs: planPrefs(ReadingPlans.proverbsMonth.id),
    );
    await tester.tap(planButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mark as read'));
    await tester.pumpAndSettle();
    expect(harness.reading.progressFor(ReadingPlans.proverbsMonth.id)!.done, {
      0,
    });
    // Today is done; tomorrow is offered, not pushed.
    expect(find.text('Done for today — next up'), findsOneWidget);
    expect(find.text('Proverbs 2'), findsOneWidget);
    // Not in the fixture translation, which is said rather than offered.
    expect(find.textContaining('not in this translation'), findsOneWidget);
  });

  testWidgets('removing a plan can be undone', (tester) async {
    final harness = await pumpReader(
      tester,
      prefs: planPrefs(ReadingPlans.proverbsMonth.id, done: [0, 1]),
    );
    await tester.tap(planButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plan options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove plan'));
    await tester.pumpAndSettle();
    expect(harness.reading.plans, isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(harness.reading.progressFor(ReadingPlans.proverbsMonth.id)!.done, {
      0,
      1,
    });
  });

  testWidgets('every day can be seen, opened at the current one', (
    tester,
  ) async {
    await pumpReader(
      tester,
      prefs: planPrefs(
        ReadingPlans.proverbsMonth.id,
        done: [for (var i = 0; i < 20; i++) i],
      ),
    );
    await tester.tap(planButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plan options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See every day'));
    await tester.pumpAndSettle();
    expect(find.text('20 of 31 days read'), findsOneWidget);
    expect(find.text('Day 21 · next'), findsOneWidget);
  });

  testWidgets('the reader\'s toolbar still fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpReader(tester, prefs: planPrefs(ReadingPlans.gospels.id));
    // An overflow would have failed the pump; the chapter name is there.
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(planButton(), findsOneWidget);
  });
}
