import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/ui/memory_screen.dart';

import 'reader_screen_test.dart' show appBarText, pumpReader, verseNumber;

Finder libraryButton() =>
    find.byTooltip('Bookmarks, highlights, notes and learning');

/// Scrolls the Learn tab until [finder] is on screen: the memory verses
/// sit under the rounds to test yourself with.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find
        .descendant(
          of: find.byType(TabBarView),
          matching: find.byType(ListView),
        )
        .first,
    const Offset(0, -150),
  );
  await tester.pumpAndSettle();
}

void main() {
  const verse = Reference('GEN', 1, 3);

  testWidgets('a verse is memorised from its sheet and shows in the library', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    expect(harness.reading.hasMemoryDue, isFalse);

    await tester.tap(verseNumber('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memorise'));
    await tester.pumpAndSettle();
    expect(harness.reading.isMemorising(verse), isTrue);
    expect(find.text('Memorising'), findsOneWidget);
    expect(find.textContaining('Memorising Genesis 1:3'), findsOneWidget);

    // The library button carries a dot while the verse is due, and the
    // library opens on Memory.
    final badge = tester.widget<Badge>(
      find.descendant(of: libraryButton(), matching: find.byType(Badge)),
    );
    expect(badge.isLabelVisible, isTrue);

    await tester.tap(find.text('Memorising'));
    await tester.pumpAndSettle();
    expect(harness.reading.isMemorising(verse), isFalse);
    await tester.tap(find.text('Memorise'));
    await tester.pumpAndSettle();
    // Close the sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    expect(find.text('1 verse due today'), findsOneWidget);
    expect(find.text('Genesis 1:3'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
  });

  testWidgets('a session shows, hints, hides and checks the verse', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Practise'));
    await tester.tap(find.text('Practise'));
    await tester.pumpAndSettle();

    // New, so read over first: the whole verse and the question at once.
    expect(find.byType(MemoryScreen), findsOneWidget);
    expect(find.text('God said, "Let there be light."'), findsOneWidget);
    expect(find.text('Did you have it?'), findsOneWidget);
    expect(find.textContaining('New · not yet recalled'), findsOneWidget);

    // First letters hide the words but keep their shape.
    await tester.tap(find.text('First letters'));
    await tester.pumpAndSettle();
    expect(find.text('G__ s___, "L__ t____ b_ l____."'), findsOneWidget);
    expect(find.text('Did you have it?'), findsNothing);
    await tester.tap(find.text('Show the verse'));
    await tester.pumpAndSettle();
    expect(find.text('God said, "Let there be light."'), findsOneWidget);

    // From memory shows nothing until asked.
    await tester.tap(find.text('From memory'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Say it to yourself'), findsOneWidget);
    await tester.tap(find.text('Show the verse'));
    await tester.pumpAndSettle();

    // Not yet: back to the bottom and asked again in the same session.
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoryScreen), findsOneWidget);
    expect(harness.reading.memoryFor(verse)!.rung, 0);
    expect(find.text('Show the verse'), findsOneWidget);

    // Got it: up a rung, due tomorrow, and the session is over.
    await tester.tap(find.text('Show the verse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(harness.reading.memoryFor(verse)!.rung, 1);
    expect(harness.reading.hasMemoryDue, isFalse);
    expect(find.text('That’s the verse for today'), findsOneWidget);
    expect(find.text('Next up: Genesis 1:3, tomorrow.'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Tomorrow'));
    expect(find.text('Nothing due today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
  });

  testWidgets('a verse can be opened in the reader from a session', (
    tester,
  ) async {
    final harness = await pumpReader(tester, resume: const Reference('PSA', 1));
    harness.reading.toggleMemorise(verse);
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Genesis 1:3'));
    await tester.tap(find.text('Genesis 1:3'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoryScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Open in the reader'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoryScreen), findsNothing);
    expect(appBarText('Genesis 1'), findsOneWidget);
  });

  testWidgets('swiping a verse away stops memorising it, with undo', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Genesis 1:3'));
    await tester.drag(find.text('Genesis 1:3'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(harness.reading.isMemorising(verse), isFalse);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(harness.reading.isMemorising(verse), isTrue);
  });
}
