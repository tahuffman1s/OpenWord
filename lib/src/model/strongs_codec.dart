import 'dart:convert';
import 'dart:typed_data';

/// One word of the original text, as it stands in a particular verse.
class OriginalWord {
  const OriginalWord({
    required this.text,
    required this.strongs,
    required this.morphology,
  });

  /// The Hebrew or Greek, pointed and accented as the source has it.
  final String text;

  /// The Strong's number, or null for a word the source leaves untagged —
  /// a few particles and prefixes.
  final StrongsNumber? strongs;

  /// The parsing, spelled out: "Noun common feminine singular absolute".
  /// Empty where the source gives none.
  final String morphology;
}

/// A Strong's number, which is a language and a number: H7225 is not G7225.
class StrongsNumber implements Comparable<StrongsNumber> {
  const StrongsNumber(this.language, this.number);

  /// 'H' for the Hebrew Bible, 'G' for the Greek New Testament.
  final String language;
  final int number;

  bool get isHebrew => language == 'H';

  /// How the number is written, and typed into the search field.
  String get label => '$language$number';

  /// The key it is stored under; Hebrew and Greek share one space.
  int get key => isHebrew ? number : 1000000 + number;

  static StrongsNumber fromKey(int key) => key >= 1000000
      ? StrongsNumber('G', key - 1000000)
      : StrongsNumber('H', key);

  /// Reads "H7225", "g2316", "H 7225". Null where the text is not one.
  static StrongsNumber? parse(String text) {
    final match = RegExp(r'^\s*([hHgG])\s*0*(\d{1,4})\s*$').firstMatch(text);
    if (match == null) return null;
    final number = int.parse(match.group(2)!);
    if (number < 1) return null;
    return StrongsNumber(match.group(1)!.toUpperCase(), number);
  }

  @override
  int compareTo(StrongsNumber other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) => other is StrongsNumber && other.key == key;

  @override
  int get hashCode => key;

  @override
  String toString() => label;
}

/// A Strong's dictionary entry.
class StrongsEntry {
  const StrongsEntry({
    required this.number,
    required this.lemma,
    required this.transliteration,
    required this.pronunciation,
    required this.derivation,
    required this.definition,
    required this.kjvUsage,
  });

  final StrongsNumber number;

  /// The headword, in Hebrew or Greek.
  final String lemma;
  final String transliteration;
  final String pronunciation;

  /// Where the word comes from, in Strong's own words.
  final String derivation;

  /// Strong's definition.
  final String definition;

  /// The words the King James translators used for it — which is also how a
  /// tapped English word is matched to its Strong's number.
  final String kjvUsage;

  /// The first few words the King James translators used, for a line under
  /// the original.
  ///
  /// Strong's gives no single gloss, and picking one would be inventing it:
  /// the usage list for H430 opens with "angels", which is not what אֱלֹהִים
  /// means. So this shows what the list actually is, and the entry shows it
  /// in full.
  String get renderedAs {
    final words = renderings.take(3).toList();
    return words.join(', ');
  }

  /// The English words this number is rendered by, for matching a tapped
  /// word against the verse.
  /// The editorial marks come out first and the list is split second.
  /// Strong's writes "God (gods) (-dess, -ly)", and splitting on the comma
  /// inside those brackets yields "god -dess", which matches nothing.
  List<String> get renderings {
    final stripped = kjvUsage
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    final words = <String>{};
    for (final part in stripped.split(RegExp(r'[,;.]'))) {
      final cleaned = _clean(part);
      if (cleaned.isNotEmpty) words.add(cleaned);
    }
    return words.toList();
  }

  /// Strong's usage lists carry editorial marks — "[idiom]", "(-ness)",
  /// "[phrase]", and a bare "X" for "not rendered literally" — which are
  /// not words anyone reads or taps.
  static String _clean(String part) => part
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^A-Za-z \-]'), ' ')
      .replaceAll(RegExp(r'(^| )[A-Za-z]( |$)'), ' ')
      .replaceAll(RegExp(r'(^|\s)-+|-+(\s|$)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

/// The binary the original-language layer ships in.
///
/// Four hundred and fifty thousand words is too many to hold as objects —
/// it would cost more memory than the Scripture itself. So the file is
/// gunzipped once into a byte array that stays put, and a verse's words are
/// decoded from it only when that verse is looked at. The indexes that make
/// that possible are small: a verse key and an offset, both varints, delta
/// coded.
///
///     'OWS' version=1
///     u32 ×4  where the lexicon, its index, the concordance and its index
///             begin
///     morphology table: varint count, then each spelled-out parsing
///     verse index: varint count, then per verse a key delta and an offset
///     verse data:  per verse, varint wordCount, then per word
///                  varint strongs key + 1 (0 where untagged),
///                  varint morphology index + 1 (0 where none),
///                  the word itself, length-prefixed
///     lexicon index / data: the same shape, keyed by Strong's number
///     concordance index / data: per number, the verses it occurs in, as
///                  deltas — this is what "N occurrences" counts
class StrongsCodec {
  const StrongsCodec._();

  static const List<int> magic = [0x4f, 0x57, 0x53]; // 'OWS'
  static const int version = 1;

  static int verseKey(int book, int chapter, int verse) =>
      (book * 1000 + chapter) * 1000 + verse;
}

/// Reads the asset without unpacking all of it.
class StrongsReader {
  StrongsReader._(
    this._bytes,
    this._morphology,
    this._verses,
    this._lexicon,
    this._concordance,
  );

  final Uint8List _bytes;
  final List<String> _morphology;

  /// Verse key → where that verse's words begin.
  final Map<int, int> _verses;

  /// Strong's key → where that entry begins.
  final Map<int, int> _lexicon;

  /// Strong's key → where its list of occurrences begins.
  final Map<int, int> _concordance;

  int get verseCount => _verses.length;
  int get entryCount => _lexicon.length;

  bool hasVerse(int key) => _verses.containsKey(key);

  /// The words of one verse, decoded now.
  List<OriginalWord> wordsAt(int key) {
    final offset = _verses[key];
    if (offset == null) return const [];
    final input = _Reader(_bytes, offset);
    final count = input.varint();
    return [
      for (var i = 0; i < count; i++)
        () {
          final strongs = input.varint();
          final morph = input.varint();
          return OriginalWord(
            text: input.string(),
            strongs: strongs == 0 ? null : StrongsNumber.fromKey(strongs - 1),
            morphology: morph == 0 ? '' : _morphology[morph - 1],
          );
        }(),
    ];
  }

  StrongsEntry? entryFor(StrongsNumber number) {
    final offset = _lexicon[number.key];
    if (offset == null) return null;
    final input = _Reader(_bytes, offset);
    return StrongsEntry(
      number: number,
      lemma: input.string(),
      transliteration: input.string(),
      pronunciation: input.string(),
      derivation: input.string(),
      definition: input.string(),
      kjvUsage: input.string(),
    );
  }

  /// How many verses a number occurs in.
  int occurrenceCount(StrongsNumber number) {
    final offset = _concordance[number.key];
    if (offset == null) return 0;
    return _Reader(_bytes, offset).varint();
  }

  /// Every verse a number occurs in, in canonical order.
  List<int> occurrences(StrongsNumber number) {
    final offset = _concordance[number.key];
    if (offset == null) return const [];
    final input = _Reader(_bytes, offset);
    final count = input.varint();
    final keys = <int>[];
    var key = 0;
    for (var i = 0; i < count; i++) {
      key += input.varint();
      keys.add(key);
    }
    return keys;
  }

  static StrongsReader parse(Uint8List bytes) {
    final input = _Reader(bytes, 0);
    for (final byte in StrongsCodec.magic) {
      if (input.byte() != byte) {
        throw const FormatException('not the original-language asset');
      }
    }
    final found = input.byte();
    if (found != StrongsCodec.version) {
      throw FormatException(
        'the original-language asset is version $found, not '
        '${StrongsCodec.version}',
      );
    }

    // Every index holds offsets from the start of its own data, so the
    // sections can be laid out without predicting their own sizes.
    final verseDataAt = input.uint32();
    final lexiconIndexAt = input.uint32();
    final lexiconDataAt = input.uint32();
    final concordanceIndexAt = input.uint32();
    final concordanceDataAt = input.uint32();

    final morphology = List<String>.generate(
      input.varint(),
      (_) => input.string(),
    );
    final verses = _index(input, verseDataAt);
    final lexicon = _index(_Reader(bytes, lexiconIndexAt), lexiconDataAt);
    final concordance = _index(
      _Reader(bytes, concordanceIndexAt),
      concordanceDataAt,
    );

    return StrongsReader._(bytes, morphology, verses, lexicon, concordance);
  }

  /// A run of key/offset pairs, both delta coded, offsets measured from
  /// [base] — the start of the data the index points into.
  static Map<int, int> _index(_Reader input, int base) {
    final count = input.varint();
    final out = <int, int>{};
    var key = 0;
    var offset = 0;
    for (var i = 0; i < count; i++) {
      key += input.varint();
      offset += input.varint();
      out[key] = base + offset;
    }
    return out;
  }
}

/// Builds the asset. Only the tool uses this; the app only reads.
class StrongsWriter {
  final Map<String, int> _morphology = {};
  final Map<int, List<OriginalWord>> _verses = {};
  final Map<int, StrongsEntry> _entries = {};

  void addVerse(int key, List<OriginalWord> words) {
    if (words.isEmpty) return;
    _verses[key] = words;
    for (final word in words) {
      if (word.morphology.isNotEmpty) {
        _morphology.putIfAbsent(word.morphology, () => _morphology.length);
      }
    }
  }

  void addEntry(StrongsEntry entry) => _entries[entry.number.key] = entry;

  int get verseCount => _verses.length;
  int get entryCount => _entries.length;

  Uint8List build() {
    // Which verses each number turns up in, gathered as the words are
    // written rather than in a second pass over the whole Bible.
    final occurrences = <int, List<int>>{};

    final verseKeys = _verses.keys.toList()..sort();
    final verseData = _Writer();
    final verseOffsets = <int, int>{};
    for (final key in verseKeys) {
      verseOffsets[key] = verseData.length;
      final words = _verses[key]!;
      verseData.varint(words.length);
      for (final word in words) {
        final strongs = word.strongs;
        verseData
          ..varint(strongs == null ? 0 : strongs.key + 1)
          ..varint(
            word.morphology.isEmpty ? 0 : _morphology[word.morphology]! + 1,
          )
          ..string(word.text);
        if (strongs != null) {
          final list = occurrences.putIfAbsent(strongs.key, () => []);
          if (list.isEmpty || list.last != key) list.add(key);
        }
      }
    }

    final entryKeys = _entries.keys.toList()..sort();
    final lexiconData = _Writer();
    final lexiconOffsets = <int, int>{};
    for (final key in entryKeys) {
      lexiconOffsets[key] = lexiconData.length;
      final entry = _entries[key]!;
      lexiconData
        ..string(entry.lemma)
        ..string(entry.transliteration)
        ..string(entry.pronunciation)
        ..string(entry.derivation)
        ..string(entry.definition)
        ..string(entry.kjvUsage);
    }

    final occurrenceKeys = occurrences.keys.toList()..sort();
    final concordanceData = _Writer();
    final concordanceOffsets = <int, int>{};
    for (final key in occurrenceKeys) {
      concordanceOffsets[key] = concordanceData.length;
      final verses = occurrences[key]!;
      concordanceData.varint(verses.length);
      var previous = 0;
      for (final verse in verses) {
        concordanceData.varint(verse - previous);
        previous = verse;
      }
    }

    final tables = _Writer()..varint(_morphology.length);
    for (final code in _morphology.keys) {
      tables.string(code);
    }
    _writeIndex(tables, verseKeys, verseOffsets);

    final lexiconIndex = _Writer();
    _writeIndex(lexiconIndex, entryKeys, lexiconOffsets);

    final concordanceIndex = _Writer();
    _writeIndex(concordanceIndex, occurrenceKeys, concordanceOffsets);

    // The header is fixed width, so where each section lands is simple
    // addition rather than a prediction that can be wrong.
    const headerLength = 3 + 1 + 4 * 5;
    final tableBytes = tables.take();
    final verseBytes = verseData.take();
    final lexiconIndexBytes = lexiconIndex.take();
    final lexiconBytes = lexiconData.take();
    final concordanceIndexBytes = concordanceIndex.take();
    final concordanceBytes = concordanceData.take();

    final verseDataAt = headerLength + tableBytes.length;
    final lexiconIndexAt = verseDataAt + verseBytes.length;
    final lexiconDataAt = lexiconIndexAt + lexiconIndexBytes.length;
    final concordanceIndexAt = lexiconDataAt + lexiconBytes.length;
    final concordanceDataAt = concordanceIndexAt + concordanceIndexBytes.length;

    final out = _Writer()
      ..bytes(StrongsCodec.magic)
      ..byte(StrongsCodec.version)
      ..uint32(verseDataAt)
      ..uint32(lexiconIndexAt)
      ..uint32(lexiconDataAt)
      ..uint32(concordanceIndexAt)
      ..uint32(concordanceDataAt)
      ..bytes(tableBytes)
      ..bytes(verseBytes)
      ..bytes(lexiconIndexBytes)
      ..bytes(lexiconBytes)
      ..bytes(concordanceIndexBytes)
      ..bytes(concordanceBytes);
    return out.take();
  }

  /// Keys and offsets, both delta coded; the offsets are measured from the
  /// start of the data the index points into.
  static void _writeIndex(_Writer out, List<int> keys, Map<int, int> offsets) {
    out.varint(keys.length);
    var key = 0;
    var offset = 0;
    for (final k in keys) {
      out.varint(k - key);
      key = k;
      final at = offsets[k]!;
      out.varint(at - offset);
      offset = at;
    }
  }
}

class _Writer {
  final BytesBuilder _out = BytesBuilder(copy: false);

  int get length => _out.length;

  void byte(int value) => _out.addByte(value);
  void bytes(List<int> value) => _out.add(value);

  void uint32(int value) => _out.add([
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ]);

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
  _Reader(this._bytes, this._at);

  final Uint8List _bytes;
  int _at;

  int byte() => _bytes[_at++];

  int uint32() {
    final value =
        (_bytes[_at] << 24) |
        (_bytes[_at + 1] << 16) |
        (_bytes[_at + 2] << 8) |
        _bytes[_at + 3];
    _at += 4;
    return value;
  }

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
