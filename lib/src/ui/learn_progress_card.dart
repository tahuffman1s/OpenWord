import 'package:flutter/material.dart';

import '../data/marks.dart';
import '../model/achievements.dart';
import '../model/learn_progress.dart';
import '../model/streak.dart';
import 'memory_screen.dart' show StreakBadge;

/// A single row for the top of the Learn tab: today's goal as a small
/// ring, how far it is, the streak and its freezes.
class GoalStrip extends StatelessWidget {
  const GoalStrip({super.key, required this.reading});

  final ReadingStore reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = reading.progress;
    final streak = reading.streak;
    final today = reading.today;
    final days = streak.currentOn(today);
    final earned = progress.xpOn(today);
    final goal = progress.goal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          InkWell(
            key: const Key('goal/strip'),
            borderRadius: BorderRadius.circular(32),
            onTap: () => showDailyGoalSheet(context, reading),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: (earned / goal.xp).clamp(0.0, 1.0),
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  Icon(
                    progress.goalMetOn(today)
                        ? Icons.check_rounded
                        : Icons.bolt_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  progress.goalMetOn(today)
                      ? 'Today’s goal met'
                      : '$earned of ${goal.xp} XP today',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  streak.practisedOn(today)
                      ? 'Practised today.'
                      : days > 0
                      ? 'Practise today to keep your streak.'
                      : 'Practise on two days running to start a streak.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (days > 0) StreakBadge(days: days),
          if (streak.freezes > 0) ...[
            const SizedBox(width: 6),
            for (var i = 0; i < streak.freezes; i++)
              Icon(Icons.ac_unit_rounded, size: 18, color: scheme.tertiary),
          ],
        ],
      ),
    );
  }
}

/// The top of the Progress tab: the level and the points towards the next,
/// today's goal as a ring, the streak and its freezes, a week of points
/// as bars, and the badges, won and still to win.
class LearnProgressCard extends StatelessWidget {
  const LearnProgressCard({super.key, required this.reading});

  final ReadingStore reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = reading.progress;
    final streak = reading.streak;
    final today = reading.today;
    final days = streak.currentOn(today);
    final earnedToday = progress.xpOn(today);
    final goal = progress.goal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Today's goal as a ring: full is the day done.
              InkWell(
                key: const Key('goal'),
                borderRadius: BorderRadius.circular(48),
                onTap: () => showDailyGoalSheet(context, reading),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: (earnedToday / goal.xp).clamp(0.0, 1.0),
                            strokeWidth: 8,
                            strokeCap: StrokeCap.round,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$earnedToday',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              'of ${goal.xp} XP',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.goalMetOn(today)
                          ? 'Today’s goal met'
                          : earnedToday == 0
                          ? 'Today’s goal: ${goal.label.toLowerCase()}'
                          : '${goal.xp - earnedToday} XP to go today',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _LevelChip(progress: progress),
                        if (days > 0) StreakBadge(days: days),
                        if (streak.freezes > 0)
                          Tooltip(
                            message: streak.freezes == 1
                                ? 'One streak freeze: a missed day is '
                                      'forgiven'
                                : '${streak.freezes} streak freezes: two '
                                      'missed days are forgiven',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < streak.freezes; i++)
                                  Icon(
                                    Icons.ac_unit_rounded,
                                    size: 18,
                                    color: scheme.tertiary,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _streakLine(streak, today),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LevelBar(progress: progress),
          const SizedBox(height: 14),
          _WeekBars(progress: progress, today: today),
          const SizedBox(height: 14),
          _BadgeStrip(progress: progress, reading: reading),
        ],
      ),
    );
  }

  static String _streakLine(Streak streak, DateTime today) {
    if (streak.practisedOn(today)) return 'Practised today.';
    if (streak.frozenOn(today)) {
      return 'A freeze is holding your streak: practise today to keep it.';
    }
    if (streak.currentOn(today) > 0) return 'Practise today to keep it going.';
    if (streak.best > 0) {
      return 'Best streak: ${streak.best} ${streak.best == 1 ? 'day' : 'days'}. '
          'Practise today to start another.';
    }
    return 'Practise on two days running to start a streak.';
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.progress});

  final LearnProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 18, color: scheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            'Level ${progress.level}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Points through the level, and how many to the next.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.progress});

  final LearnProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.levelFraction,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${progress.xp} XP · ${progress.nextLevelAt - progress.xp} to '
          'level ${progress.level + 1}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The last seven days' points as bars, today's labelled, the goal as a
/// faint line across them.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.progress, required this.today});

  final LearnProgress progress;
  final DateTime today;

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final points = progress.lastDays(today, 7);
    final goal = progress.goal.xp;
    final top = [goal, ...points].reduce((a, b) => a > b ? a : b).toDouble();
    const height = 56.0;
    // The day letters under the bars take a fixed band, so that the bars'
    // own height is known and the goal line can sit where it should.
    const labelBand = 22.0;
    return Semantics(
      label: 'Points this week: ${points.join(', ')}; goal $goal a day',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This week', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          SizedBox(
            height: height + labelBand,
            child: Stack(
              children: [
                // The goal, a hairline the bars reach for.
                Positioned(
                  left: 0,
                  right: 0,
                  top: height - height * (goal / top),
                  child: Container(height: 1, color: scheme.outlineVariant),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: points[i] == 0
                                    ? 3
                                    : (height * points[i] / top).clamp(
                                        4.0,
                                        height,
                                      ),
                                decoration: BoxDecoration(
                                  color: points[i] >= goal
                                      ? scheme.primary
                                      : points[i] == 0
                                      ? scheme.surfaceContainerHighest
                                      : scheme.primary.withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: labelBand,
                                child: Center(
                                  child: Text(
                                    _dayLetters[today
                                            .subtract(Duration(days: 6 - i))
                                            .weekday -
                                        1],
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: i == 6
                                          ? scheme.onSurface
                                          : scheme.onSurfaceVariant,
                                      fontWeight: i == 6
                                          ? FontWeight.w700
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The badges in a row, the won ones in colour, with the count; tap for
/// the whole list.
class _BadgeStrip extends StatelessWidget {
  const _BadgeStrip({required this.progress, required this.reading});

  final LearnProgress progress;
  final ReadingStore reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final won = progress.badges.length;
    return InkWell(
      key: const Key('badges'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => showAchievementsSheet(context, reading),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Badges · $won of ${Achievement.values.length}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final achievement in Achievement.values)
                  AchievementIcon(
                    achievement: achievement,
                    won: progress.badges.containsKey(achievement.id),
                    size: 32,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A badge as a round icon: in colour when won, faint when not.
class AchievementIcon extends StatelessWidget {
  const AchievementIcon({
    super.key,
    required this.achievement,
    required this.won,
    this.size = 40,
  });

  final Achievement achievement;
  final bool won;
  final double size;

  static IconData iconFor(Achievement achievement) => switch (achievement) {
    Achievement.firstStep => Icons.flag_rounded,
    Achievement.weekOfFire => Icons.local_fire_department_rounded,
    Achievement.monthOfFire => Icons.whatshot_rounded,
    Achievement.gathering => Icons.library_books_rounded,
    Achievement.byHeart => Icons.favorite_rounded,
    Achievement.fiveByHeart => Icons.volunteer_activism_rounded,
    Achievement.perfectRound => Icons.workspace_premium_rounded,
    Achievement.scribe => Icons.edit_rounded,
    Achievement.goodEar => Icons.hearing_rounded,
    Achievement.hundred => Icons.military_tech_rounded,
    Achievement.goalWeek => Icons.event_available_rounded,
    Achievement.levelFive => Icons.star_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: achievement.title,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: won
              ? scheme.tertiaryContainer
              : scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          iconFor(achievement),
          size: size * 0.55,
          color: won
              ? scheme.onTertiaryContainer
              : scheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// Choosing how much a day asks for.
Future<void> showDailyGoalSheet(BuildContext context, ReadingStore reading) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: AnimatedBuilder(
        animation: reading,
        builder: (context, _) {
          final theme = Theme.of(context);
          final current = reading.progress.goal;
          // Scrolls, for a short screen with the keyboard's worth taken.
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text('Daily goal', style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    'A verse answered right is worth 10 XP and more as it '
                    'climbs; a question, 5. The smallest goal is meant to be '
                    'kept.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                RadioGroup<DailyGoal>(
                  groupValue: current,
                  onChanged: (value) {
                    if (value != null) reading.setDailyGoal(value);
                    Navigator.of(sheetContext).pop();
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final goal in DailyGoal.values)
                        RadioListTile<DailyGoal>(
                          value: goal,
                          title: Text('${goal.label} · ${goal.xp} XP'),
                          subtitle: Text(goal.description),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// Every badge, with what wins it and when it was won.
Future<void> showAchievementsSheet(BuildContext context, ReadingStore reading) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final badges = reading.progress.badges;
      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Badges · ${badges.length} of ${Achievement.values.length}',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              for (final achievement in Achievement.values)
                ListTile(
                  leading: AchievementIcon(
                    achievement: achievement,
                    won: badges.containsKey(achievement.id),
                  ),
                  title: Text(achievement.title),
                  subtitle: Text(
                    badges[achievement.id] == null
                        ? achievement.description
                        : '${achievement.description} Won '
                              '${_dateLabel(badges[achievement.id]!)}.',
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

String _dateLabel(DateTime day) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${day.day} ${months[day.month - 1]} ${day.year}';
}
