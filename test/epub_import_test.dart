import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/epub_import.dart';
import 'package:openword/src/model/bible.dart';

/// Builds an EPUB around some XHTML documents, the way a real one is laid
/// out: a container pointing at a package file, which lists the spine.
Uint8List epub({
  required List<(String name, String xhtml)> documents,
  String title = 'Test Standard Version',
  String? rights = 'Public Domain',
  bool withSpine = true,
}) {
  final manifest = StringBuffer();
  final spine = StringBuffer();
  for (var i = 0; i < documents.length; i++) {
    manifest.write(
      '<item id="d$i" href="${documents[i].$1}" '
      'media-type="application/xhtml+xml"/>',
    );
    spine.write('<itemref idref="d$i"/>');
  }

  final opf =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>$title</dc:title>'
      '<dc:identifier>urn:test:$title</dc:identifier>'
      '${rights == null ? '' : '<dc:rights>$rights</dc:rights>'}'
      '</metadata>'
      '<manifest>$manifest</manifest>'
      '${withSpine ? '<spine>$spine</spine>' : '<spine/>'}'
      '</package>';

  final container =
      '<?xml version="1.0"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';

  final archive = Archive()
    ..addFile(_file('mimetype', 'application/epub+zip'))
    ..addFile(_file('META-INF/container.xml', container))
    ..addFile(_file('OEBPS/content.opf', opf));
  for (final document in documents) {
    archive.addFile(_file('OEBPS/${document.$1}', _page(document.$2)));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

ArchiveFile _file(String name, String content) {
  final bytes = utf8.encode(content);
  return ArchiveFile.bytes(name, bytes);
}

String _page(String body) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>x</title></head>'
    '<body>$body</body></html>';

/// An EPUB whose table of contents names the documents, for the case where
/// nothing inside them does.
Uint8List epubWithToc({
  required List<(String name, String xhtml)> documents,
  required Map<String, String> toc,
  String title = 'Test Standard Version',
}) {
  final manifest = StringBuffer(
    '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
  );
  final spine = StringBuffer();
  for (var i = 0; i < documents.length; i++) {
    manifest.write(
      '<item id="d$i" href="${documents[i].$1}" '
      'media-type="application/xhtml+xml"/>',
    );
    spine.write('<itemref idref="d$i"/>');
  }

  final points = StringBuffer();
  var order = 0;
  for (final entry in toc.entries) {
    order++;
    points.write(
      '<navPoint id="n$order" playOrder="$order">'
      '<navLabel><text>${entry.value}</text></navLabel>'
      '<content src="${entry.key}"/></navPoint>',
    );
  }

  final ncx =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
      '<navMap>$points</navMap></ncx>';

  final opf =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>$title</dc:title></metadata>'
      '<manifest>$manifest</manifest>'
      '<spine toc="ncx">$spine</spine></package>';

  final container =
      '<?xml version="1.0"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';

  final archive = Archive()
    ..addFile(_file('mimetype', 'application/epub+zip'))
    ..addFile(_file('META-INF/container.xml', container))
    ..addFile(_file('OEBPS/content.opf', opf))
    ..addFile(_file('OEBPS/toc.ncx', ncx));
  for (final document in documents) {
    archive.addFile(_file('OEBPS/${document.$1}', _page(document.$2)));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  group('the shapes a Bible EPUB comes in', () {
    test('numbered spans, the usual output of publishing tools', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1>'
                  '<h2>Chapter 1</h2>'
                  '<p><span class="verse" id="V1">1</span>In the beginning God '
                  'created the heavens and the earth. '
                  '<span class="verse" id="V2">2</span>The earth was formless.</p>'
                  '<h2>Chapter 2</h2>'
                  '<p><span class="verse">1</span>Thus the heavens were '
                  'finished.</p>',
            ),
          ],
        ),
      );

      expect(result.failure, isNull);
      final bible = result.bible!;
      expect(bible.books.single.code, 'GEN');
      expect(bible.books.single.chapterCount, 2);

      final first = bible.books.single.chapter(1)!;
      expect(first.verseCount, 2);
      expect(first.verseText(1), startsWith('In the beginning'));
      expect(first.verseText(2), 'The earth was formless.');
      expect(bible.books.single.chapter(2)!.verseText(1), contains('finished'));
    });

    test('superscript numbers', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'john.xhtml',
              '<h1>The Gospel According to John</h1>'
                  '<h2>3</h2>'
                  '<p><sup>16</sup>For God so loved the world.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.code, 'JHN');
      // The chapter is numbered from the heading, and the verse from the
      // superscript.
      expect(book.chapters.single.verseText(16), 'For God so loved the world.');
    });

    test('a number at the head of each paragraph', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'ruth.xhtml',
              '<h1>Ruth</h1><h2>Chapter 1</h2>'
                  '<p>1 Now it came to pass in the days.</p>'
                  '<p>2 And the name of the man was Elimelech.</p>',
            ),
          ],
        ),
      );

      final chapter = result.bible!.books.single.chapters.single;
      expect(chapter.verseCount, 2);
      expect(chapter.verseText(2), 'And the name of the man was Elimelech.');
    });

    test('chapter and verse at the head of each paragraph', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'psalms.xhtml',
              '<h1>Psalms</h1>'
                  '<p>23:1 The LORD is my shepherd; I shall not want.</p>'
                  '<p>23:2 He maketh me to lie down in green pastures.</p>'
                  '<p>24:1 The earth is the LORD’s, and the fulness '
                  'thereof.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.code, 'PSA');
      expect(book.chapterCount, 2);
      expect(book.chapter(1)!.verseText(1), startsWith('The LORD is my'));
      expect(book.chapter(2)!.verseText(1), startsWith('The earth is'));
    });
  });

  group('the names books are given', () {
    String? codeFrom(String heading) {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'b.xhtml',
              '<h1>$heading</h1><h2>1</h2><p><sup>1</sup>Some words.</p>',
            ),
          ],
        ),
      );
      return result.bible?.books.single.code;
    }

    test('however the heading dresses them up', () {
      expect(codeFrom('THE REVELATION OF ST. JOHN THE DIVINE'), 'REV');
      expect(
        codeFrom('The First Epistle of Paul the Apostle to the Corinthians'),
        '1CO',
      );
      expect(codeFrom('The Acts of the Apostles'), 'ACT');
      expect(codeFrom('The Second Book of the Kings'), '2KI');
      expect(codeFrom('Lamentations of Jeremiah'), 'LAM');
      expect(codeFrom('The Song of Solomon'), 'SNG');
      expect(codeFrom('II Timothy'), '2TI');
    });

    test('a heading that names the chapter as well opens it', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'jhn.xhtml',
              '<h1>John 3</h1><p><sup>16</sup>For God so loved the world.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.code, 'JHN');
      expect(book.chapters.single.verseText(16), contains('so loved'));
    });
  });

  group('what it keeps', () {
    test('poetry, headings and italics survive', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'psa.xhtml',
              '<h1>Psalms</h1><h2>Psalm 1</h2>'
                  '<h3>The Two Ways</h3>'
                  '<p class="q"><span class="verse">1</span>Blessed is the '
                  '<i>one</i> who walks not in the counsel of the wicked.</p>',
            ),
          ],
        ),
      );

      final chapter = result.bible!.books.single.chapters.single;
      expect(
        chapter.blocks.any(
          (block) =>
              block.style == BlockStyle.heading &&
              block.segments.first.text.contains('Two Ways'),
        ),
        isTrue,
      );
      final verse = chapter.blocks.firstWhere(
        (block) => block.style == BlockStyle.poetry,
      );
      expect(verse.segments.first.text, contains(Markup.addStart));
      expect(chapter.verseText(1), contains('one who walks'));
    });

    test('the translation is named from the EPUB', () {
      final result = EpubImport.convert(
        epub(
          title: 'World English Bible',
          rights: 'Public Domain',
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>',
            ),
          ],
        ),
        fileName: 'web.epub',
      );

      final info = result.bible!.translation;
      expect(info.name, 'World English Bible');
      expect(info.abbreviation, 'WEB');
      expect(info.license, 'Public Domain');
      expect(info.id, startsWith('import-world-english-bible-'));
    });

    test('the same EPUB imports under the same id twice', () {
      String idOf() => EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>',
            ),
          ],
        ),
      ).bible!.translation.id;

      expect(idOf(), idOf());
    });

    test('a licence the file does not state is not invented', () {
      final result = EpubImport.convert(
        epub(
          rights: null,
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>',
            ),
          ],
        ),
      );

      expect(result.bible!.translation.license, contains('not stated'));
    });

    test('a spineless EPUB is read in file order', () {
      final result = EpubImport.convert(
        epub(
          withSpine: false,
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>',
            ),
          ],
        ),
      );

      expect(result.bible!.books.single.code, 'GEN');
    });
  });

  group('the shapes real editions are published in', () {
    // haiola generates the EPUBs on ebible.org — around 1,500 translations,
    // and most of the freely available ones. This is its actual output:
    // chapters labelled `psalmlabel` whatever the book, verses as a span
    // classed `verse` whose text ends in a non-breaking space, footnotes
    // inline, and one file per book named for the book.
    String haiola(String body) => '<div class="main" id="GEN0_0">$body</div>';

    test('an ebible.org Bible reads', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'GEN.xhtml',
              haiola(
                '<div class="mt">Genesis</div>'
                '<div class="psalmlabel" id="GEN1_0">Chapter 1</div>'
                '<div class="p">'
                '<span class="verse" id="GEN1_1">1\u00a0</span>'
                'In the beginning God created the heavens and the earth. '
                '<span class="verse" id="GEN1_2">2\u00a0</span>'
                'The earth was formless and empty.</div>'
                '<div class="psalmlabel" id="GEN2_0">Chapter 2</div>'
                '<div class="p">'
                '<span class="verse" id="GEN2_1">1\u00a0</span>'
                'Thus the heavens were finished.</div>',
              ),
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.code, 'GEN');
      expect(book.chapterCount, 2);
      expect(book.chapter(1)!.verseCount, 2);
      expect(
        book.chapter(1)!.verseText(1),
        'In the beginning God created the heavens and the earth.',
      );
      expect(book.chapter(2)!.verseText(1), 'Thus the heavens were finished.');
    });

    test('a footnote does not end up inside the verse', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'GEN.xhtml',
              haiola(
                '<div class="mt">Genesis</div>'
                '<div class="psalmlabel">Chapter 1</div>'
                '<div class="p">'
                '<span class="verse" id="GEN1_1">1\u00a0</span>'
                'In the beginning God'
                '<a href="#FN1" epub:type="noteref" class="noteref">+</a>'
                '<span class="note"><input type="checkbox" id="FN1" '
                'class="popnote"/><label for="FN1">'
                '<span class="ntlbl">+</span><span class="box">'
                '<span class="ftxt">Hebrew: Elohim.</span>'
                '</span></label></span>'
                ' created the heavens.</div>'
                '<aside epub:type="footnote" id="FN1x">'
                '<p class="f">Hebrew: Elohim.</p></aside>',
              ),
            ),
          ],
        ),
      );

      final text = result.bible!.books.single.chapter(1)!.verseText(1);
      expect(text, 'In the beginning God created the heavens.');
      expect(text, isNot(contains('Elohim')));
    });

    test('a localized chapter label still opens the chapter', () {
      // The label says "Kapitel"; the app has never heard the word. The
      // markup calling it a chapter label is enough.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'PSA.xhtml',
              '<div class="mt1">Psalms</div>'
                  '<div class="psalmlabel">Kapitel 23</div>'
                  '<div class="q1"><span class="verse">1\u00a0</span>'
                  'The LORD is my shepherd.</div>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.code, 'PSA');
      expect(book.chapters.single.verseText(1), 'The LORD is my shepherd.');
    });

    test('a one-chapter book with no chapter heading is not lost', () {
      // Obadiah, Philemon, 2 and 3 John and Jude are published this way.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'jude.xhtml',
              '<h1>Jude</h1>'
                  '<p><sup>1</sup>Jude, a servant of Jesus Christ.</p>'
                  '<p><sup>2</sup>Mercy to you and peace be multiplied.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.code, 'JUD');
      expect(book.chapters.single.verseCount, 2);
      expect(book.chapters.single.verseText(2), startsWith('Mercy to you'));
    });

    test('chapters numbered with Roman numerals', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1>'
                  '<h2>CHAPTER I</h2><p><sup>1</sup>In the beginning.</p>'
                  '<h2>CHAPTER II</h2><p><sup>1</sup>Thus the heavens.</p>'
                  '<h2>CHAPTER IV</h2><p><sup>1</sup>Adam knew Eve.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.chapterCount, 3);
      expect(book.chapter(2)!.verseText(1), 'Thus the heavens.');
      // The third is IV, so chapter III is missing and the shift is said.
      expect(result.warnings.join(' '), contains('numbered 3 here'));
    });

    test('verse markers that print nothing and carry the number in an id', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2>'
                  '<p><a id="V1"></a>In the beginning.'
                  '<a id="V2"></a>The earth was formless.</p>',
            ),
          ],
        ),
      );

      final chapter = result.bible!.books.single.chapters.single;
      expect(chapter.verseCount, 2);
      expect(chapter.verseText(2), 'The earth was formless.');
    });

    test('a verse bridge opens at the first of the two', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2>'
                  '<p><span class="verse">1</span>In the beginning.</p>'
                  '<p><span class="verse">2-3</span>The earth was formless, '
                  'and God said.</p>',
            ),
          ],
        ),
      );

      final chapter = result.bible!.books.single.chapters.single;
      expect(chapter.verseCount, 2);
      expect(chapter.verseText(2), startsWith('The earth was formless'));
    });

    test('the file name names the book where the markup does not', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'GEN.xhtml',
              '<div class="psalmlabel">Chapter 1</div>'
                  '<div class="p"><span class="verse">1</span>'
                  'In the beginning.</div>',
            ),
          ],
        ),
      );

      expect(result.bible!.books.single.code, 'GEN');
    });

    test('the table of contents names the book where nothing else does', () {
      final result = EpubImport.convert(
        epubWithToc(
          documents: [
            (
              'ch01.xhtml',
              '<h2>Chapter 1</h2>'
                  '<p><span class="verse">1</span>In the beginning.</p>',
            ),
          ],
          toc: {'ch01.xhtml': 'Genesis'},
        ),
      );

      expect(result.bible!.books.single.code, 'GEN');
    });

    test('Project Gutenberg numbers verses from the book up', () {
      // "41:001:001" is Mark 1:1, not chapter 41. The text is the KJV, as
      // Gutenberg publishes it.
      final result = EpubImport.convert(
        epub(
          title: 'King James Version',
          documents: [
            (
              'mark.xhtml',
              '<h1>Book 41 Mark</h1>'
                  '<p>41:001:001 The beginning of the gospel of Jesus Christ, '
                  'the Son of God;</p>'
                  '<p>41:001:002 As it is written in the prophets, Behold, I '
                  'send my messenger before thy face.</p>'
                  '<p>41:002:001 And again he entered into Capernaum.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.code, 'MRK');
      expect(book.chapterCount, 2);
      expect(
        book.chapter(1)!.verseText(1),
        'The beginning of the gospel of Jesus Christ, the Son of God;',
      );
      expect(book.chapter(2)!.verseText(1), contains('Capernaum'));
    });

    test('a centred paragraph is not a chapter label', () {
      // Gutenberg's HTML centres things with class="c"; swallowing those as
      // chapter labels would drop the text inside them.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2>'
                  '<p><sup>1</sup>In the beginning.</p>'
                  '<p class="c">And the evening and the morning were the first '
                  'day, and it was very good indeed.</p>',
            ),
          ],
        ),
      );

      expect(
        result.bible!.books.single.chapter(1)!.verseText(1),
        contains('first day'),
      );
    });

    test('the ESV, whose chapter number sits inside the paragraph', () {
      // Crossway's markup: the chapter opens with a `chapter-num` holding
      // "1:1" — chapter and first verse in one marker, inline rather than
      // above the paragraph — and later verses are `verse-num`.
      final result = EpubImport.convert(
        epub(
          title: 'English Standard Version',
          documents: [
            (
              'john.xhtml',
              '<h1>John</h1>'
                  '<p><b class="chapter-num" id="v43001001-1">1:1\u00a0</b>'
                  'In the beginning was the Word.'
                  '<b class="verse-num" id="v43001002-1">2\u00a0</b>'
                  'He was in the beginning with God.</p>'
                  '<p><b class="chapter-num" id="v43002001-1">2:1\u00a0</b>'
                  'On the third day there was a wedding at Cana.'
                  '<b class="verse-num" id="v43002002-1">2\u00a0</b>'
                  'Jesus also was invited.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.code, 'JHN');
      expect(book.chapterCount, 2);
      expect(book.chapter(1)!.verseCount, 2);
      expect(book.chapter(1)!.verseText(1), 'In the beginning was the Word.');
      expect(book.chapter(2)!.verseText(1), contains('wedding at Cana'));
      expect(book.chapter(2)!.verseText(2), 'Jesus also was invited.');
      // The marker itself is a number, not Scripture.
      expect(book.chapter(1)!.verseText(1), isNot(contains('1:1')));
    });

    test('verse numbers running backwards open the next chapter', () {
      // The safety net for an edition whose chapter markers this app does
      // not recognise at all: when the numbering restarts, a chapter began.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'rut.xhtml',
              '<h1>Ruth</h1>'
                  '<p><sup>1</sup>Now it came to pass.</p>'
                  '<p><sup>2</sup>And the name of the man was Elimelech.</p>'
                  '<p><sup>1</sup>And Naomi had a kinsman.</p>'
                  '<p><sup>2</sup>And Ruth said to Naomi.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.chapterCount, 2);
      expect(book.chapter(1)!.verseText(1), 'Now it came to pass.');
      expect(book.chapter(2)!.verseText(1), 'And Naomi had a kinsman.');
      expect(book.chapter(2)!.verseText(2), 'And Ruth said to Naomi.');
    });

    test('a chapter marker that prints nothing is read from its id', () {
      // `v43002001` is John 2:1: book 43, chapter 002, verse 001.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'john.xhtml',
              '<h1>John</h1>'
                  '<p><span class="chapter-num" id="v43001001-1"></span>'
                  'In the beginning was the Word.</p>'
                  '<p><span class="chapter-num" id="v43002001-1"></span>'
                  'On the third day there was a wedding.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.code, 'JHN');
      expect(book.chapterCount, 2);
      expect(book.chapter(1)!.verseText(1), 'In the beginning was the Word.');
      expect(book.chapter(2)!.verseText(1), contains('wedding'));
    });

    test('a chapter that came through as one verse says so', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2>'
                  '<p>1 In the beginning God created the heavens and the earth, '
                  'and the earth was without form and void, and darkness was on '
                  'the face of the deep. 2 And the Spirit of God moved upon the '
                  'face of the waters, and God said, Let there be light. '
                  '3 And there was light.</p>',
            ),
          ],
        ),
      );

      // The numbers are loose in the text, so only the first was found.
      expect(result.bible!.books.single.chapters.single.verseCount, 1);
      expect(result.warnings.join(' '), contains('one long verse'));
    });
  });

  group('what it refuses to guess', () {
    test('a book with no numbered verses is left out and reported', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>',
            ),
            ('oba.xhtml', '<h1>Obadiah</h1><h2>1</h2><p>The vision.</p>'),
          ],
        ),
      );

      expect(result.bible!.books.map((book) => book.code), ['GEN']);
      expect(result.warnings.join(' '), contains('Obadiah'));
    });

    test('a paragraph that opens with a number is not therefore a verse', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2>'
                  '<p><sup>1</sup>In the beginning.</p>'
                  '<p>40 days later, nothing of the sort happened.</p>',
            ),
          ],
        ),
      );

      final chapter = result.bible!.books.single.chapters.single;
      // Verse 1 carries on into the second paragraph rather than a verse 40
      // being conjured out of a date.
      expect(chapter.verseCount, 1);
      expect(chapter.verseText(1), contains('40 days later'));
    });

    test('a book that is not in the canon is passed over', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2><p><sup>1</sup>In the beginning.</p>',
            ),
            (
              'x.xhtml',
              '<h1>Introduction by the Editor</h1><p>Some words.</p>',
            ),
          ],
        ),
      );

      expect(result.bible!.books.map((book) => book.code), ['GEN']);
    });

    test('something that is not an EPUB says so', () {
      final result = EpubImport.convert(
        Uint8List.fromList(utf8.encode('this is a text file')),
      );

      expect(result.ok, isFalse);
      expect(result.failure, contains('not an EPUB'));
    });

    test('an EPUB with no Bible in it says so', () {
      final result = EpubImport.convert(
        epub(
          title: 'A Novel',
          documents: [
            ('one.xhtml', '<h1>Chapter One</h1><p>It was a dark.</p>'),
          ],
        ),
      );

      expect(result.ok, isFalse);
      expect(result.failure, contains('No books of the Bible'));
    });
  });
}
