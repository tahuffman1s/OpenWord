import 'learn_progress.dart';

/// Badges, each won once and kept.
///
/// They mark the things worth marking — the first step, a week kept up,
/// a verse known after a month away — and nothing is lost by not having
/// one. Each knows how to tell whether it has been earned.
enum Achievement {
  firstStep('first_step', 'First step', 'Earned your first points.'),
  weekOfFire('week_of_fire', 'Week of fire', 'A seven-day streak.'),
  monthOfFire('month_of_fire', 'Month of fire', 'A thirty-day streak.'),
  gathering('gathering', 'Gathering', 'Ten verses on the ladder at once.'),
  byHeart('by_heart', 'By heart', 'A verse recalled after a month away.'),
  fiveByHeart('five_by_heart', 'Five by heart', 'Five verses learnt.'),
  perfectRound(
    'perfect_round',
    'Perfect round',
    'Every answer in a round right.',
  ),
  scribe('scribe', 'Scribe', 'A verse written out right.'),
  goodEar('good_ear', 'Good ear', 'A verse put together from hearing it.'),
  hundred('hundred', 'Hundred', 'A hundred right answers.'),
  goalWeek('goal_week', 'Goal week', 'The daily goal met seven days running.'),
  levelFive('level_five', 'Fifth level', 'Reached level five.');

  const Achievement(this.id, this.title, this.description);

  final String id;
  final String title;
  final String description;

  static Achievement? byId(String id) {
    for (final achievement in values) {
      if (achievement.id == id) return achievement;
    }
    return null;
  }

  /// Whether this badge's condition holds.
  bool earnedBy({
    required LearnProgress progress,
    required int streak,
    required int versesOnLadder,
    required int versesLearnt,
    required DateTime today,
  }) => switch (this) {
    firstStep => progress.xp > 0,
    weekOfFire => streak >= 7,
    monthOfFire => streak >= 30,
    gathering => versesOnLadder >= 10,
    byHeart => versesLearnt >= 1,
    fiveByHeart => versesLearnt >= 5,
    perfectRound => progress.perfectRounds >= 1,
    scribe => progress.scribed >= 1,
    goodEar => progress.heard >= 1,
    hundred => progress.right >= 100,
    goalWeek => progress.goalDaysRunningOn(today) >= 7,
    levelFive => progress.level >= 5,
  };
}
