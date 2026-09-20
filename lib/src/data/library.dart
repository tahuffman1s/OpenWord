import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/bible.dart';
import '../model/bible_codec.dart';
import 'shelf.dart';
import 'translations.dart';

enum LibraryStatus { loading, ready, failed }

/// Holds the Scripture the app is reading.
///
/// Three translations ship inside the app; a reader can put more on the
/// [Shelf] by importing them. Either way the work is the same — read the
/// bytes, gunzip, decode — and nothing touches the network.
class LibraryController extends ChangeNotifier {
  LibraryController({AssetBundle? bundle, this.shelf})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  /// The imported translations, where there are any. Null on the web, which
  /// has no filesystem to keep them on.
  final Shelf? shelf;

  /// The bundle the Scripture was read from. Anything else that ships as an
  /// asset — the book introductions, for one — reads from the same place, so
  /// a test can swap both at once.
  AssetBundle get bundle => _bundle;

  LibraryStatus _status = LibraryStatus.loading;
  String? _errorMessage;
  Bible? _bible;

  /// A second translation, loaded only while the reader is comparing.
  Bible? _comparison;
  bool _loadingComparison = false;

  LibraryStatus get status => _status;
  String? get errorMessage => _errorMessage;
  Bible? get bible => _bible;
  Bible? get comparison => _comparison;
  bool get loadingComparison => _loadingComparison;
  bool get isReady => _status == LibraryStatus.ready && _bible != null;

  TranslationInfo get translation =>
      _bible?.translation ?? Translations.fallback;

  /// Loads [translationId] as the translation being read. Falls back to the
  /// default translation if that asset cannot be read.
  Future<void> load(String translationId) async {
    _status = LibraryStatus.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      _bible = await _read(translationId);
      if (_comparison?.translation.id == _bible!.translation.id) {
        _comparison = null;
      }
      _status = LibraryStatus.ready;
    } on Object catch (error) {
      debugPrint('OpenWord: could not load $translationId: $error');
      if (translationId != Translations.fallback.id) {
        await load(Translations.fallback.id);
        return;
      }
      _errorMessage = 'The bundled Scripture could not be read.';
      _status = LibraryStatus.failed;
    }
    notifyListeners();
  }

  /// Loads a second translation for side-by-side reading.
  Future<void> loadComparison(String translationId) async {
    if (translationId == _bible?.translation.id) {
      clearComparison();
      return;
    }
    if (_comparison?.translation.id == translationId) return;
    _loadingComparison = true;
    notifyListeners();
    try {
      _comparison = await _read(translationId);
    } on Object catch (error) {
      debugPrint('OpenWord: could not load comparison $translationId: $error');
      _comparison = null;
    }
    _loadingComparison = false;
    notifyListeners();
  }

  /// Drops the second translation, freeing the memory it held.
  void clearComparison() {
    if (_comparison == null && !_loadingComparison) return;
    _comparison = null;
    _loadingComparison = false;
    notifyListeners();
  }

  /// True where this id names a translation that can actually be read.
  bool knows(String translationId) =>
      Translations.all.any((t) => t.id == translationId) ||
      (shelf?.has(translationId) ?? false);

  /// Everything that can be read: what ships with the app, then whatever the
  /// reader has imported.
  List<TranslationInfo> get available => [
    ...Translations.all,
    if (shelf != null)
      for (final shelved in shelf!.translations) shelved.info,
  ];

  /// What a translation id is called, bundled or imported.
  TranslationInfo infoFor(String id) => available.firstWhere(
    (translation) => translation.id == id,
    orElse: () => Translations.fallback,
  );

  /// True where the reader brought this one themselves.
  bool isImported(String id) => shelf?.has(id) ?? false;

  Future<Bible> _read(String translationId) async {
    final imported = shelf;
    if (imported != null && imported.has(translationId)) {
      return imported.read(translationId);
    }
    final data = await _bundle.load(Translations.assetFor(translationId));
    final compressed = Uint8List.sublistView(data);
    return BibleCodec.decode(const GZipDecoder().decodeBytes(compressed));
  }
}
