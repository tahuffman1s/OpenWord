import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../model/bible.dart';
import 'neural_voices.dart';

/// A voice the platform offers.
@immutable
class SpeechVoice {
  const SpeechVoice({
    required this.name,
    required this.locale,
    this.title,
    this.quality = 0,
    this.online = false,
    this.builtIn = false,
  });

  /// What the voice is chosen by, and kept in settings as.
  final String name;
  final String locale;

  /// What to call it, where that is not its name.
  final String? title;

  /// Whether it is one of OpenWord's own, downloaded into the app, rather
  /// than one of the platform's.
  final bool builtIn;

  /// Whether the voice needs the internet: it sends the words to its
  /// provider to be spoken, where every other voice speaks on the device.
  final bool online;

  /// How natural the platform says the voice is, higher better: Apple's
  /// premium and enhanced voices, Android's "very high" and "high"; and
  /// above them all, OpenWord's own neural voices.
  final int quality;

  /// What the voice sheet calls it, where it is better than ordinary.
  String? get qualityLabel => quality >= 3
      ? 'Natural'
      : quality == 2
      ? 'Enhanced'
      : null;

  /// The voices a platform lists that can read [language], best first.
  ///
  /// Voices listed but not downloaded are left out. The most natural come
  /// first, and among equals the translation's own region, so a British
  /// edition is heard in a British voice when one is as good; then a voice
  /// on the device before one that needs the internet.
  static List<SpeechVoice> rank(List<Object?> raw, String language) {
    final prefix = language.split(RegExp('[-_]')).first.toLowerCase();
    final exact = language.toLowerCase().replaceAll('_', '-');
    final result = <SpeechVoice>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['name']?.toString();
      final locale = entry['locale']?.toString() ?? '';
      if (name == null) continue;
      if (!locale.toLowerCase().startsWith(prefix)) continue;
      if ((entry['features']?.toString() ?? '').contains('notInstalled')) {
        continue;
      }
      result.add(
        SpeechVoice(
          name: name,
          locale: locale,
          online: entry['network_required']?.toString() == '1',
          quality: switch (entry['quality']?.toString()) {
            'premium' || 'very high' => 3,
            'enhanced' || 'high' => 2,
            'default' || 'normal' => 1,
            _ => 0,
          },
        ),
      );
    }
    bool own(SpeechVoice v) =>
        v.locale.toLowerCase().replaceAll('_', '-') == exact;
    result.sort((a, b) {
      if (a.quality != b.quality) return b.quality - a.quality;
      if (own(a) != own(b)) return own(a) ? -1 : 1;
      if (a.online != b.online) return a.online ? 1 : -1;
      return a.name.compareTo(b.name);
    });
    return result;
  }
}

/// What reading aloud needs from the platform's text-to-speech. A seam, so
/// a test can drive playback without a device that talks.
abstract class SpeechEngine {
  /// Whether this platform can speak at all.
  bool get isAvailable;

  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  });

  /// Speaks [text]. Completes with true when it has been said to the end,
  /// and false when it was stopped or failed. Where the platform says how
  /// far it has got, [onProgress] is given the offset in [text] of each
  /// word as it is reached.
  Future<bool> speak(
    String text, {
    void Function(int offset)? onProgress,
    void Function()? onStart,
  });

  Future<void> stop();

  /// The voices for a language, best first.
  Future<List<SpeechVoice>> voices(String language);

  /// Whether [pause] holds the voice where it is, for [resume] to go on
  /// from mid-word. Where it cannot, pausing stops the voice, and resuming
  /// speaks again from the word it had reached.
  bool get canPause;

  Future<void> pause();

  Future<void> resume();
}

/// The platform's own text-to-speech, through flutter_tts. Nothing leaves
/// the device: every platform it supports speaks with voices it already
/// has.
class PlatformSpeechEngine implements SpeechEngine {
  PlatformSpeechEngine() {
    _tts.setStartHandler(() {
      _started = true;
      _onStart?.call();
    });
    _tts.setCompletionHandler(() => _finish(true));
    // Stopping the voice to move to another verse is reported back after
    // the fact, and can arrive once the next verse has been handed over.
    // Read as the end of that next verse, it looked like the device giving
    // up — "could not read aloud" in the middle of a chapter. A stop heard
    // before the current utterance has even started belongs to the one
    // before it, and is ignored.
    _tts.setCancelHandler(() {
      if (_started) _finish(false);
    });
    _tts.setErrorHandler((_) => _finish(false));
    _tts.setProgressHandler((text, start, end, word) {
      // Only for what is being said now: a word reported late from an
      // utterance already stopped is not this one's.
      if (text == _speaking) _onProgress?.call(start);
    });
  }

  String? _speaking;
  void Function(int offset)? _onProgress;
  void Function()? _onStart;

  final FlutterTts _tts = FlutterTts();
  Completer<bool>? _pending;

  /// Whether the utterance being waited on has begun to be spoken.
  bool _started = false;
  bool _sessionReady = false;

  /// On iOS the voice is played through an audio session of the app's
  /// own. It has to be a playback session, which the silent switch and the
  /// lock screen do not mute, and it has to stay open between verses: the
  /// plugin closes it after every utterance by default, and an app with no
  /// audio session open is suspended in the background between one verse
  /// and the next.
  Future<void> _prepareSession() async {
    if (_sessionReady) return;
    _sessionReady = true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    await _tts.setSharedInstance(true);
    await _tts.autoStopSharedSession(false);
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      const [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.allowAirPlay,
      ],
      IosTextToSpeechAudioMode.spokenAudio,
    );
  }

  void _finish(bool spokenToTheEnd) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(spokenToTheEnd);
    }
  }

  /// Linux has no plugin, so there is nothing to speak with.
  @override
  bool get isAvailable =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.linux;

  /// The value handed to the plugin for a pace of [multiple] times normal.
  ///
  /// The plugin does not mean the same thing by a rate everywhere. On the
  /// web it goes straight to the browser, where 1.0 is normal. Everywhere
  /// else 0.5 is normal: Apple's voices take 0.5 as their default, the
  /// plugin doubles the value on its way to Android (whose normal is 1.0),
  /// and on Windows it adds 0.5 to it. Handing Android 1.0 for normal, as
  /// this once did, read everything at twice the speed.
  static double rateFor(double multiple, {required bool web}) =>
      (web ? 1.0 : 0.5) * multiple;

  @override
  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  }) async {
    await _prepareSession();
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(rateFor(rate, web: kIsWeb));
    // With no voice chosen, the most natural one on the device rather than
    // the platform's default, which is often its plainest. An online voice
    // is used only when someone has chosen it: it sends the words away.
    final available = await voices(language);
    final match = voice == null
        ? available.where((v) => !v.online).take(1)
        : available.where((v) => v.name == voice);
    if (match.isNotEmpty) {
      await _tts.setVoice({
        'name': match.first.name,
        'locale': match.first.locale,
      });
    }
  }

  @override
  Future<bool> speak(
    String text, {
    void Function(int offset)? onProgress,
    void Function()? onStart,
  }) async {
    _finish(false);
    _started = false;
    _speaking = text;
    _onProgress = onProgress;
    _onStart = onStart;
    final pending = _pending = Completer<bool>();
    try {
      await _tts.speak(text);
    } on Object {
      _finish(false);
    }
    return pending.future;
  }

  @override
  Future<void> stop() async {
    _finish(false);
    await _tts.stop();
  }

  @override
  Future<List<SpeechVoice>> voices(String language) async {
    final raw = await _tts.getVoices;
    return raw is List ? SpeechVoice.rank(raw, language) : const [];
  }

  /// Android's pause is a stop that remembers the word, no better than
  /// what [ReadAloud] does itself, and Apple's cannot be relied on to come
  /// back after the audio session has been interrupted.
  @override
  bool get canPause => false;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}
}

/// The platform's voices and OpenWord's own as one engine. Which of them
/// speaks is decided by the voice chosen.
class SpeechEngines implements SpeechEngine {
  SpeechEngines(this.platform, this.neural);

  final SpeechEngine platform;
  final NeuralVoices neural;
  SpeechEngine? _own;
  late SpeechEngine _active = platform;

  @override
  bool get isAvailable => platform.isAvailable;

  @override
  bool get canPause => _active.canPause;

  @override
  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  }) async {
    final chosen = NeuralModel.parse(voice);
    if (chosen != null && neural.isSupported) {
      await neural.ready;
      if (neural.isInstalled(chosen.$1)) {
        final own = _own ??= neural.engine();
        try {
          await _switchTo(own);
          await own.configure(language: language, rate: rate, voice: voice);
          return;
        } on Object catch (error) {
          // A model that will not load: the platform's voice rather than
          // silence.
          debugPrint('OpenWord: the voice could not be loaded: $error');
        }
      }
    }
    await _switchTo(platform);
    await platform.configure(
      language: language,
      rate: rate,
      voice: chosen == null ? voice : null,
    );
  }

  Future<void> _switchTo(SpeechEngine engine) async {
    if (identical(engine, _active)) return;
    await _active.stop();
    _active = engine;
  }

  @override
  Future<bool> speak(
    String text, {
    void Function(int offset)? onProgress,
    void Function()? onStart,
  }) => _active.speak(text, onProgress: onProgress, onStart: onStart);

  @override
  Future<void> stop() => _active.stop();

  @override
  Future<void> pause() => _active.pause();

  @override
  Future<void> resume() => _active.resume();

  @override
  Future<List<SpeechVoice>> voices(String language) async {
    if (neural.isSupported) await neural.ready;
    return [
      if (neural.isSupported) ...neural.voicesFor(language),
      ...await platform.voices(language),
    ];
  }
}

/// Makes the engine the reader speaks with. A test puts a silent one in
/// its place.
SpeechEngine Function() createSpeechEngine = () =>
    SpeechEngines(PlatformSpeechEngine(), neuralVoices);

enum ReadAloudState { idle, playing, paused }

/// Where listening got to: a verse, and how far into it, kept so that it
/// can be taken up again after the bar is closed or the app is.
@immutable
class ListeningPlace {
  const ListeningPlace(this.verse, {this.offset = 0, this.fromTop = false});

  final Reference verse;

  /// How far into the verse's spoken words.
  final int offset;

  /// Whether the chapter was begun from its top, so that finishing it
  /// still counts it as heard.
  final bool fromTop;

  /// Nothing heard yet: taking it up is the same as starting.
  bool get atTop => (verse.verse ?? 1) <= 1 && offset == 0;

  String encode() => '${verse.encode()}|$offset|${fromTop ? 1 : 0}';

  static ListeningPlace? decode(String? raw) {
    final parts = raw?.split('|');
    if (parts == null || parts.length != 3) return null;
    final verse = Reference.decode(parts[0]);
    final offset = int.tryParse(parts[1]);
    if (verse == null || verse.verse == null || offset == null) return null;
    return ListeningPlace(verse, offset: offset, fromTop: parts[2] == '1');
  }

  @override
  bool operator ==(Object other) =>
      other is ListeningPlace &&
      other.verse == verse &&
      other.offset == offset &&
      other.fromTop == fromTop;

  @override
  int get hashCode => Object.hash(verse, offset, fromTop);
}

/// One thing to say: a verse, or the name of a chapter as it begins.
@immutable
class Utterance {
  const Utterance(this.reference, this.text);

  /// Carries a verse, or none for a chapter's announcement.
  final Reference reference;
  final String text;
}

/// Reads Scripture aloud, a verse at a time.
///
/// It keeps its place by the verse, which is what lets the page follow
/// along and lets the reader step back a verse or on to the next; the
/// voice is handed passages of several verses at once, and the words the
/// platform reports reaching say which verse it is on. Pausing holds the
/// voice where it is, where the engine can; otherwise it stops the voice
/// and remembers the word it had reached, and resuming takes up from that
/// word, which every platform can do.
class ReadAloud extends ChangeNotifier {
  ReadAloud({
    required this.engine,
    required this.chapterFor,
    required this.nextChapter,
    this.onChapterHeard,
    this.onPlace,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// What time it is; a test sets it.
  final DateTime Function() _clock;

  final SpeechEngine engine;

  /// The chapter at a reference, from the translation being read.
  final Chapter? Function(Reference chapter) chapterFor;

  /// The chapter to go on to after this one, or null to stop.
  final Reference? Function(Reference chapter) nextChapter;

  /// Called when a whole chapter has been heard to its last verse.
  final void Function(Reference chapter)? onChapterHeard;

  /// Told where listening has got to as it moves from verse to verse, and
  /// when it is paused or stopped, so that it can be kept; told null when
  /// it has been heard to its end and there is nothing to take up. Not
  /// told about reading a selection.
  final void Function(ListeningPlace? place)? onPlace;
  ListeningPlace? _lastPlace;

  ReadAloudState _state = ReadAloudState.idle;
  List<Utterance> _queue = const [];
  int _index = 0;
  bool _stopAtEnd = false;
  bool _startedAtTop = false;
  int _generation = 0;

  String _language = 'en';
  double _rate = 1.0;
  String? _voice;

  /// The settings last handed to the engine, so they are sent again only
  /// when they change: looking a voice up is not free.
  (String, double, String?)? _applied;
  String? error;

  /// Whether the verse being said is a second attempt at it.
  bool _retrying = false;

  /// How far into the current verse the voice had got, from the words the
  /// platform reports, so that resuming after a pause takes up that word
  /// rather than starting the verse again.
  int _resumeAt = 0;

  /// Whether the engine is holding the passage, paused where it is, to go
  /// on from there.
  bool _held = false;

  /// The generation whose passage the engine has been given and not yet
  /// finished.
  int _saying = -1;

  /// How long to wait before saying a verse again after the engine did not
  /// finish it.
  @visibleForTesting
  static Duration retryDelay = const Duration(milliseconds: 400);

  ReadAloudState get state => _state;
  bool get isActive => _state != ReadAloudState.idle;
  bool get isPlaying => _state == ReadAloudState.playing;

  /// What is being said, or was about to be when paused: a verse, or a
  /// chapter with no verse while its name is announced.
  Reference? get current =>
      isActive && _index < _queue.length ? _queue[_index].reference : null;

  /// Where to take up again, as it would be kept.
  ListeningPlace? get place {
    final verse = current;
    if (verse == null || verse.verse == null || _stopAtEnd) return null;
    return ListeningPlace(verse, offset: _resumeAt, fromTop: _startedAtTop);
  }

  void _notePlace() {
    final place = this.place;
    if (place == null || place == _lastPlace) return;
    _lastPlace = place;
    onPlace?.call(place);
  }

  @override
  void notifyListeners() {
    _notePlace();
    super.notifyListeners();
  }

  /// Lets go of a passage the engine is holding paused, when what is to be
  /// said next is not what it holds.
  void _release() {
    if (!_held) return;
    _held = false;
    _generation++;
    engine.stop();
  }

  /// Sets how it sounds. Takes effect from the next verse, or at once when
  /// something is being said.
  void configure({
    required String language,
    required double rate,
    String? voice,
  }) {
    final changed = language != _language || rate != _rate || voice != _voice;
    _language = language;
    _rate = rate;
    _voice = voice;
    if (!changed) return;
    if (isPlaying) {
      _speakCurrent(interrupt: true);
    } else {
      // Held in the old voice; resuming says it again in the new one.
      _release();
    }
  }

  /// Starts reading at [from]: its verse, or the top of its chapter with
  /// the chapter's name. With [only], reads those verses and stops.
  ///
  /// [offset] takes up the verse part way in, and [fromTop] says the
  /// chapter was begun from its top before, for taking up a kept place.
  void play(
    Reference from, {
    Set<int>? only,
    int offset = 0,
    bool fromTop = false,
  }) {
    _release();
    final chapter = from.withVerse(null);
    final atTop = only == null && (from.verse ?? 1) <= 1 && offset == 0;
    _stopAtEnd = only != null;
    _startedAtTop = atTop || (only == null && fromTop);
    _queue = _utterancesFor(
      chapter,
      from: from.verse ?? 1,
      only: only,
      announce: atTop,
    );
    _index = 0;
    _resumeAt = _queue.isNotEmpty && _queue.first.reference == from
        ? offset
        : 0;
    error = null;
    if (_queue.isEmpty) {
      stop();
      return;
    }
    _state = ReadAloudState.playing;
    notifyListeners();
    _speakCurrent();
  }

  void pause() {
    if (!isPlaying) return;
    _estimator?.cancel();
    if (engine.canPause && _saying == _generation) {
      // Held where it is, mid-word, to go on from there.
      _held = true;
      _state = ReadAloudState.paused;
      notifyListeners();
      engine.pause();
      return;
    }
    // Where it had got to. Exact where the platform reports its words;
    // otherwise estimated from the time it has been speaking, and taken
    // back to the start of that sentence so that nothing is skipped.
    if (!_passageHasProgress) {
      _estimate();
      if (_index < _queue.length) {
        _resumeAt = sentenceStart(_queue[_index].text, _resumeAt);
      }
    }
    _estimator?.cancel();
    _generation++;
    _state = ReadAloudState.paused;
    notifyListeners();
    engine.stop();
  }

  void resume() {
    if (_state != ReadAloudState.paused) return;
    _state = ReadAloudState.playing;
    notifyListeners();
    if (_held) {
      _held = false;
      engine.resume();
      return;
    }
    _speakCurrent();
  }

  void stop() {
    if (isPlaying && !_passageHasProgress) {
      _estimate();
      if (_index < _queue.length) {
        _resumeAt = sentenceStart(_queue[_index].text, _resumeAt);
      }
    }
    // Kept, to be taken up another time.
    _notePlace();
    _end();
  }

  void _end() {
    _estimator?.cancel();
    _generation++;
    _held = false;
    final wasActive = isActive;
    _state = ReadAloudState.idle;
    _queue = const [];
    _index = 0;
    if (wasActive) engine.stop();
    notifyListeners();
  }

  /// On to the next verse, or back to the one before. Stepping back from a
  /// chapter's first verse says it again.
  void skip(int delta) {
    if (!isActive) return;
    _release();
    // Stepping is from the verse the voice is on, as near as can be told.
    if (isPlaying && !_passageHasProgress) _estimate();
    _resumeAt = 0;
    final next = (_index + delta).clamp(0, _queue.length - 1);
    if (delta > 0 && _index + delta >= _queue.length) {
      _generation++;
      engine.stop();
      _advanceChapter(heardToEnd: false);
      return;
    }
    _index = next;
    notifyListeners();
    if (isPlaying) _speakCurrent(interrupt: true);
  }

  @override
  void dispose() {
    _estimator?.cancel();
    _generation++;
    if (isActive) engine.stop();
    super.dispose();
  }

  /// How much is handed to the voice at once, in characters.
  ///
  /// Not a verse at a time: a voice that starts and stops between every
  /// verse clips the first syllable of many of them, most of all over
  /// Bluetooth, which lets the link sleep in the gaps. Several verses go
  /// together as one utterance. Where the platform reports each word as it
  /// reaches it, that says which verse is being read, and a passage can be
  /// long. Where it does not — Samsung's engine among others — the verse is
  /// estimated from how long the voice has been speaking, and a passage is
  /// kept to half a minute or so, so that the estimate never drifts far
  /// before the next passage puts it right.
  static const int passageLength = 1200;
  static const int estimatedPassageLength = 400;

  /// Whether this platform reports the words it reaches: unknown until it
  /// has read something.
  bool? _reportsProgress;

  /// How fast the voice speaks at normal pace, in characters a second: a
  /// fair guess to begin with, then measured from each passage it finishes.
  double _charsPerSecond = 14;

  // The passage being spoken, for estimating where the voice has got to.
  List<int> _passageStarts = const [];
  int _passageFirst = 0;
  int _passageTrim = 0;
  int _passageLength = 0;
  DateTime? _passageStartedAt;
  bool _passageHasProgress = false;
  Timer? _estimator;

  /// Moves the place along by the time the voice has been speaking, where
  /// the platform does not say which word it is on.
  void _estimate() {
    final startedAt = _passageStartedAt;
    if (_passageHasProgress || startedAt == null || _passageStarts.isEmpty) {
      return;
    }
    final seconds =
        _clock().difference(startedAt).inMilliseconds /
        Duration.millisecondsPerSecond;
    final offset = (seconds * _charsPerSecond * _rate).floor().clamp(
      0,
      _passageLength > 0 ? _passageLength - 1 : 0,
    );
    _place(offset);
  }

  /// Takes an offset into the passage to the verse, and the place in it.
  void _place(int offset) {
    final starts = _passageStarts;
    var k = 0;
    while (k + 1 < starts.length && starts[k + 1] <= offset) {
      k++;
    }
    _resumeAt = (k == 0 ? _passageTrim : 0) + offset - starts[k];
    if (_passageFirst + k != _index) {
      _index = _passageFirst + k;
      notifyListeners();
    }
  }

  /// Where the sentence around [offset] in [text] begins, so that a place
  /// that is only estimated is taken back to somewhere sensible to resume.
  static int sentenceStart(String text, int offset) {
    if (offset <= 0 || offset > text.length) return 0;
    var start = 0;
    for (final end in _sentenceEnd.allMatches(text)) {
      if (end.end > offset) break;
      start = end.end;
    }
    return start;
  }

  static final RegExp _sentenceEnd = RegExp('[.;:!?][”’"\')]*\\s+');

  /// Test hook: estimate the place now, as the timer would.
  @visibleForTesting
  void debugEstimate() => _estimate();

  /// Says a passage from the current verse on, and on to the next when it
  /// is done.
  ///
  /// With [interrupt], whatever is being said is stopped first: some
  /// platforms queue a second utterance behind the first rather than
  /// replacing it.
  Future<void> _speakCurrent({bool interrupt = false}) async {
    final generation = ++_generation;
    if (interrupt) await engine.stop();
    if (generation != _generation) return;
    final wanted = (_language, _rate, _voice);
    if (_applied != wanted) {
      _applied = wanted;
      try {
        await engine.configure(language: _language, rate: _rate, voice: _voice);
      } on Object {
        // A voice or rate the platform refuses still leaves it able to
        // speak.
      }
    }
    if (generation != _generation) return;

    // The passage: this verse and those after it, as far as will go. After
    // a pause it takes up the verse at the word it had reached.
    final first = _index;
    final firstText = _queue[first].text;
    final trim = _resumeAt > 0 && _resumeAt < firstText.length ? _resumeAt : 0;
    final starts = <int>[];
    final passage = StringBuffer();
    final length = _reportsProgress == true
        ? passageLength
        : estimatedPassageLength;
    var last = first;
    for (var i = first; i < _queue.length; i++) {
      final text = i == first ? firstText.substring(trim) : _queue[i].text;
      if (i > first && passage.length + 1 + text.length > length) break;
      if (i > first) passage.write(' ');
      starts.add(passage.length);
      passage.write(text);
      last = i;
    }
    final text = passage.toString();
    _passageStarts = starts;
    _passageFirst = first;
    _passageTrim = trim;
    _passageLength = text.length;
    _passageHasProgress = false;
    // Counted from when the platform says it has begun, or from now where
    // it says nothing.
    _passageStartedAt = _clock();
    _estimator?.cancel();
    if (_reportsProgress != true) {
      _estimator = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (generation == _generation && isPlaying) _estimate();
      });
    }
    _saying = generation;
    final said = await engine.speak(
      text,
      onStart: () {
        if (generation == _generation) _passageStartedAt = _clock();
      },
      onProgress: (offset) {
        if (generation != _generation) return;
        _passageHasProgress = true;
        _estimator?.cancel();
        // Exact: this word, in its verse.
        _place(offset);
      },
    );
    _estimator?.cancel();
    if (generation != _generation) return;
    _saying = -1;
    final progressed = _passageHasProgress;
    final startedAt = _passageStartedAt;
    if (!said) {
      // Once is a hiccup — an engine still waking up, a stop reported
      // late — and the verse is simply said again. Twice running, the
      // device really is not speaking.
      if (!_retrying) {
        _retrying = true;
        await Future<void>.delayed(retryDelay);
        if (generation != _generation) return;
        _speakCurrent();
        return;
      }
      _retrying = false;
      error =
          'Could not read aloud. The device may have no voice for this '
          'translation’s language installed.';
      stop();
      return;
    }
    _retrying = false;
    if (progressed) {
      _reportsProgress = true;
    } else {
      _reportsProgress ??= false;
      // How fast this voice really is, from a passage it has finished,
      // for the next estimate.
      final seconds = startedAt == null
          ? 0.0
          : _clock().difference(startedAt).inMilliseconds /
                Duration.millisecondsPerSecond;
      if (seconds >= 2 && text.length >= 40) {
        final measured = text.length / seconds / _rate;
        _charsPerSecond = (_charsPerSecond + measured) / 2;
      }
    }
    _resumeAt = 0;
    if (last + 1 < _queue.length) {
      _index = last + 1;
      notifyListeners();
      _speakCurrent();
      return;
    }
    _index = last;
    _advanceChapter(heardToEnd: true);
  }

  void _advanceChapter({required bool heardToEnd}) {
    final chapter = _queue.first.reference.withVerse(null);
    if (heardToEnd && _startedAtTop) onChapterHeard?.call(chapter);
    final next = _stopAtEnd ? null : nextChapter(chapter);
    if (next == null) {
      if (heardToEnd && !_stopAtEnd) {
        // Heard to the end: nothing is left to take up.
        _lastPlace = null;
        onPlace?.call(null);
        _end();
      } else {
        stop();
      }
      return;
    }
    _queue = _utterancesFor(next, from: 1, announce: true);
    _startedAtTop = true;
    _index = 0;
    _resumeAt = 0;
    if (_queue.isEmpty) {
      stop();
      return;
    }
    notifyListeners();
    if (isPlaying) _speakCurrent();
  }

  List<Utterance> _utterancesFor(
    Reference chapterRef, {
    required int from,
    Set<int>? only,
    required bool announce,
  }) {
    final chapter = chapterFor(chapterRef);
    if (chapter == null) return const [];
    return [
      if (announce) Utterance(chapterRef, announcement(chapterRef)),
      for (var verse = from; verse <= chapter.verseCount; verse++)
        if (only == null || only.contains(verse))
          if (speakable(chapter.verseText(verse)) case final text
              when text.isNotEmpty)
            Utterance(chapterRef.withVerse(verse), text),
    ];
  }

  /// "Genesis, chapter 1." A psalm is a psalm.
  static String announcement(Reference chapter) => switch (chapter.bookCode) {
    'PSA' => 'Psalm ${chapter.chapter}.',
    _ => '${chapter.bookName}, chapter ${chapter.chapter}.',
  };

  /// The words as they should be heard.
  ///
  /// The divine name is printed in capitals to set it apart on the page,
  /// and a voice reading "LORD" may spell it out letter by letter; it is
  /// said as a word.
  static String speakable(String text) => text
      .replaceAllMapped(_capitalName, (m) => m[1] == 'LORD' ? 'Lord' : 'God')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static final RegExp _capitalName = RegExp(r'\b(LORD|GOD)\b');
}
