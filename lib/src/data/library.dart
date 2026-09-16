import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../model/bible.dart';
import 'bible_cache.dart';
import 'bible_source.dart';
import 'usfx_parser.dart';

enum LibraryStatus {
  /// Looking for an already downloaded copy.
  checking,

  /// Nothing cached yet — the first launch needs to fetch the text.
  needsDownload,

  downloading,

  /// Turning USFX into the app's own structure.
  parsing,

  /// Reading the cached copy back from disk.
  loading,

  ready,

  failed,
}

/// Owns the downloaded Bible and the work of getting it onto the device.
class LibraryController extends ChangeNotifier {
  LibraryController({this._cache = const BibleCache(), http.Client? client})
    : _client = client ?? http.Client();

  /// Builds a controller that already holds [bible], for tests and previews.
  @visibleForTesting
  factory LibraryController.withBible(Bible bible) {
    final controller = LibraryController();
    controller._bible = bible;
    controller._status = LibraryStatus.ready;
    controller._progress = 1;
    return controller;
  }

  final BibleCache _cache;
  final http.Client _client;

  LibraryStatus _status = LibraryStatus.checking;
  double _progress = 0;
  String _message = '';
  String? _errorMessage;
  Bible? _bible;
  BibleSource _source = BibleSource.worldEnglishBible;

  LibraryStatus get status => _status;
  double get progress => _progress;
  String get message => _message;
  String? get errorMessage => _errorMessage;
  Bible? get bible => _bible;
  BibleSource get source => _source;
  bool get isReady => _status == LibraryStatus.ready && _bible != null;
  bool get isBusy =>
      _status == LibraryStatus.downloading ||
      _status == LibraryStatus.parsing ||
      _status == LibraryStatus.loading ||
      _status == LibraryStatus.checking;

  /// Looks for a cached copy of [sourceId] and loads it; reports
  /// [LibraryStatus.needsDownload] when this is a first launch.
  Future<void> initialize(String sourceId) async {
    _source = BibleSource.byId(sourceId);
    _set(LibraryStatus.checking, message: 'Looking for your Bible…');
    try {
      final cached = await _cache.read(_source.id);
      if (cached == null) {
        _set(LibraryStatus.needsDownload, message: '');
        return;
      }
      _set(LibraryStatus.loading, message: 'Opening ${_source.info.name}…');
      final bible = _decode(cached);
      if (bible == null) {
        await _cache.delete(_source.id);
        _set(LibraryStatus.needsDownload, message: '');
        return;
      }
      _bible = bible;
      _set(LibraryStatus.ready, progress: 1);
    } on Object catch (error) {
      _fail('Could not open the downloaded Bible.', error);
    }
  }

  /// Downloads, parses and caches [source]. Safe to call again after a
  /// failure.
  Future<void> download([BibleSource? source]) async {
    _source = source ?? _source;
    _errorMessage = null;
    _set(
      LibraryStatus.downloading,
      progress: 0,
      message: 'Downloading ${_source.info.name}…',
    );

    String? document;
    Object? lastError;
    for (final url in _source.mirrors) {
      try {
        document = await _fetch(url);
        break;
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (document == null) {
      _fail('Download failed. Check your connection and try again.', lastError);
      return;
    }

    try {
      _set(
        LibraryStatus.parsing,
        progress: 0.9,
        message: 'Preparing the text…',
      );
      final json = await compute(_parseToJson, (document, _source.id));
      final bible = _decode(json);
      if (bible == null) {
        _fail('The downloaded file could not be read.', null);
        return;
      }
      _bible = bible;
      _set(LibraryStatus.parsing, progress: 0.98, message: 'Saving…');
      await _cache.write(_source.id, json);
      _set(LibraryStatus.ready, progress: 1, message: '');
    } on Object catch (error) {
      _fail('The downloaded file could not be read.', error);
    }
  }

  /// Removes the cached copy; the next [initialize] will download again.
  Future<void> deleteDownload() async {
    await _cache.delete(_source.id);
    _bible = null;
    _set(LibraryStatus.needsDownload, progress: 0, message: '');
  }

  Future<String> _fetch(String url) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', request.url);
    }
    final expected = response.contentLength ?? _source.approximateBytes;
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      buffer.add(chunk);
      // Downloading is the long pole; keep it in the first 90% of the bar.
      _set(
        LibraryStatus.downloading,
        progress: (buffer.length / expected).clamp(0.0, 1.0) * 0.9,
        message:
            'Downloading ${_source.info.name}… '
            '${_megabytes(buffer.length)} of ${_megabytes(expected)}',
      );
    }
    return utf8.decode(buffer.takeBytes());
  }

  Bible? _decode(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    return Bible.fromJson(decoded.cast<String, Object?>());
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  void _set(LibraryStatus status, {double? progress, String? message}) {
    _status = status;
    if (progress != null) _progress = progress;
    if (message != null) _message = message;
    notifyListeners();
  }

  void _fail(String message, Object? error) {
    _errorMessage = message;
    if (error != null) {
      debugPrint('OpenWord library error: $error');
    }
    _set(LibraryStatus.failed, message: message);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

/// Runs on a background isolate: USFX in, compact JSON out.
///
/// JSON is returned rather than a [Bible] because a single string is cheap to
/// hand back across the isolate boundary and is exactly what gets cached.
String _parseToJson((String, String) request) {
  final (document, sourceId) = request;
  final bible = UsfxParser.parse(document, BibleSource.byId(sourceId).info);
  return jsonEncode(bible.toJson());
}
