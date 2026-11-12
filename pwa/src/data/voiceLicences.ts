import { rootBundle, type AssetBundle } from '../infra/assets';

// Where the app's source is published: the repository the attribution
// below points at.
export const releaseOwner = 'tahuffman1s';
export const releaseRepo = 'OpenWord';

/**
 * Where the source of the eSpeak NG the voice pronounces with can be had:
 * the `phonemizer` package compiles it to WebAssembly, and its repository
 * says which commit of eSpeak NG it builds.
 */
export const espeakSource = 'https://github.com/xenova/phonemizer.js';

/**
 * Who made the voice reading aloud is heard in, and under what licences,
 * as Settings shows it.
 *
 * eSpeak NG is GPL-3.0 and is compiled into the library the voice
 * pronounces with, so the app as built is distributed under the GPL's
 * terms too; the GPL asks that whoever has it can have the source, and
 * says so here.
 */
export const voiceAttribution =
  'KittenTTS nano 0.8 by KittenML, Apache-2.0, run with ONNX Runtime Web ' +
  '(MIT). Its pronunciation comes from eSpeak NG, GPL-3.0, which is built ' +
  'into it through phonemizer.js (Apache-2.0), so this app as built is ' +
  `also under the GPL-3.0. Source: github.com/${releaseOwner}/${releaseRepo}, ` +
  `and for eSpeak NG ${espeakSource}.`;

/** One entry of the Licences screen: who it covers, and the text. */
export interface VoiceLicence {
  packages: readonly string[];
  text: string;
}

/**
 * The licences of what the voice is made of, for the Licences screen,
 * which lists these alongside whatever else it shows.
 */
export async function voiceLicences(bundle: AssetBundle = rootBundle): Promise<VoiceLicence[]> {
  const [apache, gpl, mit] = await Promise.all([
    bundle.loadString('assets/licences/Apache-2.0.txt'),
    bundle.loadString('assets/licences/GPL-3.0.txt'),
    bundle.loadString('assets/licences/onnxruntime-MIT.txt'),
  ]);
  return [
    { packages: ['KittenTTS'], text: `KittenTTS nano 0.8, copyright KittenML.\n\n${apache}` },
    {
      packages: ['eSpeak NG'],
      text:
        'eSpeak NG, copyright Jonathan Duddington, Reece H. Dunn and its ' +
        `contributors. Its source, as built into this app: ${espeakSource}\n\n${gpl}`,
    },
    { packages: ['ONNX Runtime'], text: mit },
  ];
}
