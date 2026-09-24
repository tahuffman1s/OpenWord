import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart'
    show FilledButton, Scaffold, ScaffoldMessenger;
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:openword/src/data/neural_speech.dart';
import 'package:openword/src/data/neural_voices.dart';
import 'package:openword/src/data/neural_voices_io.dart' show tidyModels;
import 'package:openword/src/data/read_aloud.dart';
import 'package:openword/src/data/read_aloud_session.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/reading_plan.dart';

import 'fixtures.dart';
import 'reader_screen_test.dart' show appBarText, pumpReader;

/// A speech engine that says nothing and finishes when told to.
class FakeSpeech implements SpeechEngine {
  FakeSpeech({this.available = true, this.pauses = false});

  final bool available;

  /// Whether it can hold what it is saying, as OpenWord's own voices can.
  final bool pauses;
  final List<String> said = [];
  final List<double> rates = [];
  int stops = 0;
  int paused = 0;
  int resumed = 0;

  @override
  bool get canPause => pauses;

  @override
  Future<void> pause() async => paused++;

  @override
  Future<void> resume() async => resumed++;
  Completer<bool>? _saying;

  @override
  bool get isAvailable => available;

  /// Held open to keep configuring from finishing, as loading a model does.
  Completer<void>? configuring;

  @override
  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  }) async {
    rates.add(rate);
    await configuring?.future;
  }

  void Function(int offset)? _progress;
  void Function()? _start;

  @override
  Future<bool> speak(
    String text, {
    void Function(int offset)? onProgress,
    void Function()? onStart,
  }) {
    said.add(text);
    _progress = onProgress;
    _start = onStart;
    return (_saying = Completer<bool>()).future;
  }

  /// Reports the voice as having begun what it was given.
  void begin() => _start?.call();

  /// Reports the voice as having reached [words] in what it is saying.
  void reach(String words) {
    final at = said.last.indexOf(words);
    expect(at, greaterThanOrEqualTo(0), reason: '"$words" is not being said');
    _progress?.call(at);
  }

  /// Ends what is being said, as said to the end or not.
  void finish([bool toTheEnd = true]) {
    final saying = _saying;
    _saying = null;
    if (saying != null && !saying.isCompleted) saying.complete(toTheEnd);
  }

  @override
  Future<void> stop() async {
    stops++;
    finish(false);
  }

  @override
  Future<List<SpeechVoice>> voices(String language) async => const [
    SpeechVoice(name: 'Serena', locale: 'en-GB'),
  ];
}

/// OpenWord's own voices, without the downloading: each model installs
/// when asked, and speaks with a silent engine.
class FakeNeuralVoices extends NeuralVoices {
  final Set<NeuralModel> installed = {};

  NeuralModel? slow;

  @override
  NeuralModel? get fallingBehind => slow;

  final FakeSpeech speech = FakeSpeech(pauses: true);
  final List<String?> configured = [];

  @override
  bool get isSupported => true;

  @override
  Future<void> get ready => Future.value();

  @override
  bool isInstalled(NeuralModel model) => installed.contains(model);

  @override
  double? progress(NeuralModel model) => null;

  @override
  String? error(NeuralModel model) => null;

  @override
  Future<void> install(NeuralModel model) async {
    installed.add(model);
    notifyListeners();
  }

  @override
  void cancel(NeuralModel model) {}

  @override
  Future<void> remove(NeuralModel model) async {
    installed.remove(model);
    notifyListeners();
  }

  @override
  SpeechEngine engine() => _Recording(speech, configured);
}

/// Passes everything to [inner], noting the voices it is configured with.
class _Recording implements SpeechEngine {
  _Recording(this.inner, this.configured);

  final FakeSpeech inner;
  final List<String?> configured;

  @override
  bool get isAvailable => true;

  @override
  bool get canPause => inner.canPause;

  @override
  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  }) async => configured.add(voice);

  @override
  Future<bool> speak(
    String text, {
    void Function(int offset)? onProgress,
    void Function()? onStart,
  }) => inner.speak(text, onProgress: onProgress, onStart: onStart);

  @override
  Future<void> stop() => inner.stop();

  @override
  Future<void> pause() => inner.pause();

  @override
  Future<void> resume() => inner.resume();

  @override
  Future<List<SpeechVoice>> voices(String language) async => const [];
}

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final bible = parseFixture();
  Chapter? chapterFor(Reference r) =>
      bible.bookByCode(r.bookCode)?.chapter(r.chapter);

  group('the controller', () {
    late FakeSpeech speech;
    late List<Reference> heard;
    late ReadAloud voice;
    late DateTime now;

    setUp(() {
      speech = FakeSpeech();
      heard = [];
      now = DateTime(2026, 9, 24, 8);
      voice = ReadAloud(
        clock: () => now,
        engine: speech,
        chapterFor: chapterFor,
        nextChapter: (r) => r.bookCode == 'GEN' && r.chapter == 1
            ? const Reference('GEN', 2)
            : null,
        onChapterHeard: heard.add,
      );
    });

    test(
      'reads a chapter as one passage, announced, following the words',
      () async {
        voice.play(const Reference('GEN', 1));
        await settle();
        // Not a verse at a time: the whole short chapter goes to the voice at
        // once, so it is not stopped and started between verses.
        expect(speech.said, hasLength(1));
        expect(
          speech.said.single,
          startsWith('Genesis, chapter 1. In the beginning'),
        );
        expect(speech.said.single, contains('An indented paragraph'));
        // The footnote marker is not read out.
        expect(speech.said.single, isNot(contains('Elohim')));
        expect(voice.current, const Reference('GEN', 1));

        // The words it reports reaching say which verse is being read.
        speech.reach('In the beginning');
        expect(voice.current, const Reference('GEN', 1, 1));
        speech.reach('An indented paragraph');
        expect(voice.current, const Reference('GEN', 1, 5));

        speech.finish();
        await settle();
        expect(heard, [const Reference('GEN', 1)]);
        expect(speech.said.last, startsWith('Genesis, chapter 2.'));

        speech.finish();
        await settle();
        // Nothing after Genesis 2 here, so it stops.
        expect(voice.state, ReadAloudState.idle);
      },
    );

    test('started part way in, a chapter is not counted as heard', () async {
      voice.play(const Reference('GEN', 1, 4));
      await settle();
      expect(speech.said.single, startsWith('A paragraph set flush'));
      speech.finish();
      await settle();
      expect(heard, isEmpty);
      // It still goes on to the next chapter.
      expect(speech.said.last, startsWith('Genesis, chapter 2.'));
    });

    test('a selection is read and then it stops', () async {
      voice.play(const Reference('GEN', 1, 3), only: {3, 5});
      await settle();
      expect(speech.said.single, isNot(contains('A paragraph set flush')));
      speech.reach('An indented paragraph');
      expect(voice.current, const Reference('GEN', 1, 5));
      speech.finish();
      await settle();
      expect(voice.state, ReadAloudState.idle);
      expect(speech.said, hasLength(1));
    });

    test('pausing remembers the verse it had reached', () async {
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      speech.reach('A paragraph set flush');
      voice.pause();
      await settle();
      expect(voice.state, ReadAloudState.paused);
      expect(voice.current, const Reference('GEN', 1, 4));
      voice.resume();
      await settle();
      expect(speech.said.last, startsWith('A paragraph set flush'));
    });

    test('skips forward and back, interrupting what is being said', () async {
      voice.play(const Reference('GEN', 1, 2));
      await settle();
      voice.skip(1);
      await settle();
      expect(voice.current, const Reference('GEN', 1, 3));
      expect(speech.stops, greaterThan(0));
      expect(speech.said.last, startsWith('God said'));
      voice.skip(-1);
      voice.skip(-1);
      await settle();
      // No further back than where it started.
      expect(voice.current, const Reference('GEN', 1, 2));
    });

    test('resuming takes up the word it had reached, not the verse', () async {
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      speech.reach('be light');
      voice.pause();
      await settle();
      voice.resume();
      await settle();
      expect(speech.said.last, startsWith('be light'));
      expect(voice.current, const Reference('GEN', 1, 3));
      // And the verses after it follow as before.
      expect(speech.said.last, contains('A paragraph set flush'));
      // A word reached in the resumed passage is placed in its verse.
      speech.reach('light.');
      voice.pause();
      await settle();
      voice.resume();
      await settle();
      expect(speech.said.last, startsWith('light.'));
    });

    test('a voice that can pause is held where it is, not stopped', () async {
      final held = FakeSpeech(pauses: true);
      voice = ReadAloud(
        engine: held,
        chapterFor: chapterFor,
        nextChapter: (_) => null,
      );
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      held.reach('be light');
      final stops = held.stops;
      voice.pause();
      await settle();
      expect(voice.state, ReadAloudState.paused);
      expect(held.paused, 1);
      expect(held.stops, stops);
      voice.resume();
      await settle();
      // Taken up mid-word by the engine, not said again.
      expect(held.resumed, 1);
      expect(held.said, hasLength(1));
      expect(voice.isPlaying, isTrue);

      // Stepping while held lets go of it, and the next verse is said.
      voice.pause();
      voice.skip(1);
      await settle();
      expect(held.stops, greaterThan(stops));
      voice.resume();
      await settle();
      expect(held.resumed, 1);
      expect(held.said.last, startsWith('A paragraph set flush'));
    });

    test('where listening got to is kept, and taken up again', () async {
      final places = <ListeningPlace?>[];
      voice = ReadAloud(
        engine: speech,
        chapterFor: chapterFor,
        nextChapter: (_) => null,
        onPlace: places.add,
      );
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      speech.reach('be light');
      voice.stop();
      await settle();
      final kept = places.last!;
      expect(kept.verse, const Reference('GEN', 1, 3));
      expect(kept.offset, greaterThan(0));
      expect(kept.atTop, isFalse);
      expect(ListeningPlace.decode(kept.encode()), kept);

      voice.play(kept.verse, offset: kept.offset, fromTop: kept.fromTop);
      await settle();
      expect(speech.said.last, startsWith('be light'));
      // Heard to the end, there is nothing left to take up.
      speech.finish();
      await settle();
      expect(voice.isActive, isFalse);
      expect(places.last, isNull);
    });

    test('a chapter begun at its top counts as heard when taken up', () async {
      voice.play(const Reference('GEN', 1, 3), offset: 4, fromTop: true);
      await settle();
      expect(speech.said.last, startsWith('said'));
      speech.finish();
      await settle();
      expect(heard, [const Reference('GEN', 1)]);
    });

    test('a selection read aloud is not kept as a place', () async {
      final places = <ListeningPlace?>[];
      voice = ReadAloud(
        engine: speech,
        chapterFor: chapterFor,
        nextChapter: (_) => null,
        onPlace: places.add,
      );
      voice.play(const Reference('GEN', 1, 3), only: {3, 4});
      await settle();
      voice.stop();
      expect(places, isEmpty);
    });

    test('stepping to another verse starts it from the beginning', () async {
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      speech.reach('be light');
      voice.skip(1);
      await settle();
      expect(speech.said.last, startsWith('A paragraph set flush'));
    });

    test(
      'where no words are reported, the verse is estimated from time',
      () async {
        voice.play(const Reference('GEN', 1, 3));
        await settle();
        speech.begin();
        // About 14 characters a second: three seconds is past verse 3, which
        // is 31 characters, and into verse 4.
        now = now.add(const Duration(seconds: 3));
        voice.debugEstimate();
        expect(voice.current, const Reference('GEN', 1, 4));
      },
    );

    test('resuming an estimated place goes back to its sentence', () async {
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      speech.begin();
      now = now.add(const Duration(seconds: 3));
      voice.pause();
      await settle();
      expect(voice.current, const Reference('GEN', 1, 4));
      voice.resume();
      await settle();
      // Not the passage again from verse 3, and not mid-word: the start of
      // the sentence the voice was in.
      expect(speech.said.last, startsWith('A paragraph set flush'));
    });

    test('a sentence start is found for an estimated place', () {
      const text = 'In the beginning. God said, “Let there be light.” And so.';
      expect(ReadAloud.sentenceStart(text, 5), 0);
      expect(ReadAloud.sentenceStart(text, 25), 18);
      expect(ReadAloud.sentenceStart(text, text.length - 2), 50);
    });

    test('the estimate learns how fast the voice really is', () async {
      voice.play(const Reference('GEN', 1, 1));
      await settle();
      speech.begin();
      final length = speech.said.last.length;
      // This voice took twice as long as the guess would say.
      now = now.add(Duration(milliseconds: (length / 7 * 1000).round()));
      speech.finish();
      await settle();
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      speech.begin();
      now = now.add(const Duration(seconds: 3));
      voice.debugEstimate();
      // Slower now — about 10.5 characters a second, halfway to what it
      // measured — so three seconds is still in verse 3's 31 characters.
      expect(voice.current, const Reference('GEN', 1, 3));
    });

    test('one that does report progress keeps its passages', () async {
      voice.play(const Reference('GEN', 1, 1));
      await settle();
      speech.reach('The earth was');
      speech.finish();
      await settle();
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      expect(speech.said.last, contains('A paragraph set flush'));
    });

    test('a change of speed takes effect at once', () async {
      voice.configure(language: 'en', rate: 1.0);
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      voice.configure(language: 'en', rate: 1.5);
      await settle();
      expect(speech.rates.last, 1.5);
      expect(speech.said, hasLength(2));
    });

    test('one failed verse is said again, not given up on', () async {
      ReadAloud.retryDelay = Duration.zero;
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      speech.finish(false);
      await settle();
      expect(voice.isPlaying, isTrue);
      expect(voice.error, isNull);
      expect(speech.said, hasLength(2));
      expect(speech.said[0], speech.said[1]);
      // And a success clears it, so a later hiccup gets its retry too.
      speech.finish();
      await settle();
      speech.finish(false);
      await settle();
      expect(voice.isPlaying, isTrue);
      expect(voice.error, isNull);
    });

    test('a device that stops speaking ends it, and says so', () async {
      ReadAloud.retryDelay = Duration.zero;
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      speech.finish(false);
      await settle();
      speech.finish(false);
      await settle();
      expect(voice.state, ReadAloudState.idle);
      expect(voice.error, isNotNull);
    });

    test('voices are ranked most natural first, online ones marked', () {
      final ranked = SpeechVoice.rank([
        {'name': 'plain', 'locale': 'en-US', 'quality': 'normal'},
        {
          'name': 'cloud',
          'locale': 'en-US',
          'quality': 'very high',
          'network_required': '1',
        },
        {
          'name': 'missing',
          'locale': 'en-US',
          'quality': 'very high',
          'features': 'embeddedTts\tnotInstalled',
        },
        {
          'name': 'good-us',
          'locale': 'en-US',
          'quality': 'very high',
          'network_required': '0',
        },
        {'name': 'good-gb', 'locale': 'en-GB', 'quality': 'very high'},
        {'name': 'Ava (Premium)', 'locale': 'en-US', 'quality': 'premium'},
        {'name': 'Daniel', 'locale': 'en-GB', 'quality': 'enhanced'},
        {'name': 'Amélie', 'locale': 'fr-CA', 'quality': 'premium'},
      ], 'en-GB');
      expect(ranked.map((v) => v.name), [
        // Best quality first; the translation's own region breaks a tie,
        // then a voice on the device before one online.
        'good-gb', 'Ava (Premium)', 'good-us', 'cloud', 'Daniel', 'plain',
      ]);
      expect(ranked.firstWhere((v) => v.name == 'cloud').online, isTrue);
      expect(ranked.first.online, isFalse);
      expect(ranked.first.qualityLabel, 'Natural');
      expect(ranked[4].qualityLabel, 'Enhanced');
      expect(ranked.last.qualityLabel, isNull);
    });

    test('the chosen voice decides which engine speaks', () async {
      final platform = FakeSpeech();
      final neural = FakeNeuralVoices();
      final engines = SpeechEngines(platform, neural);
      final bella = NeuralModel.kitten.voiceName(
        NeuralModel.kitten.speakers.first,
      );

      // Not downloaded: the platform's own choice, rather than a name it
      // does not know.
      await engines.configure(language: 'en', rate: 1, voice: bella);
      expect(neural.configured, isEmpty);
      engines.speak('Words');
      expect(platform.said, ['Words']);
      expect(engines.canPause, isFalse);

      await neural.install(NeuralModel.kitten);
      await engines.configure(language: 'en', rate: 1, voice: bella);
      expect(neural.configured, [bella]);
      engines.speak('More words');
      expect(neural.speech.said, ['More words']);
      expect(engines.canPause, isTrue);
      // The platform was stopped as the other took over.
      expect(platform.stops, 1);

      final voices = await engines.voices('en-US');
      expect(voices.first.title, 'Bella · Kitten');
      expect(voices.first.qualityLabel, 'Natural');
      expect(voices.last.name, 'Serena');
      // English only.
      expect((await engines.voices('fr')).where((v) => v.builtIn), isEmpty);
    });

    test('a voice made ready ahead is not made ready again', () async {
      final loading = speech.configuring = Completer<void>();
      voice.configure(language: 'en', rate: 1, voice: 'Serena');
      voice.prepare();
      await settle();
      expect(speech.rates, hasLength(1));
      // Listen while it is still loading waits for it, rather than
      // speaking with nothing loaded.
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      expect(speech.said, isEmpty);
      loading.complete();
      await settle();
      expect(speech.said, hasLength(1));
      expect(speech.rates, hasLength(1));
    });

    test('a built-in voice is kept by a name that says whose it is', () {
      final lewis = NeuralModel.kokoro.speakers.last;
      final name = NeuralModel.kokoro.voiceName(lewis);
      expect(NeuralModel.parse(name), (NeuralModel.kokoro, lewis));
      expect(NeuralModel.parse('Samantha'), isNull);
      expect(NeuralModel.parse('openword:kokoro:99'), isNull);
      expect(NeuralModel.parse(null), isNull);
    });

    test('text is voiced a sentence at a time, long ones cut again', () {
      const text =
          'Genesis, chapter 1. In the beginning God created the heavens '
          'and the earth. Now the earth was formless and empty, darkness '
          'was over the surface of the deep, and the Spirit of God was '
          'hovering over the waters.';
      final pieces = NeuralSpeechEngine.pieces(text, longest: 60);
      expect(pieces.first, (0, 'Genesis, chapter 1.'));
      for (final (offset, words) in pieces) {
        expect(text.substring(offset, offset + words.length), words);
        expect(words.length, lessThanOrEqualTo(60));
        expect(words.trim(), words);
      }
      // Nothing left out, and a long sentence cut at a comma.
      expect(pieces.map((p) => p.$2).join(' '), text);
      expect(pieces.any((p) => p.$2.endsWith('empty,')), isTrue);
    });

    test('a piece that would clip is turned down, not cut off', () {
      final quiet = Float32List.fromList([0.1, -0.5, 0.9]);
      expect(identical(Synthesiser.limited(quiet), quiet), isTrue);
      final loud = Synthesiser.limited(Float32List.fromList([0.5, -1.4, 1.9]));
      expect(
        loud.reduce((a, b) => a.abs() > b.abs() ? a : b),
        closeTo(0.95, 1e-6),
      );
      // In proportion: the shape of the sound is kept.
      expect(loud[0] / loud[2], closeTo(0.5 / 1.9, 1e-6));
    });

    test(
      'models no longer offered, and broken downloads, are tidied',
      () async {
        final root = Directory.systemTemp.createTempSync('voices');
        addTearDown(() => root.deleteSync(recursive: true));
        Directory('${root.path}/kitten-nano-en-v0_8-int8').createSync();
        Directory('${root.path}/${NeuralModel.kitten.archive}').createSync();
        Directory('${root.path}/${NeuralModel.kokoro.archive}').createSync();
        File('${root.path}/kokoro-int8-en-v0_19.tar.bz2').writeAsStringSync('');
        await tidyModels(root, downloading: true);
        // A download under way is left alone.
        expect(
          File('${root.path}/kokoro-int8-en-v0_19.tar.bz2').existsSync(),
          isTrue,
        );
        await tidyModels(root, downloading: false);
        expect(
          root
              .listSync()
              .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
              .toSet(),
          {NeuralModel.kitten.archive, NeuralModel.kokoro.archive},
        );
      },
    );

    test('the first piece is short, so the voice starts at once', () {
      final text = List.filled(
        40,
        'and the evening and the morning',
      ).join(', ');
      final pieces = NeuralSpeechEngine.pieces(text);
      final lengths = [for (final (_, words) in pieces) words.length];
      expect(lengths.first, lessThanOrEqualTo(40));
      expect(lengths[1], lessThanOrEqualTo(80));
      expect(lengths[1], greaterThan(40));
      // Then as long as a piece may be, and no longer, but for whatever is
      // left at the end.
      final middle = lengths.sublist(2, lengths.length - 1);
      expect(middle.every((n) => n > 80 && n <= 160), isTrue);
      expect(pieces.map((p) => p.$2).join(' '), text);
    });

    test('normal pace is what each platform calls normal', () {
      // The plugin doubles the rate on Android and adds 0.5 on Windows, so
      // 0.5 is normal there as on Apple's voices; a browser takes 1.0.
      expect(PlatformSpeechEngine.rateFor(1.0, web: false), 0.5);
      expect(PlatformSpeechEngine.rateFor(1.0, web: true), 1.0);
      expect(PlatformSpeechEngine.rateFor(1.5, web: false), 0.75);
      expect(PlatformSpeechEngine.rateFor(0.75, web: true), 0.75);
    });

    test('the divine name is said as a word', () {
      expect(
        ReadAloud.speakable('The LORD is my shepherd; the Lord GOD'),
        'The Lord is my shepherd; the Lord God',
      );
      expect(ReadAloud.announcement(const Reference('PSA', 23)), 'Psalm 23.');
    });
  });

  group('the lock screen', () {
    late FakeSpeech speech;
    late ReadAloud voice;
    late ReadAloudHandler handler;

    setUp(() {
      speech = FakeSpeech();
      voice = ReadAloud(
        engine: speech,
        chapterFor: chapterFor,
        nextChapter: (_) => null,
      );
      handler = ReadAloudHandler(voice, () => 'Test Translation');
    });

    test('shows nothing to control while nothing is read', () {
      final state = handler.playbackState.value;
      expect(state.playing, isFalse);
      expect(state.processingState, AudioProcessingState.idle);
      expect(state.controls, isEmpty);
    });

    test('shows where it has got to, and the controls for it', () async {
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      final state = handler.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.processingState, AudioProcessingState.ready);
      expect(state.controls, [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.skipToNext,
        MediaControl.stop,
      ]);
      final item = handler.mediaItem.value!;
      expect(item.title, 'Genesis 1:3');
      expect(item.album, 'Test Translation');
    });

    test('its buttons drive the voice', () async {
      voice.play(const Reference('GEN', 1, 2));
      await settle();
      await handler.pause();
      expect(voice.state, ReadAloudState.paused);
      expect(handler.playbackState.value.controls[1], MediaControl.play);
      await handler.play();
      await settle();
      expect(voice.isPlaying, isTrue);
      await handler.skipToNext();
      await settle();
      expect(voice.current, const Reference('GEN', 1, 3));
      await handler.skipToPrevious();
      await settle();
      expect(voice.current, const Reference('GEN', 1, 2));
      // A headset's one button pauses and resumes.
      await handler.click();
      expect(voice.state, ReadAloudState.paused);
      await handler.click();
      expect(voice.isPlaying, isTrue);
      await handler.stop();
      expect(voice.state, ReadAloudState.idle);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
    });

    test('the lock screen gets a cover for the chapter', () async {
      final drawn = <Reference>[];
      handler.bind(
        voice,
        () => 'Test Translation',
        artwork: (chapter) async {
          drawn.add(chapter);
          return Uri.file('/covers/${chapter.bookCode}-${chapter.chapter}.png');
        },
      );
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      expect(handler.mediaItem.value!.artUri, Uri.file('/covers/GEN-1.png'));
      // Once per chapter, not once per verse.
      voice.skip(1);
      await settle();
      expect(drawn, [const Reference('GEN', 1)]);
    });

    test('a new voice can take over the session', () async {
      final another = ReadAloud(
        engine: speech,
        chapterFor: chapterFor,
        nextChapter: (_) => null,
      );
      handler.bind(another, () => 'Another');
      another.play(const Reference('GEN', 1, 4));
      await settle();
      expect(handler.mediaItem.value!.title, 'Genesis 1:4');
      expect(handler.mediaItem.value!.album, 'Another');
      // The first voice no longer drives what the system shows.
      voice.play(const Reference('GEN', 1, 1));
      await settle();
      expect(handler.mediaItem.value!.title, 'Genesis 1:4');
    });
  });

  group('in the reader', () {
    late FakeSpeech speech;

    final sessions = <ReadAloud>[];

    setUp(() {
      speech = FakeSpeech();
      createSpeechEngine = () => speech;
      sessions.clear();
      startReadAloudSession = (voice, describe, {artwork}) async {
        sessions.add(voice);
        return null;
      };
    });

    tearDown(() => createSpeechEngine = PlatformSpeechEngine.new);

    testWidgets('Listen reads the chapter, and the bar follows it', (
      tester,
    ) async {
      await pumpReader(tester);
      await tester.tap(find.text('LISTEN'));
      await tester.pump();
      expect(find.text('Genesis, chapter 1'), findsOneWidget);
      expect(find.textContaining('Reading aloud'), findsOneWidget);

      speech.reach('In the beginning');
      await tester.pump();
      expect(find.text('Genesis 1:1'), findsOneWidget);

      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      await tester.tap(find.byTooltip('Resume'));
      await tester.pump();
      expect(find.textContaining('Reading aloud'), findsOneWidget);

      await tester.tap(find.byTooltip('Stop reading aloud'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause'), findsNothing);
    });

    testWidgets('the chapter\'s Listen pauses, resumes, and takes up a place', (
      tester,
    ) async {
      await pumpReader(tester);
      await tester.tap(find.text('LISTEN'));
      await tester.pump();
      speech.reach('In the beginning');
      await tester.pump();

      // Not started again from the top: paused and resumed.
      await tester.ensureVisible(find.text('PAUSE'));
      await tester.tap(find.text('PAUSE'));
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      await tester.ensureVisible(find.text('RESUME'));
      await tester.tap(find.text('RESUME'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Reading aloud'), findsOneWidget);
      expect(speech.said.last, startsWith('In the beginning'));

      // Closed part way, the place is kept, and Listen takes it up.
      speech.reach('be light');
      await tester.pump();
      await tester.tap(find.byTooltip('Stop reading aloud'));
      await tester.pumpAndSettle();
      expect(find.text('LISTEN'), findsNothing);
      await tester.ensureVisible(find.text('RESUME'));
      await tester.tap(find.text('RESUME'));
      await tester.pump();
      await tester.pump();
      expect(speech.said.last, startsWith('be light'));
      expect(find.text('Genesis 1:3'), findsOneWidget);
    });

    testWidgets('a kept place outlasts the app', (tester) async {
      await pumpReader(
        tester,
        prefs: {
          'listeningPlace': const ListeningPlace(Reference('GEN', 1, 4))
              .encode(),
        },
      );
      await tester.tap(find.text('RESUME'));
      await tester.pump();
      await tester.pump();
      expect(speech.said.last, startsWith('A paragraph set flush'));
    });

    testWidgets('a natural voice is downloaded from the sheet, and chosen', (
      tester,
    ) async {
      final neural = FakeNeuralVoices();
      final previous = neuralVoices;
      neuralVoices = neural;
      addTearDown(() => neuralVoices = previous);
      createSpeechEngine = () => SpeechEngines(speech, neural);
      final harness = await pumpReader(tester);
      await tester.tap(find.text('LISTEN'));
      await tester.pump();
      await tester.tap(find.byTooltip('Speed and voice'));
      await tester.pumpAndSettle();
      expect(find.text('Natural voices for OpenWord'), findsOneWidget);
      expect(find.text('Kokoro'), findsOneWidget);

      final download = find.widgetWithText(FilledButton, 'Download').first;
      await tester.ensureVisible(download);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(neural.isInstalled(NeuralModel.kitten), isTrue);
      expect(harness.settings.speechVoice, 'openword:kitten:1');
      expect(find.text('Bella · Kitten'), findsOneWidget);

      // Removed, the voice goes back to the device's own.
      final remove = find.byTooltip('Remove Kitten');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(harness.settings.speechVoice, isNull);
      expect(find.text('Bella · Kitten'), findsNothing);
    });

    testWidgets('a voice too slow for the device says so, once', (
      tester,
    ) async {
      final neural = FakeNeuralVoices()..installed.add(NeuralModel.kokoro);
      final previous = neuralVoices;
      neuralVoices = neural;
      addTearDown(() => neuralVoices = previous);
      await pumpReader(
        tester,
        prefs: {
          'speechVoice': NeuralModel.kokoro.voiceName(
            NeuralModel.kokoro.speakers.first,
          ),
        },
      );
      neural.slow = NeuralModel.kokoro;
      neural.notifyListeners();
      await tester.pump();
      expect(find.textContaining('Kitten is quicker'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      neural.notifyListeners();
      await tester.pump();
      expect(find.textContaining('Kitten is quicker'), findsNothing);
    });

    testWidgets('a session that cannot start says why, once', (tester) async {
      startReadAloudSession = (voice, describe, {artwork}) async {
        readAloudSessionError = 'no service';
        return null;
      };
      addTearDown(() => readAloudSessionError = null);
      await pumpReader(tester);
      await tester.tap(find.text('LISTEN'));
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Lock-screen controls could not start'),
        findsOneWidget,
      );
      expect(find.textContaining('no service'), findsOneWidget);
    });

    testWidgets('listening hands the voice to the system', (tester) async {
      await pumpReader(tester);
      await tester.tap(find.text('LISTEN'));
      await tester.pump();
      expect(sessions, hasLength(1));
    });

    testWidgets('a verse offers to be read from', (tester) async {
      await pumpReader(tester);
      await tester.tap(
        find.textContaining('Let there be light', findRichText: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listen from here'));
      await tester.pumpAndSettle();
      expect(find.text('Genesis 1:3'), findsOneWidget);
      expect(speech.said.single, contains('Let there be light'));
    });

    testWidgets('turns the page when the voice moves on', (tester) async {
      await pumpReader(tester, resume: const Reference('GEN', 1, 5));
      await tester.tap(
        find.textContaining('An indented paragraph', findRichText: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Listen from here'));
      await tester.pump();
      speech.finish();
      await tester.pumpAndSettle();
      expect(appBarText('Genesis 2'), findsOneWidget);
    });

    testWidgets('a plan day is heard through, and counted as read', (
      tester,
    ) async {
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final harness = await pumpReader(
        tester,
        prefs: {
          'plans': jsonEncode([
            {
              'id': ReadingPlans.bibleInAYear.id,
              'start': '${now.year}-${two(now.month)}-${two(now.day)}',
              't': 1,
              'done': <int>[],
            },
          ]),
        },
      );
      await tester.tap(find.text('LISTEN'));
      await tester.pump();
      // Genesis 1, announced, as one passage.
      speech.finish();
      await tester.pumpAndSettle();
      final progress = harness.reading.progressFor(
        ReadingPlans.bibleInAYear.id,
      )!;
      expect(progress.done, {0});
      expect(appBarText('Genesis 2'), findsOneWidget);
      expect(speech.said.last, startsWith('Genesis, chapter 2.'));
    });

    testWidgets('speed and voice are chosen from the bar', (tester) async {
      final harness = await pumpReader(tester);
      await tester.tap(find.text('LISTEN'));
      await tester.pump();
      await tester.tap(find.byTooltip('Speed and voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5×'));
      await tester.pumpAndSettle();
      expect(harness.settings.speechRate, 1.5);
      // The automatic choice names the voice it would use; the voice's
      // own row is the second.
      expect(
        find.text('The most natural voice on this device'),
        findsOneWidget,
      );
      await tester.tap(find.text('Serena').last);
      await tester.pumpAndSettle();
      expect(harness.settings.speechVoice, 'Serena');
    });

    testWidgets('where the device cannot speak, nothing offers to', (
      tester,
    ) async {
      createSpeechEngine = () => FakeSpeech(available: false);
      await pumpReader(tester);
      expect(find.text('LISTEN'), findsNothing);
      await tester.tap(
        find.textContaining('Let there be light', findRichText: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Listen from here'), findsNothing);
    });
  });
}
