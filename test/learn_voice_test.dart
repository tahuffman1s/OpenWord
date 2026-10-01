import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/learn_voice.dart';

import 'read_aloud_test.dart' show FakeSpeech;

void main() {
  test('says the words as they should be heard, configured once', () async {
    final speech = FakeSpeech();
    final voice = LearnVoice(engine: speech, language: 'en', rate: 1.25);
    var changes = 0;
    voice.addListener(() => changes++);

    final saying = voice.say('Praise the LORD, all you nations!');
    await Future<void>.delayed(Duration.zero);
    expect(speech.rates, [1.25]);
    expect(speech.said, ['Praise the Lord, all you nations!']);
    expect(voice.isSpeaking, isTrue);
    speech.finish();
    await saying;
    expect(voice.isSpeaking, isFalse);
    expect(changes, 2);

    final again = voice.say('Jesus wept.');
    await Future<void>.delayed(Duration.zero);
    expect(speech.rates, [1.25], reason: 'the same pace is not sent again');
    speech.finish();
    await again;
  });

  test('slowly is the pace cut by a third, and back again', () async {
    final speech = FakeSpeech();
    final voice = LearnVoice(engine: speech, language: 'en', rate: 1.0);
    final slow = voice.say('Jesus wept.', slow: true);
    await Future<void>.delayed(Duration.zero);
    expect(speech.rates, [LearnVoice.slowFactor]);
    speech.finish();
    await slow;
    final plain = voice.say('Jesus wept.');
    await Future<void>.delayed(Duration.zero);
    expect(speech.rates, [LearnVoice.slowFactor, 1.0]);
    speech.finish();
    await plain;
  });

  test('a new say cuts the last short; stop silences', () async {
    final speech = FakeSpeech();
    final voice = LearnVoice(engine: speech, language: 'en', rate: 1.0);
    final first = voice.say('one');
    await Future<void>.delayed(Duration.zero);
    final second = voice.say('two');
    await Future<void>.delayed(Duration.zero);
    expect(speech.said, ['one', 'two']);
    expect(speech.stops, greaterThanOrEqualTo(1));
    await first;
    expect(voice.isSpeaking, isTrue, reason: 'the second is still going');
    await voice.stop();
    expect(voice.isSpeaking, isFalse);
    await second;
  });

  test('without a voice nothing is said', () async {
    final speech = FakeSpeech(available: false);
    final voice = LearnVoice(engine: speech, language: 'en', rate: 1.0);
    expect(voice.isAvailable, isFalse);
    await voice.say('Jesus wept.');
    expect(speech.said, isEmpty);
  });
}
