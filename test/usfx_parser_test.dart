import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bible.dart';

import 'fixtures.dart';

void main() {
  final bible = parseFixture();

  test('keeps canonical books and drops front matter', () {
    expect(bible.books.map((book) => book.code), ['GEN', 'PSA', 'MAT']);
  });

  test('drops book titles and introductions', () {
    final chapter = bible.bookByCode('GEN')!.chapter(1)!;
    final text = chapter.blocks
        .expand((block) => block.segments)
        .map((segment) => segment.text)
        .join(' ');
    expect(text, isNot(contains('introduction')));
    expect(text, isNot(contains('Front matter')));
  });

  test('keeps section headings and parallel-passage references apart', () {
    final chapter = bible.bookByCode('GEN')!.chapter(1)!;
    expect(chapter.blocks.map((block) => block.style.key), [
      'h',
      'r',
      'p',
      'p',
    ]);
    expect(chapter.blocks[0].segments.first.text, 'The Creation');
    expect(chapter.blocks[1].segments.first.text, '(John 1:1–5)');
  });

  test('groups verses into paragraphs', () {
    final chapter = bible.bookByCode('GEN')!.chapter(1)!;
    final paragraph = chapter.blocks[2];
    expect(paragraph.style, BlockStyle.paragraph);
    expect(paragraph.segments.length, 2);
    expect(paragraph.segments[0].verse, 1);
    expect(paragraph.segments[0].startsVerse, isTrue);
    expect(paragraph.segments[1].verse, 2);
    expect(chapter.verseCount, 3);
  });

  test('numbers chapters and finds them by number', () {
    final book = bible.bookByCode('GEN')!;
    expect(book.chapterCount, 2);
    expect(book.chapter(2)!.verseText(1), 'The second chapter.');
    expect(book.chapter(3), isNull);
  });

  test('collects footnotes and leaves a marker in the text', () {
    final chapter = bible.bookByCode('GEN')!.chapter(1)!;
    expect(chapter.notes, ['Elohim.']);
    expect(
      chapter.blocks[2].segments.first.text,
      contains('${Markup.noteStart}0${Markup.noteEnd}'),
    );
    expect(chapter.verseText(1), 'In the beginning, God created the heavens.');
  });

  test('marks translator additions', () {
    final text = bible
        .bookByCode('GEN')!
        .chapter(1)!
        .blocks[2]
        .segments[1]
        .text;
    expect(text, contains('${Markup.addStart}formless${Markup.addEnd}'));
    expect(Markup.strip(text), 'The earth was formless and empty.');
  });

  test('keeps poetry structure, psalm titles and headings', () {
    final chapter = bible.bookByCode('PSA')!.chapter(1)!;
    expect(chapter.blocks.map((block) => '${block.style.key}${block.indent}'), [
      'h0',
      'd0',
      'q1',
      'q2',
      'b0',
      'q1',
    ]);
    expect(chapter.blocks[0].segments.first.text, 'BOOK 1');
    expect(chapter.blocks[1].segments.first.text, 'A Psalm by David.');
    // A verse that spans two poetry lines starts on the first one only.
    expect(chapter.blocks[2].segments.first.startsVerse, isTrue);
    expect(chapter.blocks[3].segments.first.verse, 1);
    expect(chapter.blocks[3].segments.first.startsVerse, isFalse);
    expect(chapter.verseCount, 2);
  });

  test('marks Selah', () {
    final text = bible
        .bookByCode('PSA')!
        .chapter(1)!
        .blocks[3]
        .segments
        .first
        .text;
    expect(text, contains('${Markup.selahStart}Selah.${Markup.selahEnd}'));
  });

  test('marks the words of Jesus', () {
    final text = bible
        .bookByCode('MAT')!
        .chapter(1)!
        .blocks
        .first
        .segments
        .first
        .text;
    expect(text, contains('${Markup.wjStart}Follow me.${Markup.wjEnd}'));
    expect(Markup.strip(text), 'He said, Follow me. Then they followed.');
  });

  test('headings and psalm titles are not part of a verse', () {
    // The heading sits before verse 1 and would otherwise be glued to it.
    expect(
      bible.bookByCode('GEN')!.chapter(1)!.verseText(1),
      isNot(contains('The Creation')),
    );
    expect(
      bible.bookByCode('PSA')!.chapter(1)!.verseText(1),
      isNot(contains('A Psalm by David')),
    );
    expect(
      bible.bookByCode('PSA')!.chapter(1)!.verseText(1),
      isNot(contains('BOOK 1')),
    );
  });

  test('joins a verse split across poetry lines', () {
    expect(
      bible.bookByCode('PSA')!.chapter(1)!.verseText(1),
      'Blessed is the man who does not walk in the counsel of the '
      'wicked. Selah.',
    );
  });
}
