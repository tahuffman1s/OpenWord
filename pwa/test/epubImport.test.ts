import { strToU8 } from 'fflate';
import { beforeAll, describe, expect, it } from 'vitest';
import { EpubImport } from '../src/data/epubImport';
import { type Bible, type Block, BlockStyle, type Chapter, Markup } from '../src/model/bible';
import { epub, epubWithToc } from './epubFixtures';

/** Dart's `.single`: the one element, and a failure where there is not exactly one. */
function single<T>(items: readonly T[]): T {
  expect(items).toHaveLength(1);
  return items[0];
}

describe('the shapes a Bible EPUB comes in', () => {
  it('numbered spans, the usual output of publishing tools', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1>' +
              '<h2>Chapter 1</h2>' +
              '<p><span class="verse" id="V1">1</span>In the beginning God ' +
              'created the heavens and the earth. ' +
              '<span class="verse" id="V2">2</span>The earth was formless.</p>' +
              '<h2>Chapter 2</h2>' +
              '<p><span class="verse">1</span>Thus the heavens were finished.</p>',
          ],
        ],
      }),
    );

    expect(result.failure).toBeNull();
    const bible = result.bible!;
    const book = single(bible.books);
    expect(book.code).toBe('GEN');
    expect(book.chapterCount).toBe(2);

    const first = book.chapter(1)!;
    expect(first.verseCount).toBe(2);
    expect(first.verseText(1).startsWith('In the beginning')).toBe(true);
    expect(first.verseText(2)).toBe('The earth was formless.');
    expect(book.chapter(2)!.verseText(1)).toContain('finished');
  });

  it('superscript numbers', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'john.xhtml',
            '<h1>The Gospel According to John</h1><h2>3</h2><p><sup>16</sup>For God so loved the world.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.code).toBe('JHN');
    // The chapter is numbered from the heading, and the verse from the
    // superscript.
    expect(single(book.chapters).verseText(16)).toBe('For God so loved the world.');
  });

  it('a number at the head of each paragraph', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'ruth.xhtml',
            '<h1>Ruth</h1><h2>Chapter 1</h2>' +
              '<p>1 Now it came to pass in the days.</p>' +
              '<p>2 And the name of the man was Elimelech.</p>',
          ],
        ],
      }),
    );

    const chapter = single(single(result.bible!.books).chapters);
    expect(chapter.verseCount).toBe(2);
    expect(chapter.verseText(2)).toBe('And the name of the man was Elimelech.');
  });

  it('chapter and verse at the head of each paragraph', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'psalms.xhtml',
            '<h1>Psalms</h1>' +
              '<p>23:1 The LORD is my shepherd; I shall not want.</p>' +
              '<p>23:2 He maketh me to lie down in green pastures.</p>' +
              '<p>24:1 The earth is the LORD’s, and the fulness thereof.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.code).toBe('PSA');
    expect(book.chapterCount).toBe(2);
    expect(book.chapter(1)!.verseText(1).startsWith('The LORD is my')).toBe(true);
    expect(book.chapter(2)!.verseText(1).startsWith('The earth is')).toBe(true);
  });
});

describe('the names books are given', () => {
  const codeFrom = (heading: string): string | undefined => {
    const result = EpubImport.convert(
      epub({
        documents: [['b.xhtml', `<h1>${heading}</h1><h2>1</h2><p><sup>1</sup>Some words.</p>`]],
      }),
    );
    return result.bible?.books[0]?.code;
  };

  it('however the heading dresses them up', () => {
    expect(codeFrom('THE REVELATION OF ST. JOHN THE DIVINE')).toBe('REV');
    expect(codeFrom('The First Epistle of Paul the Apostle to the Corinthians')).toBe('1CO');
    expect(codeFrom('The Acts of the Apostles')).toBe('ACT');
    expect(codeFrom('The Second Book of the Kings')).toBe('2KI');
    expect(codeFrom('Lamentations of Jeremiah')).toBe('LAM');
    expect(codeFrom('The Song of Solomon')).toBe('SNG');
    expect(codeFrom('II Timothy')).toBe('2TI');
  });

  it('a heading that names the chapter as well opens it', () => {
    const result = EpubImport.convert(
      epub({
        documents: [['jhn.xhtml', '<h1>John 3</h1><p><sup>16</sup>For God so loved the world.</p>']],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.code).toBe('JHN');
    expect(single(book.chapters).verseText(16)).toContain('so loved');
  });
});

describe('what it keeps', () => {
  it('poetry, headings and italics survive', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'psa.xhtml',
            '<h1>Psalms</h1><h2>Psalm 1</h2>' +
              '<h3>The Two Ways</h3>' +
              '<p class="q"><span class="verse">1</span>Blessed is the ' +
              '<i>one</i> who walks not in the counsel of the wicked.</p>',
          ],
        ],
      }),
    );

    const chapter = single(single(result.bible!.books).chapters);
    expect(
      chapter.blocks.some(
        (block) => block.style === BlockStyle.heading && block.segments[0].text.includes('Two Ways'),
      ),
    ).toBe(true);
    const verse = chapter.blocks.find((block) => block.style === BlockStyle.poetry)!;
    expect(verse.segments[0].text).toContain(Markup.addStart);
    expect(chapter.verseText(1)).toContain('one who walks');
  });

  it('the translation is named from the EPUB', () => {
    const result = EpubImport.convert(
      epub({
        title: 'World English Bible',
        rights: 'Public Domain',
        documents: [['gen.xhtml', '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>']],
      }),
      'web.epub',
    );

    const info = result.bible!.translation;
    expect(info.name).toBe('World English Bible');
    expect(info.abbreviation).toBe('WEB');
    expect(info.license).toBe('Public Domain');
    expect(info.id.startsWith('import-world-english-bible-')).toBe(true);
  });

  it('the same EPUB imports under the same id twice', () => {
    const idOf = (): string =>
      EpubImport.convert(
        epub({
          documents: [['gen.xhtml', '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>']],
        }),
      ).bible!.translation.id;

    expect(idOf()).toBe(idOf());
  });

  it('a licence the file does not state is not invented', () => {
    const result = EpubImport.convert(
      epub({
        rights: null,
        documents: [['gen.xhtml', '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>']],
      }),
    );

    expect(result.bible!.translation.license).toContain('not stated');
  });

  it('a spineless EPUB is read in file order', () => {
    const result = EpubImport.convert(
      epub({
        withSpine: false,
        documents: [['gen.xhtml', '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>']],
      }),
    );

    expect(single(result.bible!.books).code).toBe('GEN');
  });

  it('decomposed accents are composed on the way in', () => {
    // An "é" as an "e" and a combining acute: it looks the same and
    // matches nothing a reader types, until it is normalised.
    const result = EpubImport.convert(
      epub({
        documents: [['gen.xhtml', '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>Au commencement, Dieu créa.</p>']],
      }),
    );

    expect(single(result.bible!.books).chapter(1)!.verseText(1)).toBe('Au commencement, Dieu créa.');
  });
});

describe('the shapes real editions are published in', () => {
  // haiola generates the EPUBs on ebible.org — around 1,500 translations,
  // and most of the freely available ones. This is its actual output:
  // chapters labelled `psalmlabel` whatever the book, verses as a span
  // classed `verse` whose text ends in a non-breaking space, footnotes
  // inline, and one file per book named for the book.
  const haiola = (body: string): string => `<div class="main" id="GEN0_0">${body}</div>`;

  it('an ebible.org Bible reads', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'GEN.xhtml',
            haiola(
              '<div class="mt">Genesis</div>' +
                '<div class="psalmlabel" id="GEN1_0">Chapter 1</div>' +
                '<div class="p">' +
                '<span class="verse" id="GEN1_1">1 </span>' +
                'In the beginning God created the heavens and the earth. ' +
                '<span class="verse" id="GEN1_2">2 </span>' +
                'The earth was formless and empty.</div>' +
                '<div class="psalmlabel" id="GEN2_0">Chapter 2</div>' +
                '<div class="p">' +
                '<span class="verse" id="GEN2_1">1 </span>' +
                'Thus the heavens were finished.</div>',
            ),
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.code).toBe('GEN');
    expect(book.chapterCount).toBe(2);
    expect(book.chapter(1)!.verseCount).toBe(2);
    expect(book.chapter(1)!.verseText(1)).toBe('In the beginning God created the heavens and the earth.');
    expect(book.chapter(2)!.verseText(1)).toBe('Thus the heavens were finished.');
  });

  it('a footnote does not end up inside the verse', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'GEN.xhtml',
            haiola(
              '<div class="mt">Genesis</div>' +
                '<div class="psalmlabel">Chapter 1</div>' +
                '<div class="p">' +
                '<span class="verse" id="GEN1_1">1 </span>' +
                'In the beginning God' +
                '<a href="#FN1" epub:type="noteref" class="noteref">+</a>' +
                '<span class="note"><input type="checkbox" id="FN1" ' +
                'class="popnote"/><label for="FN1">' +
                '<span class="ntlbl">+</span><span class="box">' +
                '<span class="ftxt">Hebrew: Elohim.</span>' +
                '</span></label></span>' +
                ' created the heavens.</div>' +
                '<aside epub:type="footnote" id="FN1x">' +
                '<p class="f">Hebrew: Elohim.</p></aside>',
            ),
          ],
        ],
      }),
    );

    const text = single(result.bible!.books).chapter(1)!.verseText(1);
    expect(text).toBe('In the beginning God created the heavens.');
    expect(text).not.toContain('Elohim');
  });

  it('a localized chapter label still opens the chapter', () => {
    // The label says "Kapitel"; the app has never heard the word. The
    // markup calling it a chapter label is enough.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'PSA.xhtml',
            '<div class="mt1">Psalms</div>' +
              '<div class="psalmlabel">Kapitel 23</div>' +
              '<div class="q1"><span class="verse">1 </span>' +
              'The LORD is my shepherd.</div>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.code).toBe('PSA');
    expect(single(book.chapters).verseText(1)).toBe('The LORD is my shepherd.');
  });

  it('a one-chapter book with no chapter heading is not lost', () => {
    // Obadiah, Philemon, 2 and 3 John and Jude are published this way.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'jude.xhtml',
            '<h1>Jude</h1>' +
              '<p><sup>1</sup>Jude, a servant of Jesus Christ.</p>' +
              '<p><sup>2</sup>Mercy to you and peace be multiplied.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.code).toBe('JUD');
    expect(single(book.chapters).verseCount).toBe(2);
    expect(single(book.chapters).verseText(2).startsWith('Mercy to you')).toBe(true);
  });

  it('chapters numbered with Roman numerals', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1>' +
              '<h2>CHAPTER I</h2><p><sup>1</sup>In the beginning.</p>' +
              '<h2>CHAPTER II</h2><p><sup>1</sup>Thus the heavens.</p>' +
              '<h2>CHAPTER IV</h2><p><sup>1</sup>Adam knew Eve.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.chapterCount).toBe(3);
    expect(book.chapter(2)!.verseText(1)).toBe('Thus the heavens.');
    // The third is IV, so chapter III is missing and the shift is said.
    expect(result.warnings.join(' ')).toContain('numbered 3 here');
  });

  it('verse markers that print nothing and carry the number in an id', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1><h2>1</h2>' +
              '<p><a id="V1"></a>In the beginning.' +
              '<a id="V2"></a>The earth was formless.</p>',
          ],
        ],
      }),
    );

    const chapter = single(single(result.bible!.books).chapters);
    expect(chapter.verseCount).toBe(2);
    expect(chapter.verseText(2)).toBe('The earth was formless.');
  });

  it('a verse bridge opens at the first of the two', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1><h2>1</h2>' +
              '<p><span class="verse">1</span>In the beginning.</p>' +
              '<p><span class="verse">2-3</span>The earth was formless, and God said.</p>',
          ],
        ],
      }),
    );

    const chapter = single(single(result.bible!.books).chapters);
    expect(chapter.verseCount).toBe(2);
    expect(chapter.verseText(2).startsWith('The earth was formless')).toBe(true);
    // And is printed as the edition prints it.
    expect(chapter.labelFor(2)).toBe('2-3');
  });

  it('the file name names the book where the markup does not', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'GEN.xhtml',
            '<div class="psalmlabel">Chapter 1</div><div class="p"><span class="verse">1</span>In the beginning.</div>',
          ],
        ],
      }),
    );

    expect(single(result.bible!.books).code).toBe('GEN');
  });

  it('the table of contents names the book where nothing else does', () => {
    const result = EpubImport.convert(
      epubWithToc({
        documents: [['ch01.xhtml', '<h2>Chapter 1</h2><p><span class="verse">1</span>In the beginning.</p>']],
        toc: { 'ch01.xhtml': 'Genesis' },
      }),
    );

    expect(single(result.bible!.books).code).toBe('GEN');
  });

  it('Project Gutenberg numbers verses from the book up', () => {
    // "41:001:001" is Mark 1:1, not chapter 41. The text is the KJV, as
    // Gutenberg publishes it.
    const result = EpubImport.convert(
      epub({
        title: 'King James Version',
        documents: [
          [
            'mark.xhtml',
            '<h1>Book 41 Mark</h1>' +
              '<p>41:001:001 The beginning of the gospel of Jesus Christ, the Son of God;</p>' +
              '<p>41:001:002 As it is written in the prophets, Behold, I send my messenger before thy face.</p>' +
              '<p>41:002:001 And again he entered into Capernaum.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.code).toBe('MRK');
    expect(book.chapterCount).toBe(2);
    expect(book.chapter(1)!.verseText(1)).toBe('The beginning of the gospel of Jesus Christ, the Son of God;');
    expect(book.chapter(2)!.verseText(1)).toContain('Capernaum');
  });

  it('a centred paragraph is not a chapter label', () => {
    // Gutenberg's HTML centres things with class="c"; swallowing those as
    // chapter labels would drop the text inside them.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1><h2>1</h2>' +
              '<p><sup>1</sup>In the beginning.</p>' +
              '<p class="c">And the evening and the morning were the first day, and it was very good indeed.</p>',
          ],
        ],
      }),
    );

    expect(single(result.bible!.books).chapter(1)!.verseText(1)).toContain('first day');
  });

  it('the ESV, whose chapter number sits inside the paragraph', () => {
    // Crossway's markup: the chapter opens with a `chapter-num` holding
    // "1:1" — chapter and first verse in one marker, inline rather than
    // above the paragraph — and later verses are `verse-num`.
    const result = EpubImport.convert(
      epub({
        title: 'English Standard Version',
        documents: [
          [
            'john.xhtml',
            '<h1>John</h1>' +
              '<p><b class="chapter-num" id="v43001001-1">1:1 </b>' +
              'In the beginning was the Word.' +
              '<b class="verse-num" id="v43001002-1">2 </b>' +
              'He was in the beginning with God.</p>' +
              '<p><b class="chapter-num" id="v43002001-1">2:1 </b>' +
              'On the third day there was a wedding at Cana.' +
              '<b class="verse-num" id="v43002002-1">2 </b>' +
              'Jesus also was invited.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.code).toBe('JHN');
    expect(book.chapterCount).toBe(2);
    expect(book.chapter(1)!.verseCount).toBe(2);
    expect(book.chapter(1)!.verseText(1)).toBe('In the beginning was the Word.');
    expect(book.chapter(2)!.verseText(1)).toContain('wedding at Cana');
    expect(book.chapter(2)!.verseText(2)).toBe('Jesus also was invited.');
    // The marker itself is a number, not Scripture.
    expect(book.chapter(1)!.verseText(1)).not.toContain('1:1');
  });

  it('verse numbers running backwards open the next chapter', () => {
    // The safety net for an edition whose chapter markers this app does
    // not recognise at all: when the numbering restarts, a chapter began.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'rut.xhtml',
            '<h1>Ruth</h1>' +
              '<p><sup>1</sup>Now it came to pass.</p>' +
              '<p><sup>2</sup>And the name of the man was Elimelech.</p>' +
              '<p><sup>1</sup>And Naomi had a kinsman.</p>' +
              '<p><sup>2</sup>And Ruth said to Naomi.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.chapterCount).toBe(2);
    expect(book.chapter(1)!.verseText(1)).toBe('Now it came to pass.');
    expect(book.chapter(2)!.verseText(1)).toBe('And Naomi had a kinsman.');
    expect(book.chapter(2)!.verseText(2)).toBe('And Ruth said to Naomi.');
  });

  it('a chapter marker that prints nothing is read from its id', () => {
    // `v43002001` is John 2:1: book 43, chapter 002, verse 001.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'john.xhtml',
            '<h1>John</h1>' +
              '<p><span class="chapter-num" id="v43001001-1"></span>' +
              'In the beginning was the Word.</p>' +
              '<p><span class="chapter-num" id="v43002001-1"></span>' +
              'On the third day there was a wedding.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.code).toBe('JHN');
    expect(book.chapterCount).toBe(2);
    expect(book.chapter(1)!.verseText(1)).toBe('In the beginning was the Word.');
    expect(book.chapter(2)!.verseText(1)).toContain('wedding');
  });

  it('the running head before verse 1 is not read as Scripture', () => {
    // The ESV repeats the book's name inside the paragraph that opens
    // every chapter, right before the chapter marker — not just the first,
    // where the verse count happens to make it easy to spot.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1>' +
              '<p><span class="book-name">GENESIS</span>' +
              '<b class="chapter-num" id="v01001001-1">1:1 </b>' +
              'In the beginning God created the heavens.' +
              '<b class="verse-num">2 </b>The earth was without form.</p>' +
              '<p><span class="book-name">GENESIS</span>' +
              '<b class="chapter-num" id="v01002001-1">2:1 </b>' +
              'Thus the heavens and the earth were finished.</p>' +
              '<p><span class="book-name">GENESIS</span>' +
              '<b class="chapter-num" id="v01003001-1">3:1 </b>' +
              'Now the serpent was more crafty.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.chapterCount).toBe(3);
    expect(book.chapter(1)!.verseText(1)).toBe('In the beginning God created the heavens.');
    expect(book.chapter(2)!.verseText(1)).toBe('Thus the heavens and the earth were finished.');
    expect(book.chapter(3)!.verseText(1)).toBe('Now the serpent was more crafty.');

    for (let number = 1; number <= 3; number++) {
      for (const block of book.chapter(number)!.blocks) {
        for (const segment of block.segments) {
          expect(segment.text, `the running head survived into chapter ${number}`).not.toContain('GENESIS');
        }
      }
    }
  });

  it('a heading before a chapter break heads the chapter it opens', () => {
    // "The Flood Subsides" is printed before Genesis 8:1, while the page
    // is still in chapter 7. It belongs to 8.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1>' +
              '<p><b class="chapter-num">7:24 </b>' +
              'And the waters prevailed on the earth 150 days.</p>' +
              '<h3>The Flood Subsides</h3>' +
              '<p><b class="chapter-num">8:1 </b>' +
              'But God remembered Noah.</p>',
          ],
        ],
      }),
    );

    const book = single(result.bible!.books);
    expect(book.chapterCount).toBe(2);

    const headingsIn = (chapter: number): string =>
      book
        .chapter(chapter)!
        .blocks.filter((block) => block.style === BlockStyle.heading)
        .map((block) => block.segments[0].text)
        .join('|');

    // Chapter 7 here ends with its last verse and nothing after it.
    expect(headingsIn(1)).toBe('');
    expect(headingsIn(2)).toBe('The Flood Subsides');
    expect(book.chapter(2)!.verseText(1)).toBe('But God remembered Noah.');
  });

  it('a section heading marked only by its class is still a heading', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1><h2>2</h2>' +
              '<p class="section-heading">The Creation of Man</p>' +
              '<p><sup>4</sup>These are the generations.</p>',
          ],
        ],
      }),
    );

    const chapter = single(single(result.bible!.books).chapters);
    expect(chapter.blocks[0].style, 'the heading should come before the verse it heads').toBe(BlockStyle.heading);
    expect(chapter.blocks[0].segments[0].text).toBe('The Creation of Man');
  });

  it('poetry keeps the indent level its class gives it', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'psa.xhtml',
            '<h1>Psalms</h1><h2>1</h2>' +
              '<p class="line q1"><span class="verse">1</span>Blessed is the man</p>' +
              '<p class="line q2">who walks not in the counsel of the wicked;</p>',
          ],
        ],
      }),
    );

    const blocks = single(single(result.bible!.books).chapters).blocks.filter(
      (block) => block.style === BlockStyle.poetry,
    );
    expect(blocks).toHaveLength(2);
    expect(blocks[0].indent).toBe(1);
    expect(blocks[1].indent).toBe(2);
  });

  it('a chapter that came through as one verse says so', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1><h2>1</h2>' +
              '<p>1 In the beginning God created the heavens and the earth, ' +
              'and the earth was without form and void, and darkness was on ' +
              'the face of the deep. 2 And the Spirit of God moved upon the ' +
              'face of the waters, and God said, Let there be light. ' +
              '3 And there was light.</p>',
          ],
        ],
      }),
    );

    // The numbers are loose in the text, so only the first was found.
    expect(single(single(result.bible!.books).chapters).verseCount).toBe(1);
    expect(result.warnings.join(' ')).toContain('one long verse');
  });
});

describe('what it refuses to guess', () => {
  it('a book with no numbered verses is left out and reported', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          ['gen.xhtml', '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>'],
          ['oba.xhtml', '<h1>Obadiah</h1><h2>1</h2><p>The vision.</p>'],
        ],
      }),
    );

    expect(result.bible!.books.map((book) => book.code)).toEqual(['GEN']);
    expect(result.warnings.join(' ')).toContain('Obadiah');
  });

  it('a paragraph that opens with a number is not therefore a verse', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1><h2>1</h2>' +
              '<p><sup>1</sup>In the beginning.</p>' +
              '<p>40 days later, nothing of the sort happened.</p>',
          ],
        ],
      }),
    );

    const chapter = single(single(result.bible!.books).chapters);
    // Verse 1 carries on into the second paragraph rather than a verse 40
    // being conjured out of a date.
    expect(chapter.verseCount).toBe(1);
    expect(chapter.verseText(1)).toContain('40 days later');
  });

  it('a book that is not in the canon is passed over', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          ['gen.xhtml', '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>'],
          ['x.xhtml', '<h1>Introduction by the Editor</h1><p>Some words.</p>'],
        ],
      }),
    );

    expect(result.bible!.books.map((book) => book.code)).toEqual(['GEN']);
  });

  it('something that is not an EPUB says so', () => {
    const result = EpubImport.convert(strToU8('this is a text file'));

    expect(result.ok).toBe(false);
    expect(result.failure).toContain('not an EPUB');
  });

  it('a zip that is not an EPUB says so too', () => {
    // Starts 'PK' and then stops: the decoder refuses it, and the reason
    // is passed on rather than an exception.
    const result = EpubImport.convert(new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0]));

    expect(result.ok).toBe(false);
    expect(result.failure).toContain('not an EPUB');
  });

  it('an EPUB with no Bible in it says so', () => {
    const result = EpubImport.convert(
      epub({
        title: 'A Novel',
        documents: [['one.xhtml', '<h1>Chapter One</h1><p>It was a dark.</p>']],
      }),
    );

    expect(result.ok).toBe(false);
    expect(result.failure).toContain('No books of the Bible');
  });
});

/**
 * A book's landing page lists the chapters under it, and an edition that
 * puts one in the reading order had it read as the book's first verse.
 */
describe("a page that lists a book's chapters", () => {
  const landing =
    '<h1 class="book-title">1 John</h1>' +
    '<p class="chapter-list">' +
    '<a href="1jn1.xhtml">1 John 1</a> &#183; ' +
    '<a href="1jn2.xhtml">1 John 2</a> &#183; ' +
    '<a href="1jn3.xhtml">1 John 3</a></p>';
  const chapterOne =
    '<h1>1 John</h1>' +
    '<p><b class="chapter-num" id="v62001001-1">1:1&#160;</b>' +
    'That which was from the beginning, which we have heard.' +
    '<b class="verse-num" id="v62001002-1">2&#160;</b>' +
    'And the life was manifested.</p>';
  const chapterTwo =
    '<p><b class="chapter-num" id="v62002001-1">2&#160;</b>My little children, these things I write unto you.</p>';

  let bible: Bible;

  beforeAll(() => {
    const result = EpubImport.convert(
      epub({
        documents: [
          ['1jn.xhtml', landing],
          ['1jn1.xhtml', chapterOne],
          ['1jn2.xhtml', chapterTwo],
        ],
      }),
    );
    expect(result.failure, result.failure ?? '').toBeNull();
    bible = result.bible!;
  });

  it('is not the first verse of the book', () => {
    // The "1" of "1 John 1" was taken for verse 1 — a paragraph opening
    // with a number is one of the ways an edition numbers a verse — and
    // the rest of the line became its text.
    const one = bible.bookByCode('1JN')!.chapter(1)!;
    expect(one.verseText(1)).toBe('That which was from the beginning, which we have heard.');
    expect(
      one.blocks
        .flatMap((block) => block.segments)
        .map((segment) => Markup.strip(segment.text))
        .join('\n'),
    ).not.toContain('1 John 2');
  });

  it('and the chapters it pointed at are all there', () => {
    const book = bible.bookByCode('1JN')!;
    expect(book.chapters).toHaveLength(2);
    expect(book.chapter(2)!.verseText(1)).toBe('My little children, these things I write unto you.');
  });
});

describe('a navigation footer at the foot of a book', () => {
  // Every book's own document ends with one, so it is not the
  // navigation document the manifest names and nothing declares it.
  const footer =
    '<p><a href="index.xhtml">ESV</a></p>' +
    '<p><a href="ot.xhtml">The Old Testament</a></p>' +
    '<p><a href="nt.xhtml">The New Testament</a></p>' +
    '<p><a href="#">Show Last Hilite</a></p>' +
    '<p>ESV &#183; The Old Testament</p>' +
    '<p><a href="gen.xhtml">Genesis</a> &#183; ' +
    '<a href="exo.xhtml">Exodus</a> &#183; ' +
    '<a href="lev.xhtml">Leviticus</a></p>';

  it('is not the last verse of that book', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            '2pe.xhtml',
            '<h1>2 Peter</h1>' +
              '<p><b class="chapter-num" id="v61003001-1">3:1&#160;</b>' +
              'This is now the second letter.' +
              '<b class="verse-num" id="v61003018-1">18&#160;</b>' +
              'But grow in the grace and knowledge. Amen.</p>' +
              footer,
          ],
        ],
      }),
    );
    const chapter = result.bible!.bookByCode('2PE')!.chapter(1)!;
    expect(chapter.verseText(18)).toBe('But grow in the grace and knowledge. Amen.');
    // Every line of it: the links one to a paragraph, the row of book
    // names, and the plain label between them that carries no link at
    // all to give it away.
    const everything = chapter.blocks
      .flatMap((block) => block.segments)
      .map((segment) => Markup.strip(segment.text))
      .join('\n');
    for (const line of ['ESV', 'The Old Testament', 'The New Testament', 'Show Last Hilite', 'Genesis']) {
      expect(everything, `footer: ${line}`).not.toContain(line);
    }
  });

  it('and Scripture after one is Scripture again', () => {
    // A footer between two books must not swallow the book that follows.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'both.xhtml',
            '<h1>2 Peter</h1>' +
              '<p><b class="chapter-num" id="v61003001-1">3:1&#160;</b>' +
              'This is now the second letter.</p>' +
              footer +
              '<h1>1 John</h1>' +
              '<p><b class="chapter-num" id="v62001001-1">1:1&#160;</b>' +
              'That which was from the beginning.</p>' +
              '<p>And these things we write, that your joy may be full.</p>',
          ],
        ],
      }),
    );
    const john = result.bible!.bookByCode('1JN')!.chapter(1)!;
    expect(john.verseText(1)).toContain('That which was from the beginning.');
    // Including a paragraph of its own that numbers nothing, which is a
    // continuation of the verse before it and not more footer.
    expect(john.verseText(1)).toContain('your joy may be full');
  });
});

describe('but a verse carrying links is still a verse', () => {
  it('footnote markers do not make a paragraph into a menu', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1><h2>1</h2>' +
              '<p><sup>1</sup>In the beginning God created the heavens' +
              '<a class="noteref" href="#f1">a</a> and the earth' +
              '<a class="noteref" href="#f2">b</a>.' +
              '<sup>2</sup>And the earth was without form' +
              '<a class="noteref" href="#f3">c</a>.</p>',
          ],
        ],
      }),
    );
    const chapter = result.bible!.bookByCode('GEN')!.chapter(1)!;
    expect(chapter.verseText(1)).toBe('In the beginning God created the heavens and the earth.');
    expect(chapter.verseText(2)).toBe('And the earth was without form.');
  });

  it('nor does an edition that hangs a link on the whole verse', () => {
    // Some hang one on every verse — to a commentary, to a note — and a
    // verse wrapped in a link end to end is still a verse.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1><h2>1</h2>' +
              '<p><sup>1</sup>' +
              '<a href="notes.xhtml#g1">In the beginning God created the heavens and the earth.</a></p>',
          ],
        ],
      }),
    );
    expect(result.bible!.bookByCode('GEN')!.chapter(1)!.verseText(1)).toBe(
      'In the beginning God created the heavens and the earth.',
    );
  });

  it('nor do verse numbers an edition links to itself', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1><h2>1</h2>' +
              '<p>' +
              '<a class="verse-num" href="#v1" id="v1">1</a>' +
              'In the beginning God created.' +
              '<a class="verse-num" href="#v2" id="v2">2</a>' +
              'And the earth was without form.</p>',
          ],
        ],
      }),
    );
    const chapter = result.bible!.bookByCode('GEN')!.chapter(1)!;
    expect(chapter.verseText(1)).toBe('In the beginning God created.');
    expect(chapter.verseText(2)).toBe('And the earth was without form.');
  });
});

/**
 * The four faults an imported ESV showed on a phone, each reproduced from
 * the shape of markup that caused it. The ESV prints a chapter's number
 * inside the paragraph of its first verse and does not print that verse's
 * own number, which is what most of this turns on.
 */
describe('an edition that numbers its chapters inside the text', () => {
  const genesis =
    '<h2>Genesis</h2>' +
    '<h3 class="section-heading">The Creation of the World</h3>' +
    '<p><b class="chapter-num" id="v01001001-1">1:1&#160;</b>' +
    'In the beginning, God created the heavens and the earth.' +
    '<b class="verse-num" id="v01001002-1">2&#160;</b>' +
    'The earth was without form and void.</p>' +
    '<h3 class="section-heading">The Seventh Day, God Rests</h3>' +
    // The chapter number alone: the 1 of its first verse lives in the id.
    '<p><b class="chapter-num" id="v01002001-1">2&#160;</b>' +
    'Thus the heavens and the earth were finished.' +
    '<b class="verse-num" id="v01002002-1">2&#160;</b>' +
    'And on the seventh day God finished his work.</p>' +
    // And again with an id that says nothing, so only the chapter is
    // known and verse 1 has to be taken as read.
    '<p><b class="chapter-num" id="c3">3&#160;</b>' +
    'Now the serpent was more crafty than any other beast.</p>';

  const psalms =
    '<h2>Psalms</h2>' +
    '<h3 class="section-heading">The Way of the Righteous</h3>' +
    '<p class="line"><b class="chapter-num" id="v19001001-1">1:1&#160;</b>' +
    'Blessed is the man who walks not in the counsel of the wicked</p>' +
    '<h3 class="section-heading">The Reign of the Anointed</h3>' +
    '<p class="line"><b class="chapter-num" id="v19002001-1">2:1&#160;</b>' +
    'Why do the nations rage</p>' +
    '<p class="indent">and the peoples plot in vain, on and on and on ' +
    'and on and on and on and on and on and on and on</p>' +
    // Psalm 3's heading and superscription, both of which stand ahead
    // of anything that says the psalm has changed.
    '<h3 class="section-heading">Save Me, O My God</h3>' +
    '<p class="psalm-title">A Psalm of David, when he fled from Absalom his son.</p>' +
    '<p class="line"><b class="chapter-num" id="v19003001-1">3:1&#160;</b>' +
    'O LORD, how many are my foes!</p>';

  // The table of contents, which the manifest marks as the navigation
  // document, and a copyright page, which nothing marks as anything.
  const contents =
    '<h1>Table of Contents</h1>' +
    '<p><a href="gen.xhtml">Genesis</a> &#183; <a href="psa.xhtml">Psalms</a></p>' +
    '<p>ESV &#183; The Old Testament &#183; BookNAME</p>';

  const backMatter = '<p>Copyright 2001. All rights reserved.</p><p>Published by arrangement.</p>';

  let bible: Bible;

  beforeAll(() => {
    const result = EpubImport.convert(
      epub({
        documents: [
          ['gen.xhtml', genesis],
          ['psa.xhtml', psalms],
          ['rights.xhtml', backMatter],
        ],
        nav: ['toc.xhtml', contents],
      }),
    );
    expect(result.failure, result.failure ?? '').toBeNull();
    bible = result.bible!;
  });

  const chapterOf = (code: string, number: number): Chapter =>
    bible.books.find((book) => book.code === code)!.chapters[number - 1];

  /** A block's text, markers taken out. */
  const plain = (block: Block): string =>
    block.segments
      .map((segment) => Markup.strip(segment.text))
      .join(' ')
      .trim();

  const textOf = (chapter: Chapter, verse: number): string =>
    chapter.blocks
      .flatMap((block) => block.segments)
      .filter((segment) => segment.verse === verse)
      .map((segment) => Markup.strip(segment.text))
      .join('')
      .trim();

  it('a chapter keeps its first verse', () => {
    // Genesis 2:1 was dropped outright: the marker printed "2" and the
    // verse it opened was only ever in the id, so nothing opened a verse
    // and the text was thrown away as a running head.
    expect(textOf(chapterOf('GEN', 2), 1)).toBe('Thus the heavens and the earth were finished.');
    expect(textOf(chapterOf('GEN', 2), 2)).toBe('And on the seventh day God finished his work.');
  });

  it('and keeps it where only the chapter can be known', () => {
    expect(textOf(chapterOf('GEN', 3), 1)).toBe('Now the serpent was more crafty than any other beast.');
  });

  it("a psalm's heading and superscription open their own psalm", () => {
    const two = chapterOf('PSA', 2);
    const three = chapterOf('PSA', 3);

    const linesOfTwo = two.blocks.map((block) => plain(block));
    expect(
      linesOfTwo.some((line) => line.includes('Save Me')),
      "Psalm 3's heading was landing at the end of Psalm 2",
    ).toBe(false);
    expect(linesOfTwo.some((line) => line.includes('Absalom'))).toBe(false);

    expect(plain(three.blocks[0])).toBe('Save Me, O My God');
    // Gathered while Psalm 2's last verse was still open, and it must
    // not carry that verse across with it.
    expect(single(three.blocks[0].segments).verse).toBe(0);
    expect(three.blocks[0].style).toBe(BlockStyle.heading);
    expect(three.blocks[1].style).toBe(BlockStyle.descriptiveTitle);
    expect(plain(three.blocks[1])).toContain('Absalom');
    expect(textOf(three, 1)).toBe('O LORD, how many are my foes!');
  });

  it('the second line of a couplet is a line of verse', () => {
    // Read as prose it took a paragraph's first-line indent and wrapped
    // back to the margin, so the couplet looked like a poetry line that
    // had lost its indent.
    const lines = chapterOf('PSA', 2).blocks.filter((block) => plain(block).startsWith('and the peoples'));
    expect(lines).toHaveLength(1);
    expect(lines[0].style).toBe(BlockStyle.poetry);
    expect(lines[0].indent).toBeGreaterThan(1);
  });

  it('the table of contents is not Scripture', () => {
    const everything = bible.books
      .flatMap((book) => book.chapters)
      .flatMap((chapter) => chapter.blocks)
      .map((block) => plain(block))
      .join('\n');
    expect(everything).not.toContain('Table of Contents');
    expect(everything).not.toContain('BookNAME');
    expect(everything).not.toContain('The Old Testament');
  });

  it('nor is a copyright page with nothing numbered in it', () => {
    // It followed Psalms in the spine, so every paragraph of it used to
    // be read as a continuation of the last verse left open.
    const psalmThree = chapterOf('PSA', 3);
    expect(psalmThree.blocks.map((block) => plain(block)).join('\n')).not.toContain('All rights reserved');
    expect(textOf(psalmThree, 1)).toBe('O LORD, how many are my foes!');
  });
});

/**
 * The shapes the ESV Classic Reference Bible actually uses, taken from the
 * file rather than guessed at from a screenshot. Every one of these was a
 * fault found by importing it.
 */
describe('an edition that hides its own apparatus', () => {
  it('a div the edition hides is not Scripture', () => {
    // The whole navigation apparatus — every book, every chapter, and
    // the template text around them — sits in one of these at the foot
    // of every book's file. Nothing is more authoritative about it than
    // the edition saying so itself.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'b61.00.2-Peter.text.xhtml',
            '<h1>2 Peter</h1>' +
              '<p><span class="chapter-num"> 3 </span>' +
              'But grow in the grace and knowledge.</p>' +
              '<div class="hide">' +
              '<div id="tc"><p class="nav-header">ESV</p>' +
              '<p class="nav"><a class="pop-link" ' +
              "onclick=\"nav.show('ot')\">The Old Testament</a></p>" +
              '<p class="nav"><a class="pop-link" ' +
              'onclick="lastHilite()">Show Last Hilite</a></p></div>' +
              '<div id="this-book-ot"><p class="nav-header">ESV &#183; ' +
              '<span id="bookname-ot">BookNAME</span></p>' +
              '<p class="nav" id="chapters-ot">chAPTErs</p></div>' +
              '</div>',
          ],
        ],
      }),
    );
    const chapter = result.bible!.bookByCode('2PE')!.chapter(1)!;
    const everything = chapter.blocks
      .flatMap((block) => block.segments)
      .map((segment) => Markup.strip(segment.text))
      .join('\n');
    expect(everything).toContain('But grow in the grace');
    for (const furniture of ['ESV', 'The Old Testament', 'Show Last Hilite', 'BookNAME', 'chAPTErs']) {
      expect(everything, furniture).not.toContain(furniture);
    }
  });

  it('and neither is anything else it hides', () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'gen.xhtml',
            '<h1>Genesis</h1>' +
              '<p><span class="chapter-num"> 1 </span>In the beginning.</p>' +
              '<p hidden="hidden">Hidden by attribute.</p>' +
              '<p style="display: none">Hidden by style.</p>' +
              '<p style="visibility:hidden">Hidden too.</p>',
          ],
        ],
      }),
    );
    const everything = result
      .bible!.bookByCode('GEN')!
      .chapter(1)!
      .blocks.flatMap((block) => block.segments)
      .map((segment) => Markup.strip(segment.text))
      .join('\n');
    expect(everything).toContain('In the beginning.');
    expect(everything).not.toContain('Hidden');
  });
});

describe('a book is identified by more than its file name', () => {
  it('a numbered book keeps its number', () => {
    // `b62.00.1-John.text.xhtml` holds three things: where the file
    // sorts, what book it is, and which part of the apparatus. Reading
    // all three as the name made "1-John" into John, and the whole of
    // 1, 2 and 3 John went into the Gospel — silently, with nothing
    // missing and nothing to show for it.
    const result = EpubImport.convert(
      epub({
        documents: [
          ['b43.00.John.text.xhtml', '<p><span class="chapter-num"> 1 </span>In the beginning was the Word.</p>'],
          [
            'b62.00.1-John.text.xhtml',
            '<p><span class="chapter-num"> 1 </span>That which was from the beginning.</p>',
          ],
          ['b63.00.2-John.text.xhtml', '<p><span class="chapter-num"> 1 </span>The elder to the elect lady.</p>'],
        ],
      }),
    );
    const bible = result.bible!;
    expect(bible.bookByCode('JHN')?.chapter(1)?.verseText(1)).toBe('In the beginning was the Word.');
    expect(bible.bookByCode('1JN')?.chapter(1)?.verseText(1)).toBe('That which was from the beginning.');
    expect(bible.bookByCode('2JN')?.chapter(1)?.verseText(1)).toBe('The elder to the elect lady.');
    expect(bible.bookByCode('JHN')!.chapters).toHaveLength(1);
  });

  it('and a packed id overrules a file name that is wrong', () => {
    // `v62001001` is the sixty-second book of the canon whatever the
    // file is called, and an anchor is better evidence than a name.
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'mystery.xhtml',
            '<h1>John</h1><p id="v62001001"><span class="chapter-num"> 1 </span>That which was from the beginning.</p>',
          ],
        ],
      }),
    );
    expect(result.bible!.bookByCode('1JN')?.chapter(1)?.verseText(1)).toBe('That which was from the beginning.');
  });

  it("a book's footnotes filed as a document of their own are not read", () => {
    const result = EpubImport.convert(
      epub({
        documents: [
          ['b03.00.Leviticus.text.xhtml', '<p><span class="chapter-num"> 1 </span>The LORD called Moses.</p>'],
          ['b03.00.Leviticus.crossrefs.xhtml', '<p>Exodus 40:34; Numbers 1:1. Deuteronomy 1:1.</p>'],
        ],
      }),
    );
    const leviticus = result.bible!.bookByCode('LEV')!.chapter(1)!;
    expect(leviticus.verseText(1)).toBe('The LORD called Moses.');
    expect(leviticus.verseCount).toBe(1);
  });
});

describe('the formatting this edition actually marks', () => {
  let psalm: Chapter;
  let john: Chapter;

  beforeAll(() => {
    const result = EpubImport.convert(
      epub({
        documents: [
          [
            'b19.00.Psalm.text.xhtml',
            '<header><p class="heading"><span>The Reign of the Anointed</span></p></header>' +
              '<p class="line"><span class="chapter-num"> 2 </span>Why do the nations rage</p>' +
              '<p class="line-indent">and the peoples plot in vain?</p>' +
              '<p class="line"><span class="verse-num">2</span>' +
              'Serve the L<span class="smallcap">ORD</span> with fear. ' +
              '<span class="selah">Selah</span></p>',
          ],
          [
            'b43.00.John.text.xhtml',
            '<p class="no-indent"><span class="chapter-num"> 3 </span>' +
              'Jesus answered, <span class="woc">&#8220;Truly, truly, I say to you.&#8221;</span> And he went.</p>',
          ],
        ],
      }),
    );
    psalm = result.bible!.bookByCode('PSA')!.chapter(1)!;
    john = result.bible!.bookByCode('JHN')!.chapter(1)!;
  });

  it('a heading over a chapter that has not opened yet is kept', () => {
    // It is printed before the paragraph the chapter number is in, so
    // no chapter is open when it arrives. Every book was losing the
    // heading over its first chapter.
    expect(psalm.blocks[0].style).toBe(BlockStyle.heading);
    expect(Markup.strip(psalm.blocks[0].segments[0].text)).toBe('The Reign of the Anointed');
  });

  it('a couplet is two lines of verse, the second indented', () => {
    const lines = psalm.blocks.filter((block) => block.style === BlockStyle.poetry);
    expect(lines.length).toBeGreaterThanOrEqual(2);
    expect(lines[0].indent).toBe(1);
    expect(lines[1].indent).toBeGreaterThan(1);
    expect(Markup.strip(lines[1].segments[0].text)).toBe('and the peoples plot in vain?');
  });

  it('the divine name and Selah are marked', () => {
    const second = psalm.blocks
      .flatMap((block) => block.segments)
      .filter((segment) => segment.verse === 2)
      .map((segment) => segment.text)
      .join('');
    expect(second).toContain(Markup.divineStart);
    expect(second).toContain(Markup.selahStart);
    expect(psalm.verseText(2)).toBe('Serve the LORD with fear. Selah');
  });

  it('and what Jesus says is red-lettered', () => {
    const verse = john.blocks
      .flatMap((block) => block.segments)
      .map((segment) => segment.text)
      .join('');
    expect(verse).toContain(Markup.wjStart);
    expect(verse).toContain(Markup.wjEnd);
    expect(john.verseText(1)).toBe('Jesus answered, “Truly, truly, I say to you.” And he went.');
  });

  it('a paragraph the edition sets flush is not indented', () => {
    const paragraph = john.blocks.find((block) => block.style === BlockStyle.paragraph)!;
    expect(paragraph.indentFirstLine).toBe(false);
  });
});

describe('the furniture an edition repeats around every book', () => {
  it('is swept out and reported, whatever the markup', () => {
    // Three books, each ending with the same unmarked line after its
    // last verse: no class, no link, nothing to read in the markup. Only
    // the repetition across books gives it away.
    const book = (name: string, verse: string): string =>
      `<h1>${name}</h1><h2>1</h2><p><sup>1</sup>${verse}</p><p>Scripture quotations are from the Test Standard Version.</p>`;
    const result = EpubImport.convert(
      epub({
        documents: [
          ['gen.xhtml', book('Genesis', 'In the beginning.')],
          ['exo.xhtml', book('Exodus', 'These are the names.')],
          ['lev.xhtml', book('Leviticus', 'The LORD called Moses.')],
        ],
      }),
    );

    expect(result.warnings.join('\n')).toContain('Dropped 1 line');
    for (const code of ['GEN', 'EXO', 'LEV']) {
      const text = result
        .bible!.bookByCode(code)!
        .chapter(1)!
        .blocks.flatMap((block) => block.segments)
        .map((segment) => segment.text)
        .join('\n');
      expect(text, code).not.toContain('Scripture quotations');
    }
  });
});
