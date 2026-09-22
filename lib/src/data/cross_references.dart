import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/bible.dart';
import '../model/book_meta.dart';
import '../model/xref_codec.dart';

/// Where else in Scripture a verse is taken up.
///
/// Three hundred thousand references, from the Treasury of Scripture
/// Knowledge, each hung on the phrase of the verse that prompted it. Read on
/// demand and kept afterwards: nothing wants them until a verse is opened.
class CrossReferences {
  CrossReferences({AssetBundle? bundle = _ownBundle})
    : _bundle = bundle == _ownBundle ? rootBundle : bundle;

  /// Tells "no bundle given, so use the app's" apart from "no bundle at
  /// all", which is what a set handed over as bytes has.
  static const AssetBundle? _ownBundle = null;

  /// The references a translation brought with it, in its own `xref`
  /// chunk, already in hand.
  ///
  /// A set of its own is better than the bundled one in every way that
  /// matters: it is anchored to that translation's own verse numbering, so
  /// it is right even where the bundled English set would land on the
  /// wrong verse, and it needs no asset. Answers null where the bytes are
  /// not readable, so a bad chunk costs the references and nothing else.
  static CrossReferences? fromChunk(Uint8List bytes) {
    try {
      final entries = XrefCodec.unpack(bytes);
      if (entries.isEmpty) return null;
      final own = CrossReferences(bundle: null);
      own._byVerse = {for (final entry in entries) entry.key: entry};
      return own;
    } on Object catch (error) {
      debugPrint(
        'OpenWord: a translation\'s own references are '
        'unreadable: $error',
      );
      return null;
    }
  }

  static const String assetPath = 'assets/refs/xrefs.owx.gz';

  /// The tag a translation's own references travel under.
  static const String chunkTag = XrefCodec.chunkTag;

  /// Shown wherever the references are, as the licence requires.
  static const String attribution =
      'Cross-references from CrossReferences.org, after the Treasury of '
      'Scripture Knowledge, CC BY 4.0.';

  /// Anything smaller than this is decoded where it stands, so that a test
  /// fixture does not wait on an isolate.
  static const int isolateAbove = 64 * 1024;

  final AssetBundle? _bundle;
  Map<int, XrefEntry>? _byVerse;
  Future<Map<int, XrefEntry>>? _loading;

  bool get isLoaded => _byVerse != null;

  Future<Map<int, XrefEntry>> load() {
    final loaded = _byVerse;
    if (loaded != null) return Future.value(loaded);
    return _loading ??= _read().then((entries) {
      _byVerse = entries;
      return entries;
    });
  }

  /// The anchors of one verse, or nothing where it has none. Answers only
  /// what is already in memory; call [load] first.
  List<XrefAnchor> forVerse(Reference reference) {
    final entries = _byVerse;
    final verse = reference.verse;
    if (entries == null || verse == null) return const [];
    final book = indexOfBook(reference.bookCode);
    if (book < 0) return const [];
    return entries[XrefCodec.keyOf(book, reference.chapter, verse)]?.anchors ??
        const [];
  }

  /// How many passages a verse points at, for the reader deciding whether to
  /// open them.
  int countFor(Reference reference) {
    var total = 0;
    for (final anchor in forVerse(reference)) {
      total += anchor.ranges.length;
    }
    return total;
  }

  Future<Map<int, XrefEntry>> _read() async {
    final bundle = _bundle;
    if (bundle == null) return const {};
    try {
      final data = await bundle.load(assetPath);
      final bytes = Uint8List.sublistView(data);
      final entries = bytes.length < isolateAbove
          ? decodeCrossReferences(bytes)
          : await compute(decodeCrossReferences, bytes);
      return {for (final entry in entries) entry.key: entry};
    } on Object catch (error) {
      debugPrint('OpenWord: could not read the cross-references: $error');
      return const {};
    }
  }

  /// The canonical position of a book, which is how the asset numbers them.
  static int indexOfBook(String code) => _canon.indexOf(code);

  static String? bookAt(int index) =>
      index >= 0 && index < _canon.length ? _canon[index] : null;

  static final List<String> _canon = [
    for (final meta in BookMeta.all)
      if (meta.section != BookSection.deuterocanon) meta.code,
  ];
}

/// Unpacks the asset. Top-level, because it runs in another isolate.
List<XrefEntry> decodeCrossReferences(Uint8List bytes) {
  final raw = const GZipDecoder().decodeBytes(bytes);
  return XrefCodec.decode(Uint8List.fromList(raw));
}
