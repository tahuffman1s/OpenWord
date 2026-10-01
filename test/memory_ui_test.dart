import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/read_aloud.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/memory_exercise.dart';
import 'package:openword/src/ui/memory_screen.dart';

import 'read_aloud_test.dart' show FakeSpeech;
import 'reader_screen_test.dart' show appBarText, pumpReader, verseNumber;

Finder libraryButton() =>
    find.byTooltip('Bookmarks, highlights, notes and learning');

/// Scrolls the Learn tab until [finder] is on screen: the memory verses
/// sit under the rounds to test yourself with.
Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  bool up = false,
}) async {
  await tester.dragUntilVisible(
    finder,
    find
        .descendant(
          of: find.byType(TabBarView),
          matching: find.byType(ListView),
        )
        .first,
    Offset(0, up ? 150 : -150),
  );
  await tester.pumpAndSettle();
}

/// Opens the library on Learn and practises [verse].
Future<void> openPractice(WidgetTester tester, Reference verse) async {
  await tester.tap(libraryButton());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Learn'));
  await tester.pumpAndSettle();
  await reveal(tester, find.text(verse.label));
  await tester.tap(find.text(verse.label));
  await tester.pumpAndSettle();
  expect(find.byType(MemoryScreen), findsOneWidget);
}

/// Taps a bank tile reading [text] that is not yet used.
Future<void> tapTile(WidgetTester tester, String text) async {
  final bank = find.byKey(const Key('bank'));
  final tiles = find.descendant(of: bank, matching: find.text(text));
  for (final element in tiles.evaluate()) {
    final opacity = element.findAncestorWidgetOfExactType<Opacity>();
    if (opacity != null && opacity.opacity < 1) continue;
    await tester.tap(find.byElementPredicate((e) => e == element));
    await tester.pumpAndSettle();
    return;
  }
  throw StateError('no unused tile reads "$text"');
}

/// Puts the tiles of [text] in its order.
Future<void> arrange(WidgetTester tester, String text) async {
  for (final tile in VerseTiles.of(text)) {
    await tapTile(tester, tile);
  }
}

const verse = Reference('GEN', 1, 3);
const text = 'God said, "Let there be light."';

void main() {
  final original = createSpeechEngine;
  setUp(() => createSpeechEngine = () => FakeSpeech(available: false));
  tearDown(() => createSpeechEngine = original);

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
    // library opens on Learn.
    final badge = tester.widget<Badge>(
      find.descendant(of: libraryButton(), matching: find.byType(Badge)),
    );
    expect(badge.isLabelVisible, isTrue);

    await tester.tap(find.text('Memorising'));
    await tester.pumpAndSettle();
    expect(harness.reading.isMemorising(verse), isFalse);
    await tester.tap(find.text('Memorise'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(libraryButton());
    await tester.pumpAndSettle();
    expect(
      find.text('Practise on two days running to start a streak.'),
      findsOneWidget,
    );
    await reveal(tester, find.text('Due today'));
    expect(find.text('1 verse due today'), findsOneWidget);
    expect(find.text('Genesis 1:3'), findsOneWidget);
  });

  testWidgets('a new verse is put together from tiles, and climbs', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    await openPractice(tester, verse);

    expect(find.text('Put it together'), findsOneWidget);
    expect(find.text(text), findsOneWidget);
    expect(find.textContaining('New · not yet recalled'), findsOneWidget);
    // No voice on this device: nothing offers to speak.
    expect(find.byTooltip('Hear the verse'), findsNothing);
    // Nothing to check until every tile is placed.
    final check = find.widgetWithText(FilledButton, 'Check');
    expect(tester.widget<FilledButton>(check).onPressed, isNull);

    // A tile placed can be taken back.
    await tapTile(tester, 'light."');
    expect(
      find.descendant(
        of: find.byKey(const Key('answer')),
        matching: find.text('light."'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('answer')),
        matching: find.text('light."'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('answer')),
        matching: find.text('light."'),
      ),
      findsNothing,
    );

    await arrange(tester, text);
    expect(tester.widget<FilledButton>(check).onPressed, isNotNull);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.text('Nicely done.'), findsOneWidget);
    expect(find.text('Asked again tomorrow.'), findsOneWidget);
    expect(harness.reading.memoryFor(verse)!.rung, 1);
    expect(harness.reading.streak.count, 1);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('That’s the verse for today'), findsOneWidget);
    expect(find.text('Next up: Genesis 1:3, tomorrow.'), findsOneWidget);
    expect(find.text('1-day streak'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Practised today.'), up: true);
    expect(find.text('1-day streak'), findsOneWidget);
  });

  testWidgets('a wrong order drops the verse and asks it again', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    harness.reading.reviewMemory(verse, remembered: true);
    harness.reading.reviewMemory(verse, remembered: true);
    harness.reading.reviewMemory(verse, remembered: true);
    expect(harness.reading.memoryFor(verse)!.rung, 3);
    await openPractice(tester, verse);

    // Rung 3: from memory, the text unseen until a hint is asked for.
    expect(find.text('From memory'), findsOneWidget);
    expect(find.text(text), findsNothing);
    await tester.tap(find.text('Hint'));
    await tester.pumpAndSettle();
    expect(find.text('G__ s___, "L__ t____ b_ l____."'), findsOneWidget);

    for (final tile in VerseTiles.of(text).reversed) {
      await tapTile(tester, tile);
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('Not quite.'), findsOneWidget);
    expect(find.text(text), findsOneWidget);
    expect(harness.reading.memoryFor(verse)!.rung, 0);

    // Asked again, now as a new verse: with the text to copy.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Put it together'), findsOneWidget);
    await arrange(tester, text);
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('Nicely done.'), findsOneWidget);
    expect(harness.reading.memoryFor(verse)!.rung, 1);
  });

  testWidgets('the blanks are filled from the bank', (tester) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    harness.reading.reviewMemory(verse, remembered: true);
    await openPractice(tester, verse);
    expect(find.text('Fill the blanks'), findsOneWidget);

    // The blanks say which words are wanted.
    final words = text.split(' ');
    final blanks =
        tester
            .widgetList(
              find.byWidgetPredicate((w) {
                final key = w.key;
                return key is ValueKey<String> &&
                    key.value.startsWith('blank/');
              }),
            )
            .map(
              (w) => int.parse((w.key! as ValueKey<String>).value.substring(6)),
            )
            .toList()
          ..sort();
    expect(blanks, hasLength(1));
    final wanted = VerseWord.parse(words[blanks.single]).core;

    // The wrong word first, taken back, then the right one.
    final bank = find.byKey(const Key('bank'));
    final wrong = tester
        .widgetList<Text>(
          find.descendant(of: bank, matching: find.byType(Text)),
        )
        .map((t) => t.data!)
        .firstWhere((w) => w != wanted);
    await tapTile(tester, wrong);
    await tester.tap(find.byKey(ValueKey('blank/${blanks.single}')));
    await tester.pumpAndSettle();
    await tapTile(tester, wanted);
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('Nicely done.'), findsOneWidget);
    expect(harness.reading.memoryFor(verse)!.rung, 2);
  });

  testWidgets('written out, slips forgiven; or shown, and dropped', (
    tester,
  ) async {
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    for (var i = 0; i < 4; i++) {
      harness.reading.reviewMemory(verse, remembered: true);
    }
    await openPractice(tester, verse);
    expect(find.text('Write it out'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('typed')),
      'god said let there be ligth',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('Nicely done.'), findsOneWidget);
    expect(find.text('Asked again in 30 days.'), findsOneWidget);
    expect(harness.reading.memoryFor(verse)!.rung, 5);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Back for another go, by hand: rung 5 with no voice is from memory.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text(verse.label));
    await tester.tap(find.text(verse.label));
    await tester.pumpAndSettle();
    expect(find.text('From memory'), findsOneWidget);
    await tester.tap(find.text('Show me'));
    await tester.pumpAndSettle();
    expect(find.text('Here it is.'), findsOneWidget);
    expect(find.text(text), findsOneWidget);
    expect(harness.reading.memoryFor(verse)!.rung, 0);
  });

  testWidgets('with a voice, the verse is heard and can be replayed', (
    tester,
  ) async {
    final speech = FakeSpeech(pauses: true);
    createSpeechEngine = () => speech;
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    harness.reading.reviewMemory(verse, remembered: true);
    harness.reading.reviewMemory(verse, remembered: true);
    await openPractice(tester, verse);

    // Rung 2: tap what you hear, and it is said at once.
    expect(find.text('Tap what you hear'), findsOneWidget);
    expect(find.text(text), findsNothing);
    expect(speech.said, hasLength(1));
    expect(speech.said.single, contains('Let there be light'));
    expect(find.byTooltip('Stop'), findsOneWidget);
    speech.finish();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hear the verse'), findsOneWidget);

    await tester.tap(find.byTooltip('Hear the verse'));
    await tester.pumpAndSettle();
    expect(speech.said, hasLength(2));
    speech.finish();
    await tester.pumpAndSettle();

    // Slowly: the same words at a slower pace.
    await tester.tap(find.byTooltip('Hear it slowly'));
    await tester.pumpAndSettle();
    expect(speech.said, hasLength(3));
    expect(speech.rates.last, lessThan(speech.rates.first));
    speech.finish();
    await tester.pumpAndSettle();

    // Each tile tapped is heard, then the verse whole once checked.
    final tiles = VerseTiles.of(text);
    await arrange(tester, text);
    expect(speech.said.sublist(3), tiles);
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(find.text('Nicely done.'), findsOneWidget);
    expect(speech.said.last, contains('Let there be light'));
    expect(harness.reading.memoryFor(verse)!.rung, 3);
  });

  testWidgets('a shown verse is read as it opens, unless reading is off', (
    tester,
  ) async {
    final speech = FakeSpeech(pauses: true);
    createSpeechEngine = () => speech;
    final harness = await pumpReader(tester);
    harness.reading.toggleMemorise(verse);
    await openPractice(tester, verse);
    expect(find.text('Put it together'), findsOneWidget);
    expect(speech.said, hasLength(1));
    expect(speech.said.single, contains('Let there be light'));
    speech.finish();
    await tester.pumpAndSettle();

    // Switched off: tiles and the verse go unspoken, the button still works.
    await tester.tap(find.byTooltip('Reading aloud: on'));
    await tester.pumpAndSettle();
    expect(harness.settings.learnAutoSpeak, isFalse);
    expect(find.byTooltip('Reading aloud: off'), findsOneWidget);
    await arrange(tester, text);
    expect(speech.said, hasLength(1));
    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();
    expect(speech.said, hasLength(1));
    await tester.tap(find.byTooltip('Hear the verse'));
    await tester.pumpAndSettle();
    expect(speech.said, hasLength(2));
    speech.finish();
    await tester.pumpAndSettle();

    // Back on: the next verse is read as it opens, in the Settings too.
    await tester.tap(find.byTooltip('Reading aloud: off'));
    await tester.pumpAndSettle();
    expect(harness.settings.learnAutoSpeak, isTrue);
  });

  testWidgets('a verse can be opened in the reader from a session', (
    tester,
  ) async {
    final harness = await pumpReader(tester, resume: const Reference('PSA', 1));
    harness.reading.toggleMemorise(verse);
    await openPractice(tester, verse);
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
