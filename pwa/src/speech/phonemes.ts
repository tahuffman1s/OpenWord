/**
 * Words to IPA, through eSpeak NG — the same front end KittenTTS was
 * trained with — compiled to WebAssembly by the `phonemizer` package.
 *
 * eSpeak's phonemizer splits its output at every clause and drops the
 * punctuation, and the model wants the punctuation: a comma or a full stop
 * among the phonemes is what it pauses at. So the text is cut into clauses
 * first, each is phonemized on its own, and the mark that ended it is put
 * back (see `clauses` and `joinPhonemes` in kitten.ts).
 *
 * Runs wherever it is imported — the worker, by preference, or the main
 * thread; the engine does not care which (see README.md).
 */
import { phonemize } from 'phonemizer';

import { clauses, joinPhonemes } from './kitten';

/** eSpeak's name for the voice the model was trained on. */
export const espeakLanguage = 'en-us';

/** The IPA of [text], punctuation and all, ready for `tokenIds`. */
export async function phonemesFor(text: string, language = espeakLanguage): Promise<string> {
  const parts: { phonemes: string; punctuation: string }[] = [];
  for (const clause of clauses(text)) {
    let phonemes = '';
    if (clause.text.length > 0) {
      const lines = await phonemize(clause.text, language);
      phonemes = lines.join(' ');
    }
    parts.push({ phonemes, punctuation: clause.punctuation });
  }
  return joinPhonemes(parts);
}
