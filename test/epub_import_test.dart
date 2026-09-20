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
