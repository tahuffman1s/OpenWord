import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One passage a cross-reference points at.
///
/// A reference is often a run of verses — "Proverbs 8:22-24" — so it carries
/// a first and a last verse rather than one number.
class XrefRange {
  const XrefRange({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.endVerse,
  });

  /// Index into the sixty-six books of the Protestant canon.
  final int book;
  final int chapter;
  final int verse;
  final int endVerse;

  bool get isRange => endVerse > verse;
}

/// The references hanging off one phrase of a verse.
///
/// The Treasury of Scripture Knowledge anchors its references to the words
/// they belong to, not to the verse as a whole, which is what makes a long
/// list of them readable: each is under the phrase that prompted it.
class XrefAnchor {
  const XrefAnchor({required this.phrase, required this.ranges});

  final String phrase;
  final List<XrefRange> ranges;
}

/// Every anchor of one verse.
class XrefEntry {
  XrefEntry({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.anchors,
  });

  final int book;
  final int chapter;
  final int verse;
  final List<XrefAnchor> anchors;

  int get key => XrefCodec.keyOf(book, chapter, verse);

  int get passages {
    var total = 0;
    for (final anchor in anchors) {
      total += anchor.ranges.length;
    }
    return total;
  }
}

/// The binary form the cross-references ship in.
///
/// Three hundred thousand references is too many for JSON — decoding it
/// builds a short-lived object per number. This is the same approach the
/// Scripture itself takes: LEB128 varints, deltas where the numbers climb,
/// and a table of the phrases, which repeat endlessly ("the LORD", "God").
///
///     'OWX' version=1
///     varint phraseCount, then each phrase as length-prefixed UTF-8
///     varint entryCount
///     per entry: delta of the verse key, varint anchorCount
///       per anchor: varint phrase index, varint rangeCount
///         per range: varint book, chapter, verse, endVerse - verse
class XrefCodec {
  const XrefCodec._();

  static const List<int> magic = [0x4f, 0x57, 0x58]; // 'OWX'
  static const int version = 1;

  /// The `.bib` chunk a translation's own cross-references travel in.
  /// Ancillary, so a file gains them without becoming unreadable to
  /// anything written before them.
  static const String chunkTag = 'xref';

  /// Unpacks a set as it is stored — gzipped — or throws. Free of Flutter,
  /// so the tools can read one too.
  static List<XrefEntry> unpack(Uint8List bytes) =>
      decode(Uint8List.fromList(const GZipDecoder().decodeBytes(bytes)));

  /// Verses are looked up by one number rather than three.
  static int keyOf(int book, int chapter, int verse) =>
      (book * 1000 + chapter) * 1000 + verse;

  static Uint8List encode(List<XrefEntry> entries) {
    final phrases = <String, int>{};
    for (final entry in entries) {
      for (final anchor in entry.anchors) {
        phrases.putIfAbsent(anchor.phrase, () => phrases.length);
      }
    }

    final out = _Writer()
      ..bytes(magic)
      ..byte(version)
      ..varint(phrases.length);
    for (final phrase in phrases.keys) {
      out.string(phrase);
    }

    out.varint(entries.length);
    var previous = 0;
    for (final entry in entries) {
      out.varint(entry.key - previous);
      previous = entry.key;
      out.varint(entry.anchors.length);
      for (final anchor in entry.anchors) {
        out.varint(phrases[anchor.phrase]!);
        out.varint(anchor.ranges.length);
        for (final range in anchor.ranges) {
          out
            ..varint(range.book)
            ..varint(range.chapter)
            ..varint(range.verse)
            ..varint(range.endVerse - range.verse);
        }
      }
    }
    return out.take();
  }

  static List<XrefEntry> decode(Uint8List bytes) {
    final input = _Reader(bytes);
    for (final byte in magic) {
      if (input.byte() != byte) {
        throw const FormatException('not a cross-reference asset');
      }
    }
    final found = input.byte();
    if (found != version) {
      throw FormatException(
        'cross-references are version $found, not $version',
      );
    }

    final phrases = List<String>.generate(
      input.varint(),
      (_) => input.string(),
    );
    final entries = <XrefEntry>[];
    final count = input.varint();
    var key = 0;
    for (var i = 0; i < count; i++) {
      key += input.varint();
      final anchors = <XrefAnchor>[];
      final anchorCount = input.varint();
      for (var a = 0; a < anchorCount; a++) {
        final phrase = phrases[input.varint()];
        final ranges = <XrefRange>[];
        final rangeCount = input.varint();
        for (var r = 0; r < rangeCount; r++) {
          final book = input.varint();
          final chapter = input.varint();
          final verse = input.varint();
          ranges.add(
            XrefRange(
              book: book,
              chapter: chapter,
              verse: verse,
              endVerse: verse + input.varint(),
            ),
          );
        }
        anchors.add(XrefAnchor(phrase: phrase, ranges: ranges));
      }
      entries.add(
        XrefEntry(
          book: key ~/ 1000000,
          chapter: (key ~/ 1000) % 1000,
          verse: key % 1000,
          anchors: anchors,
        ),
      );
    }
    return entries;
  }
}

class _Writer {
  final BytesBuilder _out = BytesBuilder(copy: false);

  void byte(int value) => _out.addByte(value);
  void bytes(List<int> value) => _out.add(value);

  void varint(int value) {
    var rest = value;
    while (rest >= 0x80) {
      _out.addByte((rest & 0x7f) | 0x80);
      rest >>= 7;
    }
    _out.addByte(rest);
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    varint(encoded.length);
    _out.add(encoded);
  }

  Uint8List take() => _out.takeBytes();
}

class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  int _at = 0;

  int byte() => _bytes[_at++];

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = _bytes[_at++];
      result |= (byte & 0x7f) << shift;
      if (byte < 0x80) return result;
      shift += 7;
    }
  }

  String string() {
    final length = varint();
    final value = utf8.decode(Uint8List.sublistView(_bytes, _at, _at + length));
    _at += length;
    return value;
  }
}
