import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/bible.dart';
import 'neural_voices.dart';

/// One of the voices reading aloud can be heard in.
@immutable
class SpeechVoice {
  const SpeechVoice({required this.name, required this.locale, this.title});

  /// What the voice is chosen by, and kept in settings as.
  final String name;
  final String locale;

  /// What to call it, where that is not its name.
  final String? title;
}

/// What reading aloud needs from whatever speaks. A seam, so a test can
/// drive playback without a device that talks.
abstract class SpeechEngine {
  /// Whether this platform can speak at all.
  bool get isAvailable;

  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  });

  /// Speaks [text]. Completes with true when it has been said to the end,
  /// and false when it was stopped or failed. [onProgress] is given the
  /// offset in [text] of each place it reaches that it can tell — for this
  /// voice, the start of each piece it is spoken in — and [breaks] are the
  /// offsets it should tell of as it reaches them: where each verse begins.
  Future<bool> speak(
    String text, {
    void Function(int offset)? onProgress,
    void Function()? onStart,
    List<int> breaks = const [],
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

/// Where there is nothing to speak with — the web, which has no
/// filesystem to keep the voice on — and nothing offers to.
class NoSpeechEngine implements SpeechEngine {
  @override
  bool get isAvailable => false;

  @override
  bool get canPause => false;

  @override
  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  }) async {}

  @override
  Future<bool> speak(
    String text, {
    void Function(int offset)? onProgress,
    void Function()? onStart,
    List<int> breaks = const [],
  }) async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<List<SpeechVoice>> voices(String language) async => const [];
}

/// Makes the engine the reader speaks with: OpenWord's own voice, where
/// it can run. A test puts a silent one in its place.
SpeechEngine Function() createSpeechEngine = () =>
    neuralVoices.isSupported ? neuralVoices.engine() : NoSpeechEngine();

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

  /// Handing them over, which for a voice of OpenWord's own means loading
  /// its model; speaking waits for it.
  Future<void>? _applying;

  Future<void> _apply() {
    final wanted = (_language, _rate, _voice);
    if (_applied == wanted && _applying != null) return _applying!;
    _applied = wanted;
    final (language, rate, voice) = wanted;
    // One after another: a voice chosen while the last is still loading
    // waits for it.
    return _applying = (_applying ?? Future<void>.value()).then(
      (_) => engine
          .configure(language: language, rate: rate, voice: voice)
          .catchError((Object _) {
            // A voice or rate the platform refuses still leaves it able
            // to speak.
          }),
    );
  }

  /// Gets the voice ready before it is asked to speak — for one of
  /// OpenWord's own, loading its model — so that Listen is heard at once.
  void prepare() => _apply();
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
    await _apply();
    if (generation != _generation) return;

    // The passage: this verse and those after it, as far as will go. After
    // a pause it takes up the verse at the word it had reached.
    final first = _index;
    final firstText = _queue[first].text;
    final trim = _resumeAt > 0 && _resumeAt < firstText.length ? _resumeAt : 0;
    final starts = <int>[];
    final passage = StringBuffer();
    // An engine that makes its own speech is handed the rest of the
    // chapter at once: it cuts it up itself, a sentence ahead of what is
    // heard, and a new passage would start that from nothing.
    final length = engine.canPause
        ? 1 << 30
        : _reportsProgress == true
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
    // A voice that makes its own speech tells where it is as it gets
    // there; estimating ahead of it, while it is still making the first
    // piece, would move the verse before a word had been heard.
    if (_reportsProgress != true && !engine.canPause) {
      _estimator = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (generation == _generation && isPlaying) _estimate();
      });
    }
    _saying = generation;
    final said = await engine.speak(
      text,
      breaks: starts,
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
