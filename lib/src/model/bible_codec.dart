import 'dart:convert';
import 'dart:typed_data';

import 'bible.dart';
import 'book_meta.dart';

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
///           u8:style u8:indent n:segments
///             n:verse u8:startsVerse str:text
///           n:notes str:note...
///
/// Strings are a varint byte length followed by UTF-8.
class BibleCodec {
  const BibleCodec._();

  static const List<int> _magic = [0x4f, 0x57, 0x42]; // 'OWB'
  static const int version = 1;

  static Uint8List encode(Bible bible) {
    final out = _Writer()
      ..bytes(_magic)
      ..byte(version)
      ..string(bible.translation.id)
      ..string(bible.translation.name)
      ..string(bible.translation.abbreviation)
      ..string(bible.translation.license)
      ..string(bible.translation.sourceUrl)
      ..varint(bible.books.length);

    for (final book in bible.books) {
      out
        ..string(book.code)
        ..varint(book.chapters.length);
      for (final chapter in book.chapters) {
        out
          ..varint(chapter.number)
          ..varint(chapter.blocks.length);
        for (final block in chapter.blocks) {
          out
            ..byte(block.style.index)
            ..byte(block.indent.clamp(0, 255))
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
    return out.take();
  }

  /// Decodes [data]. Throws [FormatException] if it is not this format or was
  /// written by a newer version.
  static Bible decode(Uint8List data) {
    final input = _Reader(data);
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
      final chapterCount = input.varint();
      final chapters = <Chapter>[];
      for (var c = 0; c < chapterCount; c++) {
        final number = input.varint();
        final blockCount = input.varint();
        final blocks = <Block>[];
        for (var i = 0; i < blockCount; i++) {
          final styleIndex = input.byte();
          final indent = input.byte();
          final segmentCount = input.varint();
          final segments = <VerseSegment>[];
          for (var s = 0; s < segmentCount; s++) {
            segments.add(
              VerseSegment(
                verse: input.varint(),
                startsVerse: input.byte() == 1,
                text: input.string(),
              ),
            );
          }
          blocks.add(
            Block(
              style: styleIndex < BlockStyle.values.length
                  ? BlockStyle.values[styleIndex]
                  : BlockStyle.paragraph,
              indent: indent,
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
      // Unknown book codes are skipped rather than failing the whole file.
      if (BookMeta.lookup(code) != null) {
        books.add(Book(meta: BookMeta.lookup(code)!, chapters: chapters));
      }
    }
    if (books.isEmpty) throw const FormatException('Bible file has no books');
    return Bible(translation: translation, books: books);
  }
}

class _Writer {
  Uint8List _buffer = Uint8List(1 << 20);
  int _length = 0;

  void _ensure(int extra) {
    if (_length + extra <= _buffer.length) return;
    var size = _buffer.length * 2;
    while (size < _length + extra) {
      size *= 2;
    }
    _buffer = Uint8List(size)..setRange(0, _length, _buffer);
  }

  void byte(int value) {
    _ensure(1);
    _buffer[_length++] = value & 0xff;
  }

  void bytes(List<int> values) {
    _ensure(values.length);
    _buffer.setRange(_length, _length + values.length, values);
    _length += values.length;
  }

  void varint(int value) {
    var remaining = value;
    while (remaining >= 0x80) {
      byte((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    byte(remaining);
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    varint(encoded.length);
    bytes(encoded);
  }

  Uint8List take() => Uint8List.sublistView(_buffer, 0, _length);
}

class _Reader {
  _Reader(this._data);

  final Uint8List _data;
  int _offset = 0;

  int byte() {
    if (_offset >= _data.length) {
      throw const FormatException('Bible file ended early');
    }
    return _data[_offset++];
  }

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final part = byte();
      result |= (part & 0x7f) << shift;
      if (part & 0x80 == 0) return result;
      shift += 7;
    }
  }

  String string() {
    final length = varint();
    if (_offset + length > _data.length) {
      throw const FormatException('Bible file ended early');
    }
    final value = utf8.decode(
      Uint8List.sublistView(_data, _offset, _offset + length),
    );
    _offset += length;
    return value;
  }
}
