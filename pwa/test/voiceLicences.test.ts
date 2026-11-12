import { describe, expect, it } from 'vitest';
import { espeakSource, voiceAttribution, voiceLicences } from '../src/data/voiceLicences';
import { FsAssetBundle } from './fsAssets';

describe('the voice’s licences', () => {
  it('are there in full, with the GPL source', async () => {
    const entries = await voiceLicences(new FsAssetBundle());
    const text = (pkg: string) => entries.filter((e) => e.packages.includes(pkg)).map((e) => e.text).join('\n');
    expect(text('KittenTTS')).toContain('Apache License');
    expect(text('KittenTTS')).toContain('KittenML');
    expect(text('eSpeak NG')).toContain('GNU GENERAL PUBLIC LICENSE');
    expect(text('eSpeak NG')).toContain(espeakSource);
    expect(text('ONNX Runtime')).toContain('Microsoft Corporation');
  });

  it('the credit names the GPL and where its source is', () => {
    expect(voiceAttribution).toContain('GPL-3.0');
    expect(voiceAttribution).toContain(espeakSource);
    expect(voiceAttribution).toContain('KittenTTS');
  });
});
