import { Component, type ComponentChildren, type FunctionComponent, type JSX, type VNode } from 'preact';
import { useRef } from 'preact/hooks';
import type { ReferenceMatcher } from '../../data/referenceSearch';
import { ReadingFont, type Settings } from '../../data/settings';
import { type Block, BlockAlign, BlockStyle, Markup, parseIntStrict, type Reference, type VerseSegment } from '../../model/bible';
import { Icon, currentScheme, redLetter } from '../m3';
import './scriptureText.css';

/**
 * Resolved text styles for one chapter of Scripture.
 *
 * On the web the sizes and faces live in CSS (`scriptureText.css`), driven
 * by three variables this writes to `<html>` — `--ow-reading-font`,
 * `--ow-reading-scale` and `--ow-reading-line-height` — so what is left
 * here is what a block has to decide by: which marks to draw at all.
 */
export class ScriptureStyle {
  readonly fontScale: number;
  readonly lineHeight: number;
  readonly readingFont: ReadingFont;

  /** The colour of the words of Jesus, for the brightness on the page. */
  readonly wjColor: string;
  readonly redLetter: boolean;
  readonly showFootnotes: boolean;
  readonly showVerseNumbers: boolean;
  readonly paragraphLayout: boolean;

  constructor(init: {
    fontScale: number;
    lineHeight: number;
    readingFont: ReadingFont;
    wjColor: string;
    redLetter: boolean;
    showFootnotes: boolean;
    showVerseNumbers: boolean;
    paragraphLayout: boolean;
  }) {
    this.fontScale = init.fontScale;
    this.lineHeight = init.lineHeight;
    this.readingFont = init.readingFont;
    this.wjColor = init.wjColor;
    this.redLetter = init.redLetter;
    this.showFootnotes = init.showFootnotes;
    this.showVerseNumbers = init.showVerseNumbers;
    this.paragraphLayout = init.paragraphLayout;
  }

  /**
   * The style the settings ask for. Also writes the reading typeface,
   * scale and line height to the page's CSS variables, which is where the
   * text reads them from.
   */
  static of(settings: Settings): ScriptureStyle {
    const style = new ScriptureStyle({
      fontScale: settings.fontScale,
      lineHeight: settings.lineHeight,
      readingFont: settings.readingFont,
      wjColor: redLetter(currentScheme().brightness),
      redLetter: settings.redLetter,
      showFootnotes: settings.showFootnotes,
      showVerseNumbers: settings.showVerseNumbers,
      paragraphLayout: settings.paragraphLayout,
    });
    style.apply();
    return style;
  }

  /** Writes the reading variables to `<html>`. */
  apply(root: HTMLElement | null = typeof document === 'undefined' ? null : document.documentElement): void {
    if (root === null) return;
    const set = (name: string, value: string) => {
      if (root.style.getPropertyValue(name) !== value) root.style.setProperty(name, value);
    };
    // Literata is bundled; "Sans" follows the platform's own UI font.
    // Hebrew and Greek appear in a handful of footnotes; the fallbacks in
    // the stylesheet let the platform supply those glyphs.
    set('--ow-reading-font', this.readingFont === ReadingFont.serif ? 'Literata' : 'var(--md-ref-typeface-brand)');
    set('--ow-reading-scale', `${this.fontScale}`);
    set('--ow-reading-line-height', `${this.lineHeight}`);
  }

  /** The body size in pixels, as the Dart's `body.fontSize`. */
  get bodySize(): number {
    return 17.5 * this.fontScale;
  }

  get blankHeight(): number {
    return this.bodySize * 0.7;
  }

  /** Everything a block's drawing depends on, for telling two styles apart. */
  get key(): string {
    return [
      this.fontScale,
      this.lineHeight,
      this.readingFont,
      this.wjColor,
      this.redLetter,
      this.showFootnotes,
      this.showVerseNumbers,
      this.paragraphLayout,
    ].join('|');
  }
}

/** One translucent colour as a background layer. */
export function tintLayer(color: string): string {
  return `linear-gradient(${color}, ${color})`;
}

/**
 * A colour laid over whatever tint a verse already had — Flutter's
 * `Color.alphaBlend(over, under)`, as stacked background layers.
 */
export function tintOver(over: string, under: string | undefined): string {
  return under === undefined ? tintLayer(over) : `${tintLayer(over)}, ${under}`;
}

/** How long a finger rests on a verse before it is a long press. */
const longPressTimeout = 500;

/** How far a finger may wander and still be pressing rather than scrolling. */
const pressSlop = 10;

/** The listeners `useVerseGestures` answers, to spread onto an element. */
export interface VerseGestures {
  onPointerDown: (event: PointerEvent) => void;
  onPointerMove: (event: PointerEvent) => void;
  onPointerUp: () => void;
  onPointerCancel: () => void;
  onPointerLeave: () => void;
  onContextMenu: (event: Event) => void;
  onClick: (event: MouseEvent) => void;
}

/**
 * A tap that is also a long press, for everything inside one element.
 *
 * A verse wants both: a tap opens it, holding it starts a selection.
 * Lifting before the long-press timeout is a tap, holding past it is a
 * long press, and moving off is a scroll. The verse is found from the
 * `data-verse` attribute of whatever was touched, and a footnote marker
 * from `data-note`, so one set of listeners serves a whole block.
 */
export function useVerseGestures(handlers: {
  onVerseTap?: (verse: number) => void;
  onVerseLongPress?: (verse: number) => void;
  onNoteTap?: (index: number) => void;
}): VerseGestures {
  const latest = useRef(handlers);
  latest.current = handlers;
  const state = useRef({ timer: 0 as ReturnType<typeof setTimeout> | 0, x: 0, y: 0, fired: false });
  const stable = useRef<VerseGestures | null>(null);
  if (stable.current === null) {
    const s = state.current;
    const cancel = () => {
      if (s.timer !== 0) clearTimeout(s.timer);
      s.timer = 0;
    };
    const verseOf = (target: EventTarget | null): number | null => {
      const el = target instanceof Element ? target.closest('[data-verse]') : null;
      const verse = el === null ? null : parseIntStrict(el.getAttribute('data-verse'));
      return verse !== null && verse > 0 ? verse : null;
    };
    stable.current = {
      onPointerDown: (event: PointerEvent) => {
        cancel();
        s.fired = false;
        if (event.pointerType === 'mouse' && event.button !== 0) return;
        const verse = verseOf(event.target);
        if (verse === null || latest.current.onVerseLongPress === undefined) return;
        s.x = event.clientX;
        s.y = event.clientY;
        s.timer = setTimeout(() => {
          s.timer = 0;
          s.fired = true;
          latest.current.onVerseLongPress?.(verse);
        }, longPressTimeout);
      },
      onPointerMove: (event: PointerEvent) => {
        if (s.timer !== 0 && Math.hypot(event.clientX - s.x, event.clientY - s.y) > pressSlop) cancel();
      },
      onPointerUp: cancel,
      onPointerCancel: cancel,
      onPointerLeave: cancel,
      onContextMenu: (event: Event) => {
        // Holding a verse is ours; the browser's own menu would cover it.
        if (s.fired || s.timer !== 0) event.preventDefault();
      },
      onClick: (event: MouseEvent) => {
        if (s.fired) {
          // The lift that ends a long press is not a tap as well.
          s.fired = false;
          event.preventDefault();
          return;
        }
        const note = event.target instanceof Element ? event.target.closest('[data-note]') : null;
        if (note !== null) {
          const index = parseIntStrict(note.getAttribute('data-note'));
          if (index !== null) latest.current.onNoteTap?.(index);
          return;
        }
        const verse = verseOf(event.target);
        if (verse !== null) latest.current.onVerseTap?.(verse);
      },
    };
  }
  return stable.current;
}

export interface ScriptureBlockProps {
  block: Block;
  style: ScriptureStyle;

  /** Called when any part of a verse is tapped. */
  onVerseTap: (verse: number) => void;

  /**
   * Called when any part of a verse is held: how a selection of several
   * verses begins.
   */
  onVerseLongPress?: (verse: number) => void;

  /** Called with the chapter-level note index behind a footnote marker. */
  onNoteTap: (index: number) => void;

  /**
   * How a verse's number is printed, where the translation prints
   * something other than the number — "1-2" for a bridged verse. Left
   * out, a verse is printed as its number.
   */
  labelFor?: (verse: number) => string;

  /**
   * Background tints for highlighted verses, each a CSS background-image
   * (see `tintLayer`).
   */
  highlights: ReadonlyMap<number, string>;

  /** Verses carrying a bookmark or a note, flagged in the margin. */
  flagged: ReadonlySet<number>;

  /**
   * True for the first paragraph of a chapter or section: a paragraph that
   * opens a passage is set flush, as a printed Bible does.
   */
  isFirst: boolean;

  /** Finds citations in parallel-passage lines so they can be tapped. */
  matcher?: ReferenceMatcher | null;

  onReferenceTap?: (reference: Reference) => void;
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}

function alignOf(align: BlockAlign): string {
  switch (align) {
    case BlockAlign.center:
      return 'center';
    case BlockAlign.end:
      return 'end';
    default:
      return 'start';
  }
}

function plain(block: Block): string {
  return block.segments
    .map((s) => Markup.strip(s.text))
    .join(' ')
    .trim();
}

/**
 * Lays out a single `Block` — a prose paragraph, a poetry line, a heading or
 * a stanza break — with verse numbers set as superscripts.
 */
function ScriptureBlockImpl(props: ScriptureBlockProps) {
  const { block, style } = props;
  const gestures = useVerseGestures(props);
  const label = (verse: number) => props.labelFor?.(verse) ?? `${verse}`;
  const vars = { '--ow-wj': style.wjColor } as unknown as JSX.CSSProperties;

  switch (block.style) {
    case BlockStyle.blank:
      return <div class="ow-sb ow-sb-blank" />;
    case BlockStyle.heading: {
      // A division of the book stands further from the text and larger
      // than the sections under it; a third level smaller again. "BOOK 1"
      // of the Psalms should not read like the heading of a passage.
      const level = block.level;
      return (
        <div
          class={`ow-sb ow-sb-heading${level === 1 ? ' ow-sb-heading--1' : level === 3 ? ' ow-sb-heading--3' : ''}`}
          style={{ textAlign: level === 1 ? 'center' : alignOf(block.align) }}
        >
          {plain(block)}
        </div>
      );
    }
    case BlockStyle.acrostic:
      // The letter an acrostic stanza runs on — Psalm 119's ALEPH and
      // the twenty-one after it. Set small, apart and centred, which is
      // how a printed Psalter sets them.
      return <div class="ow-sb ow-sb-acrostic">{plain(block).toUpperCase()}</div>;
    case BlockStyle.speaker:
      // Who is speaking, as the Song of Songs is set.
      return (
        <div class="ow-sb ow-sb-speaker" style={{ textAlign: alignOf(block.align) }}>
          {plain(block)}
        </div>
      );
    case BlockStyle.descriptiveTitle:
      return (
        <div class="ow-sb ow-sb-title" style={{ textAlign: alignOf(block.align) }}>
          {plain(block)}
        </div>
      );
    case BlockStyle.listItem:
      return (
        <div
          class="ow-sb ow-sb-list"
          style={{ ...vars, paddingInlineStart: `${12 + clamp(block.indent, 0, 4) * 14}px`, textAlign: alignOf(block.align) }}
          {...gestures}
        >
          {richText(props, label, false, false)}
        </div>
      );
    case BlockStyle.tableRow:
      return tableRow(props, label);
    case BlockStyle.reference:
      return (
        <div class="ow-sb ow-sb-reference">
          <LinkedText text={plain(block)} matcher={props.matcher} onTap={props.onReferenceTap} />
        </div>
      );
    case BlockStyle.poetry:
      return poetryLine(props, label, gestures, vars);
    case BlockStyle.paragraph:
    default: {
      const indentFirstLine =
        style.paragraphLayout &&
        block.indentFirstLine &&
        // A paragraph carried on from before a chapter break is
        // not the start of anything, whatever its position.
        !block.continuesParagraph &&
        !props.isFirst;
      return (
        <div
          class={`ow-sb ow-sb-paragraph${indentFirstLine ? ' ow-sb-paragraph--indent' : ''}`}
          style={{ ...vars, paddingInlineStart: `${clamp(block.indent, 0, 4) * 16}px`, textAlign: alignOf(block.align) }}
          {...gestures}
        >
          {richText(props, label, indentFirstLine, false)}
        </div>
      );
    }
  }
}

/**
 * A row of a table, its cells laid out across the column.
 *
 * Genealogies and censuses are tables in print, and used to come out of
 * here as runs of text with three spaces where a cell boundary was.
 */
function tableRow(props: ScriptureBlockProps, label: (verse: number) => string): VNode {
  const { block } = props;
  const cells = block.cells;
  const number = block.segments.find((segment) => segment.startsVerse)?.verse;
  const numbered = number !== undefined && block.segments[0].startsVerse;
  return (
    <div class="ow-sb ow-sb-table" data-vs={number !== undefined && number > 0 ? number : undefined}>
      {/* The gutter is there on every row, numbered or not, or the
          columns of a table would not line up under each other. */}
      <span class="ow-sb-table__gutter">{numbered ? <span class="ow-vn ow-vn--plain">{label(number)}</span> : null}</span>
      {cells.map((cell) => (
        <span class="ow-sb-table__cell">{cell}</span>
      ))}
    </div>
  );
}

/**
 * A line of verse. The verse number hangs in the margin so that a line too
 * long for the screen wraps back to the line's own indent, the way a
 * printed Bible sets poetry.
 */
function poetryLine(
  props: ScriptureBlockProps,
  label: (verse: number) => string,
  gestures: VerseGestures,
  vars: JSX.CSSProperties,
): VNode {
  const { block, style } = props;
  const first = block.segments[0];
  const hanging = first !== undefined && first.startsVerse && first.verse > 0 && style.showVerseNumbers;
  return (
    <div
      class={`ow-sb ow-sb-poetry${hanging ? ' ow-sb-poetry--hanging' : ''}`}
      style={{ ...vars, paddingInlineStart: `${8 + (clamp(block.indent, 1, 4) - 1) * 18}px` }}
      {...gestures}
    >
      <div class="ow-sb-poetry__stack">
        {/* Full width on purpose: the line is given the whole column, or
            centring it within its own width would do nothing. */}
        <div class="ow-sb-poetry__line" style={{ textAlign: alignOf(block.align) }}>
          {richText(props, label, false, hanging)}
        </div>
        {hanging && (
          // Sits on the first line, allowing for its half-leading.
          <span class="ow-sb-poetry__number" data-verse={first.verse}>
            <span class="ow-vn ow-vn--plain">{label(first.verse)}</span>
          </span>
        )}
      </div>
    </div>
  );
}

function richText(
  props: ScriptureBlockProps,
  label: (verse: number) => string,
  _indentFirstLine: boolean,
  skipFirstNumber: boolean,
): ComponentChildren {
  const { block, style } = props;
  const out: ComponentChildren[] = [];
  for (let i = 0; i < block.segments.length; i++) {
    if (i > 0) {
      // Paragraph layout flows verses together; the alternative puts each
      // verse on its own line.
      out.push(style.paragraphLayout ? ' ' : <br />);
    }
    out.push(segmentSpans(props, block.segments[i], label, !(i === 0 && skipFirstNumber)));
  }
  return out;
}

function segmentSpans(
  props: ScriptureBlockProps,
  segment: VerseSegment,
  label: (verse: number) => string,
  includeNumber: boolean,
): VNode {
  const { style } = props;
  const spans: ComponentChildren[] = [];
  const highlight = props.highlights.get(segment.verse);
  const tint = highlight === undefined ? undefined : { backgroundImage: highlight };

  if (segment.startsVerse && props.flagged.has(segment.verse)) {
    spans.push(<Icon name="bookmark" class="ow-flag" />);
  }

  if (includeNumber && segment.startsVerse && segment.verse > 0 && style.showVerseNumbers) {
    spans.push(<span class="ow-vn">{label(segment.verse)}</span>);
  }

  let inWords = false;
  let inAdded = false;
  let inSelah = false;
  let inDivine = false;
  let buffer = '';

  const flush = () => {
    if (buffer.length === 0) return;
    // Small capitals, the way every printed Bible sets the divine name
    // apart from "Lord" as a title: upper-cased and set a size smaller,
    // which is what a press did with a smaller sort.
    const classes =
      'ow-run' +
      (inWords && style.redLetter ? ' ow-run--wj' : '') +
      (inAdded || inSelah ? ' ow-run--italic' : '') +
      (inDivine ? ' ow-run--divine' : '');
    spans.push(
      <span class={classes} style={tint}>
        {inDivine ? buffer.toUpperCase() : buffer}
      </span>,
    );
    buffer = '';
  };

  const text = segment.text;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    switch (char) {
      case Markup.wjStart:
        flush();
        inWords = true;
        break;
      case Markup.wjEnd:
        flush();
        inWords = false;
        break;
      case Markup.addStart:
        flush();
        inAdded = true;
        break;
      case Markup.addEnd:
        flush();
        inAdded = false;
        break;
      case Markup.selahStart:
        flush();
        inSelah = true;
        break;
      case Markup.selahEnd:
        flush();
        inSelah = false;
        break;
      case Markup.divineStart:
        flush();
        inDivine = true;
        break;
      case Markup.divineEnd:
        flush();
        inDivine = false;
        break;
      case Markup.quotationStart:
      case Markup.quotationEnd:
        // Consumed, and nothing done with it. The point of carrying a
        // quotation from Scripture as its own thing is that it is no
        // longer stored as a translator's addition and set in italics,
        // which said the opposite of what it means. Most printed Bibles
        // set it like the text around it, and so does this.
        break;
      case Markup.cell:
        // A row's cells are laid out by the table, not here; in a run of
        // text the separator reads as a gap.
        buffer += '  ';
        break;
      case Markup.noteStart: {
        flush();
        const end = text.indexOf(Markup.noteEnd, i + 1);
        if (end < 0) break;
        const index = parseIntStrict(text.substring(i + 1, end));
        i = end;
        if (index !== null && style.showFootnotes) {
          spans.push(<span class="ow-note" data-note={index} role="button" aria-label="Footnote" />);
        }
        break;
      }
      default:
        buffer += char;
    }
  }
  flush();

  const verse = segment.verse > 0 ? segment.verse : undefined;
  return (
    <span class="ow-verse" data-verse={verse} data-vs={segment.startsVerse ? verse : undefined}>
      {spans}
    </span>
  );
}

/** Whether two sets of props draw the same block. */
function sameBlock(a: ScriptureBlockProps, b: ScriptureBlockProps): boolean {
  if (
    a.block !== b.block ||
    a.isFirst !== b.isFirst ||
    a.matcher !== b.matcher ||
    a.labelFor !== b.labelFor ||
    a.onVerseTap !== b.onVerseTap ||
    a.onVerseLongPress !== b.onVerseLongPress ||
    a.onNoteTap !== b.onNoteTap ||
    a.onReferenceTap !== b.onReferenceTap ||
    (a.style !== b.style && a.style.key !== b.style.key)
  ) {
    return false;
  }
  if (a.highlights === b.highlights && a.flagged === b.flagged) return true;
  for (const segment of a.block.segments) {
    if (a.highlights.get(segment.verse) !== b.highlights.get(segment.verse)) return false;
    if (a.flagged.has(segment.verse) !== b.flagged.has(segment.verse)) return false;
  }
  return true;
}

/**
 * Only the blocks whose own verses changed are drawn again. A chapter is a
 * few hundred of these, and a highlight or the verse being read aloud
 * touches one or two.
 */
function memo<P extends object>(Inner: FunctionComponent<P>, same: (a: P, b: P) => boolean): FunctionComponent<P> {
  class Memo extends Component<P> {
    override shouldComponentUpdate(next: P): boolean {
      return !same(this.props as P, next);
    }
    override render() {
      return <Inner {...(this.props as P)} />;
    }
  }
  return Memo as unknown as FunctionComponent<P>;
}

export const ScriptureBlock = memo(ScriptureBlockImpl, sameBlock);

export interface LinkedTextProps {
  text: string;
  /** Classes for the text: a typescale class, where the caller has one. */
  class?: string;
  matcher?: ReferenceMatcher | null;
  onTap?: (reference: Reference) => void;
}

/**
 * Prose with any Scripture citations in it turned into links.
 *
 * Used for parallel-passage lines and footnotes, where a translation cites
 * other passages in plain text.
 */
export function LinkedText({ text, class: cls, matcher, onTap }: LinkedTextProps) {
  if (matcher == null || onTap === undefined) return <span class={cls}>{text}</span>;
  const matches = matcher.findAll(text);
  if (matches.length === 0) return <span class={cls}>{text}</span>;

  const spans: ComponentChildren[] = [];
  let cursor = 0;
  for (const match of matches) {
    if (match.start > cursor) spans.push(text.substring(cursor, match.start));
    spans.push(
      <a
        class="ow-linked"
        role="link"
        tabIndex={0}
        onClick={(event) => {
          event.stopPropagation();
          onTap(match.reference);
        }}
        onKeyDown={(event) => {
          if (event.key === 'Enter') onTap(match.reference);
        }}
      >
        {text.substring(match.start, match.end)}
      </a>,
    );
    cursor = match.end;
  }
  if (cursor < text.length) spans.push(text.substring(cursor));
  return <span class={cls}>{spans}</span>;
}
