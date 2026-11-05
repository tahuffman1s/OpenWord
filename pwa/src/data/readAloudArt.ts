import type { Reference } from '../model/bible';

/** The colours a chapter's cover is drawn in: the reader's own theme, as CSS colours. */
export class ArtColours {
  readonly from: string;
  readonly to: string;
  readonly ink: string;
  readonly accent: string;

  constructor(init: { from: string; to: string; ink: string; accent: string }) {
    this.from = init.from;
    this.to = init.to;
    this.ink = init.ink;
    this.accent = init.accent;
  }

  get key(): string {
    return [this.from, this.to, this.ink, this.accent].map((c) => c.replace(/[^0-9a-z]/gi, '')).join('');
  }
}

type Canvas2D = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;

/** A square canvas, off screen where the browser has one. */
function makeCanvas(size: number): { canvas: OffscreenCanvas | HTMLCanvasElement; ctx: Canvas2D } {
  if (typeof OffscreenCanvas !== 'undefined') {
    const canvas = new OffscreenCanvas(size, size);
    const ctx = canvas.getContext('2d');
    if (ctx !== null) return { canvas, ctx };
  }
  if (typeof document === 'undefined') throw new Error('no canvas to draw on');
  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  if (ctx === null) throw new Error('no 2d context');
  return { canvas, ctx };
}

async function toPng(canvas: OffscreenCanvas | HTMLCanvasElement): Promise<Blob> {
  if ('convertToBlob' in canvas) return canvas.convertToBlob({ type: 'image/png' });
  return new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((blob) => (blob === null ? reject(new Error('no PNG')) : resolve(blob)), 'image/png');
  });
}

/**
 * A square cover for a chapter, drawn on the device: the book's name and
 * the chapter's number on the theme's colours. What the lock screen, a
 * car or a watch shows beside what is being read. Nothing is downloaded.
 */
export async function renderChapterArt(options: {
  book: string;
  chapter: string;
  colours: ArtColours;
  size?: number;
}): Promise<Uint8Array> {
  const size = options.size ?? 600;
  const { colours } = options;
  const { canvas, ctx } = makeCanvas(Math.round(size));
  const gradient = ctx.createLinearGradient(0, 0, size, size);
  gradient.addColorStop(0, colours.from);
  gradient.addColorStop(1, colours.to);
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, size, size);

  const margin = size * 0.09;
  const width = size - margin * 2;
  const family = '"Literata", Georgia, "Times New Roman", serif';

  interface Line {
    lines: string[];
    fontSize: number;
    height: number;
    colour: string;
    weight: number;
    alpha: number;
  }

  /** A paragraph of at most two lines, ended with an ellipsis where it would not fit. */
  const line = (text: string, fontSize: number, colour: string, weight: number, alpha = 1): Line => {
    ctx.font = `${weight} ${fontSize}px ${family}`;
    const fits = (s: string) => ctx.measureText(s).width <= width;
    const lines: string[] = [];
    let current = '';
    let overflow = false;
    for (const word of text.split(' ')) {
      const next = current.length === 0 ? word : `${current} ${word}`;
      if (fits(next) || current.length === 0) {
        current = next;
        continue;
      }
      if (lines.length === 1) {
        // A third line there is no room for: the second ends in an ellipsis.
        overflow = true;
        break;
      }
      lines.push(current);
      current = word;
    }
    lines.push(overflow ? `${current}…` : current);
    for (let i = 0; i < lines.length; i++) {
      let s = lines[i];
      if (fits(s)) continue;
      s = s.replace(/…$/, '');
      while (s.length > 0 && !fits(`${s}…`)) s = s.slice(0, -1);
      lines[i] = `${s}…`;
    }
    return { lines, fontSize, height: fontSize * 1.05 * lines.length, colour, weight, alpha };
  };

  const draw = (paragraph: Line, top: number) => {
    ctx.font = `${paragraph.weight} ${paragraph.fontSize}px ${family}`;
    ctx.fillStyle = paragraph.colour;
    ctx.globalAlpha = paragraph.alpha;
    ctx.textBaseline = 'alphabetic';
    const lineHeight = paragraph.fontSize * 1.05;
    paragraph.lines.forEach((text, i) => {
      // The baseline sits about four fifths of the way down the line box.
      ctx.fillText(text, margin, top + lineHeight * i + paragraph.fontSize * 0.8 + (lineHeight - paragraph.fontSize) / 2);
    });
    ctx.globalAlpha = 1;
  };

  const number = line(options.chapter, size * 0.42, colours.accent, 600);
  const name = line(options.book, size * 0.1, colours.ink, 600);
  const mark = line('OpenWord', size * 0.045, colours.ink, 400, 0.6);

  const bottom = size - margin;
  draw(mark, bottom - mark.height);
  const nameTop = bottom - mark.height - size * 0.03 - name.height;
  draw(name, nameTop);
  draw(number, nameTop - number.height);

  const blob = await toPng(canvas);
  return new Uint8Array(await blob.arrayBuffer());
}

const covers = new Map<string, string>();

/**
 * A chapter's cover as a URL the media session can show, drawn the first
 * time it is wanted and kept for the run of the app after that: a blob
 * URL, since the session wants a URL it can fetch, not bytes.
 *
 * Null wherever it cannot be drawn — a browser without a canvas, or a
 * worker with no document and no OffscreenCanvas: the lock screen then
 * simply has no picture.
 */
export async function chapterArtFile(chapter: Reference, options: { colours: ArtColours }): Promise<string | null> {
  const { colours } = options;
  const key = `${chapter.bookCode}-${chapter.chapter}-${colours.key}`;
  const kept = covers.get(key);
  if (kept !== undefined) return kept;
  try {
    const bytes = await renderChapterArt({
      book: chapter.bookCode === 'PSA' ? 'Psalm' : chapter.bookName,
      chapter: `${chapter.chapter}`,
      colours,
    });
    const url = URL.createObjectURL(new Blob([bytes], { type: 'image/png' }));
    covers.set(key, url);
    return url;
  } catch (error) {
    console.warn(`OpenWord: no cover for ${chapter.label}: ${error}`);
    return null;
  }
}
