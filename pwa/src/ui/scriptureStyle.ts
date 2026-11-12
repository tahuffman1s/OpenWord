import { ReadingFont, type Settings } from '../data/settings';

/**
 * The reader's body type as an inline style, for Scripture shown outside
 * the reader: a verse to learn, a question's prompt. It is the reading
 * face, 17.5 px times the reader's scale, at their line spacing.
 */
export function scriptureBodyStyle(settings: Settings, scale = 1): string {
  const family =
    settings.readingFont === ReadingFont.serif ? 'var(--md-ref-typeface-serif)' : 'var(--md-ref-typeface-brand)';
  const size = 17.5 * settings.fontScale * scale;
  return `font-family:${family};font-size:${size}px;line-height:${settings.lineHeight};font-weight:400`;
}
