import type { ComponentType } from 'preact';
import type { Reference } from '../model/bible';
import type { QuizKind, QuizQuestion } from '../model/quiz';

/**
 * The screens and widgets the reader opens but does not own.
 *
 * They are being ported alongside it, so each is looked for rather than
 * imported outright: `import.meta.glob` answers nothing for a file that is
 * not there yet, where a plain import would stop the reader compiling. As
 * each lands at the path named here, with the export named here, the
 * reader picks it up without a change. Once they are all in, these can
 * become ordinary imports.
 */

/** A plan chapter the reader was sent to read — `PlanReading` of `plans_screen.dart`. */
export interface PlanReading {
  planId: string;
  day: number;
  chapter: Reference;
}

export interface LibraryScreenProps {
  /** The tab to open on: Learn (0), Progress (1) or Saved (2). */
  initialTab?: number;
}

export interface QuizScreenProps {
  kind: QuizKind;
  questions?: readonly QuizQuestion[] | null;
  title?: string | null;
  onFinished?: ((right: number, total: number) => void) | null;
}

export interface PretestCardProps {
  questions: number;
  /** Right out of `questions` on the guess, or null before guessing. */
  guessed: number | null;
  onGuess: () => void;
}

export interface PosttestCardProps {
  questions: number;
  guessed: number;
  /** Right out of `questions` after reading, or null until answered. */
  answered: number | null;
  onAnswer: () => void;
}

export interface SimpleMarkdownProps {
  source: string;
  /** The typescale class the prose is set in, as the Dart's `baseStyle`. */
  baseStyle?: string;
}

type Module = Record<string, unknown>;

const screens = import.meta.glob<Module>([
  './libraryScreen.tsx',
  './plansScreen.tsx',
  './settingsScreen.tsx',
  './quizScreen.tsx',
  './social/socialScreen.tsx',
]);

const widgets = import.meta.glob<Module>(['./pretestCard.tsx', './widgets/simpleMarkdown.tsx'], { eager: true });

async function load<T>(path: string, name: string): Promise<T | null> {
  const loader = screens[path];
  if (loader === undefined) return null;
  try {
    const module = await loader();
    const found = module[name];
    if (found === undefined) console.warn(`OpenWord: ${path} has no export ${name}`);
    return (found as T | undefined) ?? null;
  } catch (error) {
    console.warn(`OpenWord: could not load ${path}: ${error}`);
    return null;
  }
}

function widget<T>(path: string, name: string): T | null {
  return (widgets[path]?.[name] as T | undefined) ?? null;
}

/** `LibraryScreen` of `src/ui/libraryScreen.tsx`; pops with a `Reference` to open. */
export const loadLibraryScreen = () => load<ComponentType<LibraryScreenProps>>('./libraryScreen.tsx', 'LibraryScreen');

/** `PlansScreen` of `src/ui/plansScreen.tsx`; pops with a `PlanReading` to open. */
export const loadPlansScreen = () => load<ComponentType<Record<string, never>>>('./plansScreen.tsx', 'PlansScreen');

/** `SettingsScreen` of `src/ui/settingsScreen.tsx`. */
export const loadSettingsScreen = () => load<ComponentType<Record<string, never>>>('./settingsScreen.tsx', 'SettingsScreen');

/** `QuizScreen` of `src/ui/quizScreen.tsx`; pops with a `Reference` to open. */
export const loadQuizScreen = () => load<ComponentType<QuizScreenProps>>('./quizScreen.tsx', 'QuizScreen');

/** `openSocial` of `src/ui/social/socialScreen.tsx`: friends, the feed, the account. */
export const loadOpenSocial = () => load<(tab?: string) => unknown>('./social/socialScreen.tsx', 'openSocial');

/** `PretestCard` of `src/ui/pretestCard.tsx`, or null while it is not there. */
export const PretestCard = widget<ComponentType<PretestCardProps>>('./pretestCard.tsx', 'PretestCard');

/** `PosttestCard` of `src/ui/pretestCard.tsx`, or null while it is not there. */
export const PosttestCard = widget<ComponentType<PosttestCardProps>>('./pretestCard.tsx', 'PosttestCard');

/** `SimpleMarkdown` of `src/ui/widgets/simpleMarkdown.tsx`, or null while it is not there. */
export const SimpleMarkdown = widget<ComponentType<SimpleMarkdownProps>>('./widgets/simpleMarkdown.tsx', 'SimpleMarkdown');
