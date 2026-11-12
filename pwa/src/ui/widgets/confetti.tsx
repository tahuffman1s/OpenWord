import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import { seededRandom, type RandomSource } from '../../model/random';
import { currentScheme, rgba } from '../m3/theme';
import './confetti.css';

/** One piece of the shower. */
interface Piece {
  /** Where it starts across the width, 0 to 1. */
  x: number;

  /** How far it drifts sideways on the way down, as a share of the width. */
  drift: number;

  /** How far into the shower it sets off, 0 to 0.4. */
  delay: number;
  spin: number;
  size: number;
  colour: number;
}

function randomPiece(random: RandomSource, index: number): Piece {
  return {
    x: random(),
    drift: (random() - 0.5) * 0.3,
    delay: random() * 0.4,
    spin: (random() - 0.5) * 12,
    size: 6 + random() * 6,
    colour: index,
  };
}

/** The pieces a shower is made of: the same every time, drawn from one fixed seed. */
export function confettiPieces(count: number): Piece[] {
  const random = seededRandom(7);
  const pieces: Piece[] = [];
  for (let i = 0; i < count; i++) pieces.push(randomPiece(random, i));
  return pieces;
}

/** Paints the shower at `t`, 0 to 1, onto a canvas of `width` by `height` CSS pixels. */
export function paintConfetti(
  context: CanvasRenderingContext2D,
  pieces: readonly Piece[],
  t: number,
  width: number,
  height: number,
  colours: readonly number[],
): void {
  context.clearRect(0, 0, width, height);
  for (const piece of pieces) {
    const local = Math.min(Math.max((t - piece.delay) / (1 - piece.delay), 0), 1);
    if (local <= 0 || local >= 1) continue;
    // Falls faster as it goes, the way a thing does, and fades at the end.
    const y = local * local * (height + piece.size * 2) - piece.size;
    const x = width * (piece.x + piece.drift * local);
    const fade = local > 0.75 ? (1 - local) / 0.25 : 1;
    context.fillStyle = rgba(colours[piece.colour % colours.length], fade);
    context.save();
    context.translate(x, y);
    context.rotate(piece.spin * local);
    const w = piece.size;
    const h = piece.size * 0.6;
    context.beginPath();
    if (typeof context.roundRect === 'function') context.roundRect(-w / 2, -h / 2, w, h, 1.5);
    else context.rect(-w / 2, -h / 2, w, h);
    context.fill();
    context.restore();
  }
}

export interface ConfettiProps {
  children: ComponentChildren;

  /** Whether to shower at all: false leaves the child alone. */
  play?: boolean;

  /** Milliseconds. */
  duration?: number;
  pieces?: number;
}

/**
 * A short shower of coloured pieces over whatever it wraps: the moment
 * a goal is met or a badge won. Plays once when built and gets out of
 * the way; it never takes a tap.
 */
export function Confetti({ children, play = true, duration = 2400, pieces = 48 }: ConfettiProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [completed, setCompleted] = useState(false);

  useEffect(() => {
    if (!play) return;
    const canvas = canvasRef.current;
    const context = canvas?.getContext('2d') ?? null;
    if (canvas === null || context === null) {
      setCompleted(true);
      return;
    }
    const all = confettiPieces(pieces);
    const scheme = currentScheme();
    const colours = [scheme.primary, scheme.tertiary, scheme.secondary, scheme.primaryContainer, scheme.tertiaryContainer];
    let frame = 0;
    let started: number | null = null;
    const paint = (now: number): void => {
      started ??= now;
      const t = (now - started) / duration;
      if (t >= 1) {
        setCompleted(true);
        return;
      }
      const ratio = globalThis.devicePixelRatio || 1;
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
        canvas.width = Math.round(width * ratio);
        canvas.height = Math.round(height * ratio);
      }
      context.setTransform(ratio, 0, 0, ratio, 0, 0);
      paintConfetti(context, all, t, width, height, colours);
      frame = requestAnimationFrame(paint);
    };
    frame = requestAnimationFrame(paint);
    return () => cancelAnimationFrame(frame);
  }, [play, duration, pieces]);

  return (
    <div class="ow-confetti" data-play={play ? 'true' : 'false'}>
      {children}
      {play && !completed && <canvas ref={canvasRef} class="ow-confetti__canvas" aria-hidden="true" />}
    </div>
  );
}
