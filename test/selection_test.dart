import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/verse_selection.dart';
import 'package:openword/src/ui/theme.dart';
import 'package:openword/src/ui/verse_share.dart';
import 'package:share_plus/share_plus.dart';

import 'fixtures.dart';
import 'reader_screen_test.dart' show pumpReader;

Finder verse(String words) => find.textContaining(words, findRichText: true);

// Genesis 1 in the fixture: verses 3, 4 and 5 are paragraphs of their own.
final three = verse('Let there be light');
final four = verse('A paragraph set flush');
final five = verse('An indented paragraph');

void main() {
  group('citing a selection', () {
    test('runs collapse and gaps are kept', () {
      expect(VerseSelection.ranges([16]), '16');
      expect(VerseSelection.ranges([18, 16, 17]), '16–18');
      expect(VerseSelection.ranges([16, 17, 18, 20]), '16–18, 20');
      expect(VerseSelection.ranges([1, 3, 5, 6]), '1, 3, 5–6');
    });

    test('names the book and chapter', () {
      expect(
        VerseSelection.citation(const Reference('JHN', 3), [16, 17]),
        'John 3:16–17',
      );
    });

    test('quotes the words, with an ellipsis for what is skipped', () {
      final chapter = parseFixture().bookByCode('GEN')!.chapter(1)!;
      expect(
        VerseSelection.text(chapter, [3, 5]),
        '${chapter.verseText(3)} … ${chapter.verseText(5)}',
      );
      expect(
        VerseSelection.text(chapter, [4, 3]),
        '${chapter.verseText(3)} ${chapter.verseText(4)}',
      );
      final quotation = VerseSelection.quotation(
        chapter: chapter,
        reference: const Reference('GEN', 1),
        verses: [3, 4],
        translation: 'TST',
      );
      expect(quotation, endsWith('\n\n— Genesis 1:3–4 (TST)'));
    });
  });

  group('selecting in the reader', () {
    final shared = <ShareParams>[];
    String? clipboard;

    setUp(() {
      shared.clear();
      clipboard = null;
      VerseSharing.share = (params) async => shared.add(params);
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('holding a verse starts a selection; taps add and remove', (
      tester,
    ) async {
      await pumpReader(tester);
      await tester.longPress(three);
      await tester.pumpAndSettle();
      expect(find.text('Genesis 1:3'), findsOneWidget);
      expect(find.text('1 verse · tap more to add'), findsOneWidget);

      // While selecting, a tap adds rather than opening the verse.
      await tester.tap(four);
      await tester.pumpAndSettle();
      expect(find.text('Genesis 1:3–4'), findsOneWidget);
      expect(find.text('2 verses'), findsOneWidget);
      expect(find.text('Select more'), findsNothing);

      await tester.tap(four);
      await tester.tap(five);
      await tester.pumpAndSettle();
      expect(find.text('Genesis 1:3, 5'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Copy'), findsNothing);
    });

    testWidgets('a tap with nothing selected still opens the verse', (
      tester,
    ) async {
      await pumpReader(tester);
      await tester.tap(three);
      await tester.pumpAndSettle();
      expect(find.text('Select more'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Image'), findsOneWidget);

      await tester.tap(find.text('Select more'));
      await tester.pumpAndSettle();
      expect(find.text('Genesis 1:3'), findsOneWidget);
      expect(find.byTooltip('Share as an image'), findsOneWidget);
    });

    testWidgets('copies the words with the citation', (tester) async {
      await pumpReader(tester);
      await tester.longPress(three);
      await tester.pumpAndSettle();
      await tester.tap(four);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Copy'));
      await tester.pumpAndSettle();

      expect(clipboard, contains('Let there be light'));
      expect(clipboard, contains('A paragraph set flush'));
      expect(clipboard, endsWith('— Genesis 1:3–4 (TST)'));
      expect(find.text('Copied Genesis 1:3–4'), findsOneWidget);
      // Done with, so the selection is gone.
      expect(find.byTooltip('Copy'), findsNothing);
    });

    testWidgets('shares the words through the share sheet', (tester) async {
      await pumpReader(tester);
      await tester.longPress(three);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(shared, hasLength(1));
      expect(shared.single.text, endsWith('— Genesis 1:3 (TST)'));
      expect(shared.single.subject, 'Genesis 1:3');
    });

    testWidgets('one tap shares a single verse from its own sheet', (
      tester,
    ) async {
      await pumpReader(tester);
      await tester.tap(three);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shared.single.text, contains('Let there be light'));
    });

    testWidgets('highlights every verse selected at once', (tester) async {
      final harness = await pumpReader(tester);
      await tester.longPress(three);
      await tester.pumpAndSettle();
      await tester.tap(five);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Highlight'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Highlight ${AppTheme.highlightNames.first}'),
      );
      await tester.pumpAndSettle();
      final highlights = harness.reading.highlightsIn('GEN', 1);
      expect(highlights.keys.toSet(), {3, 5});
    });

    testWidgets('turning the page ends the selection', (tester) async {
      await pumpReader(tester);
      await tester.longPress(three);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Copy'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Copy'), findsNothing);
    });

    testWidgets('escape ends it too', (tester) async {
      await pumpReader(tester);
      await tester.longPress(three);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Copy'), findsNothing);
    });

    testWidgets('shares a picture of the passage', (tester) async {
      await pumpReader(tester);
      await tester.longPress(three);
      await tester.pumpAndSettle();
      await tester.tap(four);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share as an image'));
      await tester.pumpAndSettle();

      expect(find.text('Share Genesis 1:3–4 as an image'), findsOneWidget);
      final card = tester.widget<VerseCard>(find.byType(VerseCard));
      expect(card.citation, 'Genesis 1:3–4');
      expect(card.text, contains('Let there be light'));
      expect(card.translation, testTranslation.name);

      await tester.tap(find.text('Night'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<VerseCard>(find.byType(VerseCard)).style,
        CardStyle.night,
      );

      // Rendering the image to PNG happens off the test's fake clock.
      await tester.runAsync(() async {
        await tester.tap(find.text('Share image'));
        for (var i = 0; i < 50 && shared.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      expect(shared, hasLength(1));
      final file = shared.single.files!.single;
      final Uint8List bytes =
          await tester.runAsync(file.readAsBytes) ?? Uint8List(0);
      // A PNG, at three times the card's size.
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final width = ByteData.sublistView(bytes, 16, 20).getUint32(0);
      final height = ByteData.sublistView(bytes, 20, 24).getUint32(0);
      expect((width, height), (1080, 1350));
      expect(shared.single.fileNameOverrides, ['Genesis_1-3–4.png']);
      expect(find.byType(VerseImageSheet), findsNothing);
    });
  });

  testWidgets('a whole long chapter still fits on the card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: VerseCard(
            text: 'Blessed are those whose way is blameless. ' * 60,
            citation: 'Psalm 119:1–40',
            translation: 'Berean Standard Bible',
            style: CardStyle.dawn,
          ),
        ),
      ),
    );
    // An overflow would have been reported as an exception.
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(VerseCard)), VerseCard.size);
  });

  test('longer passages are set smaller on a card', () {
    expect(
      VerseCard.fontSizeFor('short'),
      greaterThan(VerseCard.fontSizeFor('x' * 500)),
    );
  });
}
