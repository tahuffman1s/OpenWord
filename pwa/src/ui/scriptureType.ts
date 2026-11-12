import './scriptureType.css';

/**
 * The face bundled for what the reading face does not cover: the Hebrew
 * block, points and cantillation marks included, and the thirteen modifier
 * letters Strong's transliterates with — ʻayin, ʼaleph, the superscript
 * vowels, the dotted t.
 */
export const scriptureSerif = 'ScriptureSerif';

/**
 * Dresses a style for text that may hold Hebrew or a transliteration.
 *
 * A line of Strong's is rarely one alphabet: a headword in Hebrew sits
 * beside how it is said in Latin, and the transliteration itself reaches
 * for marks no reading face carries. Naming both faces, in the order that
 * suits the text at hand, is what keeps such a line whole instead of
 * half of it coming out as empty boxes.
 *
 * On the web a style is a class: this answers the class names to add to
 * whatever typescale class the text already has.
 */
export function scriptureStyle(options: { hebrew: boolean }): string {
  return options.hebrew ? 'ow-scripture-type ow-scripture-type--hebrew' : 'ow-scripture-type';
}
