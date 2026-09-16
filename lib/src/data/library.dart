import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model/bible.dart';
import '../model/bible_codec.dart';
import 'translations.dart';

enum LibraryStatus { loading, ready, failed }

/// Holds the Scripture the app is reading.
///
/// Every translation ships inside the app, so this never touches the network:
/// the only work is reading an asset, gunzipping it and decoding it, which
/// takes well under a tenth of a second.
class LibraryController extends ChangeNotifier {
  LibraryController({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

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

  Future<Bible> _read(String translationId) async {
    final data = await _bundle.load(Translations.assetFor(translationId));
    final compressed = Uint8List.sublistView(data);
    return BibleCodec.decode(const GZipDecoder().decodeBytes(compressed));
  }
}
