import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'bible.dart';
import 'bible_codec.dart';
import 'book_meta.dart';
import 'byte_io.dart';
import 'search_index.dart';

/// The `.bib` file: one translation, whole, in one file.
///
/// ## Version 2
///
/// A fixed six-byte header and then a stream of chunks, each of which says
/// how long it is and what it is, so a reader can walk past what it does not
/// understand:
///
///     offset  size  meaning
///     0       3     'BIB'
///     3       1     format version, 2
///     4       2     reserved, zero
///     then, until the end of the file:
///       4     tag, four ASCII letters
///       4     payload length, big-endian
///       4     CRC-32 of the payload, big-endian
///       …     payload
///
/// The case of a tag's first letter says what a reader must do with a chunk
/// it does not know, the way PNG does it: **critical** chunks are named in
/// upper case and a reader that does not understand one must refuse the
/// file; **ancillary** chunks are lower case and may be skipped. That one
/// rule is what lets this format grow for years without a version bump —
/// cross-references, a word-level alignment, a search index can all be
/// added as ancillary chunks and every older reader will simply walk past
/// them.
///
/// Two chunks are defined and critical: [tagMeta], the metadata, and
/// [tagText], the Scripture. See `docs/bib-format.md` for the full spec.
///
/// ## Version 1
///
/// The first format was a fixed header — `BIB`, version, a gzip flag, a
/// two-byte metadata length, JSON, then one gzip stream of the whole Bible.
/// Files of it are still read, since a reader may have a shelf of them.
class BibFile {
  const BibFile._();

  static const String extension = '.bib';
  static const List<int> magic = [0x42, 0x49, 0x42]; // 'BIB'

  /// What [encode] writes.
  static const int version = 2;

  /// The oldest version still read.
  static const int oldestVersion = 1;

  /// Metadata: UTF-8 JSON. Critical.
  static const String tagMeta = 'META';

  /// The Scripture, one compressed member per book. Critical.
  static const String tagText = 'TEXT';

  /// Which books each word is in. Ancillary: it only makes search quicker.
  static const String tagSearch = 'srch';

  /// Tags reserved for what a `.bib` file may come to carry. All ancillary,
  /// so a file using them stays readable by everything written before them:
  /// `xref` cross-references anchored to this translation's own
  /// versification, `strg` a word-level Strong's alignment, `srch` a
  /// prebuilt search index, `sign` a detached signature over the other
  /// chunks.
  static const Set<String> reservedTags = {'xref', 'strg', 'sign'};

  static const int _headerLength = 6;
  static const int _chunkHeaderLength = 12;

  /// Version 1 wrote the metadata length in two bytes, so this was its
  /// ceiling. Version 2 has none — a chunk's length is four bytes.
  static const int maxMetadataLength = 0xffff;

  /// How much of a file to read to be sure of finding out what it holds.
  ///
  /// Both formats put the metadata first, so a shelf lists a directory of
  /// translations by reading this much of each rather than opening any of
  /// them. In practice the metadata is a few hundred bytes.
  static const int maxHeaderLength =
      _headerLength + _chunkHeaderLength + maxMetadataLength;

  // ---------------------------------------------------------------- writing

  /// Packs a whole Bible.
  ///
  /// [compress] is for tests and for a file something else will compress
  /// again. [created] is stamped into the metadata when given; leaving it
  /// out keeps encoding deterministic, which is what a build wants — the
  /// same Bible encodes to the same bytes, so a rebuilt asset that has not
  /// changed does not look as though it has.
  ///
  /// [searchable] writes the word index. [carry] writes further chunks as
  /// given; left out, the Bible's own [Bible.extras] are written, so a
  /// rewrite keeps a translation's cross-references and anything else it
  /// came with. Pass `{}` to write none.
  static Uint8List encode(
    Bible bible, {
    bool compress = true,
    DateTime? created,
    bool searchable = true,
    Map<String, List<int>>? carry,
  }) {
    final text = _encodeText(bible, compress: compress);
    final metadata = utf8.encode(
      jsonEncode(
        _metadataOf(
          bible.translation,
          books: bible.books.length,
          verses: bible.verseCount,
          contentHash: 'sha256:${sha256.convert(text)}',
          created: created,
        ),
      ),
    );

    final out = ByteWriter()
      ..bytes(magic)
      ..byte(version)
      ..byte(0)
      ..byte(0);
    _writeChunk(out, tagMeta, metadata);
    _writeChunk(out, tagText, text);
    if (searchable) {
      // Keyed to the text's checksum, so an index can never outlive the
      // Scripture it describes.
      final index = SearchIndex.build(bible, textCrc: getCrc32(text));
      _writeChunk(
        out,
        tagSearch,
        compress
            ? Uint8List.fromList(const GZipEncoder().encodeBytes(index))
            : index,
      );
    }
    // Whatever the Bible came with, unless the caller says otherwise: a
    // rewrite must not quietly drop a translation's cross-references.
    for (final extra in (carry ?? bible.extras).entries) {
      _writeChunk(out, extra.key, extra.value);
    }
    return out.takeCopy();
  }

  static void _writeChunk(ByteWriter out, String tag, List<int> payload) {
    out
      ..bytes(ascii.encode(tag))
      ..uint32(payload.length)
      ..uint32(getCrc32(payload))
      ..bytes(payload);
  }

  /// The TEXT chunk: an outline of every book, then one compressed member
  /// per book in the same order.
  ///
  /// The outline is what makes the file seekable. It carries each book's
  /// code, every chapter's number and verse count, and how long that book's
  /// member is — enough to navigate the whole Bible, and to find any one
  /// book, without unpacking a word.
  static Uint8List _encodeText(Bible bible, {required bool compress}) {
    final bodies = <Uint8List>[];
    for (final book in bible.books) {
      final raw = BibleCodec.encodeChapters(book.chapters);
      bodies.add(
        compress
            ? Uint8List.fromList(const GZipEncoder().encodeBytes(raw))
            : raw,
      );
    }

    final out = ByteWriter()
      ..byte(1) // text encoding version
      ..byte(compress ? _gzip : _stored)
      ..varint(bible.books.length);
    for (var i = 0; i < bible.books.length; i++) {
      final book = bible.books[i];
      out
        ..string(book.code)
        ..varint(book.outline.length);
      for (final chapter in book.outline) {
        out
          ..varint(chapter.number)
          ..varint(chapter.verseCount);
      }
      out.varint(bodies[i].length);
    }
    for (final body in bodies) {
      out.bytes(body);
    }
    return out.takeCopy();
  }

  static const int _stored = 0;
  static const int _gzip = 1;

  // ---------------------------------------------------------------- reading

  /// True where the bytes begin like a `.bib` file. Used to tell a dropped
  /// file apart from an EPUB without reading either.
  static bool looksLikeBib(Uint8List bytes) {
    if (bytes.length < 4) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  /// What the file says it holds, read from its metadata alone.
  static TranslationInfo readInfo(Uint8List bytes) {
    final fileVersion = _version(bytes);
    final metadata = fileVersion == 1 ? _metadataV1(bytes) : _metadataV2(bytes);
    return _infoFrom(metadata);
  }

  /// The whole Bible — or rather, the shape of it. The books unpack
  /// themselves as they are read; see [Book.deferred].
  ///
  /// Pass [verify] to check every chunk's CRC first, which reads the whole
  /// file. The Scripture's own compression checks itself book by book as it
  /// is unpacked, so this is for a deliberate integrity check rather than
  /// for every open.
  static Bible decode(Uint8List bytes, {bool verify = false}) {
    final fileVersion = _version(bytes);
    if (fileVersion == 1) return _decodeV1(bytes);

    final chunks = _chunks(bytes, verify: verify);
    final meta = chunks[tagMeta];
    final text = chunks[tagText];
    if (meta == null) {
      throw const BibFormatException('the file says nothing about itself');
    }
    if (text == null) {
      throw const BibFormatException('the file carries no Scripture');
    }
    final info = _infoFrom(_decodeMetadata(meta));
    // The word index, where the file has one that matches this text. It is
    // read eagerly because it is small beside the Scripture and because a
    // search should not wait on it.
    // The word index is left packed and read on the first search. It is a
    // couple of hundred kilobytes and a few milliseconds to unpack, which
    // is nothing beside the search it saves and too much to spend opening
    // a Bible nobody may search at all.
    final search = chunks[tagSearch];
    return _decodeText(
      info,
      text,
      search: search == null
          ? null
          : () =>
                SearchIndex.parse(_gunzipped(search), textCrc: getCrc32(text)),
      // Everything else the file brought, for whoever knows what it means.
      extras: {
        for (final chunk in chunks.entries)
          if (chunk.key != tagMeta &&
              chunk.key != tagText &&
              chunk.key != tagSearch)
            chunk.key: chunk.value,
      },
    );
  }

  /// Any chunk of a v2 file, by tag, for whatever comes to be stored beside
  /// the Scripture. Null where the file does not carry one.
  static Uint8List? chunk(Uint8List bytes, String tag) =>
      _version(bytes) == 1 ? null : _chunks(bytes)[tag];

  /// Every tag the file carries, in the order they appear.
  static List<String> tags(Uint8List bytes) =>
      _version(bytes) == 1 ? const [] : _chunks(bytes).keys.toList();

  static int _version(Uint8List bytes) {
    if (!looksLikeBib(bytes)) {
      throw const BibFormatException('this is not a .bib file');
    }
    final fileVersion = bytes[3];
    if (fileVersion < oldestVersion || fileVersion > version) {
      throw BibFormatException(
        'this .bib file is version $fileVersion, and this app reads '
        'version $oldestVersion to $version',
      );
    }
    return fileVersion;
  }

  /// Walks the chunk stream. A later chunk of the same tag wins, which is
  /// how a patched file could override one without rewriting the rest.
  static Map<String, Uint8List> _chunks(
    Uint8List bytes, {
    bool verify = false,
  }) {
    final found = <String, Uint8List>{};
    var at = _headerLength;
    while (at < bytes.length) {
      if (at + _chunkHeaderLength > bytes.length) {
        throw const BibFormatException('the file stops inside a chunk header');
      }
      final tag = String.fromCharCodes(bytes, at, at + 4);
      final reader = ByteReader(bytes, at + 4);
      final length = reader.uint32();
      final crc = reader.uint32();
      final start = at + _chunkHeaderLength;
      if (start + length > bytes.length) {
        throw BibFormatException('the $tag chunk runs off the end');
      }
      final payload = Uint8List.sublistView(bytes, start, start + length);
      if (verify && getCrc32(payload) != crc) {
        throw BibFormatException('the $tag chunk is damaged');
      }
      if (!_isKnownTag(tag)) {
        if (_isCritical(tag)) {
          throw BibFormatException(
            'this file needs a $tag chunk, which this app does not know',
          );
        }
        // Ancillary and unknown: walk past it and keep the bytes, so
        // anything that does know can ask for them.
      }
      found[tag] = payload;
      at = start + length;
    }
    return found;
  }

  /// Upper case means a reader must understand it; lower case means it may
  /// be skipped.
  static bool _isCritical(String tag) {
    final first = tag.codeUnitAt(0);
    return first >= 0x41 && first <= 0x5a;
  }

  static bool _isKnownTag(String tag) =>
      tag == tagMeta ||
      tag == tagText ||
      tag == tagSearch ||
      reservedTags.contains(tag);

  /// Unpacks a chunk that may or may not be gzipped, which is how a file
  /// written with `compress: false` stays readable.
  static Uint8List _gunzipped(Uint8List payload) {
    if (payload.length < 2 || payload[0] != 0x1f || payload[1] != 0x8b) {
      return payload;
    }
    return Uint8List.fromList(const GZipDecoder().decodeBytes(payload));
  }

  static Bible _decodeText(
    TranslationInfo info,
    Uint8List text, {
    SearchIndex? Function()? search,
    Map<String, Uint8List> extras = const {},
  }) {
    final input = ByteReader(text);
    final encoding = input.byte();
    if (encoding != 1) {
      throw BibFormatException(
        'the Scripture inside is written in a way this app does not know '
        '(text encoding $encoding)',
      );
    }
    final compression = input.byte();
    if (compression != _stored && compression != _gzip) {
      throw BibFormatException(
        'the Scripture inside is compressed in a way this app does not know '
        '(method $compression)',
      );
    }

    final bookCount = input.varint();
    final codes = <String>[];
    final outlines = <List<ChapterOutline>>[];
    final lengths = <int>[];
    for (var b = 0; b < bookCount; b++) {
      codes.add(input.string());
      final chapterCount = input.varint();
      outlines.add([
        for (var c = 0; c < chapterCount; c++)
          ChapterOutline(number: input.varint(), verseCount: input.varint()),
      ]);
      lengths.add(input.varint());
    }

    // The bodies follow the outline, back to back, so where each one begins
    // is the sum of the lengths before it.
    var at = input.offset;
    final books = <Book>[];
    for (var b = 0; b < bookCount; b++) {
      final start = at;
      final length = lengths[b];
      at += length;
      if (at > text.length) {
        throw BibFormatException('${codes[b]} runs off the end of the file');
      }
      final meta = BookMeta.lookup(codes[b]);
      // Unknown book codes are skipped rather than failing the whole file.
      if (meta == null) continue;
      books.add(
        Book.deferred(
          meta: meta,
          outline: outlines[b],
          load: () {
            final body = Uint8List.sublistView(text, start, start + length);
            final raw = compression == _gzip
                ? Uint8List.fromList(const GZipDecoder().decodeBytes(body))
                : body;
            return BibleCodec.decodeChapters(raw);
          },
        ),
      );
    }
    if (books.isEmpty) {
      throw const BibFormatException('the file carries no books');
    }
    return Bible(
      translation: info,
      books: books,
      extras: extras,
      // An index built for a different set of books is no index at all.
      searchIndex: search == null
          ? null
          : () {
              final index = search();
              return index != null && index.bookCount == bookCount
                  ? index
                  : null;
            },
    );
  }

  // ------------------------------------------------------------- version 1

  static Bible _decodeV1(Uint8List bytes) {
    if (bytes.length < 7) {
      throw const BibFormatException('the file stops inside its header');
    }
    final flags = bytes[4];
    final metadataLength = (bytes[5] << 8) | bytes[6];
    final start = 7 + metadataLength;
    if (start > bytes.length) {
      throw const BibFormatException('the file stops before its Scripture');
    }
    final payload = Uint8List.sublistView(bytes, start);
    final raw = (flags & 0x01) != 0
        ? Uint8List.fromList(const GZipDecoder().decodeBytes(payload))
        : payload;
    try {
      return BibleCodec.decode(raw);
    } on Object catch (error) {
      throw BibFormatException('the Scripture inside is unreadable: $error');
    }
  }

  static Map<String, Object?> _metadataV1(Uint8List bytes) {
    if (bytes.length < 7) {
      throw const BibFormatException('the file stops inside its header');
    }
    final length = (bytes[5] << 8) | bytes[6];
    final end = 7 + length;
    if (end > bytes.length) {
      throw const BibFormatException('the header runs off the end');
    }
    return _decodeMetadata(Uint8List.sublistView(bytes, 7, end));
  }

  // -------------------------------------------------------------- metadata

  static Map<String, Object?> _metadataV2(Uint8List bytes) {
    final meta = _findChunk(bytes, tagMeta);
    if (meta == null) {
      throw const BibFormatException('the file says nothing about itself');
    }
    return _decodeMetadata(meta);
  }

  /// Finds one chunk without needing the rest of the file.
  ///
  /// This is what lets a shelf of translations be listed from the first few
  /// hundred bytes of each: META is written first, so it is found before
  /// the Scripture has been read at all. A chunk that runs past what is in
  /// hand ends the search rather than failing it — there is simply no more
  /// file here — unless it is the chunk being looked for, which is a real
  /// truncation and says so.
  static Uint8List? _findChunk(Uint8List bytes, String wanted) {
    var at = _headerLength;
    while (at + _chunkHeaderLength <= bytes.length) {
      final tag = String.fromCharCodes(bytes, at, at + 4);
      final length = ByteReader(bytes, at + 4).uint32();
      final start = at + _chunkHeaderLength;
      if (tag == wanted) {
        if (start + length > bytes.length) {
          throw BibFormatException('the $tag chunk runs off the end');
        }
        return Uint8List.sublistView(bytes, start, start + length);
      }
      if (start + length > bytes.length) return null;
      at = start + length;
    }
    return null;
  }

  static Map<String, Object?> _decodeMetadata(Uint8List payload) {
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) {
        throw const BibFormatException('the metadata is not a record');
      }
      return decoded.cast<String, Object?>();
    } on BibFormatException {
      rethrow;
    } on Object catch (error) {
      throw BibFormatException('the metadata is unreadable: $error');
    }
  }

  static Map<String, Object?> _metadataOf(
    TranslationInfo info, {
    required int books,
    required int verses,
    required String contentHash,
    required DateTime? created,
  }) => {
    'id': info.id,
    'name': info.name,
    'abbreviation': info.abbreviation,
    'license': info.license,
    'source': info.sourceUrl,
    'language': info.language,
    if (info.script.isNotEmpty) 'script': info.script,
    'direction': info.direction.key,
    'versification': info.versification,
    if (info.attribution.isNotEmpty) 'attribution': info.attribution,
    'books': books,
    'verses': verses,
    'contentHash': contentHash,
    'generator': generator,
    if (created != null) 'created': created.toUtc().toIso8601String(),
  };

  /// Stamped into every file this writes, so one found later can say what
  /// made it. Nothing reads it back; it is for whoever is holding the file
  /// and wondering.
  static const String generator = 'OpenWord';

  static TranslationInfo _infoFrom(Map<String, Object?> metadata) =>
      TranslationInfo(
        id: _string(metadata, 'id'),
        name: _string(metadata, 'name'),
        abbreviation: _string(metadata, 'abbreviation'),
        license: _string(metadata, 'license'),
        sourceUrl: _string(metadata, 'source'),
        // Version 1 said none of what follows. A file that does not say is
        // taken for what every translation shipped here is.
        language: _string(metadata, 'language', 'en'),
        script: _string(metadata, 'script'),
        direction: ReadingDirection.fromKey(_string(metadata, 'direction')),
        versification: _string(
          metadata,
          'versification',
          Versification.unknown,
        ),
        attribution: _string(metadata, 'attribution'),
      );

  static String _string(
    Map<String, Object?> metadata,
    String key, [
    String fallback = '',
  ]) {
    final value = metadata[key];
    return value is String && value.isNotEmpty ? value : fallback;
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
