/**
 * The one form Scripture text is stored in.
 *
 * Unicode can spell the same word more than one way. "é" is either one
 * codepoint or an "e" with a combining acute after it; Hebrew with two
 * points on a letter can carry them in either order. The forms look
 * identical on screen and are canonically equivalent — and are different
 * bytes, so a search for one will not find the other, and a reader typing
 * what they see on the page gets nothing back.
 *
 * So text is composed to NFC as it comes in, and a query is composed the
 * same way before it is used.
 */
const combining = /\p{M}/u;

export const ScriptureText = {
  /** `text` in NFC. */
  normalise(text: string): string {
    return combining.test(text) ? text.normalize('NFC') : text;
  },

  /** Whether `text` is already in NFC, for a build-time check. */
  isNormalised(text: string): boolean {
    return !combining.test(text) || text.normalize('NFC') === text;
  },
};
