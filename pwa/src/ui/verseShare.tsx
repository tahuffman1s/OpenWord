import { useEffect, useRef, useState } from 'preact/hooks';
import { saveBytes } from '../data/saveFile';
import { Button, Chip, Sheet, currentScheme, hexOf, showSnackBar, useOverlay } from './m3';
import { openSheet } from './overlaySettle';
import './verseShare.css';

/** What is handed to the share sheet: words, a subject for them, and files. */
export interface ShareParams {
  text?: string;
  subject?: string;
  files?: File[];
}

/** Puts text on the clipboard, by the old way where the new one is refused. */
export async function copyText(text: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(text);
    return;
  } catch {
    // No permission, or no secure context: the selection trick still works.
  }
  const area = document.createElement('textarea');
  area.value = text;
  area.setAttribute('readonly', '');
  area.style.position = 'fixed';
  area.style.opacity = '0';
  document.body.appendChild(area);
  area.select();
  try {
    document.execCommand('copy');
  } finally {
    area.remove();
  }
}

/**
 * Sends things to the platform's share sheet. A seam, so a test can see
 * what would have been shared without a platform to share it with.
 */
export const VerseSharing = {
  /**
   * The Web Share API where the browser has it. Where it has not — most
   * desktop browsers — the words go to the clipboard and the reader is
   * told so, which is the nearest thing a page can do.
   */
  share: async (params: ShareParams): Promise<void> => {
    const data: ShareData = {};
    if (params.text !== undefined) data.text = params.text;
    if (params.subject !== undefined) data.title = params.subject;
    if (params.files !== undefined) data.files = params.files;
    if (typeof navigator.share === 'function' && (params.files === undefined || VerseSharing.canShareFiles)) {
      try {
        await navigator.share(data);
      } catch (error) {
        // The reader closed the sheet: not a failure.
        if ((error as { name?: string }).name !== 'AbortError') throw error;
      }
      return;
    }
    if (params.text !== undefined) {
      await copyText(params.text);
      showSnackBar(params.subject === undefined ? 'Copied to share' : `Copied ${params.subject} to share`);
      return;
    }
    throw new Error('this browser cannot share');
  },

  /**
   * Saves an image where sharing a file is not possible. A desktop browser
   * has no share sheet for files, so there the image is saved instead.
   */
  save: async (bytes: Uint8Array, fileName: string): Promise<boolean> => {
    await saveBytes(fileName, bytes, 'image/png');
    return true;
  },

  /** Whether this browser can hand a file to a share sheet. */
  get canShareFiles(): boolean {
    if (typeof navigator === 'undefined' || typeof navigator.share !== 'function' || typeof navigator.canShare !== 'function') {
      return false;
    }
    try {
      return navigator.canShare({ files: [new File([new Uint8Array(1)], 'verse.png', { type: 'image/png' })] });
    } catch {
      return false;
    }
  },
};

/** How a verse card is coloured. */
export enum CardStyle {
  paper = 'paper',
  night = 'night',
  colour = 'colour',
  dawn = 'dawn',
}

export const cardStyles: readonly CardStyle[] = [CardStyle.paper, CardStyle.night, CardStyle.colour, CardStyle.dawn];

export const cardStyleLabel: Record<CardStyle, string> = {
  [CardStyle.paper]: 'Paper',
  [CardStyle.night]: 'Night',
  [CardStyle.colour]: 'Colour',
  [CardStyle.dawn]: 'Dawn',
};

/** The colours of the theme the "Colour" card is drawn in, as CSS colours. */
export interface CardScheme {
  primaryContainer: string;
  tertiaryContainer: string;
  onPrimaryContainer: string;
  primary: string;
}

interface CardPalette {
  /** One colour, or the stops of a gradient. */
  background: string[];
  /** Whether a gradient runs corner to corner rather than top to bottom. */
  diagonal: boolean;
  ink: string;
  accent: string;
}

function paletteFor(style: CardStyle, scheme: CardScheme): CardPalette {
  switch (style) {
    case CardStyle.paper:
      return { background: ['#FBF7EF'], diagonal: false, ink: '#2A2622', accent: '#8A6D3B' };
    case CardStyle.night:
      return { background: ['#15181E'], diagonal: false, ink: '#EDEAE4', accent: '#B9C4D6' };
    case CardStyle.colour:
      return {
        background: [scheme.primaryContainer, scheme.tertiaryContainer],
        diagonal: true,
        ink: scheme.onPrimaryContainer,
        accent: scheme.primary,
      };
    case CardStyle.dawn:
      return { background: ['#FFE2C6', '#F6B5A4', '#B98AB3'], diagonal: false, ink: '#2E1F2B', accent: '#5B3452' };
  }
}

/** A `#rrggbb` colour at an opacity. */
function withAlpha(hex: string, alpha: number): string {
  const value = Number.parseInt(hex.replace('#', ''), 16);
  return `rgb(${(value >> 16) & 0xff} ${(value >> 8) & 0xff} ${value & 0xff} / ${alpha})`;
}

type Canvas2D = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;

const cardFace = "Literata, 'Noto Serif', serif";

/** Breaks text into lines no wider than `width`, a word at a time. */
export function wrapLines(text: string, width: number, measure: (line: string) => number): string[] {
  const lines: string[] = [];
  for (const paragraph of text.split('\n')) {
    let line = '';
    for (const word of paragraph.split(/\s+/).filter((part) => part.length > 0)) {
      const candidate = line.length === 0 ? word : `${line} ${word}`;
      if (line.length > 0 && measure(candidate) > width) {
        lines.push(line);
        line = word;
      } else {
        line = candidate;
      }
    }
    lines.push(line);
  }
  return lines;
}

/**
 * A verse set as a picture: the words, where they are from, and the
 * translation, on a card sized for a phone's share sheet.
 *
 * Laid out at a fixed size in logical pixels and drawn at three times
 * that, so the image is 1080 × 1350 — the portrait shape social apps show
 * without cropping — whatever size the preview is on screen.
 */
export const VerseCard = {
  size: { width: 360, height: 450 },
  pixelRatio: 3,

  /**
   * Longer passages are set smaller; past that the words are scaled to
   * fit rather than cut off.
   */
  fontSizeFor(text: string): number {
    const length = text.length;
    if (length <= 120) return 25;
    if (length <= 240) return 21;
    if (length <= 420) return 17.5;
    if (length <= 650) return 15;
    return 13;
  },

  /** The colours of the page's own theme, for the "Colour" card. */
  themeScheme(): CardScheme {
    const scheme = currentScheme();
    return {
      primaryContainer: hexOf(scheme.primaryContainer),
      tertiaryContainer: hexOf(scheme.tertiaryContainer),
      onPrimaryContainer: hexOf(scheme.onPrimaryContainer),
      primary: hexOf(scheme.primary),
    };
  },

  /** Draws the card over the whole of a canvas of `size` × `pixelRatio`. */
  paint(
    canvas: Canvas2D,
    card: { text: string; citation: string; translation: string; style: CardStyle; scheme?: CardScheme },
  ): void {
    const { width, height } = VerseCard.size;
    const palette = paletteFor(card.style, card.scheme ?? VerseCard.themeScheme());

    canvas.save();
    canvas.setTransform(VerseCard.pixelRatio, 0, 0, VerseCard.pixelRatio, 0, 0);
    canvas.textAlign = 'left';
    canvas.textBaseline = 'alphabetic';
    canvas.direction = 'ltr';

    if (palette.background.length === 1) {
      canvas.fillStyle = palette.background[0];
    } else {
      const gradient = palette.diagonal
        ? canvas.createLinearGradient(0, 0, width, height)
        : canvas.createLinearGradient(0, 0, 0, height);
      palette.background.forEach((stop, i) => gradient.addColorStop(i / (palette.background.length - 1), stop));
      canvas.fillStyle = gradient;
    }
    canvas.fillRect(0, 0, width, height);

    const left = 32;
    const top = 36;
    const right = width - 32;
    const bottom = height - 22;
    const column = right - left;

    const font = (size: number, weight = 400) => `${weight} ${size}px ${cardFace}`;

    // Where a line's baseline sits inside a line box of a given height:
    // the face's own ascent and descent, stretched to fill it.
    const baselineIn = (size: number, lineHeight: number): number => {
      const drawingIn = canvas.font;
      canvas.font = font(size);
      const metrics = canvas.measureText('Hg');
      canvas.font = drawingIn;
      const ascent = metrics.fontBoundingBoxAscent ?? size * 0.93;
      const descent = metrics.fontBoundingBoxDescent ?? size * 0.27;
      return (lineHeight * ascent) / (ascent + descent);
    };

    // The opening quotation mark.
    const quoteHeight = 56 * 0.8;
    canvas.font = font(56);
    canvas.fillStyle = withAlpha(palette.accent, 0.55);
    canvas.fillText('“', left, top + baselineIn(56, quoteHeight));

    // From the bottom up: the translation and the app's name, the
    // citation, the rule, and the room that is left for the words.
    const smallLine = 11.5 * 1.2;
    const footTop = bottom - smallLine;
    canvas.font = font(11.5);
    canvas.fillStyle = withAlpha(palette.ink, 0.7);
    canvas.fillText(card.translation, left, footTop + baselineIn(11.5, smallLine), column - 70);

    canvas.font = font(10);
    canvas.fillStyle = withAlpha(palette.ink, 0.45);
    const mark = 'OpenWord';
    const markWidth = canvas.measureText(mark).width + 0.8 * mark.length;
    drawSpaced(canvas, mark, right - markWidth, footTop + (smallLine - 12) / 2 + baselineIn(10, 12), 0.8);

    const citeLine = 15 * 1.2;
    canvas.font = font(15, 700);
    const citeLines = wrapLines(card.citation, column, (line) => canvas.measureText(line).width);
    const citeTop = footTop - 2 - citeLines.length * citeLine;
    canvas.fillStyle = palette.accent;
    citeLines.forEach((line, i) => {
      canvas.font = font(15, 700);
      canvas.fillText(line, left, citeTop + i * citeLine + baselineIn(15, citeLine));
    });

    const ruleTop = citeTop - 10 - 2;
    canvas.fillStyle = palette.accent;
    canvas.fillRect(left, ruleTop, 36, 2);

    // The words: centred in what is left, and scaled down where even the
    // smallest size runs past it.
    const roomTop = top + quoteHeight;
    const room = ruleTop - 16 - roomTop;
    const size = VerseCard.fontSizeFor(card.text);
    const lineHeight = size * 1.45;
    canvas.font = font(size);
    const lines = wrapLines(card.text, column, (line) => canvas.measureText(line).width);
    const textHeight = lines.length * lineHeight;
    const scale = textHeight > room ? room / textHeight : 1;
    const drawnHeight = textHeight * scale;
    const baseline = baselineIn(size, lineHeight);

    canvas.save();
    canvas.translate(left, roomTop + (room - drawnHeight) / 2);
    canvas.scale(scale, scale);
    canvas.font = font(size);
    canvas.fillStyle = palette.ink;
    lines.forEach((line, i) => canvas.fillText(line, 0, i * lineHeight + baseline));
    canvas.restore();

    canvas.restore();
  },

  /** Waits for the card's face, so the picture is not drawn in a stand-in. */
  async fontsReady(): Promise<void> {
    if (typeof document === 'undefined' || document.fonts === undefined) return;
    try {
      await Promise.all([
        document.fonts.load(`400 25px ${cardFace}`),
        document.fonts.load(`700 15px ${cardFace}`),
      ]);
    } catch {
      // Drawn in the fallback face rather than not at all.
    }
  },
};

/** Text with a little air between its letters, which a canvas does not do itself everywhere. */
function drawSpaced(canvas: Canvas2D, text: string, x: number, y: number, spacing: number): void {
  let at = x;
  for (const letter of text) {
    canvas.fillText(letter, at, y);
    at += canvas.measureText(letter).width + spacing;
  }
}

/**
 * Shows the passage as a card, lets the reader pick how it looks, and
 * shares it as an image.
 */
export function showVerseImageSheet(options: { text: string; citation: string; translation: string }): Promise<void> {
  return openSheet(<VerseImageSheet {...options} />, { name: 'verse-image' }).then(() => undefined);
}

export function VerseImageSheet({ text, citation, translation }: { text: string; citation: string; translation: string }) {
  const overlay = useOverlay();
  const canvas = useRef<HTMLCanvasElement>(null);
  const [style, setStyle] = useState(CardStyle.paper);
  const [busy, setBusy] = useState(false);
  const canShareFiles = VerseSharing.canShareFiles;

  /** "John_3-16–18.png": a name any file system takes. */
  const fileName = `${citation.replace(/[:/\\,]+/g, '-').replace(/ /g, '_')}.png`;

  const paint = () => {
    const context = canvas.current?.getContext('2d');
    if (context) VerseCard.paint(context, { text, citation, translation, style });
  };

  useEffect(() => {
    let live = true;
    paint();
    void VerseCard.fontsReady().then(() => {
      if (live) paint();
    });
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [style, text, citation, translation]);

  /** The card as a PNG, at full resolution. */
  const render = async (): Promise<Uint8Array | null> => {
    const element = canvas.current;
    if (element === null) return null;
    await VerseCard.fontsReady();
    paint();
    const blob = await new Promise<Blob | null>((resolve) => element.toBlob(resolve, 'image/png'));
    return blob === null ? null : new Uint8Array(await blob.arrayBuffer());
  };

  const share = async () => {
    setBusy(true);
    try {
      const bytes = await render();
      if (bytes === null) return;
      if (canShareFiles) {
        await VerseSharing.share({
          files: [new File([bytes.slice()], fileName, { type: 'image/png' })],
          subject: citation,
        });
        overlay.close();
      } else {
        const saved = await VerseSharing.save(bytes, fileName);
        overlay.close();
        if (saved) showSnackBar(`Saved ${citation} as an image`);
      }
    } catch (error) {
      showSnackBar(`Could not share the image: ${error}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet class="ow-verse-image">
      <div class="m3-title-medium">Share {citation} as an image</div>
      <div class="ow-verse-image__preview">
        <canvas
          ref={canvas}
          class="ow-verse-image__card"
          width={VerseCard.size.width * VerseCard.pixelRatio}
          height={VerseCard.size.height * VerseCard.pixelRatio}
          role="img"
          aria-label={`${text} — ${citation}`}
        />
      </div>
      <div class="ow-verse-image__styles">
        {cardStyles.map((candidate) => (
          <Chip variant="choice" label={cardStyleLabel[candidate]} selected={style === candidate} onClick={() => setStyle(candidate)} />
        ))}
      </div>
      <Button class="ow-verse-image__share" icon={canShareFiles ? 'ios_share' : 'save_alt'} disabled={busy} onClick={() => void share()}>
        {canShareFiles ? 'Share image' : 'Save image'}
      </Button>
    </Sheet>
  );
}
