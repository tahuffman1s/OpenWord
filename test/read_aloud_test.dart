import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:openword/src/data/read_aloud.dart';
import 'package:openword/src/data/read_aloud_session.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/reading_plan.dart';

import 'fixtures.dart';
import 'reader_screen_test.dart' show appBarText, pumpReader;

/// A speech engine that says nothing and finishes when told to.
class FakeSpeech implements SpeechEngine {
  FakeSpeech({this.available = true});

  final bool available;
  final List<String> said = [];
  final List<double> rates = [];
  int stops = 0;
  Completer<bool>? _saying;

  @override
  bool get isAvailable => available;

  @override
  Future<void> configure({
    required String language,
    required double rate,
    String? voice,
  }) async => rates.add(rate);

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
