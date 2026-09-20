import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'bible.dart';
import 'bible_codec.dart';

/// The `.bib` file: one translation, whole, in one file.
///
/// The app already had a compact binary encoding for a Bible — see
/// [BibleCodec] — but only as an asset built at compile time. A `.bib` file
/// wraps that encoding in a small header so that a file found on a disk can
/// say what it is and what is in it without being decoded:
///
///     offset  size  meaning
///     0       3     'BIB'
///     3       1     format version, 1
///     4       1     flags; bit 0 set means the payload is gzipped
///     5       2     length of the metadata, big-endian
///     7       …     metadata: UTF-8 JSON, the fields of TranslationInfo
///     …       …     payload: the BibleCodec encoding of the whole Bible
///
/// The metadata is held in the clear so that a shelf of translations can be
/// listed by reading a few dozen bytes of each. It repeats what the payload
/// says; where the two disagree the payload wins, since that is what will be
/// read.
class BibFile {
  const BibFile._();

  static const String extension = '.bib';
  static const List<int> magic = [0x42, 0x49, 0x42]; // 'BIB'
  static const int version = 1;

  /// Set when the payload is gzipped, which it always is in practice: the
  /// bit exists so a reader can be written without a gzip implementation.
  static const int gzipFlag = 0x01;

  static const int _headerLength = 7;

  /// Everything but the payload, for listing what a file holds.
  static const int maxMetadataLength = 0xffff;

  /// The most of a file that ever needs reading to say what it holds.
  static const int maxHeaderLength = _headerLength + maxMetadataLength;

  static Uint8List encode(Bible bible, {bool compress = true}) {
    final payload = BibleCodec.encode(bible);
    final body = compress
        ? Uint8List.fromList(const GZipEncoder().encodeBytes(payload))
        : payload;

    final metadata = utf8.encode(jsonEncode(_metadataOf(bible.translation)));
    if (metadata.length > maxMetadataLength) {
      throw const BibFormatException('the metadata is absurdly long');
    }

    final out = BytesBuilder(copy: false)
      ..add(magic)
      ..addByte(version)
      ..addByte(compress ? gzipFlag : 0)
      ..addByte((metadata.length >> 8) & 0xff)
      ..addByte(metadata.length & 0xff)
      ..add(metadata)
      ..add(body);
    return out.takeBytes();
  }

  /// What the file says it holds, read from the header alone.
  static TranslationInfo readInfo(Uint8List bytes) {
    final metadata = _metadata(bytes);
    return TranslationInfo(
      id: _string(metadata, 'id'),
      name: _string(metadata, 'name'),
      abbreviation: _string(metadata, 'abbreviation'),
      license: _string(metadata, 'license'),
      sourceUrl: _string(metadata, 'source'),
    );
  }

  /// The whole Bible. The payload's own metadata is authoritative.
  static Bible decode(Uint8List bytes) {
    _check(bytes);
    final flags = bytes[4];
    final metadataLength = (bytes[5] << 8) | bytes[6];
    final start = _headerLength + metadataLength;
    if (start > bytes.length) {
      throw const BibFormatException('the file stops before its Scripture');
    }

    final payload = Uint8List.sublistView(bytes, start);
    final raw = (flags & gzipFlag) != 0
        ? Uint8List.fromList(const GZipDecoder().decodeBytes(payload))
        : payload;
    try {
      return BibleCodec.decode(raw);
    } on Object catch (error) {
      throw BibFormatException('the Scripture inside is unreadable: $error');
    }
  }

  /// True where the bytes begin like a `.bib` file. Used to tell a dropped
  /// file apart from an EPUB without reading either.
  static bool looksLikeBib(Uint8List bytes) {
    if (bytes.length < _headerLength) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  static Map<String, Object?> _metadataOf(TranslationInfo info) => {
    'id': info.id,
    'name': info.name,
    'abbreviation': info.abbreviation,
    'license': info.license,
    'source': info.sourceUrl,
  };

  static Map<String, Object?> _metadata(Uint8List bytes) {
    _check(bytes);
    final length = (bytes[5] << 8) | bytes[6];
    final end = _headerLength + length;
    if (end > bytes.length) {
      throw const BibFormatException('the header runs off the end');
    }
    try {
      final decoded = jsonDecode(
        utf8.decode(Uint8List.sublistView(bytes, _headerLength, end)),
      );
      if (decoded is! Map) {
        throw const BibFormatException('the header is not a record');
      }
      return decoded.cast<String, Object?>();
    } on BibFormatException {
      rethrow;
    } on Object catch (error) {
      throw BibFormatException('the header is unreadable: $error');
    }
  }

  static void _check(Uint8List bytes) {
    if (!looksLikeBib(bytes)) {
      throw const BibFormatException('this is not a .bib file');
    }
    if (bytes[3] != version) {
      throw BibFormatException(
        'this .bib file is version ${bytes[3]}, and this app reads version '
        '$version',
      );
    }
  }

  static String _string(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    return value is String ? value : '';
  }
}

/// Thrown when a file claiming to be Scripture is not, or is of a version
/// this app does not know.
class BibFormatException implements Exception {
  const BibFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
