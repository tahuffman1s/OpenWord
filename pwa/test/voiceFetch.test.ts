import { describe, expect, it } from 'vitest';
import { mayFetchUnasked, NeuralModel, WebNeuralVoices } from '../src/data/neuralVoices';

/** A server that knows some paths, and counts what it is asked for. */
function server(known: Record<string, string>) {
  const asked: string[] = [];
  const fetchFake = (async (input: RequestInfo | URL) => {
    const url = String(input);
    asked.push(url);
    const body = known[url];
    if (body === undefined) return new Response('<!doctype html>', { status: 200, headers: { 'content-type': 'text/html' } });
    return new Response(body, { status: 200, headers: { 'content-type': 'application/octet-stream' } });
  }) as typeof fetch;
  return { asked, fetch: fetchFake };
}

const dir = `/voice/${NeuralModel.kitten.archive}/`;

describe('fetching the voice', () => {
  it('asks for the model under the name Cloudflare caches, where the server answers to it', async () => {
    const s = server({
      [`${dir}model.fp32.onnx.bin`]: 'MODEL',
      [`${dir}voices.bin`]: 'VOICES',
      [`${dir}tokens.txt`]: 'TOKENS',
    });
    const voices = new WebNeuralVoices({ store: { fetch: s.fetch, caches: null } });
    const files = await voices.files(NeuralModel.kitten);
    expect(new TextDecoder().decode(files.model)).toBe('MODEL');
    expect(s.asked).toContain(`${dir}model.fp32.onnx.bin`);
    expect(s.asked).not.toContain(`${dir}model.fp32.onnx`);
  });

  it('falls back to the plain name on a server that answers the other with a page', async () => {
    const s = server({
      [`${dir}model.fp32.onnx`]: 'MODEL',
      [`${dir}voices.bin`]: 'VOICES',
      [`${dir}tokens.txt`]: 'TOKENS',
    });
    const voices = new WebNeuralVoices({ store: { fetch: s.fetch, caches: null } });
    const files = await voices.files(NeuralModel.kitten);
    expect(new TextDecoder().decode(files.model)).toBe('MODEL');
    expect(files.tokens).toBe('TOKENS');
  });
});

describe('fetching it before it is asked for', () => {
  it('is fair on an unmetered connection, or where the browser does not say', () => {
    expect(mayFetchUnasked(undefined)).toBe(true);
    expect(mayFetchUnasked({ type: 'wifi', effectiveType: '4g' })).toBe(true);
    expect(mayFetchUnasked({})).toBe(true);
  });

  it('is not when the reader is saving data, on a mobile network, or on a slow one', () => {
    expect(mayFetchUnasked({ saveData: true })).toBe(false);
    expect(mayFetchUnasked({ type: 'cellular', effectiveType: '4g' })).toBe(false);
    expect(mayFetchUnasked({ effectiveType: '3g' })).toBe(false);
  });
});
