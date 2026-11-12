import type { ComponentChildren, JSX } from 'preact';
import { markedRuns, runPieces } from '../../model/verseCompare';
import './scriptureText.css';

/**
 * One verse set as Scripture outside the chapter's own layout — beside
 * another translation, or in a sheet — with the marks the page gives it:
 * the words of Jesus in red, the translators' additions in italics, the
 * divine name in small capitals.
 *
 * `differing` marks the words another translation does not share (see
 * `differingWords`), by their place among the verse's words.
 */
export function MarkedVerse({
  marked,
  redLetter,
  wjColor,
  differing,
}: {
  /** The verse as `Chapter.verseMarked` gives it. */
  marked: string;
  redLetter: boolean;
  /** The red for the page's brightness; see `redLetter` in the theme. */
  wjColor: string;
  differing?: ReadonlySet<number>;
}) {
  const runs = markedRuns(marked);
  const pieces = differing !== undefined && differing.size > 0 ? runPieces(runs) : null;
  const vars = { '--ow-wj': wjColor } as unknown as JSX.CSSProperties;
  return (
    <span style={vars}>
      {runs.map((run, i) => {
        const classes =
          'ow-run' +
          (run.wj && redLetter ? ' ow-run--wj' : '') +
          (run.italic ? ' ow-run--italic' : '') +
          (run.divine ? ' ow-run--divine' : '');
        const set = (text: string) => (run.divine ? text.toUpperCase() : text);
        let body: ComponentChildren = set(run.text);
        if (pieces !== null) {
          body = pieces[i].map((piece) =>
            piece.word >= 0 && differing!.has(piece.word) ? <mark class="ow-diff">{set(piece.text)}</mark> : set(piece.text),
          );
        }
        return <span class={classes}>{body}</span>;
      })}
    </span>
  );
}
