import 'dart:typed_data';

import 'bible.dart';
import 'book_meta.dart';
import 'byte_io.dart';

/// A compact binary encoding for a whole [Bible].
///
/// The app reads its bundled Scripture through this rather than JSON. Decoding
/// JSON of this size builds millions of short-lived maps and strings — around
/// 230 MB of peak heap in measurement — whereas this format is read in one
/// pass straight into the model, so allocation is roughly the size of what is
/// kept. It is also about a third smaller on disk and several times faster.
///
/// Layout, all integers LEB128 varints unless stated:
///
///     'OWB' u8:version
///     str:id str:name str:abbreviation str:license str:sourceUrl
///     n:books
///       str:code n:chapters
///         n:number n:blocks
///           u8:style u8:indent u8:flags n:segments
///             (flags bit 0: the first line is indented)
///             n:verse u8:startsVerse str:text
///           n:notes str:note...
///
/// Strings are a varint byte length followed by UTF-8.
class BibleCodec {
  const BibleCodec._();

  static const List<int> _magic = [0x4f, 0x57, 0x42]; // 'OWB'
  static const int version = 2;

  static Uint8List encode(Bible bible) {
    final out = ByteWriter()
      ..bytes(_magic)
      ..byte(version)
      ..string(bible.translation.id)
      ..string(bible.translation.name)
      ..string(bible.translation.abbreviation)
      ..string(bible.translation.license)
      ..string(bible.translation.sourceUrl)
      ..varint(bible.books.length);

    for (final book in bible.books) {
      out.string(book.code);
      writeChapters(out, book.chapters);
    }
    return out.take();
  }

  /// One book's chapters, and nothing else.
  ///
  /// This is what a `.bib` v2 file compresses one at a time, so that reading
  /// Genesis costs Genesis rather than the whole Bible. The bytes are
  /// exactly what [encode] writes after a book's code, which is what lets
  /// both formats share a decoder.
  static void writeChapters(ByteWriter out, List<Chapter> chapters) {
    out.varint(chapters.length);
    for (final chapter in chapters) {
      out
        ..varint(chapter.number)
        ..varint(chapter.blocks.length);
      for (final block in chapter.blocks) {
        out
          ..byte(block.style.index)
          ..byte(block.indent.clamp(0, 255))
          ..byte(block.indentFirstLine ? 1 : 0)
          ..varint(block.segments.length);
        for (final segment in block.segments) {
          out
            ..varint(segment.verse)
            ..byte(segment.startsVerse ? 1 : 0)
            ..string(segment.text);
        }
      }
      out.varint(chapter.notes.length);
      for (final note in chapter.notes) {
        out.string(note);
      }
    }
  }

  /// The inverse of [writeChapters].
  static List<Chapter> readChapters(ByteReader input) {
    final chapterCount = input.varint();
    final chapters = <Chapter>[];
    for (var c = 0; c < chapterCount; c++) {
      final number = input.varint();
      final blockCount = input.varint();
      final blocks = <Block>[];
      for (var i = 0; i < blockCount; i++) {
        final styleIndex = input.byte();
        final indent = input.byte();
        final flags = input.byte();
        final segmentCount = input.varint();
        final segments = <VerseSegment>[
          for (var s = 0; s < segmentCount; s++)
            VerseSegment(
              verse: input.varint(),
              startsVerse: input.byte() == 1,
              text: input.string(),
            ),
        ];
        blocks.add(
          Block(
            style: styleIndex < BlockStyle.values.length
                ? BlockStyle.values[styleIndex]
                : BlockStyle.paragraph,
            indent: indent,
            indentFirstLine: flags & 1 != 0,
            segments: segments,
          ),
        );
      }
      final noteCount = input.varint();
      final notes = <String>[
        for (var n = 0; n < noteCount; n++) input.string(),
      ];
      chapters.add(Chapter(number: number, blocks: blocks, notes: notes));
    }
    return chapters;
  }

  /// One book's chapters, packed on their own.
  static Uint8List encodeChapters(List<Chapter> chapters) {
    final out = ByteWriter();
    writeChapters(out, chapters);
    return out.takeCopy();
  }

  /// Unpacks what [encodeChapters] wrote.
  static List<Chapter> decodeChapters(Uint8List data) =>
      readChapters(ByteReader(data));

  /// Decodes [data]. Throws [FormatException] if it is not this format or was
  /// written by a newer version.
  static Bible decode(Uint8List data) {
    final input = ByteReader(data);
    for (final expected in _magic) {
      if (input.byte() != expected) {
        throw const FormatException('Not an OpenWord Bible file');
      }
    }
    final fileVersion = input.byte();
    if (fileVersion != version) {
      throw FormatException('Unsupported Bible format version $fileVersion');
    }

    final translation = TranslationInfo(
      id: input.string(),
      name: input.string(),
      abbreviation: input.string(),
      license: input.string(),
      sourceUrl: input.string(),
    );

    final bookCount = input.varint();
    final books = <Book>[];
    for (var b = 0; b < bookCount; b++) {
      final code = input.string();
      final chapters = readChapters(input);
      // Unknown book codes are skipped rather than failing the whole file.
      final meta = BookMeta.lookup(code);
      if (meta != null) books.add(Book(meta: meta, chapters: chapters));
    }
    if (books.isEmpty) throw const FormatException('Bible file has no books');
    return Bible(translation: translation, books: books);
  }
}
