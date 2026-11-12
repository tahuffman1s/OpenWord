import { describe, expect, it } from 'vitest';
import { LearnVoice } from '../src/data/learnVoice';
import { FakeSpeech } from './fakeSpeech';

const tick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

describe('the voice in learning', () => {
  it('says the words as they should be heard, configured once', async () => {
    const speech = new FakeSpeech();
    const voice = new LearnVoice({ engine: speech, language: 'en', rate: 1.25 });
    let changes = 0;
    voice.addListener(() => changes++);

    const saying = voice.say('Praise the LORD, all you nations!');
    await tick();
    expect(speech.rates).toEqual([1.25]);
    expect(speech.said).toEqual(['Praise the Lord, all you nations!']);
    expect(voice.isSpeaking).toBe(true);
    speech.finish();
    await saying;
    expect(voice.isSpeaking).toBe(false);
    expect(changes).toBe(2);

    const again = voice.say('Jesus wept.');
    await tick();
    // The same pace is not sent again.
    expect(speech.rates).toEqual([1.25]);
    speech.finish();
    await again;
  });

  it('slowly is the pace cut by a third, and back again', async () => {
    const speech = new FakeSpeech();
    const voice = new LearnVoice({ engine: speech, language: 'en', rate: 1.0 });
    const slow = voice.say('Jesus wept.', { slow: true });
    await tick();
    expect(speech.rates).toEqual([LearnVoice.slowFactor]);
    speech.finish();
    await slow;
    const plain = voice.say('Jesus wept.');
    await tick();
    expect(speech.rates).toEqual([LearnVoice.slowFactor, 1.0]);
    speech.finish();
    await plain;
  });

  it('a new say cuts the last short; stop silences', async () => {
    const speech = new FakeSpeech();
    const voice = new LearnVoice({ engine: speech, language: 'en', rate: 1.0 });
    const first = voice.say('one');
    await tick();
    const second = voice.say('two');
    await tick();
    expect(speech.said).toEqual(['one', 'two']);
    expect(speech.stops).toBeGreaterThanOrEqual(1);
    await first;
    // The second is still going.
    expect(voice.isSpeaking).toBe(true);
    await voice.stop();
    expect(voice.isSpeaking).toBe(false);
    await second;
  });

  it('without a voice nothing is said', async () => {
    const speech = new FakeSpeech({ available: false });
    const voice = new LearnVoice({ engine: speech, language: 'en', rate: 1.0 });
    expect(voice.isAvailable).toBe(false);
    await voice.say('Jesus wept.');
    expect(speech.said).toEqual([]);
  });
});
