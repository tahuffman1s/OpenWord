import type { LearnProgress } from './learnProgress';

export interface AchievementContext {
  progress: LearnProgress;
  streak: number;
  versesOnLadder: number;
  versesLearnt: number;
  today: Date;
}

/**
 * Badges, each won once and kept.
 *
 * They mark the things worth marking — the first step, a week kept up,
 * a verse known after a month away — and nothing is lost by not having
 * one. Each knows how to tell whether it has been earned.
 */
export class Achievement {
  static readonly firstStep = new Achievement('first_step', 'First step', 'Earned your first points.', (c) => c.progress.xp > 0);
  static readonly weekOfFire = new Achievement('week_of_fire', 'Week of fire', 'A seven-day streak.', (c) => c.streak >= 7);
  static readonly monthOfFire = new Achievement('month_of_fire', 'Month of fire', 'A thirty-day streak.', (c) => c.streak >= 30);
  static readonly gathering = new Achievement('gathering', 'Gathering', 'Ten verses on the ladder at once.', (c) => c.versesOnLadder >= 10);
  static readonly byHeart = new Achievement('by_heart', 'By heart', 'A verse recalled after a month away.', (c) => c.versesLearnt >= 1);
  static readonly fiveByHeart = new Achievement('five_by_heart', 'Five by heart', 'Five verses learnt.', (c) => c.versesLearnt >= 5);
  static readonly perfectRound = new Achievement('perfect_round', 'Perfect round', 'Every answer in a round right.', (c) => c.progress.perfectRounds >= 1);
  static readonly scribe = new Achievement('scribe', 'Scribe', 'A verse written out right.', (c) => c.progress.scribed >= 1);
  static readonly goodEar = new Achievement('good_ear', 'Good ear', 'A verse put together from hearing it.', (c) => c.progress.heard >= 1);
  static readonly hundred = new Achievement('hundred', 'Hundred', 'A hundred right answers.', (c) => c.progress.right >= 100);
  static readonly goalWeek = new Achievement('goal_week', 'Goal week', 'The daily goal met seven days running.', (c) => c.progress.goalDaysRunningOn(c.today) >= 7);
  static readonly levelFive = new Achievement('level_five', 'Fifth level', 'Reached level five.', (c) => c.progress.level >= 5);

  /** Every badge, in the order they are shown. */
  static readonly values: readonly Achievement[] = [
    Achievement.firstStep,
    Achievement.weekOfFire,
    Achievement.monthOfFire,
    Achievement.gathering,
    Achievement.byHeart,
    Achievement.fiveByHeart,
    Achievement.perfectRound,
    Achievement.scribe,
    Achievement.goodEar,
    Achievement.hundred,
    Achievement.goalWeek,
    Achievement.levelFive,
  ];

  private constructor(
    readonly id: string,
    readonly title: string,
    readonly description: string,
    private readonly condition: (context: AchievementContext) => boolean,
  ) {}

  static byId(id: string): Achievement | null {
    for (const achievement of Achievement.values) {
      if (achievement.id === id) return achievement;
    }
    return null;
  }

  /** Whether this badge's condition holds. */
  earnedBy(context: AchievementContext): boolean {
    return this.condition(context);
  }
}
