import { useEffect, useRef } from 'preact/hooks';
import { useAppScope } from '../app/scope';
import type { ReadingStore } from '../data/marks';
import { PlanProgress } from '../data/planProgress';
import { useNotifier } from '../infra/changeNotifier';
import type { Bible, Reference } from '../model/bible';
import { Passage, ReadingPlans, type PlanDay, type ReadingPlan } from '../model/readingPlan';
import { historySettled } from './historySettled';
import {
  AppBar,
  FilledButton,
  Icon,
  IconButton,
  LinearProgress,
  MenuItem,
  PopupMenuButton,
  Screen,
  Sheet,
  TextButton,
  TonalButton,
  confirm,
  nav,
  showSheet,
  showSnackBar,
  useOverlay,
} from './m3';
import { hasReader, openPlanInReader } from './readerNav';
import './shared.css';
import './plansScreen.css';

/**
 * A chapter to open, and the plan day it was opened from, so the reader
 * can offer to tick it off when the reader gets to the end.
 */
export class PlanReading {
  readonly planId: string;
  readonly day: number;
  readonly chapter: Reference;

  constructor(init: { planId: string; day: number; chapter: Reference }) {
    this.planId = init.planId;
    this.day = init.day;
    this.chapter = init.chapter;
  }
}

/**
 * The reading plans: the ones under way, with today's reading on top,
 * and the ones that could be started. Closes with a `PlanReading` to
 * open, which a registered reader has been sent to already.
 */
export function PlansScreen() {
  const scope = useAppScope();
  const overlay = useOverlay();
  const reading = scope.reading;
  useNotifier(reading, scope.library);
  const bible = scope.library.bible;

  const open = (chosen: PlanReading): void => {
    overlay.close(chosen);
    openPlanInReader(chosen);
  };

  const preview = async (plan: ReadingPlan): Promise<void> => {
    const start = await showSheet<boolean>(<PlanPreview plan={plan} />, { name: 'plan-preview' });
    if (start !== true) return;
    await historySettled();
    reading.startPlan(plan);
    const first = plan.days[0];
    open(new PlanReading({ planId: plan.id, day: 1, chapter: first.chapters[0] }));
  };

  const active = reading.plans;
  const activeIds = new Set(active.map((p) => p.plan.id));
  const available = ReadingPlans.all.filter((plan) => !activeIds.has(plan.id));

  return (
    <Screen class="ow-plans" appBar={(scrolled) => <AppBar scrolled={scrolled} title="Reading plans" />}>
      <div class="ow-plans__page">
        {active.length === 0 && (
          <div class="m3-body-large ow-muted ow-plans__lead">
            Read a little every day. Pick a plan and it tells you what to read next. Miss a day and it waits for you —
            nothing piles up.
          </div>
        )}
        {active.map((progress) => (
          <div class="ow-plans__active" key={progress.plan.id}>
            <ActivePlanCard progress={progress} reading={reading} bible={bible} onOpen={open} />
          </div>
        ))}
        {available.length > 0 && (
          <>
            <div class="m3-title-small m3-primary ow-plans__heading">{active.length === 0 ? 'Choose a plan' : 'Start another plan'}</div>
            {available.map((plan) => (
              <PlanTile
                key={plan.id}
                plan={plan}
                // Pointed out only to someone who has not begun one.
                recommend={active.length === 0 && plan.recommended}
                onTap={() => void preview(plan)}
              />
            ))}
          </>
        )}
      </div>
    </Screen>
  );
}

/**
 * Whether `bible` has this chapter. A plan is built on the whole English
 * Bible, and an imported translation may be a New Testament, or lack the
 * odd chapter.
 */
export function hasChapter(bible: Bible | null, chapter: Reference): boolean {
  return bible?.bookByCode(chapter.bookCode)?.chapterNumbers.includes(chapter.chapter) ?? false;
}

/** "30 days · about 10 min a day" */
export function planMeta(plan: ReadingPlan): string {
  return `${plan.length} days · about ${plan.minutesPerDay} min a day`;
}

function PlanTile({ plan, recommend, onTap }: { plan: ReadingPlan; recommend: boolean; onTap: () => void }) {
  return (
    <button type="button" class="ow-plan-tile m3-interactive" onClick={onTap}>
      <span class="ow-plan-tile__text">
        {recommend && <span class="ow-plan-tile__start m3-label-small">Good place to start</span>}
        <span class="m3-title-medium">{plan.name}</span>
        <span class="m3-body-medium ow-muted">{plan.summary}</span>
        <span class="m3-label-medium ow-muted ow-plan-tile__meta">{planMeta(plan)}</span>
      </span>
      <Icon name="chevron_right" class="ow-muted" />
    </button>
  );
}

/** What a plan is and what its first days hold, with one button to start. */
function PlanPreview({ plan }: { plan: ReadingPlan }) {
  const overlay = useOverlay();
  return (
    <Sheet>
      <div class="ow-plan-preview">
        <div class="m3-headline-small">{plan.name}</div>
        <div class="m3-label-large m3-primary ow-plan-preview__meta">{planMeta(plan)}</div>
        <div class="m3-body-large ow-plan-preview__description">{plan.description}</div>
        {plan.days.slice(0, 3).map((day) => (
          <div class="ow-plan-preview__day" key={day.number}>
            <span class="m3-label-large ow-muted ow-plan-preview__number">Day {day.number}</span>
            <span class="m3-body-medium ow-plan-preview__label">{day.label}</span>
          </div>
        ))}
        <div class="m3-body-small ow-muted">…and so on. Skip a day and it waits for you.</div>
        <FilledButton class="ow-plan-preview__start" icon="play_arrow" onClick={() => overlay.close(true)}>
          Start today
        </FilledButton>
      </div>
    </Sheet>
  );
}

/** Whether `chapter` of `day` falls inside `passage`. */
function inPassage(chapter: Reference, passage: Passage): boolean {
  return chapter.bookCode === passage.bookCode && chapter.chapter >= passage.firstChapter && chapter.chapter <= passage.lastChapter;
}

/**
 * A plan under way: where the reader is, today's reading, and one button
 * that opens the next chapter to read.
 */
export function ActivePlanCard({
  progress,
  reading,
  bible,
  onOpen,
}: {
  progress: PlanProgress;
  reading: ReadingStore;
  bible: Bible | null;
  onOpen: (chosen: PlanReading) => void;
}) {
  const plan = progress.plan;
  const today = reading.today;
  const day = progress.currentDay;
  const behind = progress.behindOn(today);
  const due = progress.hasReadingDueOn(today);

  const has = (chapter: Reference): boolean => hasChapter(bible, chapter);

  const open = (from: PlanDay, chapter: Reference): void => {
    onOpen(new PlanReading({ planId: plan.id, day: from.number, chapter }));
  };

  const firstUnread = (of: PlanDay, passage: Passage): Reference => {
    for (let i = 0; i < of.chapters.length; i++) {
      const chapter = of.chapters[i];
      if (!inPassage(chapter, passage)) continue;
      if (!progress.isRead(of.firstSlot + i)) return chapter;
    }
    return passage.chapters[0];
  };

  const setPassage = (of: PlanDay, passage: Passage, read: boolean): void => {
    for (let i = 0; i < of.chapters.length; i++) {
      if (inPassage(of.chapters[i], passage)) {
        reading.setPlanSlot(plan.id, of.firstSlot + i, read);
      }
    }
  };

  const continueButton = (of: PlanDay) => {
    const slot = progress.nextSlot;
    if (slot === null) return null;
    const chapter = progress.chapterAt(slot);
    const started = progress.readInDay(of) > 0;
    const label = !due ? `Read ahead: ${Passage.labelFor(chapter)}` : started ? `Continue: ${Passage.labelFor(chapter)}` : 'Start reading';
    if (!has(chapter)) {
      return (
        <div class="m3-body-medium ow-plan-card__missing">
          {Passage.labelFor(chapter)} is not in this translation. Tick it off when you have read it elsewhere.
        </div>
      );
    }
    return due ? (
      <FilledButton class="ow-plan-card__continue" icon="menu_book" onClick={() => open(of, chapter)}>
        {label}
      </FilledButton>
    ) : (
      <TonalButton class="ow-plan-card__continue" icon="menu_book" onClick={() => open(of, chapter)}>
        {label}
      </TonalButton>
    );
  };

  return (
    <div class="ow-plan-card" data-key={`plan/${plan.id}`}>
      <div class="ow-plan-card__head">
        <div class="m3-title-medium ow-plan-card__name">{plan.name}</div>
        <PlanMenu progress={progress} reading={reading} onOpen={onOpen} />
      </div>
      <div class="ow-plan-card__body">
        <div class="m3-label-large ow-muted">{day === null ? `All ${plan.length} days read` : `Day ${day.number} of ${plan.length}`}</div>
        <LinearProgress class="ow-plan-card__progress" value={progress.fraction} height={6} />
        {day === null ? (
          <>
            <div class="m3-body-large">You read the whole plan. Well done.</div>
            <div class="ow-plan-card__finished">
              <TonalButton onClick={() => reading.startPlan(plan)}>Read it again</TonalButton>
              <TextButton onClick={() => reading.stopPlan(plan.id)}>Remove</TextButton>
            </div>
          </>
        ) : (
          <>
            {behind >= PlanProgress.behindThreshold && <BehindNote days={behind} onPickUp={() => reading.pickUpPlanToday(plan.id)} />}
            <div class="m3-label-large m3-primary ow-plan-card__today">{due ? 'Today' : 'Done for today — next up'}</div>
            {day.passages.map((passage) => (
              <PassageRow
                key={passage.label}
                passage={passage}
                day={day}
                progress={progress}
                available={has(passage.chapters[0])}
                onToggle={(read) => setPassage(day, passage, read)}
                onOpen={() => open(day, firstUnread(day, passage))}
              />
            ))}
            <div class="ow-plan-card__next">{continueButton(day)}</div>
          </>
        )}
      </div>
    </div>
  );
}

/** One passage of a day: a tick to mark it, and its name to open it. */
function PassageRow({
  passage,
  day,
  progress,
  available,
  onToggle,
  onOpen,
}: {
  passage: Passage;
  day: PlanDay;
  progress: PlanProgress;
  available: boolean;
  onToggle: (read: boolean) => void;
  onOpen: () => void;
}) {
  let read = 0;
  let total = 0;
  for (let i = 0; i < day.chapters.length; i++) {
    if (inPassage(day.chapters[i], passage)) {
      total++;
      if (progress.isRead(day.firstSlot + i)) read++;
    }
  }
  const done = read === total;
  return (
    <div class="ow-passage">
      <IconButton
        class={done ? 'm3-primary' : 'ow-muted'}
        icon={done ? 'check_circle' : read > 0 ? 'timelapse' : 'radio_button_unchecked'}
        label={done ? 'Mark as not read' : 'Mark as read'}
        onClick={() => onToggle(!done)}
      />
      <button
        type="button"
        class={`ow-passage__name m3-body-large${available ? ' m3-interactive' : ''}${done ? ' ow-passage__name--done' : ''}${done || !available ? ' ow-muted' : ''}`}
        disabled={!available}
        onClick={onOpen}
      >
        {read > 0 && !done ? `${passage.label}  ·  ${read} of ${total} read` : passage.label}
      </button>
    </div>
  );
}

/**
 * Said once the reader is two days or more behind, and never as a
 * reproach: the fix is one tap, and it marks nothing read.
 */
function BehindNote({ days, onPickUp }: { days: number; onPickUp: () => void }) {
  return (
    <div class="ow-behind">
      <div class="m3-body-medium">
        You are {days} days behind the pace you started with. That is fine — the plan is waiting where you left it.
      </div>
      <div class="ow-behind__action">
        <TextButton onClick={onPickUp}>Pick up from today</TextButton>
      </div>
    </div>
  );
}

type MenuAction = 'allDays' | 'pickUp' | 'restart' | 'remove';

function PlanMenu({ progress, reading, onOpen }: { progress: PlanProgress; reading: ReadingStore; onOpen: (chosen: PlanReading) => void }) {
  const act = async (action: MenuAction): Promise<void> => {
    const plan = progress.plan;
    switch (action) {
      case 'allDays': {
        await historySettled();
        const chosen = await nav.push<PlanReading>(<PlanDaysScreen planId={plan.id} />);
        // Where a reader has registered, it was sent there as the days closed.
        if (chosen !== undefined && !hasReader()) onOpen(chosen);
        break;
      }
      case 'pickUp':
        reading.pickUpPlanToday(plan.id);
        break;
      case 'restart':
        if (
          await confirm({
            title: `Start ${plan.name} over?`,
            body: 'Every day is marked unread again and day 1 is today. Your bookmarks, highlights and notes are not touched.',
            confirmLabel: 'Start over',
          })
        ) {
          reading.startPlan(plan);
        }
        break;
      case 'remove': {
        const saved = progress;
        reading.stopPlan(plan.id);
        showSnackBar(`Removed ${plan.name}`, { action: { label: 'Undo', onPressed: () => reading.restorePlan(saved) } });
        break;
      }
    }
  };
  return (
    <PopupMenuButton
      label="Plan options"
      onSelected={(action) => void act(action as MenuAction)}
      items={() => (
        <>
          <MenuItem icon="calendar_view_day" label="See every day" value="allDays" />
          {progress.behindOn(reading.today) > 0 && <MenuItem icon="today" label="Pick up from today" value="pickUp" />}
          <MenuItem icon="restart_alt" label="Start over" value="restart" />
          <MenuItem icon="delete_outline" label="Remove plan" value="remove" />
        </>
      )}
    />
  );
}

const rowHeight = 72;

/** Every day of a plan, ticked or not, opened at the current day. */
export function PlanDaysScreen({ planId }: { planId: string }) {
  const scope = useAppScope();
  const overlay = useOverlay();
  const reading = scope.reading;
  useNotifier(reading);
  const bible = scope.library.bible;
  const body = useRef<HTMLDivElement>(null);
  const progress = reading.progressFor(planId);

  // Opened at the current day, a couple of rows down from the top.
  useEffect(() => {
    const current = progress?.currentDay ?? null;
    if (current === null || progress === null || body.current === null) return;
    body.current.scrollTop = Math.min(Math.max(current.number - 3, 0), progress.plan.length) * rowHeight;
    // Only as the screen opens: ticking a day must not move the list.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (progress === null) {
    return <Screen appBar={<AppBar />} />;
  }
  const plan = progress.plan;
  const current = progress.currentDay;

  const open = (chosen: PlanReading): void => {
    overlay.close(chosen);
    openPlanInReader(chosen);
  };

  return (
    <Screen
      class="ow-plan-days"
      bodyRef={body}
      appBar={(scrolled) => <AppBar scrolled={scrolled} title={plan.name} subtitle={`${progress.daysRead} of ${plan.length} days read`} />}
    >
      <div class="ow-plan-days__list">
        {plan.days.map((day) => {
          const read = progress.readInDay(day);
          const done = read === day.slotCount;
          const isCurrent = day.number === current?.number;
          const first = day.chapters[0];
          const available = hasChapter(bible, first);
          return (
            <div class={`ow-plan-day${isCurrent ? ' ow-plan-day--current' : ''}`} key={day.number} style={`height:${rowHeight}px`}>
              <button
                type="button"
                role="checkbox"
                aria-checked={done ? 'true' : read > 0 ? 'mixed' : 'false'}
                aria-label={`Day ${day.number} read`}
                class={`m3-checkbox m3-interactive${done || read > 0 ? ' m3-checkbox--checked' : ''}`}
                onClick={() => reading.setPlanDay(plan.id, day, !done)}
              >
                <span class="m3-checkbox__box">{done ? <Icon name="check" /> : read > 0 ? <Icon name="remove" /> : null}</span>
              </button>
              <button
                type="button"
                class={`ow-plan-day__text${available ? ' m3-interactive' : ''}`}
                disabled={!available}
                onClick={() => {
                  let chapter = first;
                  for (let i = 0; i < day.slotCount; i++) {
                    if (!progress.isRead(day.firstSlot + i)) {
                      chapter = day.chapters[i];
                      break;
                    }
                  }
                  open(new PlanReading({ planId: plan.id, day: day.number, chapter }));
                }}
              >
                <span class="m3-body-large">{isCurrent ? `Day ${day.number} · next` : `Day ${day.number}`}</span>
                <span class="m3-body-medium ow-muted ow-clamp-1">{day.label}</span>
              </button>
            </div>
          );
        })}
      </div>
    </Screen>
  );
}

// --- at the end of a plan's chapter, in the reader ----------------------

/** Where a chapter falls in a plan: the plan, the day, and the slot. */
export interface PlanSlot {
  progress: PlanProgress;
  day: PlanDay;
  slot: number;
}

/**
 * Where `chapter` falls in a plan the reader is following: the day they
 * were sent to first (`focus`), then each plan's current day.
 */
export function planSlotFor(reading: ReadingStore, chapter: Reference, focus: PlanReading | null = null): PlanSlot | null {
  const candidates: [PlanProgress, PlanDay][] = [];
  if (focus !== null) {
    const progress = reading.progressFor(focus.planId);
    if (progress !== null && focus.day >= 1 && focus.day <= progress.plan.length) {
      candidates.push([progress, progress.plan.days[focus.day - 1]]);
    }
  }
  for (const progress of reading.plans) {
    const day = progress.currentDay;
    if (day !== null) candidates.push([progress, day]);
  }
  for (const [progress, day] of candidates) {
    for (let i = 0; i < day.slotCount; i++) {
      const entry = day.chapters[i];
      if (entry.bookCode === chapter.bookCode && entry.chapter === chapter.chapter) {
        return { progress, day, slot: day.firstSlot + i };
      }
    }
  }
  return null;
}

/**
 * The next chapter of the day still to read after `slot`, skipping any
 * this translation does not have.
 */
export function nextInDay(bible: Bible | null, progress: PlanProgress, day: PlanDay, slot: number): Reference | null {
  for (let i = 0; i < day.slotCount; i++) {
    const candidate = day.firstSlot + i;
    if (candidate === slot || progress.isRead(candidate)) continue;
    const chapter = day.chapters[i];
    if (hasChapter(bible, chapter)) return chapter;
  }
  return null;
}

/**
 * At the end of a chapter that a plan has the reader in: one button that
 * ticks it off and goes on to the next chapter of the day.
 */
export function PlanChapterCard({
  planName,
  day,
  read,
  nextLabel,
  onDone,
  onUndo,
  onNext,
}: {
  planName: string;
  day: number;
  read: boolean;

  /**
   * The next chapter of the day still to read, or null when this is the
   * last.
   */
  nextLabel: string | null;
  onDone: () => void;
  onUndo: () => void;
  onNext: (() => void) | null;
}) {
  return (
    <div class="ow-plan-chapter" data-key="plan-chapter">
      <div class="ow-plan-chapter__head m3-label-large">
        <Icon name={read ? 'check_circle' : 'event_note'} size={18} />
        <span class="ow-plan-chapter__name">
          {planName} · day {day}
        </span>
      </div>
      {!read ? (
        <FilledButton class="ow-plan-chapter__done" icon="check" onClick={onDone}>
          {nextLabel === null ? `Done — that’s day ${day}` : `Done — next: ${nextLabel}`}
        </FilledButton>
      ) : (
        <div class="ow-plan-chapter__read">
          <span class="m3-body-large ow-plan-chapter__name">Read</span>
          <TextButton onClick={onUndo}>Undo</TextButton>
          {onNext !== null && <FilledButton onClick={onNext}>Next: {nextLabel}</FilledButton>}
        </div>
      )}
    </div>
  );
}
