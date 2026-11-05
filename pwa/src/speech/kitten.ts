/**
 * The pure part of running KittenTTS: what sherpa-onnx does for the native
 * app between the phonemes and the network, written out so that the worker
 * can do it and a test can check it without a model.
 *
 * KittenTTS nano v0.8 takes a row of token ids — one per IPA codepoint,
 * with punctuation among them, wrapped as the model's metadata asks — a
 * style vector chosen by how many tokens there are, and a speed. These are
 * the facts of the model, from its ONNX metadata, and they are not
 * negotiable: a different wrapping gives garbled speech.
 */

/** The metadata of `model.fp32.onnx`, as sherpa-onnx reads it. */
export const kittenMeta = {
  startId: 0,
  endId: 10,
  padId: 0,
  addPadAfterEnd: true,
  maxTokenLen: 400,
  styleRows: 400,
  styleDim: 256,
  speakers: 8,
  sampleRate: 24000,
  /** Indexed by speaker id; see `NeuralSpeaker.prior`. */
  speedPriors: [0.8, 0.8, 0.8, 0.8, 0.9, 0.8, 0.8, 0.8],
} as const;

/**
 * `tokens.txt` as a map from codepoint to id. Each line is `<symbol> <id>`;
 * a line whose symbol is a space is just ` <id>` with the space at the
 * front, so the id is whatever follows the last space.
 */
export function parseTokens(text: string): Map<number, number> {
  const map = new Map<number, number>();
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\r$/, '');
    if (line.length === 0) continue;
    const at = line.lastIndexOf(' ');
    if (at < 0) continue;
    const id = Number.parseInt(line.slice(at + 1), 10);
    if (!Number.isInteger(id)) continue;
    const symbol = at === 0 ? ' ' : line.slice(0, at);
    const codepoints = [...symbol];
    if (codepoints.length !== 1) continue;
    map.set(codepoints[0].codePointAt(0)!, id);
  }
  return map;
}

/**
 * The ids the model is handed for one piece of phonemes: wrapped in the
 * start id and the end id, with a pad after the end as the metadata says,
 * and any codepoint the model has no token for left out, as sherpa-onnx
 * leaves it out.
 */
export function tokenIds(phonemes: string, tokens: ReadonlyMap<number, number>): number[] {
  const ids: number[] = [kittenMeta.startId];
  for (const ch of phonemes) {
    const id = tokens.get(ch.codePointAt(0)!);
    if (id !== undefined) ids.push(id);
  }
  ids.push(kittenMeta.endId);
  if (kittenMeta.addPadAfterEnd) ids.push(kittenMeta.padId);
  return ids;
}

/** Whether [ids] carry anything beyond the wrapping. */
export function hasContent(ids: readonly number[]): boolean {
  return contentTokens(ids) > 0;
}

/**
 * How many tokens of [ids] are content: all but a leading start id, a
 * trailing pad and the end id before it — sherpa-onnx's `SelectStyleRow`.
 */
export function contentTokens(ids: readonly number[]): number {
  let n = ids.length;
  if (n > 0 && ids[0] === kittenMeta.startId) n--;
  let last = ids.length - 1;
  if (n > 0 && ids[last] === kittenMeta.padId) {
    n--;
    last--;
  }
  if (n > 0 && last >= 0 && ids[last] === kittenMeta.endId) n--;
  return Math.max(n, 0);
}

/**
 * Which row of the speaker's style table goes with [ids]: the row for
 * their number of content tokens, and the last row for more tokens than
 * there are rows.
 */
export function styleRow(ids: readonly number[]): number {
  return Math.min(contentTokens(ids), kittenMeta.styleRows - 1);
}

/**
 * The style vector for a speaker and a row, out of `voices.bin`: raw
 * little-endian float32, `[speakers][rows][dim]`. A copy, so it can be
 * handed to the runtime as a tensor of its own.
 */
export function styleVector(voices: Float32Array, sid: number, row: number): Float32Array {
  const { styleRows, styleDim } = kittenMeta;
  const start = (sid * styleRows + row) * styleDim;
  if (start + styleDim > voices.length) {
    throw new RangeError(`no style for speaker ${sid}, row ${row}: voices.bin holds ${voices.length} floats`);
  }
  return voices.slice(start, start + styleDim);
}

/** `voices.bin` as floats; the bytes must be 4-aligned, which a fresh copy is. */
export function parseVoices(bytes: Uint8Array): Float32Array {
  if (bytes.byteLength % 4 !== 0) throw new RangeError(`voices.bin is ${bytes.byteLength} bytes, not whole floats`);
  const floats = new Float32Array(bytes.byteLength / 4);
  new Uint8Array(floats.buffer).set(bytes);
  return floats;
}

/**
 * The speed the model is handed. sherpa-onnx multiplies the speaker's
 * prior into whatever speed it is asked for, and the native app asks for
 * `rate / prior` so that the prior cancels and 1× is the pace the voice
 * was trained at (see `NeuralSpeechEngine._configure`). Here both steps
 * are ours, and the product is the same: the rate itself. Kept as one
 * function so the arithmetic is written down once.
 */
export function modelSpeed(requested: number, sid: number): number {
  const prior = kittenMeta.speedPriors[sid] ?? 1;
  // requested is already rate / prior, as the engine passes it.
  return requested * prior;
}

/**
 * A little silence cut from either end: samples below [floor] beyond
 * [keepMs] of it. The model leaves a short breath before and after a
 * piece, which between pieces played back to back would be heard as a
 * stammer.
 */
export function trimSilence(samples: Float32Array, sampleRate: number, floor = 0.002, keepMs = 50): Float32Array {
  const keep = Math.round((sampleRate * keepMs) / 1000);
  let start = 0;
  while (start < samples.length && Math.abs(samples[start]) < floor) start++;
  let end = samples.length;
  while (end > start && Math.abs(samples[end - 1]) < floor) end--;
  if (start === samples.length) return samples.subarray(0, 0);
  start = Math.max(0, start - keep);
  end = Math.min(samples.length, end + keep);
  if (start === 0 && end === samples.length) return samples;
  return samples.subarray(start, end);
}

/**
 * [samples] brought gently to one loudness, so that one verse is not
 * heard louder than the one before: the speech in them — frames of
 * [sampleRate] / 50 above a whisper — is moved towards [target], by no
 * more than 3 dB either way, and then [limited].
 */
export function levelled(samples: Float32Array, sampleRate: number, target = 0.14): Float32Array {
  const frame = Math.max(1, Math.trunc(sampleRate / 50));
  let energy = 0;
  let frames = 0;
  for (let start = 0; start + frame <= samples.length; start += frame) {
    let sum = 0;
    for (let i = start; i < start + frame; i++) sum += samples[i] * samples[i];
    const rms = Math.sqrt(sum / frame);
    if (rms > 0.01) {
      energy += rms * rms;
      frames++;
    }
  }
  if (frames === 0) return limited(samples);
  const gain = Math.min(Math.max(target / Math.sqrt(energy / frames), 0.7), 1.4);
  const scaled = new Float32Array(samples.length);
  for (let i = 0; i < samples.length; i++) scaled[i] = samples[i] * gain;
  return limited(scaled);
}

/**
 * [samples] turned down, if need be, so that none is louder than
 * [ceiling].
 *
 * A model's output can go past full scale, and played out the loudest are
 * cut off flat: heard as a crackle. Where a piece would be, the whole
 * piece is made a little quieter instead.
 */
export function limited(samples: Float32Array, ceiling = 0.95): Float32Array {
  let peak = 0;
  for (let i = 0; i < samples.length; i++) {
    const level = Math.abs(samples[i]);
    if (level > peak) peak = level;
  }
  if (peak <= ceiling) return samples;
  const gain = ceiling / peak;
  const out = new Float32Array(samples.length);
  for (let i = 0; i < samples.length; i++) out[i] = samples[i] * gain;
  return out;
}

/**
 * The punctuation the model knows as a pause: what sherpa-onnx counts as
 * punctuation, and what eSpeak ends a clause at. A phonemizer that drops
 * punctuation has it put back from here.
 */
export const clausePunctuation = ',.;:!?';

export interface Clause {
  /** The words, with no punctuation at the end. */
  text: string;
  /** The punctuation that closed it: one of [clausePunctuation], or ''. */
  punctuation: string;
}

/**
 * [text] cut into clauses at its punctuation, each with the mark that
 * ended it, so that the phonemes of each can be joined with the mark put
 * back. Quotes, brackets and dashes are not clause ends to the model, and
 * stay with the words. A run of marks — "…" written as "..." — counts
 * once, as its first.
 */
export function clauses(text: string): Clause[] {
  const result: Clause[] = [];
  let words = '';
  for (const ch of text.replace(/[—–]/g, ', ').replace(/…/g, '...')) {
    if (clausePunctuation.includes(ch)) {
      const last = result[result.length - 1];
      if (words.trim().length === 0 && last !== undefined && last.punctuation !== '') {
        // Another mark straight after one: "..." or "?!" — one pause.
        words = '';
        continue;
      }
      result.push({ text: words.trim(), punctuation: ch });
      words = '';
    } else {
      words += ch;
    }
  }
  if (words.trim().length > 0) result.push({ text: words.trim(), punctuation: '' });
  return result.filter((c) => c.text.length > 0 || c.punctuation !== '');
}

/**
 * The phonemes of a piece, as one string with its punctuation back in:
 * the clauses' phonemes, each followed by its mark and a space, as the
 * phonemizer the model was trained with wrote them.
 */
export function joinPhonemes(parts: readonly { phonemes: string; punctuation: string }[]): string {
  let out = '';
  for (const part of parts) {
    const phonemes = part.phonemes.trim();
    if (phonemes.length === 0 && part.punctuation === '') continue;
    if (out.length > 0 && !out.endsWith(' ')) out += ' ';
    out += phonemes + part.punctuation;
  }
  return out.trim();
}
