import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'neural_voices.dart';
import 'read_aloud.dart';

/// Speaks with a neural model on the device, through sherpa-onnx.
///
/// The model runs on an isolate of its own, one piece of the text at a
/// time, a piece ahead of what is being heard; each piece is played as it
/// is ready, on one of two players that take turns, so that the next is
/// loaded while this one plays and there is no gap to hear between them.
///
/// Unlike the platform's voices it can truly pause: the audio simply
/// stops where it is and goes on from there, mid-word.
class NeuralSpeechEngine implements SpeechEngine {
  NeuralSpeechEngine({
    required this.ready,
    required this.modelDirectory,
    this.onFallingBehind,
  });

  /// Settles once the model is unpacked where [modelDirectory] says.
  final Future<void> Function() ready;

  /// Where the model was unpacked.
  final String Function(NeuralModel model) modelDirectory;

  /// Told, once for each model, when this device makes its speech more
  /// slowly than it is heard, so that there will be pauses.
  final void Function(NeuralModel model)? onFallingBehind;
  final Set<NeuralModel> _toldSlow = {};

  Synthesiser? _synth;
  NeuralModel? _model;
  int _speaker = 0;
  double _speed = 1.0;

  /// Made when first wanted: an engine is made for every reader screen,
  /// and most are never asked to speak.
  late final List<AudioPlayer> _players = [AudioPlayer(), AudioPlayer()];
  bool _playersReady = false;
  Directory? _clips;
  _Reading? _reading;

  @override
  bool get isAvailable => true;

  @override
  bool get canPause => true;

  /// Loading one model after another, never two at once.
  Future<void> _configuring = Future.value();

  @override
  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  }) {
    final next = _configuring.then(
      (_) => _configure(language: language, rate: rate, voice: voice),
    );
    _configuring = next.catchError((Object _) {});
    return next;
  }

  Future<void> _configure({
    required String language,
    required double rate,
    String? voice,
  }) async {
    final (model, speaker) = NeuralModel.chosen(voice);
    _speaker = speaker.id;
    _speed = rate;
    await ready();
    await _preparePlayers();
    if (model != _model || _synth == null) {
      await stop();
      _synth?.close();
      _synth = null;
      _model = null;
      _synth = await Synthesiser.start(model, modelDirectory(model));
      _model = model;
    }
  }

  /// Played as speech, through the same audio session reading aloud has
  /// always used: not muted by the silent switch, going on with the
  /// screen off, and holding the device awake between pieces.
  Future<void> _preparePlayers() async {
    if (_playersReady) return;
    final context = AudioContext(
      android: const AudioContextAndroid(
        stayAwake: true,
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gain,
      ),
      iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
    );
    for (final player in _players) {
      await player.setAudioContext(context);
      await player.setReleaseMode(ReleaseMode.stop);
    }
    // Made afresh each run: what an earlier one left is of no use.
    final clips = Directory('${(await getTemporaryDirectory()).path}/voice');
    if (clips.existsSync()) clips.deleteSync(recursive: true);
    _clips = clips..createSync(recursive: true);
    _playersReady = true;
  }

  @override
  Future<bool> speak(
    String text, {
    void Function(int offset)? onProgress,
    void Function()? onStart,
  }) async {
    _reading?.cancel();
    final synth = _synth;
    final clips = _clips;
    if (synth == null || clips == null) return false;
    final reading = _reading = _Reading(
      text: text,
      synth: synth,
      players: _players,
      clips: clips,
      speaker: _speaker,
      speed: _speed,
      onProgress: onProgress,
      onStart: onStart,
      onHeard: _checkPace,
    );
    final said = await reading.run();
    if (identical(_reading, reading)) _reading = null;
    return said;
  }

  void _checkPace() {
    final model = _model;
    if (model != null &&
        (_synth?.fallingBehind ?? false) &&
        _toldSlow.add(model)) {
      onFallingBehind?.call(model);
    }
  }

  @override
  Future<void> stop() async {
    _reading?.cancel();
    _reading = null;
    if (!_playersReady) return;
    for (final player in _players) {
      try {
        await player.stop();
      } on Object {
        // Nothing was playing.
      }
    }
  }

  @override
  Future<void> pause() async => _reading?.pause();

  @override
  Future<void> resume() async => _reading?.resume();

  @override
  Future<List<SpeechVoice>> voices(String language) async =>
      NeuralModel.kitten.voices;

  /// Where [text] is cut to be voiced a piece at a time, as the offset of
  /// each piece and its words.
  ///
  /// At the end of every sentence, and a sentence longer than a piece may
  /// be again at a comma, or failing that a space. Nothing is heard until
  /// the first piece has been made whole, so the first is short — [first]
  /// characters at most — and each after it may be twice the one before,
  /// up to [longest]: the voice starts almost at once, and the pieces grow
  /// while it is being made ahead of what is heard.
  static List<(int, String)> pieces(
    String text, {
    int first = 40,
    int longest = 160,
  }) {
    final result = <(int, String)>[];
    int limit() => math.min(longest, first << math.min(result.length, 8));
    void add(int start, int end) {
      while (start < end && text.codeUnitAt(start) == 0x20) {
        start++;
      }
      while (end > start && text.codeUnitAt(end - 1) == 0x20) {
        end--;
      }
      if (end > start) result.add((start, text.substring(start, end)));
    }

    void cut(int start, int end) {
      while (end - start > limit()) {
        final size = limit();
        final window = text.substring(start, start + size);
        var at = math.max(window.lastIndexOf(', '), window.lastIndexOf('; '));
        if (at > size ~/ 3) {
          at++;
        } else {
          // At a space, but not straight after a little word that leans on
          // the next: "God created | the heavens", not "created the |".
          at = window.lastIndexOf(' ');
          var earlier = at;
          while (earlier > size ~/ 3) {
            final before = window.lastIndexOf(' ', earlier - 1);
            final word = window.substring(before + 1, earlier).toLowerCase();
            if (!_leaning.contains(word)) break;
            earlier = before;
          }
          if (earlier > size ~/ 3) at = earlier;
        }
        if (at <= 0) at = size;
        add(start, start + at);
        start += at;
      }
      add(start, end);
    }

    var start = 0;
    for (final end in _sentenceEnd.allMatches(text)) {
      cut(start, end.end);
      start = end.end;
    }
    cut(start, text.length);
    return result;
  }

  static final RegExp _sentenceEnd = RegExp('[.;:!?][”’"\')]*\\s+');

  static const Set<String> _leaning = {
    'a',
    'an',
    'and',
    'as',
    'at',
    'but',
    'by',
    'for',
    'from',
    'his',
    'her',
    'in',
    'into',
    'its',
    'my',
    'nor',
    'o',
    'of',
    'on',
    'or',
    'our',
    'that',
    'the',
    'their',
    'thy',
    'to',
    'upon',
    'with',
    'your',
  };
}

/// One passage being voiced: made, played, paused, or given up.
class _Reading {
  _Reading({
    required String text,
    required this.synth,
    required this.players,
    required this.clips,
    required this.speaker,
    required this.speed,
    this.onProgress,
    this.onStart,
    this.onHeard,
  }) : pieces = NeuralSpeechEngine.pieces(text);

  final Synthesiser synth;
  final List<AudioPlayer> players;
  final Directory clips;
  final int speaker;
  final double speed;
  final void Function(int offset)? onProgress;
  final void Function()? onStart;

  /// After each piece has been heard.
  final void Function()? onHeard;
  final List<(int, String)> pieces;

  final Map<int, Future<String?>> _made = {};
  final Map<int, Future<bool>> _loaded = {};
  final Completer<void> _cancelled = Completer();
  Completer<void>? _unpaused;
  AudioPlayer? _playing;

  bool get cancelled => _cancelled.isCompleted;
  bool get paused => _unpaused != null;

  static int _clipCount = 0;

  /// How many pieces are made ahead of the one being heard.
  static const int _ahead = 3;

  /// The audio for a piece, made once, as a file.
  Future<String?> _make(int i) => _made[i] ??= synth.say(
    pieces[i].$2,
    speaker: speaker,
    speed: speed,
    path: '${clips.path}/clip-${_clipCount++}.wav',
    owner: this,
  );

  /// A piece made and loaded into its player, ready to start at once.
  Future<bool> _load(int i) => _loaded[i] ??= _make(i).then((path) async {
    if (path == null || cancelled) return false;
    await players[i % 2].setSource(DeviceFileSource(path));
    return true;
  });

  Future<bool> run() async {
    try {
      for (var i = 0; i < pieces.length; i++) {
        if (!await _load(i) || cancelled) return false;
        // The next is loaded into the other player while this one plays,
        // and those after it are made, so that a slow sentence can borrow
        // time from quick ones.
        if (i + 1 < pieces.length) unawaited(_load(i + 1));
        for (var k = i + 2; k < pieces.length && k <= i + _ahead; k++) {
          unawaited(_make(k));
        }
        await _whileUnpaused();
        if (cancelled) return false;
        final player = players[i % 2];
        final done = player.onPlayerComplete.first;
        if (i == 0) onStart?.call();
        onProgress?.call(pieces[i].$1);
        _playing = player;
        await player.resume();
        // Paused while it was starting.
        if (paused) await player.pause();
        await Future.any([done, _cancelled.future]);
        _playing = null;
        if (cancelled) return false;
        _forget(i);
        onHeard?.call();
      }
      return true;
    } on Object {
      return false;
    } finally {
      for (final i in _made.keys.toList()) {
        _forget(i);
      }
    }
  }

  /// The file of a piece is deleted once heard, or once it is no longer
  /// wanted, whenever it is finished being made.
  void _forget(int i) {
    final made = _made.remove(i);
    made?.then((path) {
      if (path != null) File(path).delete().ignore();
    });
  }

  Future<void> _whileUnpaused() async {
    while (_unpaused != null && !cancelled) {
      await Future.any([_unpaused!.future, _cancelled.future]);
    }
  }

  void pause() {
    if (cancelled || paused) return;
    _unpaused = Completer();
    _playing?.pause();
  }

  void resume() {
    final unpaused = _unpaused;
    if (unpaused == null) return;
    _unpaused = null;
    _playing?.resume();
    unpaused.complete();
  }

  void cancel() {
    if (cancelled) return;
    _cancelled.complete();
    // What it asked for and no longer wants is not made.
    synth.forget(this);
  }
}

/// The model, loaded on an isolate of its own so that making speech never
/// holds up the screen.
@visibleForTesting
class Synthesiser {
  Synthesiser._(this._isolate, this._requests, this._replies);

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _replies;
  final Map<int, Completer<String?>> _waiting = {};
  int _next = 0;

  /// Asked for and not yet sent. The isolate is handed one at a time, so
  /// that what is no longer wanted — after a skip, say — can be dropped
  /// before it takes its turn, rather than keep the next words waiting.
  final List<_Request> _queue = [];
  bool _busy = false;

  /// How long making speech takes against how long it lasts, smoothed
  /// over the pieces made so far; above 1 it cannot keep up.
  double _pace = 0;
  int _made = 0;

  /// Whether this device makes speech more slowly than it is heard.
  bool get fallingBehind => _made >= 4 && _pace > 1.05;

  static Future<Synthesiser> start(NeuralModel model, String directory) async {
    final replies = ReceivePort();
    final threads = math.min(4, math.max(1, Platform.numberOfProcessors - 1));
    final isolate = await Isolate.spawn(_serve, (
      replies.sendPort,
      directory,
      model.modelFile,
      threads,
    ), debugName: 'voice');
    final first = Completer<Object?>();
    late final Synthesiser synth;
    replies.listen((message) {
      if (!first.isCompleted) {
        first.complete(message);
        return;
      }
      if (message case (int id, String? path, double lasts, double took)) {
        if (path != null && lasts > 0) {
          final pace = took / lasts;
          synth._pace = synth._made == 0
              ? pace
              : synth._pace * 0.7 + pace * 0.3;
          synth._made++;
        }
        synth._waiting.remove(id)?.complete(path);
        synth._busy = false;
        synth._sendNext();
      }
    });
    final answer = await first.future;
    if (answer is! SendPort) {
      replies.close();
      isolate.kill();
      throw StateError('The voice could not be loaded: $answer');
    }
    return synth = Synthesiser._(isolate, answer, replies);
  }

  /// Makes [text] into a WAV file at [path]; null if it could not, or if
  /// [owner] no longer wants it.
  Future<String?> say(
    String text, {
    required int speaker,
    required double speed,
    required String path,
    Object? owner,
  }) {
    final id = _next++;
    final waiting = _waiting[id] = Completer<String?>();
    _queue.add(_Request(id, (id, text, speaker, speed, path), owner));
    _sendNext();
    return waiting.future;
  }

  void _sendNext() {
    if (_busy || _queue.isEmpty) return;
    _busy = true;
    _requests.send(_queue.removeAt(0).message);
  }

  /// Drops what [owner] asked for that has not yet been begun.
  void forget(Object owner) {
    _queue.removeWhere((request) {
      if (!identical(request.owner, owner)) return false;
      _waiting.remove(request.id)?.complete(null);
      return true;
    });
  }

  void close() {
    _requests.send(null);
    _replies.close();
    _queue.clear();
    for (final waiting in _waiting.values) {
      waiting.complete(null);
    }
    _waiting.clear();
    // Let it free the model before it goes.
    Future<void>.delayed(const Duration(seconds: 5), _isolate.kill);
  }

  static sherpa.OfflineTtsModelConfig configFor(
    String directory,
    String modelFile,
    int threads,
  ) => sherpa.OfflineTtsModelConfig(
    kitten: sherpa.OfflineTtsKittenModelConfig(
      model: '$directory/$modelFile',
      voices: '$directory/voices.bin',
      tokens: '$directory/tokens.txt',
      dataDir: '$directory/espeak-ng-data',
    ),
    numThreads: threads,
    debug: false,
  );

  /// [samples] turned down, if need be, so that none is louder than
  /// [ceiling].
  ///
  /// A model's output can go past full scale, and written out as 16-bit
  /// samples the loudest are cut off flat: heard as a crackle. Where a
  /// piece would be, the whole piece is made a little quieter instead.
  static Float32List limited(Float32List samples, {double ceiling = 0.95}) {
    var peak = 0.0;
    for (final sample in samples) {
      final level = sample.abs();
      if (level > peak) peak = level;
    }
    if (peak <= ceiling) return samples;
    final gain = ceiling / peak;
    return Float32List.fromList([for (final sample in samples) sample * gain]);
  }

  static void _serve((SendPort, String, String, int) setup) {
    final (reply, directory, modelFile, threads) = setup;
    final sherpa.OfflineTts tts;
    try {
      sherpa.initBindings();
      tts = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: configFor(directory, modelFile, threads),
        ),
      );
    } on Object catch (error) {
      reply.send('$error');
      return;
    }
    final requests = ReceivePort();
    reply.send(requests.sendPort);
    // The first run of a model is slower than any after it; it is had
    // now, while nothing is waiting to be heard.
    try {
      tts.generate(text: 'Hello.', sid: 0, speed: 1);
    } on Object {
      // Found out on the first real piece, if it matters.
    }
    requests.listen((message) {
      if (message case (
        int id,
        String text,
        int speaker,
        double speed,
        String path,
      )) {
        String? made;
        var lasts = 0.0;
        final clock = Stopwatch()..start();
        try {
          final audio = tts.generate(text: text, sid: speaker, speed: speed);
          final samples = limited(audio.samples);
          if (samples.isNotEmpty &&
              sherpa.writeWave(
                filename: path,
                samples: samples,
                sampleRate: audio.sampleRate,
              )) {
            made = path;
            lasts = samples.length / audio.sampleRate;
          }
        } on Object {
          made = null;
        }
        final took = clock.elapsedMicroseconds / Duration.microsecondsPerSecond;
        reply.send((id, made, lasts, took));
      } else {
        tts.free();
        requests.close();
      }
    });
  }
}

class _Request {
  _Request(this.id, this.message, this.owner);

  final int id;
  final (int, String, int, double, String) message;
  final Object? owner;
}
