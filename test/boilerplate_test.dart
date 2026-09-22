import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/epub_import.dart';
import 'package:openword/src/data/import_tidy.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/boilerplate.dart';
import 'package:openword/src/model/book_meta.dart';

import 'epub_import_test.dart' show epub;

/// A book whose text is followed by the edition's footer, marked up as
/// plainly as it can be: no links, no classes, nothing to recognise it by.
/// Whatever an edition dresses its furniture in, the rule has to hold.
String _bookWithFooter(String name, String id, int chapter, String text) =>
    '<h1>$name</h1>'
    '<p><b class="chapter-num" id="$id">$chapter:1&#160;</b>$text</p>'
    '<p>ESV</p>'
    '<p>The Old Testament</p>'
    '<p>The New Testament</p>'
    '<p>Show Last Hilite</p>'
    '<p>ESV &#183; The Old Testament</p>'
    '<p>Genesis &#183; Exodus &#183; Leviticus</p>';

Bible _withFooters() {
  final result = EpubImport.convert(
    epub(
      documents: [
        (
          '2pe.xhtml',
          _bookWithFooter('2 Peter', 'v61003001-1', 3, 'But grow in grace.'),
        ),
        (
          '1jn.xhtml',
          _bookWithFooter('1 John', 'v62001001-1', 1, 'That which was.'),
        ),
        (
          '2jn.xhtml',
          _bookWithFooter('2 John', 'v63001001-1', 1, 'The elder unto.'),
        ),
        (
          '3jn.xhtml',
          _bookWithFooter('3 John', 'v64001001-1', 1, 'The elder to Gaius.'),
        ),
      ],
    ),
  );
  expect(result.bible, isNotNull, reason: result.failure ?? '');
  return result.bible!;
}

Book _book(String code, List<List<String>> chapters, {int firstVerse = 1}) =>
    Book(
      meta: BookMeta.lookup(code)!,
      chapters: [
        for (var i = 0; i < chapters.length; i++)
          Chapter(
            number: i + 1,
            notes: const [],
            blocks: [
              for (final line in chapters[i])
                Block(
                  style: BlockStyle.paragraph,
                  segments: [
                    // A line ending in "!" is one that belongs to a verse.
                    VerseSegment(
                      verse: line.endsWith('!') ? firstVerse : 0,
                      startsVerse: line.endsWith('!'),
                      text: line,
                    ),
                  ],
                ),
            ],
          ),
      ],
    );

void main() {
  group('furniture is what repeats around every book', () {
    test('the footer goes, whatever it is marked up as', () {
      final bible = _withFooters();
      final everything = bible.books
          .expand((book) => book.chapters)
          .expand((chapter) => chapter.blocks)
          .expand((block) => block.segments)
          .map((segment) => Markup.strip(segment.text))
          .join('\n');

      for (final line in const [
        'ESV',
        'The Old Testament',
        'The New Testament',
        'Show Last Hilite',
        'Genesis',
      ]) {
        expect(everything, isNot(contains(line)), reason: 'footer: $line');
      }
      // And every book still reads.
      expect(everything, contains('But grow in grace.'));
      expect(everything, contains('The elder to Gaius.'));
    });

    test('and the import says what it dropped', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              '2pe.xhtml',
              _bookWithFooter('2 Peter', 'v61003001-1', 3, 'But grow.'),
            ),
            (
              '1jn.xhtml',
              _bookWithFooter('1 John', 'v62001001-1', 1, 'That which.'),
            ),
            (
              '2jn.xhtml',
              _bookWithFooter('2 John', 'v63001001-1', 1, 'The elder.'),
            ),
          ],
        ),
      );
      expect(result.warnings.join('\n'), contains('repeats around every book'));
      // It names the longest few and counts the rest rather than
      // reprinting the whole footer back at the reader.
      expect(result.warnings.join('\n'), contains('The Old Testament'));
      expect(result.warnings.join('\n'), contains('6 lines'));
    });

    test('text belonging to a verse is never touched', () {
      // "Amen." ends book after book and is Scripture every time. It is
      // safe because it sits inside a verse, which puts it out of reach.
      final swept = stripBoilerplate([
        _book('MAT', [
          ['The book of the generations!', 'Amen.'],
        ]),
        _book('MRK', [
          ['The beginning of the gospel!', 'Amen.'],
        ]),
        _book('LUK', [
          ['Forasmuch as many!', 'Amen.'],
        ]),
      ]);
      // Standing on its own outside a verse, three times over, it goes.
      expect(swept.removed, ['Amen.']);

      final inVerse = stripBoilerplate([
        _book('MAT', [
          ['The generations. Amen.!'],
        ]),
        _book('MRK', [
          ['The gospel. Amen.!'],
        ]),
        _book('LUK', [
          ['Forasmuch as many. Amen.!'],
        ]),
      ]);
      expect(inVerse.removed, isEmpty);
      expect(inVerse.isEmpty, isTrue);
    });

    test('two books are not enough to condemn a line', () {
      // A pair can share a line honestly. Three is where coincidence
      // stops being the likely explanation.
      final two = stripBoilerplate([
        _book('MAT', [
          ['Now to him that is of power', 'The gospel!'],
        ]),
        _book('MRK', [
          ['Now to him that is of power', 'The gospel!'],
        ]),
      ]);
      expect(two.removed, isEmpty);
    });

    test('and repeating inside one book is not repeating across books', () {
      // A psalm's superscription repeats a hundred times over and is
      // Scripture every time; Psalms is one book, and one is not three.
      final psalms = stripBoilerplate([
        _book('PSA', [
          ['A Psalm of David.', 'Blessed is the man!'],
          ['A Psalm of David.', 'Why do the nations rage!'],
          ['A Psalm of David.', 'O LORD, how many are my foes!'],
        ]),
      ]);
      expect(psalms.removed, isEmpty);
    });

    test('a blank is not a line', () {
      // An edition that spaces its furniture out would otherwise have
      // every stanza break in the Bible counted as one thing.
      final spaced = stripBoilerplate([
        for (final code in const ['MAT', 'MRK', 'LUK'])
          Book(
            meta: BookMeta.lookup(code)!,
            chapters: [
              Chapter(
                number: 1,
                notes: const [],
                blocks: const [
                  Block(style: BlockStyle.blank),
                  Block(
                    style: BlockStyle.paragraph,
                    segments: [
                      VerseSegment(verse: 1, startsVerse: true, text: 'Text.'),
                    ],
                  ),
                  Block(style: BlockStyle.blank),
                ],
              ),
            ],
          ),
      ]);
      expect(spaced.removed, isEmpty);
      for (final book in spaced.books) {
        expect(book.chapter(1)!.blocks, hasLength(3));
      }
    });
  });

  group('and a translation already on the shelf can be swept', () {
    // The point of the whole thing: an import is a stored file that app
    // updates never touch, so a fix has to be able to reach one without
    // the EPUB it came from. A file imported today is already clean, so
    // this builds one the way an older import left it — footers and all.
    Bible stale() => Bible(
      translation: const TranslationInfo(
        id: 'stale',
        name: 'An Older Import',
        abbreviation: 'OLD',
        license: 'Unknown',
        sourceUrl: 'https://example.invalid/old',
      ),
      books: [
        for (final (code, text) in const [
          ('2PE', 'But grow in grace!'),
          ('1JN', 'That which was!'),
          ('2JN', 'The elder unto!'),
          ('3JN', 'The elder to Gaius!'),
        ])
          _book(code, [
            [
              text,
              'ESV',
              'The Old Testament',
              'The New Testament',
              'Show Last Hilite',
            ],
          ]),
      ],
    );

    test('the stored .bib is rewritten, text out and Scripture in', () {
      final before = BibFile.encode(stale());
      final tidied = tidyBib(before);

      expect(tidied.failure, isNull);
      expect(tidied.foundSomething, isTrue);
      expect(tidied.removed, contains('Show Last Hilite'));

      final after = BibFile.decode(tidied.bytes!, verify: true);
      final everything = after.books
          .expand((book) => book.chapters)
          .expand((chapter) => chapter.blocks)
          .expand((block) => block.segments)
          .map((segment) => Markup.strip(segment.text))
          .join('\n');
      expect(everything, isNot(contains('Show Last Hilite')));
      expect(everything, contains('But grow in grace'));
      expect(
        after.books.map((book) => book.code),
        BibFile.decode(before).books.map((book) => book.code),
      );
    });

    test('a file with nothing to take out is left alone', () {
      final clean = tidyBib(BibFile.encode(stale()));
      final again = tidyBib(clean.bytes!);
      expect(again.foundSomething, isFalse);
      expect(again.bytes, isNull);
      expect(again.failure, isNull);
    });

    test('and whatever chunks the file carried stay with it', () {
      final carrying = BibFile.encode(
        stale(),
        carry: {
          'zzzz': Uint8List.fromList([1, 2, 3]),
        },
      );
      final tidied = tidyBib(carrying);
      expect(tidied.foundSomething, isTrue);
      expect(BibFile.decode(tidied.bytes!).extras['zzzz'], [1, 2, 3]);
    });

    test('a file that is not a .bib is reported, not thrown', () {
      final result = tidyBib(Uint8List.fromList(List.filled(64, 7)));
      expect(result.failure, isNotNull);
      expect(result.bytes, isNull);
    });
  });
}
