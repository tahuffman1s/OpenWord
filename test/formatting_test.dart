import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/epub_import.dart';
import 'package:openword/src/data/usfx_parser.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/book_meta.dart';

import 'package:flutter/material.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/ui/widgets/scripture_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'epub_import_test.dart' show epub;
import 'fixtures.dart';

/// USFX exercising everything the format learned to carry.
const String richUsfx = '''
<?xml version="1.0" encoding="UTF-8"?>
<usfx><book id="PSA"><h>Psalms</h>
<ms>BOOK 1</ms>
<c id="1"/><cl>Psalm 1</cl>
<s>A Tree by the Water</s>
<s level="2">The first stanza</s>
<qa>ALEPH</qa>
<sp>The Beloved</sp>
<q level="1"><v id="1"/>Blessed is the man who fears <nd>Yahweh</nd>.</q>
<qc><v id="2"/>A centred line of praise.</qc>
<qr><v id="3"/>Set to the right.</qr>
<p><v id="4"/>As it is written, <qt>the stone the builders rejected</qt>,
so <add>indeed</add> it was.</p>
<p><v id="5"/><vp>5-6</vp>Two verses printed as one.</p>
<v id="7"/><ve/>
<li level="1"><v id="8"/>One item of a list.</li>
<li level="2"><v id="9"/>Another, further in.</li>
<tr><v id="10"/><tc>Judah</tc><tc>seventy</tc></tr>
<tr><tc>Benjamin</tc><tc>twelve</tc></tr>
<nb><v id="11"/>Carried on from before the break.</nb>
</book></usfx>
''';

void main() {
  late Settings settings;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    settings = await Settings.load();
  });

  final bible = UsfxParser.parse(richUsfx, testTranslation);
  final chapter = bible.bookByCode('PSA')!.chapter(1)!;
  List<Block> styled(BlockStyle style) =>
      chapter.blocks.where((block) => block.style == style).toList();

  group('the divine name', () {
    test('is carried as its own marker, not as italics', () {
      final line = chapter.blocks.firstWhere(
        (block) => block.segments.any((s) => s.verse == 1),
      );
      final text = line.segments.first.text;

      expect(text, contains(Markup.divineStart));
      expect(text, contains(Markup.divineEnd));
      expect(
        text,
        isNot(contains(Markup.addStart)),
        reason: 'the divine name is not a translator\'s addition',
      );
    });

    test('and the markers never reach the reader', () {
      expect(chapter.verseText(1), 'Blessed is the man who fears Yahweh.');
    });
  });

  group('a quotation from Scripture', () {
    test('is no longer stored as a translator\'s addition', () {
      final text = chapter.blocks
          .firstWhere((block) => block.segments.any((s) => s.verse == 4))
          .segments
          .map((s) => s.text)
          .join();

      expect(text, contains(Markup.quotationStart));
      // \add is still italics, and is still there for the word that is one.
      expect(text, contains(Markup.addStart));
      expect(
        text.indexOf(Markup.quotationStart),
        lessThan(text.indexOf(Markup.addStart)),
      );
    });
  });

  group('headings', () {
    test('a division of the book outranks the sections under it', () {
      final headings = styled(BlockStyle.heading);

      expect(headings.map((h) => h.level), [1, 2, 3]);
      expect(headings.first.segments.first.text, 'BOOK 1');
      // Alignment in the file says what the source said; a book division
      // is centred by the reader whatever the source claims.
    });

    test('an acrostic letter is its own style', () {
      expect(styled(BlockStyle.acrostic).single.segments.first.text, 'ALEPH');
    });

    test('a speaker is its own style', () {
      expect(
        styled(BlockStyle.speaker).single.segments.first.text,
        'The Beloved',
      );
    });

    test('the chapter knows what it is called', () {
      expect(chapter.label, 'Psalm 1');
    });
  });

  group('alignment', () {
    test('centred and right-set lines keep their alignment', () {
      final centred = chapter.blocks.firstWhere(
        (block) => block.segments.any((s) => s.verse == 2),
      );
      final right = chapter.blocks.firstWhere(
        (block) => block.segments.any((s) => s.verse == 3),
      );

      expect(centred.align, BlockAlign.center);
      expect(right.align, BlockAlign.end);
    });

    test('and an ordinary line does not claim any', () {
      expect(
        chapter.blocks
            .firstWhere((block) => block.segments.any((s) => s.verse == 4))
            .align,
        BlockAlign.start,
      );
    });
  });

  test('a paragraph carried across a chapter break says so', () {
    expect(
      chapter.blocks
          .firstWhere((block) => block.segments.any((s) => s.verse == 11))
          .continuesParagraph,
      isTrue,
    );
  });

  group('lists and tables', () {
    test('a list item is a list item, at its level', () {
      final items = styled(BlockStyle.listItem);

      expect(items, hasLength(2));
      expect(items.map((item) => item.indent), [1, 2]);
    });

    test('a table row keeps its cells apart', () {
      final rows = styled(BlockStyle.tableRow);

      expect(rows, hasLength(2));
      expect(rows.first.cells, ['Judah', 'seventy']);
      expect(rows.last.cells, ['Benjamin', 'twelve']);
    });

    test('and the separator reads as a space, not as nothing', () {
      // Both rows belong to verse 10: only the first carries a verse
      // marker, so the second continues it, as a table in print does.
      final text = chapter.verseText(10);

      expect(text, isNot(contains(Markup.cell)));
      expect(text, 'Judah seventy Benjamin twelve');
      expect(
        text,
        isNot(contains('Judahseventy')),
        reason: 'dropping the boundary would run two words together',
      );
    });
  });

  group('verses', () {
    test('a printed number can differ from the stored one', () {
      expect(chapter.labelFor(5), '5-6');
      expect(chapter.labelFor(4), '4');
    });

    test('a verse left out on purpose is recorded as such', () {
      // Numbered, and with no text: Matthew 17:21 and the rest.
      expect(chapter.isOmitted(7), isTrue);
      expect(chapter.isOmitted(4), isFalse);
      expect(chapter.verseText(7), isEmpty);
    });
  });

  group('all of it survives a .bib file', () {
    late Chapter reread;

    setUpAll(() {
      reread = BibFile.decode(BibFile.encode(bible))
          .bookByCode('PSA')!
          .chapter(1)!;
    });

    test('the block attributes', () {
      for (var i = 0; i < chapter.blocks.length; i++) {
        final before = chapter.blocks[i];
        final after = reread.blocks[i];
        expect(after.style, before.style, reason: 'block $i style');
        expect(after.level, before.level, reason: 'block $i level');
        expect(after.align, before.align, reason: 'block $i align');
        expect(after.indent, before.indent, reason: 'block $i indent');
        expect(
          after.continuesParagraph,
          before.continuesParagraph,
          reason: 'block $i no-break',
        );
        expect(
          after.segments.map((s) => s.text),
          before.segments.map((s) => s.text),
          reason: 'block $i text',
        );
      }
    });

    test('the chapter label, the verse labels and the omissions', () {
      expect(reread.label, 'Psalm 1');
      expect(reread.labelFor(5), '5-6');
      expect(reread.omitted, chapter.omitted);
      expect(reread.isOmitted(7), isTrue);
    });

    test('and the cells of a table', () {
      expect(
        reread.blocks
            .firstWhere((block) => block.style == BlockStyle.tableRow)
            .cells,
        ['Judah', 'seventy'],
      );
    });
  });

  test('every reserved control character is stripped, not only the used', () {
    // A marker added after a reader was written must be dropped rather
    // than printed into the middle of a verse.
    const withUnknown = 'In the \u001ebeginning\u001f, God.';
    expect(Markup.strip(withUnknown), 'In the beginning, God.');
  });

  group('an EPUB brings what it can express', () {
    late Chapter imported;

    setUpAll(() {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2>'
                  '<h3 class="s1">The Creation</h3>'
                  '<p><sup>1</sup>In the beginning '
                  '<span class="nd">Lord</span> created.</p>'
                  '<p class="s2">A lesser heading</p>'
                  '<p><sup>2</sup>And the '
                  '<span style="font-variant: small-caps">Lord</span> '
                  'said so.</p>'
                  '<p class="sp">The Beloved</p>'
                  '<p class="qa">ALEPH</p>',
            ),
          ],
        ),
        fileName: 'formatted.epub',
      );
      expect(result.bible, isNotNull, reason: result.failure ?? '');
      imported = result.bible!.bookByCode('GEN')!.chapter(1)!;
    });

    test('the divine name from a class', () {
      expect(
        imported.blocks
            .expand((block) => block.segments)
            .where((segment) => segment.verse == 1)
            .map((segment) => segment.text)
            .join(),
        contains(Markup.divineStart),
      );
      expect(imported.verseText(1), 'In the beginning Lord created.');
    });

    test('and from a small-caps style attribute', () {
      expect(
        imported.blocks
            .expand((block) => block.segments)
            .where((segment) => segment.verse == 2)
            .map((segment) => segment.text)
            .join(),
        contains(Markup.divineStart),
      );
    });

    test('heading levels', () {
      final headings = imported.blocks
          .where((block) => block.style == BlockStyle.heading)
          .toList();

      expect(headings.map((h) => h.segments.first.text), [
        'The Creation',
        'A lesser heading',
      ]);
      expect(headings.map((h) => h.level), [2, 3]);
    });

    test('speakers and acrostic letters', () {
      expect(
        imported.blocks
            .where((block) => block.style == BlockStyle.speaker)
            .map((block) => block.segments.first.text),
        ['The Beloved'],
      );
      expect(
        imported.blocks
            .where((block) => block.style == BlockStyle.acrostic)
            .map((block) => block.segments.first.text),
        ['ALEPH'],
      );
    });
  });

  group('the reader draws what the file says', () {
    /// The rich text of a block, as opposed to the plain Text holding its
    /// verse number.
    Text richText(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((text) => text.textSpan != null);

    Future<void> pumpBlock(WidgetTester tester, Block block) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ScriptureBlock(
                block: block,
                style: ScriptureStyle.of(context, settings),
                onVerseTap: (_) {},
                onNoteTap: (_) {},
                highlights: const {},
                flagged: const {},
                isFirst: true,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a centred line is centred and a right-set one is not', (
      tester,
    ) async {
      // This went wrong once already: inside a Stack the line was given
      // only the room it needed, and centring within its own width does
      // nothing at all.
      for (final pair in const [
        (BlockAlign.center, TextAlign.center),
        (BlockAlign.end, TextAlign.end),
        (BlockAlign.start, TextAlign.start),
      ]) {
        await pumpBlock(
          tester,
          Block(
            style: BlockStyle.poetry,
            indent: 1,
            align: pair.$1,
            segments: const [
              VerseSegment(verse: 1, startsVerse: true, text: 'A line.'),
            ],
          ),
        );

        expect(richText(tester).textAlign, pair.$2, reason: '${pair.$1}');
      }
    });

    testWidgets('a table row keeps its number gutter on every row', (
      tester,
    ) async {
      // Without it the second row's columns would not sit under the
      // first's.
      await pumpBlock(
        tester,
        const Block(
          style: BlockStyle.tableRow,
          segments: [
            VerseSegment(
              verse: 0,
              startsVerse: false,
              text: 'Benjamin\u001dtwelve',
            ),
          ],
        ),
      );

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('Benjamin'), findsOneWidget);
      expect(find.text('twelve'), findsOneWidget);
    });

    testWidgets('the divine name is drawn smaller and upper-cased', (
      tester,
    ) async {
      await pumpBlock(
        tester,
        Block(
          style: BlockStyle.paragraph,
          segments: [
            VerseSegment(
              verse: 1,
              startsVerse: true,
              text: 'I am ${Markup.divineStart}Lord${Markup.divineEnd}.',
            ),
          ],
        ),
      );

      final rich = richText(tester);
      final runs = <String>[];
      double? small;
      double? normal;
      rich.textSpan!.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').isNotEmpty) {
          runs.add(span.text!);
          if (span.text == 'LORD') {
            small = span.style?.fontSize;
          } else if (span.text!.startsWith('I am')) {
            normal = span.style?.fontSize;
          }
        }
        return true;
      });

      expect(runs, contains('LORD'));
      expect(small, isNotNull);
      expect(normal, isNotNull);
      expect(small, lessThan(normal!));
    });
  });

  group('an EPUB brings all of it, not only some', () {
    late Chapter imported;

    setUpAll(() {
      // An edition marking everything it can: the divine name, quotations,
      // heading depth, alignment, a bridged verse, a verse it leaves out,
      // a nested list and a table.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'num.xhtml',
              '<h1>Numbers</h1><h2>1</h2>'
                  '<p class="ms">BOOK ONE</p>'
                  '<h3 class="s1">The Census</h3>'
                  '<p><sup>1</sup>And the '
                  '<span class="nd">Lord</span> spoke.</p>'
                  '<p style="text-align: center"><sup>2</sup>'
                  'A centred line.</p>'
                  '<p class="qr"><sup>3</sup>Set to the right.</p>'
                  '<p><sup>4</sup>As it says, <q>a chosen stone</q>, '
                  'and <i>indeed</i> so.</p>'
                  '<p><sup>5-6</sup>Two printed as one.</p>'
                  '<p><sup>7</sup></p>'
                  '<ol><li><sup>8</sup>The sons of Judah;</li>'
                  '<ol><li><sup>9</sup>and of Benjamin.</li></ol></ol>'
                  '<table><tr><td><sup>10</sup>Judah</td>'
                  '<td>seventy and four</td></tr>'
                  '<tr><td>Benjamin</td><td>twelve</td></tr></table>',
            ),
          ],
        ),
        fileName: 'everything.epub',
      );
      expect(result.bible, isNotNull, reason: result.failure ?? '');
      imported = result.bible!.bookByCode('NUM')!.chapter(1)!;
    });

    Block blockFor(int verse) => imported.blocks.firstWhere(
      (block) => block.segments.any((segment) => segment.verse == verse),
    );

    test('the divine name', () {
      expect(
        blockFor(1).segments.map((s) => s.text).join(),
        contains(Markup.divineStart),
      );
      expect(imported.verseText(1), 'And the Lord spoke.');
    });

    test('a quotation, apart from the italics beside it', () {
      final text = blockFor(4).segments.map((s) => s.text).join();

      expect(text, contains(Markup.quotationStart));
      expect(text, contains(Markup.addStart));
      expect(
        imported.verseText(4),
        'As it says, a chosen stone, and indeed so.',
      );
    });

    test('alignment, from a style attribute and from a class', () {
      expect(blockFor(2).align, BlockAlign.center);
      expect(blockFor(3).align, BlockAlign.end);
      expect(blockFor(1).align, BlockAlign.start);
    });

    test('heading depth', () {
      final headings = imported.blocks
          .where((block) => block.style == BlockStyle.heading)
          .toList();

      expect(headings.map((h) => h.segments.first.text), [
        'BOOK ONE',
        'The Census',
      ]);
      expect(headings.map((h) => h.level), [1, 2]);
    });

    test('a bridged verse keeps the number it is printed as', () {
      expect(imported.labelFor(5), '5-6');
      expect(imported.labelFor(4), '4');
    });

    test('a verse numbered and left empty is recorded as left out', () {
      expect(imported.isOmitted(7), isTrue);
      expect(imported.isOmitted(4), isFalse);
    });

    test('a nested list, at its depths', () {
      final items = imported.blocks
          .where((block) => block.style == BlockStyle.listItem)
          .toList();

      expect(items, hasLength(2));
      expect(items.map((item) => item.segments.first.verse), [8, 9]);
      expect(items.first.indent, lessThan(items.last.indent));
    });

    test('a table, as rows of cells rather than a paragraph each', () {
      final rows = imported.blocks
          .where((block) => block.style == BlockStyle.tableRow)
          .toList();

      expect(rows, hasLength(2));
      expect(rows.first.cells, ['Judah', 'seventy and four']);
      expect(rows.last.cells, ['Benjamin', 'twelve']);
    });

    test('and every bit of it survives the .bib the import writes', () {
      final written = BibFile.decode(
        BibFile.encode(
          Bible(
            translation: testTranslation,
            books: [
              Book(meta: BookMeta.lookup('NUM')!, chapters: [imported]),
            ],
          ),
        ),
      ).bookByCode('NUM')!.chapter(1)!;

      expect(written.labelFor(5), '5-6');
      expect(written.isOmitted(7), isTrue);
      expect(
        written.blocks.firstWhere((b) => b.style == BlockStyle.tableRow).cells,
        ['Judah', 'seventy and four'],
      );
      expect(
        written.blocks
            .where((b) => b.style == BlockStyle.heading)
            .map((b) => b.level),
        [1, 2],
      );
      for (var i = 0; i < imported.blocks.length; i++) {
        expect(
          written.blocks[i].align,
          imported.blocks[i].align,
          reason: 'block $i alignment',
        );
      }
    });
  });
}
