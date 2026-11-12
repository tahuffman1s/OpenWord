import { describe, expect, it } from 'vitest';
import { parseInline, parseMarkdown, type MarkdownBlock } from '../src/ui/widgets/simpleMarkdown';

/**
 * The plain text of everything a source renders as, in order: what the
 * Dart test reads off the screen's RichTexts. A list item is its marker,
 * then its text; a rule has no text at all.
 */
function rendered(source: string): string[] {
  const out: string[] = [];
  for (const block of parseMarkdown(source)) {
    if (block.kind === 'rule') continue;
    if (block.kind === 'bullet') out.push('•');
    if (block.kind === 'numbered') out.push(`${block.marker}.`);
    out.push(
      parseInline(block.text)
        .map((span) => span.text)
        .join(''),
    );
  }
  return out;
}

const kinds = (blocks: MarkdownBlock[]): string[] => blocks.map((block) => block.kind);

describe('SimpleMarkdown', () => {
  it('joins wrapped lines into one paragraph', () => {
    expect(rendered('Genesis is the book\nof beginnings.\n\nIt tells how.')).toEqual(['Genesis is the book of beginnings.', 'It tells how.']);
  });

  it('reads underlined headings, as the source writes them', () => {
    const source = 'Setting\n=======\n\nText.\n\nAuthor\n------\n\nMore.';
    expect(rendered(source)).toEqual(['Setting', 'Text.', 'Author', 'More.']);
    expect(kinds(parseMarkdown(source))).toEqual(['heading', 'paragraph', 'heading', 'paragraph']);
  });

  it('a heading is set apart from the text around it', () => {
    const [heading, body] = parseMarkdown('Setting\n=======\n\nPlain text.');
    // The component sets a heading in the primary colour, bold, a size up;
    // here, that it is a heading at all and of which rank.
    expect(heading.kind).toBe('heading');
    expect(heading.level).toBe(1);
    expect(body.kind).toBe('paragraph');
    expect(parseMarkdown('Author\n------\n\nMore.')[0].level).toBe(2);
  });

  it('reads hash headings too', () => {
    expect(rendered('## Summary\n\nText.')).toEqual(['Summary', 'Text.']);
    expect(parseMarkdown('## Summary\n\nText.')[0]).toMatchObject({ kind: 'heading', level: 2 });
  });

  it('a rule on its own is not a heading', () => {
    const source = 'Text.\n\n-----\n\nMore.';
    expect(rendered(source)).toEqual(['Text.', 'More.']);
    expect(kinds(parseMarkdown(source)).filter((kind) => kind === 'rule')).toHaveLength(1);
  });

  it('renders bullets and numbered items', () => {
    expect(rendered('* First\n* Second\n\n1. One\n2. Two')).toEqual(['•', 'First', '•', 'Second', '1.', 'One', '2.', 'Two']);
  });

  it('emphasises bold and italic without showing the markers', () => {
    const source = 'A **bold** and *italic* line.';
    expect(rendered(source)).toEqual(['A bold and italic line.']);
    const spans = parseInline(source);
    expect(spans.find((span) => span.text === 'bold')).toMatchObject({ bold: true, italic: false });
    expect(spans.find((span) => span.text === 'italic')).toMatchObject({ bold: false, italic: true });
    expect(spans.find((span) => span.text === 'A ')).toMatchObject({ bold: false, italic: false });
  });

  it('unescapes backslash escapes, which the source is full of', () => {
    expect(rendered('CC BY\\-SA 4\\.0 and non\\-Israelite')).toEqual(['CC BY-SA 4.0 and non-Israelite']);
    // An escaped star is a star, not the start of emphasis.
    expect(parseInline('2 \\* 3')).toEqual([{ text: '2 * 3', bold: false, italic: false }]);
  });

  it('renders nothing for empty input', () => {
    expect(rendered('   \n\n  ')).toEqual([]);
  });

  it('reads Windows line endings as it reads any other', () => {
    expect(rendered('One\r\ntwo.\r\n\r\nThree.')).toEqual(['One two.', 'Three.']);
  });
});
