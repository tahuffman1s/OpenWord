import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
  clauses,
  contentTokens,
  hasContent,
  joinPhonemes,
  kittenMeta,
  levelled,
  limited,
  modelSpeed,
  parseTokens,
  parseVoices,
  styleRow,
  styleVector,
  tokenIds,
  trimSilence,
} from '../src/speech/kitten';

const tokensText = readFileSync(new URL('./fixtures/tokens.txt', import.meta.url), 'utf8');

describe('tokens.txt', () => {
  const tokens = parseTokens(tokensText);

  it('maps every symbol the model knows, the space among them', () => {
    expect(tokens.size).toBe(175);
    expect(tokens.get('$'.codePointAt(0)!)).toBe(0);
    expect(tokens.get(' '.codePointAt(0)!)).toBe(16);
    expect(tokens.get(','.codePointAt(0)!)).toBe(3);
    expect(tokens.get('.'.codePointAt(0)!)).toBe(4);
    expect(tokens.get('…'.codePointAt(0)!)).toBe(kittenMeta.endId);
    expect(tokens.get("'".codePointAt(0)!)).toBe(176);
    expect(tokens.get('ᵻ'.codePointAt(0)!)).toBe(177);
    expect(tokens.get('ˈ'.codePointAt(0)!)).toBe(156);
  });

  it('wraps a sentence as the metadata asks, keeping its punctuation', () => {
    const ids = tokenIds('həlˈoʊ, wˈɜːld.', tokens);
    expect(ids[0]).toBe(kittenMeta.startId);
    expect(ids.slice(-2)).toEqual([kittenMeta.endId, kittenMeta.padId]);
    const inner = ids.slice(1, -2);
    expect(inner).toEqual(
      [...'həlˈoʊ, wˈɜːld.'].map((ch) => tokens.get(ch.codePointAt(0)!)),
    );
    expect(inner).toContain(3); // ,
    expect(inner).toContain(4); // .
    expect(inner).toContain(16); // space
  });

  it('skips a codepoint the model has no token for', () => {
    const ids = tokenIds('a b', tokens); // a no-break space
    expect(ids).toEqual([0, tokens.get(97), tokens.get(98), 10, 0]);
    expect(hasContent(ids)).toBe(true);
    expect(hasContent(tokenIds(' ', tokens))).toBe(false);
  });
});

describe('the style row', () => {
  it('is the number of content tokens, as sherpa-onnx counts them', () => {
    expect(contentTokens([0, 5, 6, 7, 10, 0])).toBe(3);
    expect(styleRow([0, 5, 6, 7, 10, 0])).toBe(3);
    expect(contentTokens([0, 10, 0])).toBe(0);
    expect(contentTokens([])).toBe(0);
    // Without the wrapping, every token is content.
    expect(contentTokens([5, 6, 7])).toBe(3);
  });

  it('never goes past the last row', () => {
    const long = [0, ...new Array<number>(450).fill(43), 10, 0];
    expect(styleRow(long)).toBe(kittenMeta.styleRows - 1);
  });

  it('is read out of voices.bin by speaker and row', () => {
    const { speakers, styleRows, styleDim } = kittenMeta;
    const floats = new Float32Array(speakers * styleRows * styleDim);
    for (let i = 0; i < floats.length; i++) floats[i] = i;
    const bytes = new Uint8Array(floats.buffer.slice(0));
    const voices = parseVoices(bytes);
    expect(voices.length).toBe(819200);
    const row = styleVector(voices, 1, 3);
    expect(row.length).toBe(styleDim);
    expect(row[0]).toBe((1 * styleRows + 3) * styleDim);
    expect(row[styleDim - 1]).toBe((1 * styleRows + 3) * styleDim + styleDim - 1);
    expect(() => styleVector(voices, 8, 0)).toThrow(RangeError);
    expect(() => parseVoices(new Uint8Array(3))).toThrow(RangeError);
  });
});

describe('speed', () => {
  it('hands the model the rate itself, the prior of the speaker cancelling out', () => {
    // The engine passes rate / prior (NeuralSpeechEngine._configure).
    expect(modelSpeed(1 / 0.8, 1)).toBeCloseTo(1, 6);
    expect(modelSpeed(1.5 / 0.9, 4)).toBeCloseTo(1.5, 6);
  });
});

describe('clauses and punctuation', () => {
  it('keeps every mark the model pauses at', () => {
    expect(clauses('Hello, world. How are you?')).toEqual([
      { text: 'Hello', punctuation: ',' },
      { text: 'world', punctuation: '.' },
      { text: 'How are you', punctuation: '?' },
    ]);
    expect(clauses('One; two: three!')).toEqual([
      { text: 'One', punctuation: ';' },
      { text: 'two', punctuation: ':' },
      { text: 'three', punctuation: '!' },
    ]);
  });

  it('counts a run of marks once, and a dash as a comma', () => {
    expect(clauses('Wait... what?!')).toEqual([
      { text: 'Wait', punctuation: '.' },
      { text: 'what', punctuation: '?' },
    ]);
    expect(clauses('He said — go')).toEqual([
      { text: 'He said', punctuation: ',' },
      { text: 'go', punctuation: '' },
    ]);
    expect(clauses('and then…')).toEqual([{ text: 'and then', punctuation: '.' }]);
  });

  it('leaves quotes and brackets with their words', () => {
    expect(clauses('"Let there be light," and there was light.')).toEqual([
      { text: '"Let there be light', punctuation: ',' },
      { text: '" and there was light', punctuation: '.' },
    ]);
  });

  it('joins phonemes with the marks back, a space between clauses', () => {
    expect(
      joinPhonemes([
        { phonemes: 'həlˈoʊ', punctuation: ',' },
        { phonemes: 'wˈɜːld', punctuation: '.' },
        { phonemes: 'hˈaʊ ɑːɹ juː', punctuation: '?' },
      ]),
    ).toBe('həlˈoʊ, wˈɜːld. hˈaʊ ɑːɹ juː?');
    expect(joinPhonemes([{ phonemes: '', punctuation: '.' }, { phonemes: 'ɡˈoʊ', punctuation: '' }])).toBe('. ɡˈoʊ');
  });
});

describe('the samples', () => {
  it('lose a little silence at either end, no more', () => {
    const rate = 24000;
    const samples = new Float32Array(rate);
    // Half a second of silence, a tenth of a second of sound, then silence.
    for (let i = 12000; i < 14400; i++) samples[i] = 0.5;
    const trimmed = trimSilence(samples, rate);
    expect(trimmed.length).toBe(2400 + 2 * 1200);
    expect(trimmed[1200]).toBe(0.5);
    // Nothing to trim: the same array back.
    const loud = new Float32Array(100).fill(0.3);
    expect(trimSilence(loud, rate)).toBe(loud);
    expect(trimSilence(new Float32Array(100), rate).length).toBe(0);
  });

  it('a piece that would clip is turned down, not cut off', () => {
    const quiet = Float32Array.from([0.1, -0.5, 0.9]);
    expect(limited(quiet)).toBe(quiet);
    const loud = limited(Float32Array.from([0.5, -1.4, 1.9]));
    const peak = loud.reduce((a, b) => (Math.abs(a) > Math.abs(b) ? a : b));
    expect(peak).toBeCloseTo(0.95, 6);
    // In proportion: the shape of the sound is kept.
    expect(loud[0] / loud[2]).toBeCloseTo(0.5 / 1.9, 6);
  });

  it('pieces are brought to one loudness, gently', () => {
    const tone = (level: number) => Float32Array.from({ length: 2400 }, (_, i) => level * Math.sin(i / 3));
    const rms = (x: Float32Array) => Math.sqrt(x.reduce((a, v) => a + v * v, 0) / x.length);
    const quiet = levelled(tone(0.1), 24000);
    const loud = levelled(tone(0.25), 24000);
    // Nearer each other than they were…
    expect(rms(loud) / rms(quiet)).toBeLessThan(2.5 / 1.5);
    // …but never more than twice as loud, nor clipped.
    const whisper = levelled(tone(0.02), 24000);
    expect(rms(whisper)).toBeLessThanOrEqual(rms(tone(0.02)) * 1.4 + 1e-9);
    expect(loud.every((v) => Math.abs(v) <= 0.95)).toBe(true);
  });
});
