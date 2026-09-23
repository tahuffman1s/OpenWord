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

  @override
  Future<bool> speak(String text) {
    said.add(text);
    return (_saying = Completer<bool>()).future;
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

    setUp(() {
      speech = FakeSpeech();
      heard = [];
      voice = ReadAloud(
        engine: speech,
        chapterFor: chapterFor,
        nextChapter: (r) => r.bookCode == 'GEN' && r.chapter == 1
            ? const Reference('GEN', 2)
            : null,
        onChapterHeard: heard.add,
      );
    });

    test('reads a chapter verse by verse, announced, then the next', () async {
      voice.play(const Reference('GEN', 1));
      await settle();
      expect(speech.said, ['Genesis, chapter 1.']);
      expect(voice.current, const Reference('GEN', 1));

      for (var i = 0; i < 5; i++) {
        speech.finish();
        await settle();
      }
      expect(voice.current, const Reference('GEN', 1, 5));
      expect(speech.said[1], startsWith('In the beginning'));
      // The footnote marker is not read out.
      expect(speech.said[1], isNot(contains('Elohim')));

      speech.finish();
      await settle();
      expect(heard, [const Reference('GEN', 1)]);
      expect(speech.said.last, 'Genesis, chapter 2.');

      speech.finish();
      await settle();
      speech.finish();
      await settle();
      // Nothing after Genesis 2 here, so it stops.
      expect(voice.state, ReadAloudState.idle);
    });

    test('started part way in, a chapter is not counted as heard', () async {
      voice.play(const Reference('GEN', 1, 4));
      await settle();
      expect(speech.said.single, startsWith('A paragraph set flush'));
      speech.finish();
      await settle();
      speech.finish();
      await settle();
      expect(heard, isEmpty);
      // It still goes on to the next chapter.
      expect(speech.said.last, 'Genesis, chapter 2.');
    });

    test('a selection is read and then it stops', () async {
      voice.play(const Reference('GEN', 1, 3), only: {3, 5});
      await settle();
      speech.finish();
      await settle();
      expect(voice.current, const Reference('GEN', 1, 5));
      speech.finish();
      await settle();
      expect(voice.state, ReadAloudState.idle);
      expect(speech.said, hasLength(2));
    });

    test('pausing remembers the verse; resuming says it again', () async {
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      voice.pause();
      await settle();
      expect(voice.state, ReadAloudState.paused);
      expect(voice.current, const Reference('GEN', 1, 3));
      voice.resume();
      await settle();
      expect(speech.said, hasLength(2));
      expect(speech.said[0], speech.said[1]);
    });

    test('skips forward and back, interrupting what is being said', () async {
      voice.play(const Reference('GEN', 1, 2));
      await settle();
      voice.skip(1);
      await settle();
      expect(voice.current, const Reference('GEN', 1, 3));
      expect(speech.stops, greaterThan(0));
      voice.skip(-1);
      voice.skip(-1);
      await settle();
      // No further back than where it started.
      expect(voice.current, const Reference('GEN', 1, 2));
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

    test('a device that stops speaking ends it, and says so', () async {
      voice.play(const Reference('GEN', 1, 3));
      await settle();
      speech.finish(false);
      await settle();
      expect(voice.state, ReadAloudState.idle);
      expect(voice.error, isNotNull);
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
      startReadAloudSession = (voice, describe) async {
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

      speech.finish();
      await tester.pump();
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
      // The announcement and Genesis 1's five verses.
      for (var i = 0; i < 6; i++) {
        speech.finish();
        await tester.pump();
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final progress = harness.reading.progressFor(
        ReadingPlans.bibleInAYear.id,
      )!;
      expect(progress.done, {0});
      expect(appBarText('Genesis 2'), findsOneWidget);
      expect(speech.said.last, 'Genesis, chapter 2.');
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
      await tester.tap(find.text('Serena'));
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
