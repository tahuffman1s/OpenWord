import type { ComponentChildren, VNode } from 'preact';
import type { ReadingStore } from '../data/marks';
import { useNotifier } from '../infra/changeNotifier';
import type { Bible, Reference } from '../model/bible';
import { MemoryStage, type MemoryVerse } from '../model/memoryVerse';
import { QuizKind } from '../model/quiz';
import { SleepMode } from '../model/sleepPolicy';
import { SuggestedVerse } from '../model/suggestedVerses';
import { historySettled } from './historySettled';
import { GoalStrip } from './learnProgressCard';
import { Chip, FilledButton, Icon, ListTile, Sheet, TextButton, TonalButton, nav, showSheet, showSnackBar } from './m3';
import { MemoryScreen, memoryDueLabel } from './memoryScreen';
import { QuizScreen } from './quizScreen';
import { hasReader } from './readerNav';
import { CheckboxListTile } from './widgets/listTiles';
import { Dismissible } from './widgets/dismissible';
import './shared.css';
import './learnTab.css';

/** Questions in a lesson's round: enough to count, short enough to do. */
export const lessonQuestions = 5;

const quizIcons: Record<string, string> = {
  [QuizKind.whichBook.name]: 'auto_stories',
  [QuizKind.finishVerse.name]: 'short_text',
  [QuizKind.bookOrder.name]: 'format_list_numbered',
  [QuizKind.mixed.name]: 'shuffle',
};

/**
 * The Learn tab: one thing to do today, up top, and under it the verses
 * being learnt, with suggestions when there are none, and the rounds to
 * test yourself with.
 *
 * Tells the library, through `onOpen`, when a verse or passage is opened
 * in the reader from any screen it leads to, so that it closes with it.
 */
export function LearnTab({ reading, bible, onOpen }: { reading: ReadingStore; bible: Bible | null; onOpen: (reference: Reference) => void }) {
  const today = reading.today;
  const verses = reading.memoryVerses;
  const offered = reading.memoryDue;
  const due = offered.length;
  const recalls = offered.filter((v) => v.awaitsFirstRecall).length;
  const fresh = offered.filter((v) => v.stage === MemoryStage.waiting).length;
  const heldBack = reading.memoryHeldBack.length;
  const policy = reading.sleepPolicy;
  const ordered = [...verses].sort((a, b) => {
    const byDue = a.due.getTime() - b.due.getTime();
    return byDue !== 0 ? byDue : a.added.getTime() - b.added.getTime();
  });
  const suggestions = bible === null ? [] : SuggestedVerse.available(bible, (reference) => reading.isMemorising(reference));

  const textOf = (reference: Reference): string => {
    const verse = reference.verse;
    if (bible === null || verse === null) return '';
    return bible.bookByCode(reference.bookCode)?.chapter(reference.chapter)?.verseText(verse) ?? '';
  };

  /**
   * A reference a screen closed with goes up to the library, which closes
   * with it in turn — unless a reader has registered, which was sent there
   * as the screen closed.
   */
  const passUp = (reference: Reference | undefined): void => {
    if (reference !== undefined && !hasReader()) onOpen(reference);
  };

  const open = async (screen: VNode): Promise<void> => {
    passUp(await nav.push<Reference>(screen));
  };

  /** Today's lesson: the verses due, then a short round. */
  const startLesson = async (): Promise<void> => {
    let opened: Reference | undefined;
    if (reading.memoryDue.length > 0) {
      opened = await nav.push<Reference>(<MemoryScreen />);
      if (opened === undefined) await historySettled();
    }
    if (opened === undefined) {
      opened = await nav.push<Reference>(<QuizScreen kind={QuizKind.mixed} count={lessonQuestions} />);
    }
    passUp(opened);
  };

  const add = (reference: Reference): void => {
    if (reading.toggleMemorise(reference)) {
      showSnackBar(`Memorising ${reference.label}`);
    }
  };

  return (
    <div class="ow-learn ow-content">
      <GoalStrip reading={reading} />
      <div class="ow-learn__lesson">
        <LessonCard
          due={due}
          recalls={recalls}
          fresh={fresh}
          heldBack={heldBack}
          evening={policy.mode !== SleepMode.off && policy.isEvening(today)}
          morning={policy.mode !== SleepMode.off && policy.isMorning(today)}
          goalMet={reading.progress.goalMetOn(today)}
          onStart={bible === null ? null : () => void startLesson()}
        />
      </div>
      <Header
        title="Verses you’re learning"
        trailing={
          suggestions.length === 0 ? null : (
            <TextButton icon="add" onClick={() => showSuggestionsSheet(reading, suggestions)}>
              Add
            </TextButton>
          )
        }
      />
      {verses.length === 0 ? (
        <>
          <div class="ow-learn__nothing m3-body-medium ow-muted">
            Nothing yet. Tap a verse while reading and choose Memorise, or start with one of these.
          </div>
          {suggestions.slice(0, 3).map((suggestion) => (
            <SuggestionTile key={suggestion.reference.key} suggestion={suggestion} text={textOf(suggestion.reference)} onAdd={() => add(suggestion.reference)} />
          ))}
        </>
      ) : (
        ordered.map((verse) => (
          <VerseTile
            key={verse.key}
            verse={verse}
            text={textOf(verse.reference)}
            today={today}
            onTap={() => void open(<MemoryScreen first={verse.reference} />)}
            onRemove={() => {
              reading.removeMemory(verse.reference);
              showSnackBar(`No longer memorising ${verse.reference.label}`, {
                action: { label: 'Undo', onPressed: () => reading.restoreMemory(verse) },
              });
            }}
          />
        ))
      )}
      <Header title="Quiz yourself" />
      <div class="ow-learn__rounds">
        {QuizKind.values.map((kind) => (
          <Chip
            key={kind.name}
            variant="assist"
            icon={quizIcons[kind.name]}
            label={kind.label}
            title={kind.description}
            disabled={bible === null}
            onClick={() => void open(<QuizScreen kind={kind} />)}
          />
        ))}
      </div>
    </div>
  );
}

/** What a lesson holds, in a line: "1 to recall · 2 verses due · 5 questions · about 2 minutes". */
export function lessonSummary(due: number, recalls: number, fresh: number): string {
  const ladder = due - recalls - fresh;
  const parts = [
    ...(recalls > 0 ? [recalls === 1 ? '1 to recall' : `${recalls} to recall`] : []),
    ...(ladder > 0 ? [ladder === 1 ? '1 verse due' : `${ladder} verses due`] : []),
    ...(fresh > 0 ? [fresh === 1 ? '1 new' : `${fresh} new`] : []),
    `${lessonQuestions} questions`,
  ];
  const minutes = Math.ceil((due * 20 + lessonQuestions * 10) / 60);
  return `${parts.join(' · ')} · about ${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`;
}

/** What the lesson card is headed, by the hour and what waits. */
export function lessonTitle(options: { morning: boolean; evening: boolean; recalls: number; fresh: number; goalMet: boolean }): string {
  const { morning, evening, recalls, fresh, goalMet } = options;
  if (morning && recalls > 0) return 'Recall last night’s verses';
  if (evening && fresh > 0) {
    return fresh === 1 ? 'Learn a new verse tonight' : `Learn ${fresh} new verses tonight`;
  }
  return goalMet ? 'Another lesson?' : 'Today’s lesson';
}

/**
 * The one thing to do: today's lesson, with what it holds and about how
 * long it takes.
 */
function LessonCard({
  due,
  recalls,
  fresh,
  heldBack,
  evening,
  morning,
  goalMet,
  onStart,
}: {
  due: number;

  /**
   * Of `due`, first recalls of verses learnt last time, and verses
   * still to be learnt.
   */
  recalls: number;
  fresh: number;

  /** New verses the sleep policy keeps for the evening, or for tomorrow. */
  heldBack: number;
  evening: boolean;
  morning: boolean;
  goalMet: boolean;
  onStart: (() => void) | null;
}) {
  return (
    <div class="ow-lesson" data-key="lesson">
      <div class="ow-lesson__head">
        <Icon name="play_lesson" />
        <div class="m3-title-large ow-lesson__title">{lessonTitle({ morning, evening, recalls, fresh, goalMet })}</div>
      </div>
      <div class="m3-body-medium ow-lesson__summary">{lessonSummary(due, recalls, fresh)}</div>
      {heldBack > 0 && (
        <div class="m3-body-small ow-lesson__held">
          {evening
            ? heldBack === 1
              ? '1 new verse waits for tomorrow, to be learnt by day.'
              : `${heldBack} new verses wait for tomorrow, to be learnt by day.`
            : heldBack === 1
              ? '1 new verse waits for this evening, to be slept on.'
              : `${heldBack} new verses wait for this evening, to be slept on.`}
        </div>
      )}
      <FilledButton class="ow-lesson__start" icon="play_arrow" disabled={onStart === null} onClick={() => onStart?.()}>
        {goalMet ? 'Keep going' : 'Start'}
      </FilledButton>
    </div>
  );
}

function Header({ title, trailing = null }: { title: string; trailing?: ComponentChildren }) {
  return (
    <div class="ow-learn__header">
      <div class="m3-title-medium ow-learn__header-title">{title}</div>
      {trailing}
    </div>
  );
}

function VerseTile({ verse, text, today, onTap, onRemove }: { verse: MemoryVerse; text: string; today: Date; onTap: () => void; onRemove: () => void }) {
  const due = verse.isDueOn(today);
  const tone = due ? 'm3-primary' : 'ow-muted';
  return (
    <Dismissible onDismissed={onRemove} label={`Stop memorising ${verse.reference.label}`}>
      <ListTile
        leading={<Icon name={verse.isLearnt ? 'verified' : 'psychology'} class={tone} />}
        title={verse.reference.label}
        subtitle={<span class="ow-clamp-1">{text}</span>}
        trailing={<span class={`m3-label-medium ${tone}`}>{memoryDueLabel(verse, today)}</span>}
        onClick={onTap}
      />
    </Dismissible>
  );
}

function SuggestionTile({ suggestion, text, onAdd }: { suggestion: SuggestedVerse; text: string; onAdd: () => void }) {
  return (
    <ListTile
      static
      leading={<Icon name="auto_awesome" class="ow-tertiary" />}
      title={`${suggestion.reference.label} · ${suggestion.theme}`}
      subtitle={<span class="ow-clamp-2">{text}</span>}
      trailing={<TonalButton onClick={onAdd}>Add</TonalButton>}
    />
  );
}

/**
 * Every suggestion this translation has, grouped by what it is for,
 * each a tap from the ladder.
 */
export function showSuggestionsSheet(reading: ReadingStore, suggestions: readonly SuggestedVerse[]): Promise<void> {
  return showSheet<void>(<SuggestionsSheet reading={reading} suggestions={suggestions} />, { name: 'suggestions' }).then(() => undefined);
}

function SuggestionsSheet({ reading, suggestions }: { reading: ReadingStore; suggestions: readonly SuggestedVerse[] }) {
  useNotifier(reading);
  const themes = new Map<string, SuggestedVerse[]>();
  for (const suggestion of suggestions) {
    const list = themes.get(suggestion.theme) ?? [];
    list.push(suggestion);
    themes.set(suggestion.theme, list);
  }
  return (
    <Sheet title="Verses worth knowing">
      <p class="ow-sheet-lead">Tap one to start learning it. Any verse can be added from its sheet while reading.</p>
      {[...themes.entries()].map(([theme, entries]) => (
        <div key={theme}>
          <div class="m3-label-large m3-primary ow-suggestions__theme">{theme}</div>
          {entries.map((suggestion) => (
            <CheckboxListTile
              key={suggestion.reference.key}
              class="ow-suggestions__tile"
              value={reading.isMemorising(suggestion.reference)}
              title={suggestion.reference.label}
              onChange={() => reading.toggleMemorise(suggestion.reference)}
            />
          ))}
        </div>
      ))}
    </Sheet>
  );
}
