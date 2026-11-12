import { describe, expect, it } from 'vitest';
import { MemoryStorage } from '../src/infra/prefs';
import { BackendChoice } from '../src/speech/backendChoice';

function choice(storage = new MemoryStorage(), env: { agent?: string; hasGpu?: boolean; now?: () => number } = {}) {
  return new BackendChoice(storage, { agent: env.agent ?? 'browser/1', hasGpu: env.hasGpu ?? true, now: env.now });
}

describe('which backend the voice runs on', () => {
  it('tries the graphics processor first, and proves it the first time', () => {
    expect(choice().plan()).toEqual({ backends: ['webgpu', 'wasm'], prove: true });
  });

  it('asks for the processor alone where the browser has no WebGPU', () => {
    expect(choice(new MemoryStorage(), { hasGpu: false }).plan()).toEqual({ backends: ['wasm'], prove: false });
  });

  it('does not prove a graphics processor that has spoken before', () => {
    const storage = new MemoryStorage();
    const first = choice(storage);
    first.begin(first.plan());
    first.loaded('webgpu', []);
    expect(choice(storage).plan()).toEqual({ backends: ['webgpu', 'wasm'], prove: false });
  });

  it('passes over a graphics processor that was refused', () => {
    const storage = new MemoryStorage();
    const first = choice(storage);
    first.begin(first.plan());
    first.loaded('wasm', [{ backend: 'webgpu', why: 'the graphics processor gave silence' }]);
    expect(choice(storage).plan()).toEqual({ backends: ['wasm'], prove: false });
  });

  it('forgets what it learnt when the browser changes', () => {
    const storage = new MemoryStorage();
    const first = choice(storage);
    first.loaded('wasm', [{ backend: 'webgpu', why: 'no' }]);
    expect(choice(storage, { agent: 'browser/2' }).plan().backends).toEqual(['webgpu', 'wasm']);
  });

  it('gives a page that died one more go, then passes over what it was trying', () => {
    const storage = new MemoryStorage();
    let now = 1000;
    const launch = () => choice(storage, { now: () => now });
    // The first launch begins a load and is never heard from again.
    let c = launch();
    c.begin(c.plan());
    // The second tries the same, and dies too.
    c = launch();
    expect(c.plan().backends).toEqual(['webgpu', 'wasm']);
    c.begin(c.plan());
    // The third goes to the processor.
    c = launch();
    expect(c.plan()).toEqual({ backends: ['wasm'], prove: false });
    c.begin(c.plan());
    c.loaded('wasm', []);
    expect(launch().plan().backends).toEqual(['wasm']);
    // And in time the graphics processor is given another chance.
    now += 15 * 24 * 60 * 60 * 1000;
    expect(launch().plan().backends).toEqual(['webgpu', 'wasm']);
  });

  it('has nothing to run on once both have ended the page', () => {
    const storage = new MemoryStorage();
    for (let i = 0; i < 4; i++) {
      const c = choice(storage);
      c.begin(c.plan());
    }
    const last = choice(storage);
    expect(last.plan().backends).toEqual([]);
    expect(last.canRun).toBe(false);
  });

  it('does not count a load that failed with an error, or was left on purpose, as a death', () => {
    const storage = new MemoryStorage();
    for (let i = 0; i < 5; i++) {
      const c = choice(storage);
      c.begin(c.plan());
      c.failed();
    }
    expect(choice(storage).plan().backends).toEqual(['webgpu', 'wasm']);
  });

  it('puts the processor first where the graphics processor cannot keep up', () => {
    const storage = new MemoryStorage();
    const c = choice(storage);
    c.loaded('webgpu', []);
    c.paced('webgpu', 1.4);
    expect(choice(storage).plan().backends).toEqual(['wasm', 'webgpu']);
    // Unless the processor turns out slower still.
    c.paced('wasm', 2.1);
    expect(choice(storage).plan().backends).toEqual(['webgpu', 'wasm']);
  });

  it('stops using a graphics processor that breaks mid-chapter', () => {
    const storage = new MemoryStorage();
    const c = choice(storage);
    c.loaded('webgpu', []);
    c.broke('webgpu');
    expect(choice(storage).plan().backends).toEqual(['wasm']);
  });

  it('remembers nothing, and still plans, without storage', () => {
    const c = new BackendChoice(null, { agent: 'x', hasGpu: true });
    c.begin(c.plan());
    c.loaded('wasm', [{ backend: 'webgpu', why: 'no' }]);
    expect(c.plan()).toEqual({ backends: ['webgpu', 'wasm'], prove: true });
  });
});
