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
  (String name, String xhtml)? nav,
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
  // The navigation document, which most EPUBs put in the reading order.
  if (nav != null) {
    manifest.write(
      '<item id="nav" href="${nav.$1}" properties="nav" '
      'media-type="application/xhtml+xml"/>',
    );
    spine.write('<itemref idref="nav"/>');
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
  if (nav != null) {
    archive.addFile(_file('OEBPS/${nav.$1}', _page(nav.$2)));
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
  _theEditionItself();
  _aRowOfLinksIsNotScripture();
  _theShapeOfARealEdition();
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

    test('the running head before verse 1 is not read as Scripture', () {
      // The ESV repeats the book's name inside the paragraph that opens
      // every chapter, right before the chapter marker — not just the first,
      // where the verse count happens to make it easy to spot.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1>'
                  '<p><span class="book-name">GENESIS</span>'
                  '<b class="chapter-num" id="v01001001-1">1:1\u00a0</b>'
                  'In the beginning God created the heavens.'
                  '<b class="verse-num">2\u00a0</b>The earth was without '
                  'form.</p>'
                  '<p><span class="book-name">GENESIS</span>'
                  '<b class="chapter-num" id="v01002001-1">2:1\u00a0</b>'
                  'Thus the heavens and the earth were finished.</p>'
                  '<p><span class="book-name">GENESIS</span>'
                  '<b class="chapter-num" id="v01003001-1">3:1\u00a0</b>'
                  'Now the serpent was more crafty.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.chapterCount, 3);
      expect(
        book.chapter(1)!.verseText(1),
        'In the beginning God created the heavens.',
      );
      expect(
        book.chapter(2)!.verseText(1),
        'Thus the heavens and the earth were finished.',
      );
      expect(book.chapter(3)!.verseText(1), 'Now the serpent was more crafty.');

      for (var number = 1; number <= 3; number++) {
        for (final block in book.chapter(number)!.blocks) {
          for (final segment in block.segments) {
            expect(
              segment.text,
              isNot(contains('GENESIS')),
              reason: 'the running head survived into chapter $number',
            );
          }
        }
      }
    });

    test('a heading before a chapter break heads the chapter it opens', () {
      // "The Flood Subsides" is printed before Genesis 8:1, while the page
      // is still in chapter 7. It belongs to 8.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1>'
                  '<p><b class="chapter-num">7:24\u00a0</b>'
                  'And the waters prevailed on the earth 150 days.</p>'
                  '<h3>The Flood Subsides</h3>'
                  '<p><b class="chapter-num">8:1\u00a0</b>'
                  'But God remembered Noah.</p>',
            ),
          ],
        ),
      );

      final book = result.bible!.books.single;
      expect(book.chapterCount, 2);

      String headingsIn(int chapter) => book
          .chapter(chapter)!
          .blocks
          .where((block) => block.style == BlockStyle.heading)
          .map((block) => block.segments.first.text)
          .join('|');

      // Chapter 7 here ends with its last verse and nothing after it.
      expect(headingsIn(1), isEmpty);
      expect(headingsIn(2), 'The Flood Subsides');
      expect(book.chapter(2)!.verseText(1), 'But God remembered Noah.');
    });

    test('a section heading marked only by its class is still a heading', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>2</h2>'
                  '<p class="section-heading">The Creation of Man</p>'
                  '<p><sup>4</sup>These are the generations.</p>',
            ),
          ],
        ),
      );

      final chapter = result.bible!.books.single.chapters.single;
      expect(
        chapter.blocks.first.style,
        BlockStyle.heading,
        reason: 'the heading should come before the verse it heads',
      );
      expect(chapter.blocks.first.segments.first.text, 'The Creation of Man');
    });

    test('poetry keeps the indent level its class gives it', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'psa.xhtml',
              '<h1>Psalms</h1><h2>1</h2>'
                  '<p class="line q1"><span class="verse">1</span>'
                  'Blessed is the man</p>'
                  '<p class="line q2">who walks not in the counsel '
                  'of the wicked;</p>',
            ),
          ],
        ),
      );

      final blocks = result.bible!.books.single.chapters.single.blocks
          .where((block) => block.style == BlockStyle.poetry)
          .toList();
      expect(blocks, hasLength(2));
      expect(blocks[0].indent, 1);
      expect(blocks[1].indent, 2);
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

/// A book's landing page lists the chapters under it, and an edition that
/// puts one in the reading order had it read as the book's first verse.
void _aRowOfLinksIsNotScripture() {
  group('a page that lists a book\'s chapters', () {
    const landing =
        '<h1 class="book-title">1 John</h1>'
        '<p class="chapter-list">'
        '<a href="1jn1.xhtml">1 John 1</a> &#183; '
        '<a href="1jn2.xhtml">1 John 2</a> &#183; '
        '<a href="1jn3.xhtml">1 John 3</a></p>';
    const chapterOne =
        '<h1>1 John</h1>'
        '<p><b class="chapter-num" id="v62001001-1">1:1&#160;</b>'
        'That which was from the beginning, which we have heard.'
        '<b class="verse-num" id="v62001002-1">2&#160;</b>'
        'And the life was manifested.</p>';
    const chapterTwo =
        '<p><b class="chapter-num" id="v62002001-1">2&#160;</b>'
        'My little children, these things I write unto you.</p>';

    late Bible bible;

    setUpAll(() {
      final result = EpubImport.convert(
        epub(
          documents: [
            ('1jn.xhtml', landing),
            ('1jn1.xhtml', chapterOne),
            ('1jn2.xhtml', chapterTwo),
          ],
        ),
      );
      expect(result.failure, isNull, reason: result.failure ?? '');
      bible = result.bible!;
    });

    test('is not the first verse of the book', () {
      // The "1" of "1 John 1" was taken for verse 1 — a paragraph opening
      // with a number is one of the ways an edition numbers a verse — and
      // the rest of the line became its text.
      final one = bible.bookByCode('1JN')!.chapter(1)!;
      expect(
        one.verseText(1),
        'That which was from the beginning, which we have heard.',
      );
      expect(
        one.blocks
            .expand((block) => block.segments)
            .map((segment) => Markup.strip(segment.text))
            .join('\n'),
        isNot(contains('1 John 2')),
      );
    });

    test('and the chapters it pointed at are all there', () {
      final book = bible.bookByCode('1JN')!;
      expect(book.chapters, hasLength(2));
      expect(
        book.chapter(2)!.verseText(1),
        'My little children, these things I write unto you.',
      );
    });
  });

  group('a navigation footer at the foot of a book', () {
    // Every book's own document ends with one, so it is not the
    // navigation document the manifest names and nothing declares it.
    const footer =
        '<p><a href="index.xhtml">ESV</a></p>'
        '<p><a href="ot.xhtml">The Old Testament</a></p>'
        '<p><a href="nt.xhtml">The New Testament</a></p>'
        '<p><a href="#">Show Last Hilite</a></p>'
        '<p>ESV &#183; The Old Testament</p>'
        '<p><a href="gen.xhtml">Genesis</a> &#183; '
        '<a href="exo.xhtml">Exodus</a> &#183; '
        '<a href="lev.xhtml">Leviticus</a></p>';

    test('is not the last verse of that book', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              '2pe.xhtml',
              '<h1>2 Peter</h1>'
                  '<p><b class="chapter-num" id="v61003001-1">3:1&#160;</b>'
                  'This is now the second letter.'
                  '<b class="verse-num" id="v61003018-1">18&#160;</b>'
                  'But grow in the grace and knowledge. Amen.</p>'
                  '$footer',
            ),
          ],
        ),
      );
      final chapter = result.bible!.bookByCode('2PE')!.chapter(1)!;
      expect(
        chapter.verseText(18),
        'But grow in the grace and knowledge. Amen.',
      );
      // Every line of it: the links one to a paragraph, the row of book
      // names, and the plain label between them that carries no link at
      // all to give it away.
      final everything = chapter.blocks
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
    });

    test('and Scripture after one is Scripture again', () {
      // A footer between two books must not swallow the book that follows.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'both.xhtml',
              '<h1>2 Peter</h1>'
                  '<p><b class="chapter-num" id="v61003001-1">3:1&#160;</b>'
                  'This is now the second letter.</p>'
                  '$footer'
                  '<h1>1 John</h1>'
                  '<p><b class="chapter-num" id="v62001001-1">1:1&#160;</b>'
                  'That which was from the beginning.</p>'
                  '<p>And these things we write, that your joy may be full.</p>',
            ),
          ],
        ),
      );
      final john = result.bible!.bookByCode('1JN')!.chapter(1)!;
      expect(john.verseText(1), contains('That which was from the beginning.'));
      // Including a paragraph of its own that numbers nothing, which is a
      // continuation of the verse before it and not more footer.
      expect(john.verseText(1), contains('your joy may be full'));
    });
  });

  group('but a verse carrying links is still a verse', () {
    test('footnote markers do not make a paragraph into a menu', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2>'
                  '<p><sup>1</sup>In the beginning God created the heavens'
                  '<a class="noteref" href="#f1">a</a> and the earth'
                  '<a class="noteref" href="#f2">b</a>.'
                  '<sup>2</sup>And the earth was without form'
                  '<a class="noteref" href="#f3">c</a>.</p>',
            ),
          ],
        ),
      );
      final chapter = result.bible!.bookByCode('GEN')!.chapter(1)!;
      expect(
        chapter.verseText(1),
        'In the beginning God created the heavens and the earth.',
      );
      expect(chapter.verseText(2), 'And the earth was without form.');
    });

    test('nor does an edition that hangs a link on the whole verse', () {
      // Some hang one on every verse — to a commentary, to a note — and a
      // verse wrapped in a link end to end is still a verse.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2>'
                  '<p><sup>1</sup>'
                  '<a href="notes.xhtml#g1">In the beginning God created the '
                  'heavens and the earth.</a></p>',
            ),
          ],
        ),
      );
      expect(
        result.bible!.bookByCode('GEN')!.chapter(1)!.verseText(1),
        'In the beginning God created the heavens and the earth.',
      );
    });

    test('nor do verse numbers an edition links to itself', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1><h2>1</h2>'
                  '<p>'
                  '<a class="verse-num" href="#v1" id="v1">1</a>'
                  'In the beginning God created.'
                  '<a class="verse-num" href="#v2" id="v2">2</a>'
                  'And the earth was without form.</p>',
            ),
          ],
        ),
      );
      final chapter = result.bible!.bookByCode('GEN')!.chapter(1)!;
      expect(chapter.verseText(1), 'In the beginning God created.');
      expect(chapter.verseText(2), 'And the earth was without form.');
    });
  });
}

/// The four faults an imported ESV showed on a phone, each reproduced from
/// the shape of markup that caused it. The ESV prints a chapter's number
/// inside the paragraph of its first verse and does not print that verse's
/// own number, which is what most of this turns on.
void _theShapeOfARealEdition() {
  group('an edition that numbers its chapters inside the text', () {
    const genesis =
        '<h2>Genesis</h2>'
        '<h3 class="section-heading">The Creation of the World</h3>'
        '<p><b class="chapter-num" id="v01001001-1">1:1&#160;</b>'
        'In the beginning, God created the heavens and the earth.'
        '<b class="verse-num" id="v01001002-1">2&#160;</b>'
        'The earth was without form and void.</p>'
        '<h3 class="section-heading">The Seventh Day, God Rests</h3>'
        // The chapter number alone: the 1 of its first verse lives in the id.
        '<p><b class="chapter-num" id="v01002001-1">2&#160;</b>'
        'Thus the heavens and the earth were finished.'
        '<b class="verse-num" id="v01002002-1">2&#160;</b>'
        'And on the seventh day God finished his work.</p>'
        // And again with an id that says nothing, so only the chapter is
        // known and verse 1 has to be taken as read.
        '<p><b class="chapter-num" id="c3">3&#160;</b>'
        'Now the serpent was more crafty than any other beast.</p>';

    const psalms =
        '<h2>Psalms</h2>'
        '<h3 class="section-heading">The Way of the Righteous</h3>'
        '<p class="line"><b class="chapter-num" id="v19001001-1">1:1&#160;</b>'
        'Blessed is the man who walks not in the counsel of the wicked</p>'
        '<h3 class="section-heading">The Reign of the Anointed</h3>'
        '<p class="line"><b class="chapter-num" id="v19002001-1">2:1&#160;</b>'
        'Why do the nations rage</p>'
        '<p class="indent">and the peoples plot in vain, on and on and on '
        'and on and on and on and on and on and on and on</p>'
        // Psalm 3's heading and superscription, both of which stand ahead
        // of anything that says the psalm has changed.
        '<h3 class="section-heading">Save Me, O My God</h3>'
        '<p class="psalm-title">A Psalm of David, when he fled from '
        'Absalom his son.</p>'
        '<p class="line"><b class="chapter-num" id="v19003001-1">3:1&#160;</b>'
        'O LORD, how many are my foes!</p>';

    // The table of contents, which the manifest marks as the navigation
    // document, and a copyright page, which nothing marks as anything.
    const contents =
        '<h1>Table of Contents</h1>'
        '<p><a href="gen.xhtml">Genesis</a> &#183; '
        '<a href="psa.xhtml">Psalms</a></p>'
        '<p>ESV &#183; The Old Testament &#183; BookNAME</p>';

    const backMatter =
        '<p>Copyright 2001. All rights reserved.</p>'
        '<p>Published by arrangement.</p>';

    late Bible bible;

    setUpAll(() {
      final result = EpubImport.convert(
        epub(
          documents: [
            ('gen.xhtml', genesis),
            ('psa.xhtml', psalms),
            ('rights.xhtml', backMatter),
          ],
          nav: ('toc.xhtml', contents),
        ),
      );
      expect(result.failure, isNull, reason: result.failure ?? '');
      bible = result.bible!;
    });

    Chapter chapterOf(String code, int number) => bible.books
        .firstWhere((book) => book.code == code)
        .chapters[number - 1];

    /// A block's text, markers taken out.
    String plain(Block block) => block.segments
        .map((segment) => Markup.strip(segment.text))
        .join(' ')
        .trim();

    String textOf(Chapter chapter, int verse) => chapter.blocks
        .expand((block) => block.segments)
        .where((segment) => segment.verse == verse)
        .map((segment) => Markup.strip(segment.text))
        .join()
        .trim();

    test('a chapter keeps its first verse', () {
      // Genesis 2:1 was dropped outright: the marker printed "2" and the
      // verse it opened was only ever in the id, so nothing opened a verse
      // and the text was thrown away as a running head.
      expect(
        textOf(chapterOf('GEN', 2), 1),
        'Thus the heavens and the earth were finished.',
      );
      expect(
        textOf(chapterOf('GEN', 2), 2),
        'And on the seventh day God finished his work.',
      );
    });

    test('and keeps it where only the chapter can be known', () {
      expect(
        textOf(chapterOf('GEN', 3), 1),
        'Now the serpent was more crafty than any other beast.',
      );
    });

    test("a psalm's heading and superscription open their own psalm", () {
      final two = chapterOf('PSA', 2);
      final three = chapterOf('PSA', 3);

      expect(
        two.blocks.map((block) => plain(block)),
        isNot(contains(contains('Save Me'))),
        reason: "Psalm 3's heading was landing at the end of Psalm 2",
      );
      expect(
        two.blocks.map((block) => plain(block)),
        isNot(contains(contains('Absalom'))),
      );

      expect(plain(three.blocks.first), 'Save Me, O My God');
      // Gathered while Psalm 2's last verse was still open, and it must
      // not carry that verse across with it.
      expect(three.blocks.first.segments.single.verse, 0);
      expect(three.blocks.first.style, BlockStyle.heading);
      expect(three.blocks[1].style, BlockStyle.descriptiveTitle);
      expect(plain(three.blocks[1]), contains('Absalom'));
      expect(textOf(three, 1), 'O LORD, how many are my foes!');
    });

    test('the second line of a couplet is a line of verse', () {
      // Read as prose it took a paragraph's first-line indent and wrapped
      // back to the margin, so the couplet looked like a poetry line that
      // had lost its indent.
      final lines = chapterOf(
        'PSA',
        2,
      ).blocks.where((block) => plain(block).startsWith('and the peoples'));
      expect(lines, hasLength(1));
      expect(lines.first.style, BlockStyle.poetry);
      expect(lines.first.indent, greaterThan(1));
    });

    test('the table of contents is not Scripture', () {
      final everything = bible.books
          .expand((book) => book.chapters)
          .expand((chapter) => chapter.blocks)
          .map((block) => plain(block))
          .join('\n');
      expect(everything, isNot(contains('Table of Contents')));
      expect(everything, isNot(contains('BookNAME')));
      expect(everything, isNot(contains('The Old Testament')));
    });

    test('nor is a copyright page with nothing numbered in it', () {
      // It followed Psalms in the spine, so every paragraph of it used to
      // be read as a continuation of the last verse left open.
      final psalmThree = chapterOf('PSA', 3);
      expect(
        psalmThree.blocks.map((block) => plain(block)).join('\n'),
        isNot(contains('All rights reserved')),
      );
      expect(textOf(psalmThree, 1), 'O LORD, how many are my foes!');
    });
  });
}

/// The shapes the ESV Classic Reference Bible actually uses, taken from the
/// file rather than guessed at from a screenshot. Every one of these was a
/// fault found by importing it.
void _theEditionItself() {
  group('an edition that hides its own apparatus', () {
    test('a div the edition hides is not Scripture', () {
      // The whole navigation apparatus — every book, every chapter, and
      // the template text around them — sits in one of these at the foot
      // of every book's file. Nothing is more authoritative about it than
      // the edition saying so itself.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'b61.00.2-Peter.text.xhtml',
              '<h1>2 Peter</h1>'
                  '<p><span class="chapter-num"> 3 </span>'
                  'But grow in the grace and knowledge.</p>'
                  '<div class="hide">'
                  '<div id="tc"><p class="nav-header">ESV</p>'
                  '<p class="nav"><a class="pop-link" '
                  'onclick="nav.show(\'ot\')">The Old Testament</a></p>'
                  '<p class="nav"><a class="pop-link" '
                  'onclick="lastHilite()">Show Last Hilite</a></p></div>'
                  '<div id="this-book-ot"><p class="nav-header">ESV &#183; '
                  '<span id="bookname-ot">BookNAME</span></p>'
                  '<p class="nav" id="chapters-ot">chAPTErs</p></div>'
                  '</div>',
            ),
          ],
        ),
      );
      final chapter = result.bible!.bookByCode('2PE')!.chapter(1)!;
      final everything = chapter.blocks
          .expand((block) => block.segments)
          .map((segment) => Markup.strip(segment.text))
          .join('\n');
      expect(everything, contains('But grow in the grace'));
      for (final furniture in const [
        'ESV',
        'The Old Testament',
        'Show Last Hilite',
        'BookNAME',
        'chAPTErs',
      ]) {
        expect(everything, isNot(contains(furniture)), reason: furniture);
      }
    });

    test('and neither is anything else it hides', () {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'gen.xhtml',
              '<h1>Genesis</h1>'
                  '<p><span class="chapter-num"> 1 </span>In the beginning.</p>'
                  '<p hidden="hidden">Hidden by attribute.</p>'
                  '<p style="display: none">Hidden by style.</p>'
                  '<p style="visibility:hidden">Hidden too.</p>',
            ),
          ],
        ),
      );
      final everything = result.bible!
          .bookByCode('GEN')!
          .chapter(1)!
          .blocks
          .expand((block) => block.segments)
          .map((segment) => Markup.strip(segment.text))
          .join('\n');
      expect(everything, contains('In the beginning.'));
      expect(everything, isNot(contains('Hidden')));
    });
  });

  group('a book is identified by more than its file name', () {
    test('a numbered book keeps its number', () {
      // `b62.00.1-John.text.xhtml` holds three things: where the file
      // sorts, what book it is, and which part of the apparatus. Reading
      // all three as the name made "1-John" into John, and the whole of
      // 1, 2 and 3 John went into the Gospel — silently, with nothing
      // missing and nothing to show for it.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'b43.00.John.text.xhtml',
              '<p><span class="chapter-num"> 1 </span>'
                  'In the beginning was the Word.</p>',
            ),
            (
              'b62.00.1-John.text.xhtml',
              '<p><span class="chapter-num"> 1 </span>'
                  'That which was from the beginning.</p>',
            ),
            (
              'b63.00.2-John.text.xhtml',
              '<p><span class="chapter-num"> 1 </span>'
                  'The elder to the elect lady.</p>',
            ),
          ],
        ),
      );
      final bible = result.bible!;
      expect(
        bible.bookByCode('JHN')?.chapter(1)?.verseText(1),
        'In the beginning was the Word.',
      );
      expect(
        bible.bookByCode('1JN')?.chapter(1)?.verseText(1),
        'That which was from the beginning.',
      );
      expect(
        bible.bookByCode('2JN')?.chapter(1)?.verseText(1),
        'The elder to the elect lady.',
      );
      expect(bible.bookByCode('JHN')!.chapters, hasLength(1));
    });

    test('and a packed id overrules a file name that is wrong', () {
      // `v62001001` is the sixty-second book of the canon whatever the
      // file is called, and an anchor is better evidence than a name.
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'mystery.xhtml',
              '<h1>John</h1>'
                  '<p id="v62001001"><span class="chapter-num"> 1 </span>'
                  'That which was from the beginning.</p>',
            ),
          ],
        ),
      );
      expect(
        result.bible!.bookByCode('1JN')?.chapter(1)?.verseText(1),
        'That which was from the beginning.',
      );
    });
  });

  group('the formatting this edition actually marks', () {
    late Chapter psalm;
    late Chapter john;

    setUpAll(() {
      final result = EpubImport.convert(
        epub(
          documents: [
            (
              'b19.00.Psalm.text.xhtml',
              '<header><p class="heading"><span>The Reign of the '
                  'Anointed</span></p></header>'
                  '<p class="line"><span class="chapter-num"> 2 </span>'
                  'Why do the nations rage</p>'
                  '<p class="line-indent">and the peoples plot in vain?</p>'
                  '<p class="line"><span class="verse-num">2</span>'
                  'Serve the L<span class="smallcap">ORD</span> with fear. '
                  '<span class="selah">Selah</span></p>',
            ),
            (
              'b43.00.John.text.xhtml',
              '<p class="no-indent"><span class="chapter-num"> 3 </span>'
                  'Jesus answered, <span class="woc">&#8220;Truly, truly, '
                  'I say to you.&#8221;</span> And he went.</p>',
            ),
          ],
        ),
      );
      psalm = result.bible!.bookByCode('PSA')!.chapter(1)!;
      john = result.bible!.bookByCode('JHN')!.chapter(1)!;
    });

    test('a heading over a chapter that has not opened yet is kept', () {
      // It is printed before the paragraph the chapter number is in, so
      // no chapter is open when it arrives. Every book was losing the
      // heading over its first chapter.
      expect(psalm.blocks.first.style, BlockStyle.heading);
      expect(
        Markup.strip(psalm.blocks.first.segments.first.text),
        'The Reign of the Anointed',
      );
    });

    test('a couplet is two lines of verse, the second indented', () {
      final lines = psalm.blocks
          .where((block) => block.style == BlockStyle.poetry)
          .toList();
      expect(lines, hasLength(greaterThanOrEqualTo(2)));
      expect(lines[0].indent, 1);
      expect(lines[1].indent, greaterThan(1));
      expect(
        Markup.strip(lines[1].segments.first.text),
        'and the peoples plot in vain?',
      );
    });

    test('the divine name and Selah are marked', () {
      final second = psalm.blocks
          .expand((block) => block.segments)
          .where((segment) => segment.verse == 2)
          .map((segment) => segment.text)
          .join();
      expect(second, contains(Markup.divineStart));
      expect(second, contains(Markup.selahStart));
      expect(psalm.verseText(2), 'Serve the LORD with fear. Selah');
    });

    test('and what Jesus says is red-lettered', () {
      final verse = john.blocks
          .expand((block) => block.segments)
          .map((segment) => segment.text)
          .join();
      expect(verse, contains(Markup.wjStart));
      expect(verse, contains(Markup.wjEnd));
      expect(
        john.verseText(1),
        'Jesus answered, “Truly, truly, I say to you.” And he went.',
      );
    });
  });
}
