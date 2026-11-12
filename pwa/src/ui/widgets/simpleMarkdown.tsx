import type { ComponentChildren } from 'preact';
import './simpleMarkdown.css';

export type MarkdownBlockKind = 'heading' | 'paragraph' | 'bullet' | 'numbered' | 'rule';

export interface MarkdownBlock {
  kind: MarkdownBlockKind;
  text: string;
  level: number;
  marker: string | null;
}

/** A run of text set one way: plain, bold, italic or both. */
export interface MarkdownSpan {
  text: string;
  bold: boolean;
  italic: boolean;
}

function block(kind: MarkdownBlockKind, text: string, options: { level?: number; marker?: string | null } = {}): MarkdownBlock {
  return { kind, text, level: options.level ?? 1, marker: options.marker ?? null };
}

/**
 * Splits the source into blocks. Runs of text become one paragraph, a line
 * of `=` or `-` under text turns it into a heading.
 */
export function parseMarkdown(source: string): MarkdownBlock[] {
  const lines = source.replaceAll('\r\n', '\n').split('\n');
  const blocks: MarkdownBlock[] = [];
  const paragraph: string[] = [];

  const flush = (): void => {
    if (paragraph.length === 0) return;
    blocks.push(block('paragraph', paragraph.join(' ').trim()));
    paragraph.length = 0;
  };

  for (const raw of lines) {
    const trimmed = raw.trim();

    if (trimmed.length === 0) {
      flush();
      continue;
    }

    // An underline turns the paragraph above it into a heading.
    if (/^=+$/.test(trimmed) && paragraph.length > 0) {
      blocks.push(block('heading', paragraph.join(' ').trim(), { level: 1 }));
      paragraph.length = 0;
      continue;
    }
    if (/^-{2,}$/.test(trimmed)) {
      if (paragraph.length > 0) {
        blocks.push(block('heading', paragraph.join(' ').trim(), { level: 2 }));
        paragraph.length = 0;
      } else {
        blocks.push(block('rule', ''));
      }
      continue;
    }

    const atx = /^(#{1,6})\s+(.*)$/.exec(trimmed);
    if (atx !== null) {
      flush();
      blocks.push(block('heading', atx[2].trim(), { level: atx[1].length }));
      continue;
    }

    const bullet = /^[*\-+]\s+(.*)$/.exec(trimmed);
    if (bullet !== null) {
      flush();
      blocks.push(block('bullet', bullet[1].trim()));
      continue;
    }

    const numbered = /^(\d+)[.)]\s+(.*)$/.exec(trimmed);
    if (numbered !== null) {
      flush();
      blocks.push(block('numbered', numbered[2].trim(), { marker: numbered[1] }));
      continue;
    }

    paragraph.push(trimmed);
  }
  flush();
  return blocks;
}

/** Handles `**bold**`, `*italic*` and backslash escapes. */
export function parseInline(text: string): MarkdownSpan[] {
  const spans: MarkdownSpan[] = [];
  let buffer = '';
  let bold = false;
  let italic = false;

  const flush = (): void => {
    if (buffer.length === 0) return;
    spans.push({ text: buffer, bold, italic });
    buffer = '';
  };

  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === '\\' && i + 1 < text.length) {
      buffer += text[i + 1];
      i++;
      continue;
    }
    if (char === '*') {
      const double = i + 1 < text.length && text[i + 1] === '*';
      flush();
      if (double) {
        bold = !bold;
        i++;
      } else {
        italic = !italic;
      }
      continue;
    }
    buffer += char;
  }
  flush();
  return spans;
}

function Inline({ text }: { text: string }) {
  return (
    <>
      {parseInline(text).map((span) => {
        let node: ComponentChildren = span.text;
        if (span.italic) node = <em>{node}</em>;
        if (span.bold) node = <strong>{node}</strong>;
        return node;
      })}
    </>
  );
}

/**
 * Renders the small slice of Markdown the bundled book introductions use:
 * headings (both `## atx` and the underlined kind), paragraphs, bullet and
 * numbered lists, bold, italic and backslash escapes. There are no links,
 * images, tables or HTML in the source, so none are handled — a full
 * Markdown package would be a dependency earning its keep on nothing.
 */
export function SimpleMarkdown({
  source,
  baseStyle,
  class: cls,
  style,
}: {
  source: string;

  /** The typescale class the prose is set in — `m3-body-large`, say — where not body-medium. */
  baseStyle?: string;
  class?: string;
  style?: string;
}) {
  const blocks = parseMarkdown(source);
  return (
    <div class={`ow-markdown ${baseStyle ?? 'm3-body-medium'}${cls ? ` ${cls}` : ''}`} style={style}>
      {blocks.map((b, index) => {
        switch (b.kind) {
          case 'heading':
            return (
              <div
                role="heading"
                aria-level={Math.min(b.level + 1, 6)}
                class={`ow-markdown__heading${b.level <= 1 ? ' ow-markdown__heading--major' : ''}${index === 0 ? ' ow-markdown__heading--first' : ''}`}
              >
                <Inline text={b.text} />
              </div>
            );
          case 'paragraph':
            return (
              <p class="ow-markdown__paragraph">
                <Inline text={b.text} />
              </p>
            );
          case 'bullet':
          case 'numbered':
            return (
              <div class="ow-markdown__item">
                <span class="ow-markdown__marker">{b.kind === 'bullet' ? '•' : `${b.marker}.`}</span>
                <span class="ow-markdown__item-text">
                  <Inline text={b.text} />
                </span>
              </div>
            );
          case 'rule':
            return <hr class="m3-divider ow-markdown__rule" />;
        }
      })}
    </div>
  );
}
