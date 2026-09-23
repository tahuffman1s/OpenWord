import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../model/bible.dart';

/// A voice the platform offers.
@immutable
class SpeechVoice {
  const SpeechVoice({required this.name, required this.locale});

  final String name;
  final String locale;
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
  /// and false when it was stopped or failed.
  Future<bool> speak(String text);

  Future<void> stop();

  /// The voices for a language, best first.
  Future<List<SpeechVoice>> voices(String language);
}

/// The platform's own text-to-speech, through flutter_tts. Nothing leaves
/// the device: every platform it supports speaks with voices it already
/// has.
class PlatformSpeechEngine implements SpeechEngine {
  PlatformSpeechEngine() {
    _tts.setCompletionHandler(() => _finish(true));
    _tts.setCancelHandler(() => _finish(false));
    _tts.setErrorHandler((_) => _finish(false));
  }

  final FlutterTts _tts = FlutterTts();
  Completer<bool>? _pending;

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

  /// Apple's voices take 0.5 as their normal pace and everyone else's take
  /// 1.0, so the reader's multiple is scaled to the platform's.
  static double get _normalRate =>
      !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)
      ? 0.5
      : 1.0;

  @override
  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  }) async {
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(_normalRate * rate);
    if (voice != null) {
      final match = (await voices(language)).where((v) => v.name == voice);
      if (match.isNotEmpty) {
        await _tts.setVoice({
          'name': match.first.name,
          'locale': match.first.locale,
        });
      }
    }
  }

  @override
  Future<bool> speak(String text) async {
    _finish(false);
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
    if (raw is! List) return const [];
    final prefix = language.split('-').first.toLowerCase();
    final result = <SpeechVoice>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['name']?.toString();
      final locale = entry['locale']?.toString() ?? '';
      if (name == null) continue;
      if (!locale.toLowerCase().startsWith(prefix)) continue;
      result.add(SpeechVoice(name: name, locale: locale));
    }
    // The translation's own region first: a British edition in a British
    // voice.
    final exact = language.toLowerCase().replaceAll('_', '-');
    result.sort((a, b) {
      final aExact = a.locale.toLowerCase().replaceAll('_', '-') == exact;
      final bExact = b.locale.toLowerCase().replaceAll('_', '-') == exact;
      if (aExact != bExact) return aExact ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return result;
  }
}

/// Makes the engine the reader speaks with. A test puts a silent one in
/// its place.
SpeechEngine Function() createSpeechEngine = PlatformSpeechEngine.new;

enum ReadAloudState { idle, playing, paused }

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
/// A verse at a time rather than a chapter at a time, because that is what
/// lets the page follow along, and lets the reader step back a verse or on
/// to the next without losing their place. Pausing stops the voice and
/// remembers the verse; resuming says that verse again from its beginning,
/// which every platform can do, where a true mid-sentence pause is only
/// offered by some.
class ReadAloud extends ChangeNotifier {
  ReadAloud({
    required this.engine,
    required this.chapterFor,
    required this.nextChapter,
    this.onChapterHeard,
  });

  final SpeechEngine engine;

  /// The chapter at a reference, from the translation being read.
  final Chapter? Function(Reference chapter) chapterFor;

  /// The chapter to go on to after this one, or null to stop.
  final Reference? Function(Reference chapter) nextChapter;

  /// Called when a whole chapter has been heard to its last verse.
  final void Function(Reference chapter)? onChapterHeard;

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

  ReadAloudState get state => _state;
  bool get isActive => _state != ReadAloudState.idle;
  bool get isPlaying => _state == ReadAloudState.playing;

  /// What is being said, or was about to be when paused: a verse, or a
  /// chapter with no verse while its name is announced.
  Reference? get current =>
      isActive && _index < _queue.length ? _queue[_index].reference : null;

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
    if (changed && isPlaying) _speakCurrent(interrupt: true);
  }

  /// Starts reading at [from]: its verse, or the top of its chapter with
  /// the chapter's name. With [only], reads those verses and stops.
  void play(Reference from, {Set<int>? only}) {
    final chapter = from.withVerse(null);
    _stopAtEnd = only != null;
    _startedAtTop = only == null && (from.verse ?? 1) <= 1;
    _queue = _utterancesFor(
      chapter,
      from: from.verse ?? 1,
      only: only,
      announce: _startedAtTop,
    );
    _index = 0;
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
    _generation++;
    _state = ReadAloudState.paused;
    notifyListeners();
    engine.stop();
  }

  void resume() {
    if (_state != ReadAloudState.paused) return;
    _state = ReadAloudState.playing;
    notifyListeners();
    _speakCurrent();
  }

  void stop() {
    _generation++;
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
    _generation++;
    if (isActive) engine.stop();
    super.dispose();
  }

  /// Says the current utterance, and on to the next when it is done.
  ///
  /// With [interrupt], whatever is being said is stopped first: some
  /// platforms queue a second utterance behind the first rather than
  /// replacing it.
  Future<void> _speakCurrent({bool interrupt = false}) async {
    final generation = ++_generation;
    final utterance = _queue[_index];
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
    final said = await engine.speak(utterance.text);
    if (generation != _generation) return;
    if (!said) {
      error =
          'Could not read aloud. The device may have no voice for this '
          'translation’s language installed.';
      stop();
      return;
    }
    if (_index + 1 < _queue.length) {
      _index++;
      notifyListeners();
      _speakCurrent();
      return;
    }
    _advanceChapter(heardToEnd: true);
  }

  void _advanceChapter({required bool heardToEnd}) {
    final chapter = _queue.first.reference.withVerse(null);
    if (heardToEnd && _startedAtTop) onChapterHeard?.call(chapter);
    final next = _stopAtEnd ? null : nextChapter(chapter);
    if (next == null) {
      stop();
      return;
    }
    _queue = _utterancesFor(next, from: 1, announce: true);
    _startedAtTop = true;
    _index = 0;
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
