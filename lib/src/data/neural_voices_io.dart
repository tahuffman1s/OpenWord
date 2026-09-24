import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'neural_speech.dart';
import 'neural_voices.dart';
import 'read_aloud.dart';
import 'update_backend_io.dart';

NeuralVoices openNeuralVoices() => DeviceNeuralVoices();

/// The models kept in the app's own support directory, one directory each,
/// as unpacked from their archives.
class DeviceNeuralVoices extends NeuralVoices {
  DeviceNeuralVoices() {
    ready = isSupported ? _scan() : Future.value();
  }

  /// Where sherpa-onnx has a build and OpenWord reads aloud. Linux has the
  /// one but not the other.
  @override
  bool get isSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  @override
  late final Future<void> ready;

  Directory? _root;
  final Set<String> _installed = {};
  final Map<String, double> _progress = {};
  final Map<String, String> _errors = {};
  final Set<String> _cancelled = {};
  NeuralSpeechEngine? _engine;

  /// Written last, so a model half unpacked is never taken for one that
  /// is ready.
  static const String _marker = '.ready';

  Future<Directory> _directory() async {
    final root = _root ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/voices',
    );
    await root.create(recursive: true);
    return root;
  }

  String _modelPath(NeuralModel model) => '${_root!.path}/${model.archive}';

  Future<void> _scan() async {
    try {
      final root = await _directory();
      for (final model in NeuralModel.catalog) {
        if (File('${_modelPath(model)}/$_marker').existsSync()) {
          _installed.add(model.id);
        }
      }
      await tidyModels(root, downloading: _progress.isNotEmpty);
    } on Object {
      // No support directory: nothing is installed, and a download will
      // say why it cannot be kept.
    }
    notifyListeners();
  }

  @override
  bool isInstalled(NeuralModel model) => _installed.contains(model.id);

  @override
  double? progress(NeuralModel model) => _progress[model.id];

  @override
  String? error(NeuralModel model) => _errors[model.id];

  @override
  void cancel(NeuralModel model) {
    if (_progress.containsKey(model.id)) _cancelled.add(model.id);
  }

  @override
  Future<void> install(NeuralModel model) async {
    if (!isSupported || _progress.containsKey(model.id) || isInstalled(model)) {
      return;
    }
    _errors.remove(model.id);
    _cancelled.remove(model.id);
    _progress[model.id] = 0;
    notifyListeners();
    File? download;
    try {
      final root = await _directory();
      download = File('${root.path}/${model.archive}.tar.bz2');
      await _download(model, download);
      // Unpacked in the background: decompressing a hundred megabytes
      // takes a while, and the sheet should go on answering meanwhile.
      _progress[model.id] = 1;
      notifyListeners();
      final archive = download.path;
      final target = root.path;
      final unpacked = _modelPath(model);
      await Isolate.run(() => unpackModel(archive, target, unpacked));
      _installed.add(model.id);
    } on _Cancelled {
      // Asked for; nothing to report.
    } on Object catch (error) {
      _errors[model.id] = error is _Damaged
          ? 'The download was damaged. Try again.'
          : 'Could not download the voice. Check the connection and try '
                'again.';
    } finally {
      if (download != null && download.existsSync()) {
        download.deleteSync();
      }
      _progress.remove(model.id);
      _cancelled.remove(model.id);
      notifyListeners();
    }
  }

  Future<void> _download(NeuralModel model, File file) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(model.url);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        NativeUpdateBackend.userAgent,
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('Answered ${response.statusCode}', uri: model.url);
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : model.bytes;
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      final sink = file.openWrite();
      var received = 0;
      var shown = 0.0;
      try {
        await for (final chunk in response) {
          if (_cancelled.contains(model.id)) throw const _Cancelled();
          sink.add(chunk);
          hash.add(chunk);
          received += chunk.length;
          final progress = (received / total).clamp(0.0, 0.99);
          // A hundredth at a time is often enough to redraw.
          if (progress - shown >= 0.01) {
            shown = progress;
            _progress[model.id] = progress;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      hash.close();
      if (digest.value.toString() != model.sha256) throw const _Damaged();
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> remove(NeuralModel model) async {
    _installed.remove(model.id);
    notifyListeners();
    try {
      await _directory();
      final directory = Directory(_modelPath(model));
      if (directory.existsSync()) await directory.delete(recursive: true);
    } on Object {
      // A file still held open; it goes the next time.
    }
  }

  @override
  SpeechEngine engine() => _engine ??= NeuralSpeechEngine(
    modelDirectory: _modelPath,
    onFallingBehind: (model) {
      _fallingBehind = model;
      notifyListeners();
    },
  );

  NeuralModel? _fallingBehind;

  @override
  NeuralModel? get fallingBehind => _fallingBehind;
}

/// Deletes from [root] what no model here uses: a model this version no
/// longer offers — the 8-bit Kitten that 1.21.0 downloaded, say — and,
/// unless one is [downloading], a download or unpacking cut short.
Future<void> tidyModels(Directory root, {required bool downloading}) async {
  final wanted = {for (final model in NeuralModel.catalog) model.archive};
  await for (final entry in root.list()) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final unused = entry is Directory
        ? !wanted.contains(name)
        : !downloading && (name.endsWith('.tar.bz2') || name.endsWith('.tar'));
    if (!unused) continue;
    try {
      await entry.delete(recursive: true);
    } on Object {
      // Tried again the next time the app opens.
    }
  }
}

/// Unpacks a model's `.tar.bz2` [archive] into [target], where it makes
/// the directory [unpacked], and marks it ready.
///
/// Decompressed to a file of its own first, beside the archive, rather
/// than in memory or the system's temporary directory, which on Android
/// an app cannot write to.
Future<void> unpackModel(String archive, String target, String unpacked) async {
  final directory = Directory(unpacked);
  if (directory.existsSync()) directory.deleteSync(recursive: true);
  final tar = '$archive.tar';
  final input = InputFileStream(archive);
  final output = OutputFileStream(tar);
  try {
    BZip2Decoder().decodeStream(input, output);
  } finally {
    await input.close();
    await output.close();
  }
  try {
    await extractFileToDisk(tar, target);
  } finally {
    File(tar).deleteSync();
  }
  File('$unpacked/${DeviceNeuralVoices._marker}').writeAsStringSync('');
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _Damaged implements Exception {
  const _Damaged();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
