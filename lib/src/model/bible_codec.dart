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
      // This writes the single-stream format, which predates the extra
      // block attributes; a reader of it would not know to skip them.
      writeChapters(out, book.chapters, rich: false);
    }
    return out.take();
  }

  /// One book's chapters, and nothing else.
  ///
  /// This is what a `.bib` v2 file compresses one at a time, so that reading
  /// Genesis costs Genesis rather than the whole Bible. The bytes are
  /// exactly what [encode] writes after a book's code, which is what lets
  /// both formats share a decoder.
  static void writeChapters(
    ByteWriter out,
    List<Chapter> chapters, {
    bool rich = true,
  }) {
    out.varint(chapters.length);
    for (final chapter in chapters) {
      out
        ..varint(chapter.number)
        ..varint(chapter.blocks.length);
      for (final block in chapter.blocks) {
        out
          ..byte(block.style.index)
          ..byte(block.indent.clamp(0, 255))
          ..byte(
            (block.indentFirstLine ? _indentsFirstLine : 0) |
                (block.continuesParagraph ? _continues : 0),
          );
        // Version 1 of the encoding had neither, and files of it are read
        // by readers that would not know to skip them. They come before
        // the segment count, which is where the reader looks for them.
        if (rich) {
          out
            ..byte(block.level.clamp(0, 255))
            ..byte(block.align.index);
        }
        out.varint(block.segments.length);
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
      if (!rich) continue;
      // What the chapter is called, where the translation says.
      out.string(chapter.label);
      // What a verse is printed as, where that is not its number.
      out.varint(chapter.labels.length);
      for (final label in chapter.labels.entries) {
        out
          ..varint(label.key)
          ..string(label.value);
      }
      // Verses this translation leaves out on purpose.
      final omitted = chapter.omitted.toList()..sort();
      out.varint(omitted.length);
      var previous = 0;
      for (final verse in omitted) {
        out.varint(verse - previous);
        previous = verse;
      }
    }
  }

  static const int _indentsFirstLine = 0x01;
  static const int _continues = 0x02;

  /// The inverse of [writeChapters].
  ///
  /// [rich] says whether the extra block attributes and the chapter's
  /// labels and omissions are there to read — version 1 of the text
  /// encoding had none of them, and files of it are still read.
  static List<Chapter> readChapters(ByteReader input, {bool rich = true}) {
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
        final level = rich ? input.byte() : 0;
        final align = rich ? BlockAlign.fromIndex(input.byte()) : null;
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
            // A style added after this reader was written is read as a
            // paragraph rather than refused.
            style: styleIndex < BlockStyle.values.length
                ? BlockStyle.values[styleIndex]
                : BlockStyle.paragraph,
            indent: indent,
            indentFirstLine: flags & _indentsFirstLine != 0,
            continuesParagraph: flags & _continues != 0,
            level: level,
            align: align ?? BlockAlign.start,
            segments: segments,
          ),
        );
      }
      final noteCount = input.varint();
      final notes = <String>[
        for (var n = 0; n < noteCount; n++) input.string(),
      ];

      var chapterLabel = '';
      var labels = const <int, String>{};
      var omitted = const <int>{};
      if (rich) {
        chapterLabel = input.string();
        final labelCount = input.varint();
        if (labelCount > 0) {
          labels = {
            for (var l = 0; l < labelCount; l++) input.varint(): input.string(),
          };
        }
        final omittedCount = input.varint();
        if (omittedCount > 0) {
          final found = <int>{};
          var previous = 0;
          for (var o = 0; o < omittedCount; o++) {
            previous += input.varint();
            found.add(previous);
          }
          omitted = found;
        }
      }

      chapters.add(
        Chapter(
          number: number,
          blocks: blocks,
          notes: notes,
          labels: labels,
          omitted: omitted,
          label: chapterLabel,
        ),
      );
    }
    return chapters;
  }

  /// One book's chapters, packed on their own.
  static Uint8List encodeChapters(List<Chapter> chapters, {bool rich = true}) {
    final out = ByteWriter();
    writeChapters(out, chapters, rich: rich);
    return out.takeCopy();
  }

  /// Unpacks what [encodeChapters] wrote.
  static List<Chapter> decodeChapters(Uint8List data, {bool rich = true}) =>
      readChapters(ByteReader(data), rich: rich);

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
      // The single-stream format predates the extra block attributes.
      final chapters = readChapters(input, rich: false);
      // Unknown book codes are skipped rather than failing the whole file.
      final meta = BookMeta.lookup(code);
      if (meta != null) books.add(Book(meta: meta, chapters: chapters));
    }
    if (books.isEmpty) throw const FormatException('Bible file has no books');
    return Bible(translation: translation, books: books);
  }
}
