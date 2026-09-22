import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/bible.dart';
import '../model/book_meta.dart';
import '../model/strongs_codec.dart';

/// The Hebrew and Greek behind the English, with Strong's numbers.
///
/// Keyed by verse rather than by word, which is what lets it work under any
/// translation — the ones that ship, and any the reader imports. The words
/// of Genesis 1:1 are the same whichever English is on top of them.
class Originals {
  Originals({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  /// A layer already in hand, which has no bundle to go back to.
  Originals._over(StrongsReader reader) : _bundle = null, _reader = reader;

  /// The Hebrew and Greek a translation brought with it, in its own `strg`
  /// chunk.
  ///
  /// A layer of its own is better than the bundled one in the way that
  /// matters most: it is keyed to that translation's own verse numbering,
  /// so it is right even where the bundled layer would hand back the words
  /// of a neighbouring verse. Answers null where the bytes are not
  /// readable, so a bad chunk costs the originals and nothing else.
  static Future<Originals?> fromChunk(Uint8List bytes) async {
    try {
      final reader = bytes.length < isolateAbove
          ? decodeOriginals(bytes)
          : await compute(decodeOriginals, bytes);
      return reader.verseCount == 0 ? null : Originals._over(reader);
    } on Object catch (error) {
      debugPrint(
        "OpenWord: a translation's own Hebrew and Greek are "
        'unreadable: $error',
      );
      return null;
    }
  }

  /// The tag a translation's own layer travels under.
  static const String chunkTag = StrongsCodec.chunkTag;

  static const String assetPath = 'assets/strongs/originals.ows.gz';

  static const String attribution =
      'Hebrew from the Open Scriptures Hebrew Bible (CC BY 4.0); Greek from '
      'the Byzantine Majority Text, Robinson–Pierpont (public domain); '
      "Strong's dictionaries from Open Scriptures (CC BY-SA 4.0).";

  /// Below this the asset is unpacked where it stands, so a fixture does
  /// not wait on an isolate.
  static const int isolateAbove = 64 * 1024;

  final AssetBundle? _bundle;
  StrongsReader? _reader;
  Future<StrongsReader?>? _loading;

  StrongsReader? get reader => _reader;
  bool get isLoaded => _reader != null;

  Future<StrongsReader?> load() {
    final loaded = _reader;
    if (loaded != null) return Future.value(loaded);
    return _loading ??= _read().then((reader) {
      _reader = reader;
      return reader;
    });
  }

  /// The original words of a verse, in their own order.
  List<OriginalWord> wordsFor(Reference reference) {
    final reader = _reader;
    final verse = reference.verse;
    if (reader == null || verse == null) return const [];
    final book = _canon.indexOf(reference.bookCode);
    if (book < 0) return const [];
    return reader.wordsAt(
      StrongsCodec.verseKey(book, reference.chapter, verse),
    );
  }

  /// Whether a verse has an original behind it at all. The deuterocanonical
  /// books do not: they are neither in the Hebrew Bible nor the Greek New
  /// Testament as this app carries them.
  bool hasOriginal(Reference reference) => wordsFor(reference).isNotEmpty;

  StrongsEntry? entryFor(StrongsNumber number) => _reader?.entryFor(number);

  int occurrenceCount(StrongsNumber number) =>
      _reader?.occurrenceCount(number) ?? 0;

  /// Every verse a number occurs in, as references.
  List<Reference> occurrences(StrongsNumber number) {
    final reader = _reader;
    if (reader == null) return const [];
    return [
      for (final key in reader.occurrences(number))
        if (_referenceFor(key) case final reference?) reference,
    ];
  }

  /// Which of a verse's original words an English word most likely came
  /// from.
  ///
  /// Strong's lists the words the King James translators used for each
  /// number, so a tapped word is looked for in those lists. It is a guess
  /// where the translation is not the KJV, so where nothing matches this
  /// answers nothing rather than something plausible.
  List<int> matchesFor(List<OriginalWord> words, String englishWord) {
    final needle = englishWord.toLowerCase().replaceAll(
      RegExp(r"[^a-z'\-]"),
      '',
    );
    if (needle.length < 2) return const [];

    final exact = <int>[];
    final stemmed = <int>[];
    for (var i = 0; i < words.length; i++) {
      final number = words[i].strongs;
      if (number == null) continue;
      final entry = entryFor(number);
      if (entry == null) continue;
      for (final rendering in entry.renderings) {
        if (rendering == needle) {
          exact.add(i);
          break;
        }
        if (_sameStem(rendering, needle)) {
          stemmed.add(i);
          break;
        }
      }
    }
    return exact.isNotEmpty ? exact : stemmed;
  }

  /// Rough English stemming: enough to tie "loved" to "love" and "waters"
  /// to "water", and no more. Getting clever here would produce confident
  /// wrong answers.
  static bool _sameStem(String a, String b) {
    final rootA = _stem(a);
    final rootB = _stem(b);
    if (rootA.length < 3 || rootB.length < 3) return false;
    if (rootA == rootB) return true;
    // English drops a silent e before -ed and -ing: "create" and "created"
    // stem to "create" and "creat", which are the same word.
    return rootA == '${rootB}e' || rootB == '${rootA}e';
  }

  static String _stem(String word) {
    for (final ending in const ['ing', 'edly', 'est', 'eth', 'ed', 'es', 's']) {
      if (word.length > ending.length + 2 && word.endsWith(ending)) {
        return word.substring(0, word.length - ending.length);
      }
    }
    return word;
  }

  static Reference? _referenceFor(int key) {
    final book = key ~/ 1000000;
    if (book < 0 || book >= _canon.length) return null;
    return Reference(_canon[book], (key ~/ 1000) % 1000, key % 1000);
  }

  Future<StrongsReader?> _read() async {
    final bundle = _bundle;
    if (bundle == null) return _reader;
    try {
      final data = await bundle.load(assetPath);
      final bytes = Uint8List.sublistView(data);
      return bytes.length < isolateAbove
          ? decodeOriginals(bytes)
          : await compute(decodeOriginals, bytes);
    } on Object catch (error) {
      debugPrint('OpenWord: could not read the original languages: $error');
      return null;
    }
  }

  static final List<String> _canon = [
    for (final meta in BookMeta.all)
      if (meta.section != BookSection.deuterocanon) meta.code,
  ];
}

/// Unpacks the asset. Top-level, because it runs in another isolate.
///
/// What comes back is a reader over the bytes rather than four hundred
/// thousand objects: a verse is decoded when it is looked at.
StrongsReader decodeOriginals(Uint8List bytes) => StrongsCodec.unpack(bytes);
