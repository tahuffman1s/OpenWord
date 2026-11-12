import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { NeuralSpeechEngine, Synthesiser } from '../src/data/neuralSpeech';
import { NeuralModel } from '../src/data/neuralVoices';
import { ListeningPlace, ReadAloud, ReadAloudState } from '../src/data/readAloud';
import { AudioProcessingState, MediaControl, ReadAloudHandler } from '../src/data/readAloudSession';
import { Reference } from '../src/model/bible';
import { FakeSpeech, settle, Completer } from './fakeSpeech';
import { parseFixture } from './readAloudFixture';

const bible = parseFixture();
const chapterFor = (r: Reference) => bible.bookByCode(r.bookCode)?.chapter(r.chapter) ?? null;
const ref = (book: string, chapter: number, verse?: number) => new Reference(book, chapter, verse ?? null);

describe('the controller', () => {
  let speech: FakeSpeech;
  let heard: Reference[];
  let voice: ReadAloud;
  let now: Date;
  const made: ReadAloud[] = [];

  const makeVoice = (init: Partial<ConstructorParameters<typeof ReadAloud>[0]> = {}) => {
    const v = new ReadAloud({
      clock: () => now,
      engine: speech,
      chapterFor,
      nextChapter: (r) => (r.bookCode === 'GEN' && r.chapter === 1 ? ref('GEN', 2) : null),
      onChapterHeard: (r) => heard.push(r),
      ...init,
    });
    made.push(v);
    return v;
  };

  beforeEach(() => {
    speech = new FakeSpeech();
    heard = [];
    now = new Date(2026, 8, 24, 8);
    voice = makeVoice();
  });

  afterEach(() => {
    for (const v of made) v.dispose();
    made.length = 0;
    ReadAloud.retryDelay = 400;
  });

  it('reads a chapter as one passage, announced, following the words', async () => {
    voice.play(ref('GEN', 1));
    await settle();
    // Not a verse at a time: the whole short chapter goes to the voice at
    // once, so it is not stopped and started between verses.
    expect(speech.said).toHaveLength(1);
    expect(speech.said[0].startsWith('Genesis, chapter 1. In the beginning')).toBe(true);
    expect(speech.said[0]).toContain('An indented paragraph');
    // The footnote marker is not read out.
    expect(speech.said[0]).not.toContain('Elohim');
    expect(voice.current!.equals(ref('GEN', 1))).toBe(true);

    // The words it reports reaching say which verse is being read.
    speech.reach('In the beginning');
    expect(voice.current!.equals(ref('GEN', 1, 1))).toBe(true);
    speech.reach('An indented paragraph');
    expect(voice.current!.equals(ref('GEN', 1, 5))).toBe(true);

    speech.finish();
    await settle();
    expect(heard.map((r) => r.key)).toEqual([ref('GEN', 1).key]);
    expect(speech.said[speech.said.length - 1].startsWith('Genesis, chapter 2.')).toBe(true);

    speech.finish();
    await settle();
    // Nothing after Genesis 2 here, so it stops.
    expect(voice.state).toBe(ReadAloudState.idle);
  });

  it('started part way in, a chapter is not counted as heard', async () => {
    voice.play(ref('GEN', 1, 4));
    await settle();
    expect(speech.said[0].startsWith('A paragraph set flush')).toBe(true);
    speech.finish();
    await settle();
    expect(heard).toHaveLength(0);
    // It still goes on to the next chapter.
    expect(speech.said[speech.said.length - 1].startsWith('Genesis, chapter 2.')).toBe(true);
  });

  it('a selection is read and then it stops', async () => {
    voice.play(ref('GEN', 1, 3), { only: new Set([3, 5]) });
    await settle();
    expect(speech.said[0]).not.toContain('A paragraph set flush');
    speech.reach('An indented paragraph');
    expect(voice.current!.equals(ref('GEN', 1, 5))).toBe(true);
    speech.finish();
    await settle();
    expect(voice.state).toBe(ReadAloudState.idle);
    expect(speech.said).toHaveLength(1);
  });

  it('pausing remembers the verse it had reached', async () => {
    voice.play(ref('GEN', 1, 3));
    await settle();
    speech.reach('A paragraph set flush');
    voice.pause();
    await settle();
    expect(voice.state).toBe(ReadAloudState.paused);
    expect(voice.current!.equals(ref('GEN', 1, 4))).toBe(true);
    voice.resume();
    await settle();
    expect(speech.said[speech.said.length - 1].startsWith('A paragraph set flush')).toBe(true);
  });

  it('skips forward and back, interrupting what is being said', async () => {
    voice.play(ref('GEN', 1, 2));
    await settle();
    voice.skip(1);
    await settle();
    expect(voice.current!.equals(ref('GEN', 1, 3))).toBe(true);
    expect(speech.stops).toBeGreaterThan(0);
    expect(speech.said[speech.said.length - 1].startsWith('God said')).toBe(true);
    voice.skip(-1);
    voice.skip(-1);
    await settle();
    // No further back than where it started.
    expect(voice.current!.equals(ref('GEN', 1, 2))).toBe(true);
  });

  it('resuming takes up the word it had reached, not the verse', async () => {
    voice.play(ref('GEN', 1, 3));
    await settle();
    speech.reach('be light');
    voice.pause();
    await settle();
    voice.resume();
    await settle();
    expect(speech.said[speech.said.length - 1].startsWith('be light')).toBe(true);
    expect(voice.current!.equals(ref('GEN', 1, 3))).toBe(true);
    // And the verses after it follow as before.
    expect(speech.said[speech.said.length - 1]).toContain('A paragraph set flush');
    // A word reached in the resumed passage is placed in its verse.
    speech.reach('light.');
    voice.pause();
    await settle();
    voice.resume();
    await settle();
    expect(speech.said[speech.said.length - 1].startsWith('light.')).toBe(true);
  });

  it('a voice that can pause is held where it is, not stopped', async () => {
    const held = new FakeSpeech({ pauses: true });
    voice = makeVoice({ engine: held, nextChapter: () => null });
    voice.play(ref('GEN', 1, 3));
    await settle();
    held.reach('be light');
    const stops = held.stops;
    voice.pause();
    await settle();
    expect(voice.state).toBe(ReadAloudState.paused);
    expect(held.paused).toBe(1);
    expect(held.stops).toBe(stops);
    voice.resume();
    await settle();
    // Taken up mid-word by the engine, not said again.
    expect(held.resumed).toBe(1);
    expect(held.said).toHaveLength(1);
    expect(voice.isPlaying).toBe(true);

    // Stepping while held lets go of it, and the next verse is said.
    voice.pause();
    voice.skip(1);
    await settle();
    expect(held.stops).toBeGreaterThan(stops);
    voice.resume();
    await settle();
    expect(held.resumed).toBe(1);
    expect(held.said[held.said.length - 1].startsWith('A paragraph set flush')).toBe(true);
  });

  it('where listening got to is kept, and taken up again', async () => {
    const places: (ListeningPlace | null)[] = [];
    voice = makeVoice({ nextChapter: () => null, onPlace: (p) => places.push(p) });
    voice.play(ref('GEN', 1, 3));
    await settle();
    speech.reach('be light');
    voice.stop();
    await settle();
    const kept = places[places.length - 1]!;
    expect(kept.verse.equals(ref('GEN', 1, 3))).toBe(true);
    expect(kept.offset).toBeGreaterThan(0);
    expect(kept.atTop).toBe(false);
    expect(ListeningPlace.decode(kept.encode())!.equals(kept)).toBe(true);

    voice.play(kept.verse, { offset: kept.offset, fromTop: kept.fromTop });
    await settle();
    expect(speech.said[speech.said.length - 1].startsWith('be light')).toBe(true);
    // Heard to the end, there is nothing left to take up.
    speech.finish();
    await settle();
    expect(voice.isActive).toBe(false);
    expect(places[places.length - 1]).toBeNull();
  });

  it('a chapter begun at its top counts as heard when taken up', async () => {
    voice.play(ref('GEN', 1, 3), { offset: 4, fromTop: true });
    await settle();
    expect(speech.said[speech.said.length - 1].startsWith('said')).toBe(true);
    speech.finish();
    await settle();
    expect(heard.map((r) => r.key)).toEqual([ref('GEN', 1).key]);
  });

  it('a selection read aloud is not kept as a place', async () => {
    const places: (ListeningPlace | null)[] = [];
    voice = makeVoice({ nextChapter: () => null, onPlace: (p) => places.push(p) });
    voice.play(ref('GEN', 1, 3), { only: new Set([3, 4]) });
    await settle();
    voice.stop();
    expect(places).toHaveLength(0);
  });

  it('stepping to another verse starts it from the beginning', async () => {
    voice.play(ref('GEN', 1, 3));
    await settle();
    speech.reach('be light');
    voice.skip(1);
    await settle();
    expect(speech.said[speech.said.length - 1].startsWith('A paragraph set flush')).toBe(true);
  });

  it('where no words are reported, the verse is estimated from time', async () => {
    voice.play(ref('GEN', 1, 3));
    await settle();
    speech.begin();
    // About 14 characters a second: three seconds is past verse 3, which
    // is 31 characters, and into verse 4.
    now = new Date(now.getTime() + 3000);
    voice.debugEstimate();
    expect(voice.current!.equals(ref('GEN', 1, 4))).toBe(true);
  });

  it('resuming an estimated place goes back to its sentence', async () => {
    voice.play(ref('GEN', 1, 3));
    await settle();
    speech.begin();
    now = new Date(now.getTime() + 3000);
    voice.pause();
    await settle();
    expect(voice.current!.equals(ref('GEN', 1, 4))).toBe(true);
    voice.resume();
    await settle();
    // Not the passage again from verse 3, and not mid-word: the start of
    // the sentence the voice was in.
    expect(speech.said[speech.said.length - 1].startsWith('A paragraph set flush')).toBe(true);
  });

  it('a sentence start is found for an estimated place', () => {
    const text = 'In the beginning. God said, “Let there be light.” And so.';
    expect(ReadAloud.sentenceStart(text, 5)).toBe(0);
    expect(ReadAloud.sentenceStart(text, 25)).toBe(18);
    expect(ReadAloud.sentenceStart(text, text.length - 2)).toBe(50);
  });

  it('the estimate learns how fast the voice really is', async () => {
    voice.play(ref('GEN', 1, 1));
    await settle();
    speech.begin();
    const length = speech.said[speech.said.length - 1].length;
    // This voice took twice as long as the guess would say.
    now = new Date(now.getTime() + Math.round((length / 7) * 1000));
    speech.finish();
    await settle();
    voice.play(ref('GEN', 1, 3));
    await settle();
    speech.begin();
    now = new Date(now.getTime() + 3000);
    voice.debugEstimate();
    // Slower now — about 10.5 characters a second, halfway to what it
    // measured — so three seconds is still in verse 3's 31 characters.
    expect(voice.current!.equals(ref('GEN', 1, 3))).toBe(true);
  });

  it('one that does report progress keeps its passages', async () => {
    voice.play(ref('GEN', 1, 1));
    await settle();
    speech.reach('The earth was');
    speech.finish();
    await settle();
    voice.play(ref('GEN', 1, 3));
    await settle();
    expect(speech.said[speech.said.length - 1]).toContain('A paragraph set flush');
  });

  it('a change of speed takes effect at once', async () => {
    voice.configure({ language: 'en', rate: 1.0 });
    voice.play(ref('GEN', 1, 3));
    await settle();
    voice.configure({ language: 'en', rate: 1.5 });
    await settle();
    expect(speech.rates[speech.rates.length - 1]).toBe(1.5);
    expect(speech.said).toHaveLength(2);
  });

  it('one failed verse is said again, not given up on', async () => {
    ReadAloud.retryDelay = 0;
    voice.play(ref('GEN', 1, 3));
    await settle();
    speech.finish(false);
    await settle();
    expect(voice.isPlaying).toBe(true);
    expect(voice.error).toBeNull();
    expect(speech.said).toHaveLength(2);
    expect(speech.said[0]).toBe(speech.said[1]);
    // And a success clears it, so a later hiccup gets its retry too.
    speech.finish();
    await settle();
    speech.finish(false);
    await settle();
    expect(voice.isPlaying).toBe(true);
    expect(voice.error).toBeNull();
  });

  it('a device that stops speaking ends it, and says so', async () => {
    ReadAloud.retryDelay = 0;
    voice.play(ref('GEN', 1, 3));
    await settle();
    speech.finish(false);
    await settle();
    speech.finish(false);
    await settle();
    expect(voice.state).toBe(ReadAloudState.idle);
    expect(voice.error).not.toBeNull();
  });

  it('a voice made ready ahead is not made ready again', async () => {
    const loading = (speech.configuring = new Completer<void>());
    voice.configure({ language: 'en', rate: 1, voice: 'Serena' });
    voice.prepare();
    await settle();
    expect(speech.rates).toHaveLength(1);
    // Listen while it is still loading waits for it, rather than
    // speaking with nothing loaded.
    voice.play(ref('GEN', 1, 3));
    await settle();
    expect(speech.said).toHaveLength(0);
    loading.complete();
    await settle();
    expect(speech.said).toHaveLength(1);
    expect(speech.rates).toHaveLength(1);
  });

  it('a voice is kept by a name that says whose it is', () => {
    const leo = NeuralModel.kitten.speakers[NeuralModel.kitten.speakers.length - 1];
    const name = NeuralModel.kitten.voiceName(leo);
    expect(name).toBe('openword:kitten:6');
    expect(NeuralModel.parse(name)).toEqual([NeuralModel.kitten, leo]);
    expect(NeuralModel.parse('openword:kitten:99')).toBeNull();
    // Kokoro, and the device's voices, that 1.21 read with.
    expect(NeuralModel.parse('openword:kokoro:1')).toBeNull();
    expect(NeuralModel.parse('Samantha')).toBeNull();
    expect(NeuralModel.parse(null)).toBeNull();
    // Those, or none, mean the first voice.
    expect(NeuralModel.chosen('Samantha')).toEqual([NeuralModel.kitten, NeuralModel.kitten.speakers[0]]);
    expect(NeuralModel.chosen(name)[1]).toBe(leo);
    // Offered by their names, in the model's order, Bella first.
    expect(NeuralModel.kitten.voices.map((v) => v.title)).toEqual([
      'Bella',
      'Jasper',
      'Luna',
      'Bruno',
      'Rosie',
      'Hugo',
      'Kiki',
      'Leo',
    ]);
    // The priors are the model's own, by speaker id.
    expect(NeuralModel.kitten.speakers.find((s) => s.id === 4)!.prior).toBe(0.9);
  });

  it('text is voiced a sentence at a time, long ones cut again', () => {
    const text =
      'Genesis, chapter 1. In the beginning God created the heavens ' +
      'and the earth. Now the earth was formless and empty, darkness ' +
      'was over the surface of the deep, and the Spirit of God was ' +
      'hovering over the waters.';
    const pieces = NeuralSpeechEngine.pieces(text, { longest: 60 });
    expect(pieces[0]).toEqual([0, 'Genesis, chapter 1.']);
    for (const [offset, words] of pieces) {
      expect(text.substring(offset, offset + words.length)).toBe(words);
      expect(words.length).toBeLessThanOrEqual(60);
      expect(words.trim()).toBe(words);
    }
    // Nothing left out, and a long sentence cut at a comma.
    expect(pieces.map((p) => p[1]).join(' ')).toBe(text);
    expect(pieces.some((p) => p[1].endsWith('empty,'))).toBe(true);
  });

  it('a piece that would clip is turned down, not cut off', () => {
    const quiet = Float32Array.from([0.1, -0.5, 0.9]);
    expect(Synthesiser.limited(quiet)).toBe(quiet);
    const loud = Synthesiser.limited(Float32Array.from([0.5, -1.4, 1.9]));
    expect(Math.max(...Array.from(loud, Math.abs))).toBeCloseTo(0.95, 6);
    expect(loud[0] / loud[2]).toBeCloseTo(0.5 / 1.9, 6);
  });

  it('pieces are brought to one loudness, gently', () => {
    const tone = (level: number) => Float32Array.from({ length: 2400 }, (_, i) => level * Math.sin(i / 3));
    const rms = (x: Float32Array) => Math.sqrt(x.reduce((a, v) => a + v * v, 0) / x.length);
    const quiet = Synthesiser.levelled(tone(0.1), 24000);
    const loud = Synthesiser.levelled(tone(0.25), 24000);
    expect(rms(loud) / rms(quiet)).toBeLessThan(2.5 / 1.5);
    const whisper = Synthesiser.levelled(tone(0.02), 24000);
    expect(rms(whisper)).toBeLessThanOrEqual(rms(tone(0.02)) * 1.4 + 1e-9);
    expect(loud.every((v) => Math.abs(v) <= 0.95)).toBe(true);
  });

  it('a piece ending mid-phrase is told so, with a comma', () => {
    // Without one the voice swallows the last word a third of the time.
    expect(NeuralSpeechEngine.voiced('in it I have')).toBe('in it I have,');
    expect(NeuralSpeechEngine.voiced('there was light.')).toBe('there was light.');
    expect(NeuralSpeechEngine.voiced('God said,')).toBe('God said,');
    expect(NeuralSpeechEngine.voiced('“Let there be light.”')).toBe('“Let there be light.”');
    expect(NeuralSpeechEngine.voiced('he asked?')).toBe('he asked?');
  });

  it('every verse begins a piece of its own', () => {
    const text = 'Psalm 23. The Lord is my shepherd; I shall not want He makes me lie down in green pastures';
    const verse2 = text.indexOf('He makes');
    const pieces = NeuralSpeechEngine.pieces(text, { breaks: [0, text.indexOf('The Lord'), verse2] });
    expect(pieces.map((p) => p[0])).toContain(verse2);
    expect(pieces.find((p) => p[0] === verse2)![1].startsWith('He makes')).toBe(true);
    expect(pieces.map((p) => p[1]).join(' ')).toBe(text);
  });

  it('the voice is told where every verse begins', async () => {
    voice.play(ref('GEN', 1));
    await settle();
    const passage = speech.said[0];
    const chapter = chapterFor(ref('GEN', 1))!;
    expect(speech.breaks[0]).toBe(0);
    expect(passage.substring(speech.breaks[1]).startsWith(ReadAloud.speakable(chapter.verseText(1)))).toBe(true);
    expect(speech.breaks).toHaveLength(chapter.verseCount + 1);
  });

  it('a piece is not cut straight after a little word', () => {
    const pieces = NeuralSpeechEngine.pieces('In the beginning God created the heavens and the earth.');
    expect(pieces[0][1]).toBe('In the beginning God created');
    expect(pieces[1][1]).toBe('the heavens and the earth.');
  });

  it('the first piece is short, so the voice starts at once', () => {
    const text = new Array<string>(40).fill('and the evening and the morning').join(', ');
    const pieces = NeuralSpeechEngine.pieces(text);
    const lengths = pieces.map(([, words]) => words.length);
    expect(lengths[0]).toBeLessThanOrEqual(40);
    expect(lengths[1]).toBeLessThanOrEqual(80);
    expect(lengths[1]).toBeGreaterThan(40);
    // Then as long as a piece may be, and no longer, but for whatever is
    // left at the end.
    const middle = lengths.slice(2, lengths.length - 1);
    expect(middle.every((n) => n > 80 && n <= 160)).toBe(true);
    expect(pieces.map((p) => p[1]).join(' ')).toBe(text);
  });

  it('the divine name is said as a word', () => {
    expect(ReadAloud.speakable('The LORD is my shepherd; the Lord GOD')).toBe('The Lord is my shepherd; the Lord God');
    expect(ReadAloud.announcement(ref('PSA', 23))).toBe('Psalm 23.');
  });
});

describe('the lock screen', () => {
  let speech: FakeSpeech;
  let voice: ReadAloud;
  let handler: ReadAloudHandler;

  beforeEach(() => {
    speech = new FakeSpeech();
    voice = new ReadAloud({ engine: speech, chapterFor, nextChapter: () => null });
    // No navigator.mediaSession under Node: the handler keeps its own
    // notifiers, which is what the system would be shown.
    handler = new ReadAloudHandler(voice, () => 'Test Translation', null);
  });

  afterEach(() => voice.dispose());

  it('shows nothing to control while nothing is read', () => {
    const state = handler.playbackState.value;
    expect(state.playing).toBe(false);
    expect(state.processingState).toBe(AudioProcessingState.idle);
    expect(state.controls).toEqual([]);
  });

  it('shows where it has got to, and the controls for it', async () => {
    voice.play(ref('GEN', 1, 3));
    await settle();
    const state = handler.playbackState.value;
    expect(state.playing).toBe(true);
    expect(state.processingState).toBe(AudioProcessingState.ready);
    expect(state.controls).toEqual([
      MediaControl.skipToPrevious,
      MediaControl.pause,
      MediaControl.skipToNext,
      MediaControl.stop,
    ]);
    const item = handler.mediaItem.value!;
    expect(item.title).toBe('Genesis 1:3');
    expect(item.album).toBe('Test Translation');
    expect(item.id).toBe('GEN/1');
  });

  it('its buttons drive the voice', async () => {
    voice.play(ref('GEN', 1, 2));
    await settle();
    await handler.pause();
    expect(voice.state).toBe(ReadAloudState.paused);
    expect(handler.playbackState.value.controls[1]).toBe(MediaControl.play);
    await handler.play();
    await settle();
    expect(voice.isPlaying).toBe(true);
    await handler.skipToNext();
    await settle();
    expect(voice.current!.equals(ref('GEN', 1, 3))).toBe(true);
    await handler.skipToPrevious();
    await settle();
    expect(voice.current!.equals(ref('GEN', 1, 2))).toBe(true);
    // A headset's one button pauses and resumes.
    await handler.click();
    expect(voice.state).toBe(ReadAloudState.paused);
    await handler.click();
    expect(voice.isPlaying).toBe(true);
    await handler.stop();
    expect(voice.state).toBe(ReadAloudState.idle);
    expect(handler.playbackState.value.processingState).toBe(AudioProcessingState.idle);
  });

  it('the lock screen gets a cover for the chapter', async () => {
    const drawn: Reference[] = [];
    handler.bind(voice, () => 'Test Translation', {
      artwork: async (chapter) => {
        drawn.push(chapter);
        return `blob:covers/${chapter.bookCode}-${chapter.chapter}.png`;
      },
    });
    voice.play(ref('GEN', 1, 3));
    await settle();
    expect(handler.mediaItem.value!.artUri).toBe('blob:covers/GEN-1.png');
    // Once per chapter, not once per verse.
    voice.skip(1);
    await settle();
    expect(drawn.map((r) => r.key)).toEqual([ref('GEN', 1).key]);
  });

  it('a new voice can take over the session', async () => {
    const another = new ReadAloud({ engine: speech, chapterFor, nextChapter: () => null });
    handler.bind(another, () => 'Another');
    another.play(ref('GEN', 1, 4));
    await settle();
    expect(handler.mediaItem.value!.title).toBe('Genesis 1:4');
    expect(handler.mediaItem.value!.album).toBe('Another');
    // The first voice no longer drives what the system shows.
    voice.play(ref('GEN', 1, 1));
    await settle();
    expect(handler.mediaItem.value!.title).toBe('Genesis 1:4');
    another.dispose();
  });

  it('the chapter is announced by its name, without the full stop', () => {
    voice.play(ref('GEN', 1));
    expect(ReadAloudHandler.itemFor(voice, 'Album')!.title).toBe('Genesis, chapter 1');
  });
});
