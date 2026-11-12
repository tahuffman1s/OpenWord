import { describe, expect, it, vi } from 'vitest';

// The colour library ships modules Node cannot resolve by itself (the
// bundler can); nothing here draws a palette, so it is stood in for.
vi.mock('@material/material-color-utilities', () => ({ Blend: {}, Hct: {}, MaterialDynamicColors: {}, SchemeTonalSpot: class {} }));

import { ReadingStore } from '../src/data/marks';
import { Prefs } from '../src/infra/prefs';
import { Reference } from '../src/model/bible';
import { millisPerDay } from '../src/model/localDate';
import { ReadingPlans } from '../src/model/readingPlan';
import { dateLabel, streakLine } from '../src/ui/learnProgressCard';
import { lessonSummary, lessonTitle } from '../src/ui/learnTab';
import { hasSomethingDue } from '../src/ui/libraryScreen';
import { memoryDueLabel } from '../src/ui/memoryScreen';
import { PlanReading, nextInDay, planMeta, planSlotFor } from '../src/ui/plansScreen';
import { licenceBlocks, rateLabel } from '../src/ui/settingsScreen';
import { hourLabel } from '../src/ui/sleepSheet';

/** The words the learning screens put together, as they would be read off the screen. */
const monday = new Date(2026, 8, 28, 9, 30);

async function store(clock: { now: Date }): Promise<ReadingStore> {
  const prefs = Prefs.memory();
  prefs.setString('sleep', JSON.stringify({ mode: 'off' }));
  return ReadingStore.load({ prefs, clock: () => clock.now });
}

describe('the lesson card', () => {
  it('says what a lesson holds and about how long it takes', () => {
    expect(lessonSummary(0, 0, 0)).toBe('5 questions · about 1 minute');
    expect(lessonSummary(1, 0, 1)).toBe('1 new · 5 questions · about 2 minutes');
    expect(lessonSummary(4, 1, 1)).toBe('1 to recall · 2 verses due · 1 new · 5 questions · about 3 minutes');
    expect(lessonSummary(3, 2, 0)).toBe('2 to recall · 1 verse due · 5 questions · about 2 minutes');
  });

  it('is headed by the hour and what waits', () => {
    const base = { morning: false, evening: false, recalls: 0, fresh: 0, goalMet: false };
    expect(lessonTitle(base)).toBe('Today’s lesson');
    expect(lessonTitle({ ...base, goalMet: true })).toBe('Another lesson?');
    expect(lessonTitle({ ...base, morning: true, recalls: 1 })).toBe('Recall last night’s verses');
    expect(lessonTitle({ ...base, evening: true, fresh: 1 })).toBe('Learn a new verse tonight');
    expect(lessonTitle({ ...base, evening: true, fresh: 3 })).toBe('Learn 3 new verses tonight');
    // By day a new verse is simply part of the lesson.
    expect(lessonTitle({ ...base, fresh: 2 })).toBe('Today’s lesson');
  });
});

describe('due dates, streaks and hours', () => {
  it('a verse says when it is next due', async () => {
    const clock = { now: monday };
    const reading = await store(clock);
    const verse = new Reference('GEN', 1, 3);
    reading.toggleMemorise(verse);
    expect(memoryDueLabel(reading.memoryFor(verse)!, monday)).toBe('Due today');
    expect(hasSomethingDue(reading)).toBe(true);
    reading.reviewMemory(verse, { remembered: true });
    expect(memoryDueLabel(reading.memoryFor(verse)!, monday)).toBe('Tomorrow');
    expect(hasSomethingDue(reading)).toBe(false);
    clock.now = new Date(monday.getTime() + millisPerDay);
    reading.reviewMemory(verse, { remembered: true });
    expect(memoryDueLabel(reading.memoryFor(verse)!, clock.now)).toMatch(/^In \d+ days$/);
  });

  it('the streak line says where the run stands', async () => {
    const clock = { now: monday };
    const reading = await store(clock);
    expect(streakLine(reading.streak, monday)).toBe('Practise on two days running to start a streak.');
    reading.recordPractice();
    expect(streakLine(reading.streak, monday)).toBe('Practised today.');
    const tuesday = new Date(monday.getTime() + millisPerDay);
    expect(streakLine(reading.streak, tuesday)).toBe('Practise today to keep it going.');
    const friday = new Date(monday.getTime() + 4 * millisPerDay);
    expect(streakLine(reading.streak, friday)).toBe('Best streak: 1 day. Practise today to start another.');
  });

  it('hours and rates read as a person says them', () => {
    expect([0, 7, 12, 19, 23].map(hourLabel)).toEqual(['12 am', '7 am', '12 pm', '7 pm', '11 pm']);
    expect([0.75, 1, 1.25, 1.5, 2].map(rateLabel)).toEqual(['0.75×', '1×', '1.25×', '1.5×', '2×']);
    expect(dateLabel(new Date(Date.UTC(2026, 8, 28)))).toBe('28 September 2026');
  });
});

describe('a plan chapter in the reader', () => {
  it('is found in the day the reader was sent to, then in each plan’s current day', async () => {
    const clock = { now: monday };
    const reading = await store(clock);
    const plan = ReadingPlans.gospels;
    expect(planMeta(plan)).toBe(`30 days · about ${plan.minutesPerDay} min a day`);
    expect(planSlotFor(reading, new Reference('MAT', 1))).toBeNull();

    reading.startPlan(plan);
    const first = planSlotFor(reading, new Reference('MAT', 1, 5));
    expect(first).not.toBeNull();
    expect(first!.day.number).toBe(1);
    expect(first!.slot).toBe(0);
    // Day 2's chapters are not the current day's: found only by the focus.
    const ahead = plan.days[1].chapters[0];
    expect(planSlotFor(reading, ahead)).toBeNull();
    const focus = new PlanReading({ planId: plan.id, day: 2, chapter: ahead });
    expect(planSlotFor(reading, ahead, focus)!.slot).toBe(plan.days[1].firstSlot);
  });

  it('goes on to the next chapter of the day still unread', async () => {
    const clock = { now: monday };
    const reading = await store(clock);
    const plan = ReadingPlans.gospels;
    reading.startPlan(plan);
    const day = plan.days[0];
    // No translation in hand has no chapters to go on to.
    expect(nextInDay(null, reading.progressFor(plan.id)!, day, 0)).toBeNull();
  });
});

describe('a licence', () => {
  it('runs a paragraph’s lines together and sets a title in the middle', () => {
    const blocks = licenceBlocks(
      '                    GNU GENERAL PUBLIC LICENSE\n                       Version 3, 29 June 2007\n\n' +
        ' Everyone is permitted to copy and distribute verbatim copies\n of this license document.\n\n' +
        '    a) The work must carry prominent notices\n    stating that you modified it.\n',
    );
    expect(blocks).toEqual([
      { text: 'GNU GENERAL PUBLIC LICENSE', centred: true, indent: 0 },
      { text: 'Version 3, 29 June 2007', centred: true, indent: 0 },
      { text: 'Everyone is permitted to copy and distribute verbatim copies of this license document.', centred: false, indent: 0 },
      { text: 'a) The work must carry prominent notices stating that you modified it.', centred: false, indent: 2 },
    ]);
    expect(licenceBlocks('  \n\n ')).toEqual([]);
  });
});
