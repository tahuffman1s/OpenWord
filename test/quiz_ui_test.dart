import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/quiz.dart';
import 'package:openword/src/ui/quiz_screen.dart';
import 'package:openword/src/ui/reader_screen.dart';

import 'package:openword/src/data/read_aloud.dart';

import 'fixtures.dart';
import 'memory_ui_test.dart' show reveal;
import 'read_aloud_test.dart' show FakeSpeech;
import 'reader_screen_test.dart' show appBarText, pumpReader;

Finder libraryButton() => find.byTooltip('Learn, and what you have saved');

/// Opens a round of [kind] over the reader, with a fixed draw.
Future<void> pushQuiz(WidgetTester tester, QuizKind kind, {int seed = 1}) {
  final navigator = Navigator.of(tester.element(find.byType(ReaderScreen)));
  navigator.push(
    MaterialPageRoute<Reference>(
      builder: (_) => QuizScreen(kind: kind, seed: seed),
    ),
  );
  return tester.pumpAndSettle();
}

/// Which book the verse shown by a Which book? question is from, read
/// off the fixture rather than the screen, so the test knows the answer
/// the way a reader who had learnt it would.
String bookOfShownVerse(WidgetTester tester, Bible fixture) {
  final shown = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .toSet();
  for (final book in fixture.books) {
    for (final chapter in book.chapters) {
      for (var verse = 1; verse <= chapter.verseCount; verse++) {
        if (shown.contains(chapter.verseText(verse))) return book.name;
      }
    }
  }
  throw StateError('no fixture verse is on screen');
}

void main() {
  final original = createSpeechEngine;
  setUp(() => createSpeechEngine = () => FakeSpeech(available: false));
  tearDown(() => createSpeechEngine = original);

  testWidgets('with a voice, the verse asked about is read out', (
    tester,
  ) async {
    final speech = FakeSpeech(pauses: true);
    createSpeechEngine = () => speech;
    final fixture = parseFixture();
    await pumpReader(tester);
    await pushQuiz(tester, QuizKind.whichBook);

    final right = bookOfShownVerse(tester, fixture);
    expect(speech.said, hasLength(1));
    final prompt = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .firstWhere((t) => speech.said.single.contains(t.substring(0, 10)));
    expect(prompt, isNotEmpty);
    speech.finish();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hear the verse'));
    await tester.pumpAndSettle();
    expect(speech.said, hasLength(2));
    speech.finish();
    await tester.pumpAndSettle();

    await tester.tap(find.text(right));
    await tester.pumpAndSettle();
    expect(find.text('Right.'), findsOneWidget);
    // Which book? has nothing more to say once answered.
    expect(speech.said, hasLength(2));

    // Books in order shows no Scripture, so nothing speaks there.
    await tester.tap(find.byTooltip('Reading aloud: on'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Reading aloud: off'), findsOneWidget);
  });

  testWidgets('the Learn tab offers the four rounds and memory verses', (
    tester,
  ) async {
    await pumpReader(tester);
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Quiz yourself'));
    for (final kind in QuizKind.values) {
      await reveal(tester, find.text(kind.label));
    }
    await reveal(tester, find.text('Verses you’re learning'));
    expect(find.textContaining('choose Memorise'), findsOneWidget);

    await reveal(tester, find.text('Books in order'));
    await tester.tap(find.text('Books in order'));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsOneWidget);
    expect(find.textContaining('Which book comes'), findsOneWidget);
  });

  testWidgets('a round asks, tells, and scores', (tester) async {
    await pumpReader(tester);
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
      final right = order[about.group(1) == 'after' ? at + 1 : at - 1];

      // Nothing is told before a choice is made.
      expect(find.text('Right.'), findsNothing);
      expect(find.text('Not that one.'), findsNothing);
      await tester.tap(find.text(right).last);
      await tester.pumpAndSettle();
      expect(find.text('Right.'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      final last = find.text('Finish').evaluate().isNotEmpty;
      await tester.tap(find.text(last ? 'Finish' : 'Next'));
      await tester.pumpAndSettle();
    }
    expect(asked, greaterThan(0));
    expect(find.text('$asked of $asked'), findsOneWidget);
    expect(find.text('Every one.'), findsOneWidget);
    expect(find.text('To read again'), findsNothing);

    // Again draws a new round; Done leaves.
    await tester.tap(find.text('Again'));
    await tester.pumpAndSettle();
    expect(find.text('Question 1 of $asked'), findsOneWidget);
    await tester.tap(find.text(order0(tester)).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(find.text('Finish').evaluate().isEmpty ? 'Next' : 'Finish'),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a wrong answer is shown up, listed, and opens the passage', (
    tester,
  ) async {
    final fixture = parseFixture();
    await pumpReader(tester, resume: const Reference('PSA', 1));
    // Through the library, which is what carries the reference back to
    // the reader.
    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Learn'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Which book?'));
    await tester.tap(find.text('Which book?'));
    await tester.pumpAndSettle();

    final right = bookOfShownVerse(tester, fixture);
    final wrong = [
      'Genesis',
      'Psalms',
      'Matthew',
    ].firstWhere((b) => b != right);
    // Only the options carry the names: the stem does not.
    await tester.tap(find.text(wrong));
    await tester.pumpAndSettle();
    expect(find.text('Not that one.'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // Nothing else can be chosen now.
    await tester.tap(find.text(right));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // The reference under the answer opens the passage.
    final reference = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .firstWhere((t) => t.startsWith('$right ') && t.contains(':'));
    await tester.tap(find.text(reference));
    await tester.pumpAndSettle();
    expect(find.byType(QuizScreen), findsNothing);
    expect(appBarText(reference.split(':').first), findsOneWidget);
  });

  testWidgets('the ones missed are listed at the end', (tester) async {
    final fixture = parseFixture();
    await pumpReader(tester);
    await pushQuiz(tester, QuizKind.whichBook);

    var missed = 0;
    var asked = 0;
    while (find.textContaining('Question ').evaluate().isNotEmpty) {
      asked++;
      final right = bookOfShownVerse(tester, fixture);
      // Miss the first, get the rest.
      final choice = asked == 1
          ? ['Genesis', 'Psalms', 'Matthew'].firstWhere((b) => b != right)
          : right;
      if (choice != right) missed++;
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      final last = find.text('Finish').evaluate().isNotEmpty;
      await tester.tap(find.text(last ? 'Finish' : 'Next'));
      await tester.pumpAndSettle();
    }
    expect(missed, 1);
    expect(find.text('${asked - 1} of $asked'), findsOneWidget);
    expect(find.text('To read again'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
  });
}

/// The right answer to the Books in order question on screen.
String order0(WidgetTester tester) {
  final stem = tester.widget<Text>(find.textContaining('Which book comes'));
  final about = RegExp(r'(after|before) (.+)\?').firstMatch(stem.data!)!;
  const order = ['Genesis', 'Psalms', 'Matthew'];
  final at = order.indexOf(about.group(2)!);
  return order[about.group(1) == 'after' ? at + 1 : at - 1];
}
