import { Blend, Hct, MaterialDynamicColors, SchemeTonalSpot, type DynamicScheme } from '@material/material-color-utilities';

/**
 * Builds the app's light and dark themes, Flutter's `ColorScheme.fromSeed`
 * done with the same library Flutter uses underneath (SchemeTonalSpot,
 * 2021 spec), and writes every role as a CSS custom property —
 * `--md-sys-color-primary` and the rest — on `<html>`, so the whole page
 * is themed by the same tokens Material 3 names.
 *
 * The web has no wallpaper palette to read, so the seed colour the reader
 * picks is the seed everywhere, and light or dark follows the system
 * unless the reader says otherwise.
 */
export enum ThemeMode {
  system = 0,
  light = 1,
  dark = 2,
}

export type Brightness = 'light' | 'dark';

const roles = [
  'primary',
  'onPrimary',
  'primaryContainer',
  'onPrimaryContainer',
  'inversePrimary',
  'secondary',
  'onSecondary',
  'secondaryContainer',
  'onSecondaryContainer',
  'tertiary',
  'onTertiary',
  'tertiaryContainer',
  'onTertiaryContainer',
  'error',
  'onError',
  'errorContainer',
  'onErrorContainer',
  'background',
  'onBackground',
  'surface',
  'onSurface',
  'surfaceVariant',
  'onSurfaceVariant',
  'surfaceDim',
  'surfaceBright',
  'surfaceContainerLowest',
  'surfaceContainerLow',
  'surfaceContainer',
  'surfaceContainerHigh',
  'surfaceContainerHighest',
  'inverseSurface',
  'inverseOnSurface',
  'outline',
  'outlineVariant',
  'shadow',
  'scrim',
  'surfaceTint',
  'primaryFixed',
  'primaryFixedDim',
  'onPrimaryFixed',
  'onPrimaryFixedVariant',
  'secondaryFixed',
  'secondaryFixedDim',
  'onSecondaryFixed',
  'onSecondaryFixedVariant',
  'tertiaryFixed',
  'tertiaryFixedDim',
  'onTertiaryFixed',
  'onTertiaryFixedVariant',
] as const;

export type ColorRole = (typeof roles)[number];
export type ColorScheme = Record<ColorRole, number> & { brightness: Brightness; seed: number };

const kebab = (s: string) => s.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);

export function schemeFromSeed(seed: number, brightness: Brightness): ColorScheme {
  const scheme: DynamicScheme = new SchemeTonalSpot(Hct.fromInt(seed), brightness === 'dark', 0, '2021');
  const out = { brightness, seed } as ColorScheme;
  for (const role of roles) {
    const color = (MaterialDynamicColors as unknown as Record<string, { getArgb(s: DynamicScheme): number }>)[role];
    out[role] = color.getArgb(scheme);
  }
  return out;
}

/** `#rrggbb` (alpha dropped) from ARGB. */
export function hexOf(argb: number): string {
  return `#${(argb & 0xffffff).toString(16).padStart(6, '0')}`;
}

/** `rgb(r g b / a)` from ARGB and an alpha of your own. */
export function rgba(argb: number, alpha: number): string {
  const r = (argb >> 16) & 0xff;
  const g = (argb >> 8) & 0xff;
  const b = argb & 0xff;
  return `rgb(${r} ${g} ${b} / ${alpha})`;
}

export function argbFromHex(hex: string): number {
  const h = hex.replace('#', '');
  const v = Number.parseInt(h.length === 6 ? `ff${h}` : h, 16);
  return v >>> 0;
}

/** Blends a fixed colour towards the theme, as `Color.harmonizeWith`. */
export function harmonize(design: number, seed: number): number {
  return Blend.harmonize(design, seed);
}

const media = typeof matchMedia === 'function' ? matchMedia('(prefers-color-scheme: dark)') : null;

export function systemBrightness(): Brightness {
  return media?.matches ? 'dark' : 'light';
}

export function resolveBrightness(mode: ThemeMode): Brightness {
  return mode === ThemeMode.light ? 'light' : mode === ThemeMode.dark ? 'dark' : systemBrightness();
}

let current: ColorScheme | null = null;

/** The scheme on the page right now. */
export function currentScheme(): ColorScheme {
  return current ?? schemeFromSeed(0xff6750a4, systemBrightness());
}

/** Writes the scheme's tokens to `<html>` and the browser chrome. */
export function applyScheme(scheme: ColorScheme): void {
  current = scheme;
  const root = document.documentElement;
  for (const role of roles) root.style.setProperty(`--md-sys-color-${kebab(role)}`, hexOf(scheme[role]));
  root.style.setProperty('--md-sys-color-primary-rgb', rgbTriplet(scheme.primary));
  root.style.setProperty('--md-sys-color-on-surface-rgb', rgbTriplet(scheme.onSurface));
  root.style.setProperty('--md-sys-color-on-surface-variant-rgb', rgbTriplet(scheme.onSurfaceVariant));
  root.style.setProperty('--md-sys-color-surface-tint-rgb', rgbTriplet(scheme.surfaceTint));
  root.style.setProperty('--md-sys-color-shadow-rgb', rgbTriplet(scheme.shadow));
  root.style.setProperty('--md-sys-color-scrim-rgb', rgbTriplet(scheme.scrim));
  root.style.colorScheme = scheme.brightness;
  root.dataset.theme = scheme.brightness;
  for (const meta of document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')) {
    meta.content = hexOf(scheme.surface);
  }
}

function rgbTriplet(argb: number): string {
  return `${(argb >> 16) & 0xff} ${(argb >> 8) & 0xff} ${argb & 0xff}`;
}

/**
 * Keeps the page's theme in step with the settings and the system. Returns
 * a function that stops listening.
 */
export function watchTheme(read: () => { seed: number; mode: ThemeMode }, onChange?: () => void): () => void {
  const apply = () => {
    const { seed, mode } = read();
    applyScheme(schemeFromSeed(seed, resolveBrightness(mode)));
    onChange?.();
  };
  apply();
  media?.addEventListener('change', apply);
  return () => media?.removeEventListener('change', apply);
}

/** The colour used for the words of Jesus, tuned per brightness. */
export function redLetter(brightness: Brightness): string {
  return brightness === 'dark' ? '#FF8A80' : '#B3261E';
}

/** Names of the highlight colours, in palette order. */
export const highlightNames = ['Yellow', 'Green', 'Blue', 'Pink', 'Purple'] as const;

const highlightHues = [0xffffd54f, 0xff81c784, 0xff64b5f6, 0xfff48fb1, 0xffb39ddb];

/** Highlight tints, translucent so the text stays readable in either theme. */
export function highlights(brightness: Brightness): string[] {
  const alpha = brightness === 'dark' ? 0.32 : 0.55;
  return highlightHues.map((hue) => rgba(hue, alpha));
}

/** A solid version for swatches and chips. */
export function highlightSwatch(index: number): string {
  return hexOf(highlightHues[index % highlightHues.length]);
}

export const highlightCount = highlightHues.length;
