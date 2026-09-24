import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'neural_speech.dart';
import 'neural_voices.dart';
import 'read_aloud.dart';

NeuralVoices openNeuralVoices() => DeviceNeuralVoices();

/// The voice as bundled: a gzipped tar of the model's directory, made by
/// `tool/fetch_voice.dart`.
const String voiceAsset = 'assets/voice/kitten.tar.gz';

/// The voice unpacked into the app's own support directory, where the
/// runtime can open its files by path, as it cannot open an asset.
class DeviceNeuralVoices extends NeuralVoices {
  DeviceNeuralVoices({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  /// Everywhere with a filesystem and a build of sherpa-onnx.
  @override
  bool get isSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux;

  /// Unpacked the first time it is asked for, and only once — or again,
  /// if that failed.
  @override
  Future<void> get ready =>
      _ready ??= _unpack().onError<Object>((error, stack) {
        _ready = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<void>? _ready;

  Directory? _root;
  NeuralSpeechEngine? _engine;
  bool _fallingBehind = false;

  /// Written last, so a model half unpacked is never taken for one that
  /// is ready.
  static const String _marker = '.ready';

  String _modelPath(NeuralModel model) => '${_root!.path}/${model.archive}';

  Future<void> _unpack() async {
    final root = _root = Directory(
      '${(await getApplicationSupportDirectory()).path}/voices',
    );
    await root.create(recursive: true);
    final model = NeuralModel.kitten;
    if (!File('${_modelPath(model)}/$_marker').existsSync()) {
      // Written out of the bundle to a file first: the unpacking runs in the
      // background, where the bundle cannot be reached, and reads it from
      // disk rather than holding fifty megabytes twice over.
      final packed = File('${root.path}/${model.archive}.tar.gz');
      final bytes = await _bundle.load(voiceAsset);
      await packed.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      final archive = packed.path;
      final target = root.path;
      final unpacked = _modelPath(model);
      try {
        await Isolate.run(() => unpackModel(archive, target, unpacked));
      } finally {
        if (packed.existsSync()) packed.deleteSync();
      }
    }
    await tidyModels(root);
  }

  @override
  SpeechEngine engine() => _engine ??= NeuralSpeechEngine(
    ready: () => ready,
    modelDirectory: _modelPath,
    onFallingBehind: (_) {
      _fallingBehind = true;
      notifyListeners();
    },
  );

  @override
  bool get fallingBehind => _fallingBehind;
}

/// Deletes from [root] what the voice does not use: a model this version
/// no longer has — the 8-bit Kitten and Kokoro that 1.21.0 downloaded —
/// and an archive left by unpacking cut short.
@visibleForTesting
Future<void> tidyModels(Directory root) async {
  final wanted = {for (final model in NeuralModel.catalog) model.archive};
  await for (final entry in root.list()) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final unused = entry is Directory
        ? !wanted.contains(name)
        : name.endsWith('.tar.gz') ||
              name.endsWith('.tar.bz2') ||
              name.endsWith('.tar');
    if (!unused) continue;
    try {
      await entry.delete(recursive: true);
    } on Object {
      // Tried again the next time the voice is made ready.
    }
  }
}

/// Unpacks a model's `.tar.gz` or `.tar.bz2` [archive] into [target],
/// where it makes the directory [unpacked], and marks it ready.
///
/// Decompressed to a file of its own first, beside the archive, rather
/// than in memory or the system's temporary directory, which on Android
/// an app cannot write to.
Future<void> unpackModel(String archive, String target, String unpacked) async {
  final directory = Directory(unpacked);
  if (directory.existsSync()) directory.deleteSync(recursive: true);
  final tar = '${archive.replaceFirst(RegExp(r'\.(gz|bz2)$'), '')}.part.tar';
  final input = InputFileStream(archive);
  final output = OutputFileStream(tar);
  try {
    if (archive.endsWith('.bz2')) {
      BZip2Decoder().decodeStream(input, output);
    } else {
      GZipDecoder().decodeStream(input, output);
    }
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
