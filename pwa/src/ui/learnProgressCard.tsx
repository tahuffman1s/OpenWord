import type { ComponentChildren } from 'preact';
import type { ReadingStore } from '../data/marks';
import { useNotifier } from '../infra/changeNotifier';
import { Achievement } from '../model/achievements';
import { DailyGoal, type LearnProgress } from '../model/learnProgress';
import { millisPerDay } from '../model/localDate';
import type { Streak } from '../model/streak';
import { Icon, LinearProgress, ListTile, Sheet, showSheet, useOverlay } from './m3';
import { StreakBadge } from './memoryScreen';
import { RadioListTile } from './widgets/listTiles';
import './shared.css';
import './learnProgressCard.css';

/**
 * Today's goal as a ring: full is the day done. A determinate circular
 * progress indicator with round caps over a track, filling its box.
 */
function GoalRing({ value, size, stroke, children }: { value: number; size: number; stroke: number; children?: ComponentChildren }) {
  const radius = (size - stroke) / 2;
  const around = 2 * Math.PI * radius;
  const shown = Math.min(Math.max(value, 0), 1);
  return (
    <span class="ow-goal-ring" style={`width:${size}px;height:${size}px`} role="progressbar" aria-valuenow={Math.round(shown * 100)}>
      <svg viewBox={`0 0 ${size} ${size}`} width={size} height={size} aria-hidden="true">
        <circle class="ow-goal-ring__track" cx={size / 2} cy={size / 2} r={radius} style={`stroke-width:${stroke}`} />
        {shown > 0 && (
          <circle
            class="ow-goal-ring__value"
            cx={size / 2}
            cy={size / 2}
            r={radius}
            style={`stroke-width:${stroke};stroke-dasharray:${around};stroke-dashoffset:${around * (1 - shown)}`}
          />
        )}
      </svg>
      <span class="ow-goal-ring__label">{children}</span>
    </span>
  );
}

/** A streak's freezes, as snowflakes. */
function Freezes({ count, title }: { count: number; title?: string }) {
  return (
    <span class="ow-freezes" title={title} aria-label={title ?? `${count} streak ${count === 1 ? 'freeze' : 'freezes'}`}>
      {Array.from({ length: count }, () => (
        <Icon name="ac_unit" size={18} />
      ))}
    </span>
  );
}

/**
 * A single row for the top of the Learn tab: today's goal as a small
 * ring, how far it is, the streak and its freezes.
 */
export function GoalStrip({ reading }: { reading: ReadingStore }) {
  const progress = reading.progress;
  const streak = reading.streak;
  const today = reading.today;
  const days = streak.currentOn(today);
  const earned = progress.xpOn(today);
  const goal = progress.goal;
  const met = progress.goalMetOn(today);
  return (
    <div class="ow-goal-strip">
      <button type="button" class="ow-goal-strip__ring m3-interactive" data-key="goal/strip" aria-label="Daily goal" onClick={() => showDailyGoalSheet(reading)}>
        <GoalRing value={earned / goal.xp} size={52} stroke={6}>
          <Icon name={met ? 'check' : 'bolt'} size={20} />
        </GoalRing>
      </button>
      <div class="ow-goal-strip__text">
        <div class="m3-title-medium">{met ? 'Today’s goal met' : `${earned} of ${goal.xp} XP today`}</div>
        <div class="m3-body-small ow-muted">
          {streak.practisedOn(today)
            ? 'Practised today.'
            : days > 0
              ? 'Practise today to keep your streak.'
              : 'Practise on two days running to start a streak.'}
        </div>
      </div>
      {days > 0 && <StreakBadge days={days} />}
      {streak.freezes > 0 && <Freezes count={streak.freezes} />}
    </div>
  );
}

/**
 * The top of the Progress tab: the level and the points towards the next,
 * today's goal as a ring, the streak and its freezes, a week of points
 * as bars, and the badges, won and still to win.
 */
export function LearnProgressCard({ reading }: { reading: ReadingStore }) {
  const progress = reading.progress;
  const streak = reading.streak;
  const today = reading.today;
  const days = streak.currentOn(today);
  const earnedToday = progress.xpOn(today);
  const goal = progress.goal;

  return (
    <div class="ow-progress-card">
      <div class="ow-progress-card__top">
        <button type="button" class="ow-progress-card__ring m3-interactive" data-key="goal" aria-label="Daily goal" onClick={() => showDailyGoalSheet(reading)}>
          <GoalRing value={earnedToday / goal.xp} size={92} stroke={8}>
            <span class="ow-progress-card__earned">{earnedToday}</span>
            <span class="m3-label-small ow-muted">of {goal.xp} XP</span>
          </GoalRing>
        </button>
        <div class="ow-progress-card__summary">
          <div class="m3-title-medium">
            {progress.goalMetOn(today)
              ? 'Today’s goal met'
              : earnedToday === 0
                ? `Today’s goal: ${goal.label.toLowerCase()}`
                : `${goal.xp - earnedToday} XP to go today`}
          </div>
          <div class="ow-progress-card__chips">
            <LevelChip progress={progress} />
            {days > 0 && <StreakBadge days={days} />}
            {streak.freezes > 0 && (
              <Freezes
                count={streak.freezes}
                title={
                  streak.freezes === 1
                    ? 'One streak freeze: a missed day is forgiven'
                    : `${streak.freezes} streak freezes: two missed days are forgiven`
                }
              />
            )}
          </div>
          <div class="m3-body-small ow-muted">{streakLine(streak, today)}</div>
        </div>
      </div>
      <LevelBar progress={progress} />
      <WeekBars progress={progress} today={today} />
      <BadgeStrip progress={progress} reading={reading} />
    </div>
  );
}

export function streakLine(streak: Streak, today: Date): string {
  if (streak.practisedOn(today)) return 'Practised today.';
  if (streak.frozenOn(today)) {
    return 'A freeze is holding your streak: practise today to keep it.';
  }
  if (streak.currentOn(today) > 0) return 'Practise today to keep it going.';
  if (streak.best > 0) {
    return `Best streak: ${streak.best} ${streak.best === 1 ? 'day' : 'days'}. Practise today to start another.`;
  }
  return 'Practise on two days running to start a streak.';
}

function LevelChip({ progress }: { progress: LearnProgress }) {
  return (
    <span class="ow-level-chip m3-label-large">
      <Icon name="star" size={18} />
      Level {progress.level}
    </span>
  );
}

/** Points through the level, and how many to the next. */
function LevelBar({ progress }: { progress: LearnProgress }) {
  return (
    <div class="ow-level-bar">
      <LinearProgress value={progress.levelFraction} height={8} />
      <div class="m3-label-small ow-muted">
        {progress.xp} XP · {progress.nextLevelAt - progress.xp} to level {progress.level + 1}
      </div>
    </div>
  );
}

const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/**
 * The last seven days' points as bars, today's labelled, the goal as a
 * faint line across them.
 */
function WeekBars({ progress, today }: { progress: LearnProgress; today: Date }) {
  const points = progress.lastDays(today, 7);
  const goal = progress.goal.xp;
  const top = Math.max(goal, ...points);
  const height = 56;
  // The day letters under the bars take a fixed band, so that the bars'
  // own height is known and the goal line can sit where it should.
  const labelBand = 22;
  return (
    <div class="ow-week" role="img" aria-label={`Points this week: ${points.join(', ')}; goal ${goal} a day`}>
      <div class="m3-label-large">This week</div>
      <div class="ow-week__chart" style={`height:${height + labelBand}px`}>
        {/* The goal, a hairline the bars reach for. */}
        <div class="ow-week__goal" style={`top:${height - height * (goal / top)}px`} />
        <div class="ow-week__bars">
          {points.map((earned, i) => {
            const day = new Date(today.getTime() - (6 - i) * millisPerDay);
            const bar = earned === 0 ? 3 : Math.min(Math.max((height * earned) / top, 4), height);
            const tone = earned >= goal ? 'met' : earned === 0 ? 'none' : 'some';
            return (
              <div class="ow-week__day">
                <div class={`ow-week__bar ow-week__bar--${tone}`} style={`height:${bar}px`} />
                <div class={`ow-week__letter m3-label-small${i === 6 ? ' ow-week__letter--today' : ''}`} style={`height:${labelBand}px`}>
                  {dayLetters[(day.getDay() + 6) % 7]}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

/**
 * The badges in a row, the won ones in colour, with the count; tap for
 * the whole list.
 */
function BadgeStrip({ progress, reading }: { progress: LearnProgress; reading: ReadingStore }) {
  const won = progress.badges.size;
  return (
    <button type="button" class="ow-badge-strip m3-interactive" data-key="badges" onClick={() => showAchievementsSheet(reading)}>
      <span class="ow-badge-strip__head">
        <span class="m3-label-large">
          Badges · {won} of {Achievement.values.length}
        </span>
        <Icon name="chevron_right" class="ow-muted" />
      </span>
      <span class="ow-badge-strip__icons">
        {Achievement.values.map((achievement) => (
          <AchievementIcon key={achievement.id} achievement={achievement} won={progress.badges.has(achievement.id)} size={32} />
        ))}
      </span>
    </button>
  );
}

const achievementIcons: Record<string, string> = {
  [Achievement.firstStep.id]: 'flag',
  [Achievement.weekOfFire.id]: 'local_fire_department',
  [Achievement.monthOfFire.id]: 'whatshot',
  [Achievement.gathering.id]: 'library_books',
  [Achievement.byHeart.id]: 'favorite',
  [Achievement.fiveByHeart.id]: 'volunteer_activism',
  [Achievement.perfectRound.id]: 'workspace_premium',
  [Achievement.scribe.id]: 'edit',
  [Achievement.goodEar.id]: 'hearing',
  [Achievement.hundred.id]: 'military_tech',
  [Achievement.goalWeek.id]: 'event_available',
  [Achievement.levelFive.id]: 'star',
};

/** The icon a badge is drawn with. */
export function achievementIconFor(achievement: Achievement): string {
  return achievementIcons[achievement.id] ?? 'star';
}

/** A badge as a round icon: in colour when won, faint when not. */
export function AchievementIcon({ achievement, won, size = 40 }: { achievement: Achievement; won: boolean; size?: number }) {
  return (
    <span
      class={`ow-achievement${won ? ' ow-achievement--won' : ''}`}
      style={`width:${size}px;height:${size}px`}
      title={achievement.title}
      role="img"
      aria-label={`${achievement.title}${won ? ', won' : ''}`}
    >
      <Icon name={achievementIconFor(achievement)} size={size * 0.55} />
    </span>
  );
}

/** Choosing how much a day asks for. */
export function showDailyGoalSheet(reading: ReadingStore): Promise<void> {
  return showSheet<void>(<DailyGoalSheet reading={reading} />, { name: 'daily-goal' }).then(() => undefined);
}

function DailyGoalSheet({ reading }: { reading: ReadingStore }) {
  useNotifier(reading);
  const overlay = useOverlay();
  const current = reading.progress.goal;
  return (
    <Sheet title="Daily goal">
      <p class="ow-sheet-lead">
        A verse answered right is worth 10 XP and more as it climbs; a question, 5. The smallest goal is meant to be
        kept.
      </p>
      <div role="radiogroup">
        {DailyGoal.values.map((goal) => (
          <RadioListTile
            key={goal.name}
            checked={goal === current}
            title={`${goal.label} · ${goal.xp} XP`}
            subtitle={goal.description}
            onSelect={() => {
              reading.setDailyGoal(goal);
              overlay.close();
            }}
          />
        ))}
      </div>
    </Sheet>
  );
}

/** Every badge, with what wins it and when it was won. */
export function showAchievementsSheet(reading: ReadingStore): Promise<void> {
  return showSheet<void>(<AchievementsSheet reading={reading} />, { name: 'badges' }).then(() => undefined);
}

function AchievementsSheet({ reading }: { reading: ReadingStore }) {
  const badges = reading.progress.badges;
  return (
    <Sheet title={`Badges · ${badges.size} of ${Achievement.values.length}`}>
      {Achievement.values.map((achievement) => {
        const day = badges.get(achievement.id);
        return (
          <ListTile
            key={achievement.id}
            static
            leading={<AchievementIcon achievement={achievement} won={day !== undefined} />}
            title={achievement.title}
            subtitle={day === undefined ? achievement.description : `${achievement.description} Won ${dateLabel(day)}.`}
          />
        );
      })}
    </Sheet>
  );
}

const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/** "28 September 2026", of a date kept as `LocalDate.only` keeps it. */
export function dateLabel(day: Date): string {
  return `${day.getUTCDate()} ${months[day.getUTCMonth()]} ${day.getUTCFullYear()}`;
}
