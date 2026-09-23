import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/marks.dart';
import '../data/plan_progress.dart';
import '../model/bible.dart';
import '../model/reading_plan.dart';

/// A chapter to open, and the plan day it was opened from, so the reader
/// can offer to tick it off when the reader gets to the end.
class PlanReading {
  const PlanReading({
    required this.planId,
    required this.day,
    required this.chapter,
  });

  final String planId;
  final int day;
  final Reference chapter;
}

/// The reading plans: the ones under way, with today's reading on top,
/// and the ones that could be started. Returns a [PlanReading] to open.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final reading = scope.reading;
    final bible = scope.library.bible;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reading plans')),
      body: AnimatedBuilder(
        animation: reading,
        builder: (context, _) {
          final active = reading.plans;
          final activeIds = {for (final p in active) p.plan.id};
          final available = [
            for (final plan in ReadingPlans.all)
              if (!activeIds.contains(plan.id)) plan,
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (active.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
                  child: Text(
                    'Read a little every day. Pick a plan and it tells you '
                    'what to read next. Miss a day and it waits for you — '
                    'nothing piles up.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final progress in active)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ActivePlanCard(
                    progress: progress,
                    reading: reading,
                    bible: bible,
                  ),
                ),
              if (available.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text(
                    active.isEmpty ? 'Choose a plan' : 'Start another plan',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                for (final plan in available)
                  _PlanTile(
                    plan: plan,
                    // Pointed out only to someone who has not begun one.
                    recommend: active.isEmpty && plan.recommended,
                    onTap: () => _preview(context, plan, reading),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  static Future<void> _preview(
    BuildContext context,
    ReadingPlan plan,
    ReadingStore reading,
  ) async {
    final start = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PlanPreview(plan: plan),
    );
    if (start != true || !context.mounted) return;
    reading.startPlan(plan);
    final first = plan.days.first;
    Navigator.of(
      context,
    ).pop(PlanReading(planId: plan.id, day: 1, chapter: first.chapters.first));
  }
}

/// Whether [bible] has this chapter. A plan is built on the whole English
/// Bible, and an imported translation may be a New Testament, or lack the
/// odd chapter.
bool hasChapter(Bible? bible, Reference chapter) =>
    bible
        ?.bookByCode(chapter.bookCode)
        ?.chapterNumbers
        .contains(chapter.chapter) ??
    false;

/// "30 days · about 10 minutes a day"
String planMeta(ReadingPlan plan) =>
    '${plan.length} days · about ${plan.minutesPerDay} min a day';

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.recommend,
    required this.onTap,
  });

  final ReadingPlan plan;
  final bool recommend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recommend) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Good place to start',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(plan.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      plan.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      planMeta(plan),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a plan is and what its first days hold, with one button to start.
class _PlanPreview extends StatelessWidget {
  const _PlanPreview({required this.plan});

  final ReadingPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plan.name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              planMeta(plan),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(plan.description, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            for (final day in plan.days.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        'Day ${day.number}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(day.label, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            Text(
              '…and so on. Skip a day and it waits for you.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start today'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A plan under way: where the reader is, today's reading, and one button
/// that opens the next chapter to read.
class ActivePlanCard extends StatelessWidget {
  const ActivePlanCard({
    required this.progress,
    required this.reading,
    required this.bible,
    super.key,
  });

  final PlanProgress progress;
  final ReadingStore reading;
  final Bible? bible;

  ReadingPlan get plan => progress.plan;

  bool _has(Reference chapter) => hasChapter(bible, chapter);

  void _open(BuildContext context, PlanDay day, Reference chapter) {
    Navigator.of(context)
        .pop(PlanReading(planId: plan.id, day: day.number, chapter: chapter));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = reading.today;
    final day = progress.currentDay;
    final behind = progress.behindOn(today);
    final due = progress.hasReadingDueOn(today);

    return Card.filled(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(plan.name, style: theme.textTheme.titleMedium),
                ),
                _PlanMenu(progress: progress, reading: reading, bible: bible),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    day == null
                        ? 'All ${plan.length} days read'
                        : 'Day ${day.number} of ${plan.length}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (day == null)
                    ..._finished(context, theme)
                  else ...[
                    if (behind >= PlanProgress.behindThreshold)
                      _BehindNote(
                        days: behind,
                        onPickUp: () => reading.pickUpPlanToday(plan.id),
                      ),
                    Text(
                      due ? 'Today' : 'Done for today — next up',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final passage in day.passages)
                      _PassageRow(
                        passage: passage,
                        day: day,
                        progress: progress,
                        available: _has(passage.chapters.first),
                        onToggle: (read) =>
                            _setPassage(day, passage, read: read),
                        onOpen: () =>
                            _open(context, day, _firstUnread(day, passage)),
                      ),
                    const SizedBox(height: 12),
                    _continueButton(context, day, due),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _continueButton(BuildContext context, PlanDay day, bool due) {
    final slot = progress.nextSlot;
    if (slot == null) return const SizedBox.shrink();
    final chapter = progress.chapterAt(slot);
    final started = progress.readInDay(day) > 0;
    final label = !due
        ? 'Read ahead: ${Passage.labelFor(chapter)}'
        : started
        ? 'Continue: ${Passage.labelFor(chapter)}'
        : 'Start reading';
    return SizedBox(
      width: double.infinity,
      child: _has(chapter)
          ? (due
                ? FilledButton.icon(
                    onPressed: () => _open(context, day, chapter),
                    icon: const Icon(Icons.menu_book_rounded),
                    label: Text(label),
                  )
                : FilledButton.tonalIcon(
                    onPressed: () => _open(context, day, chapter),
                    icon: const Icon(Icons.menu_book_rounded),
                    label: Text(label),
                  ))
          : Text(
              '${Passage.labelFor(chapter)} is not in this translation. '
              'Tick it off when you have read it elsewhere.',
            ),
    );
  }

  List<Widget> _finished(BuildContext context, ThemeData theme) => [
    Text(
      'You read the whole plan. Well done.',
      style: theme.textTheme.bodyLarge,
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      children: [
        FilledButton.tonal(
          onPressed: () => reading.startPlan(plan),
          child: const Text('Read it again'),
        ),
        TextButton(
          onPressed: () => reading.stopPlan(plan.id),
          child: const Text('Remove'),
        ),
      ],
    ),
  ];

  Reference _firstUnread(PlanDay day, Passage passage) {
    for (var i = 0; i < day.chapters.length; i++) {
      final chapter = day.chapters[i];
      if (chapter.bookCode != passage.bookCode ||
          chapter.chapter < passage.firstChapter ||
          chapter.chapter > passage.lastChapter) {
        continue;
      }
      if (!progress.isRead(day.firstSlot + i)) return chapter;
    }
    return passage.chapters.first;
  }

  void _setPassage(PlanDay day, Passage passage, {required bool read}) {
    for (var i = 0; i < day.chapters.length; i++) {
      final chapter = day.chapters[i];
      if (chapter.bookCode == passage.bookCode &&
          chapter.chapter >= passage.firstChapter &&
          chapter.chapter <= passage.lastChapter) {
        reading.setPlanSlot(plan.id, day.firstSlot + i, read: read);
      }
    }
  }
}

/// One passage of a day: a tick to mark it, and its name to open it.
class _PassageRow extends StatelessWidget {
  const _PassageRow({
    required this.passage,
    required this.day,
    required this.progress,
    required this.available,
    required this.onToggle,
    required this.onOpen,
  });

  final Passage passage;
  final PlanDay day;
  final PlanProgress progress;
  final bool available;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var read = 0;
    var total = 0;
    for (var i = 0; i < day.chapters.length; i++) {
      final chapter = day.chapters[i];
      if (chapter.bookCode == passage.bookCode &&
          chapter.chapter >= passage.firstChapter &&
          chapter.chapter <= passage.lastChapter) {
        total++;
        if (progress.isRead(day.firstSlot + i)) read++;
      }
    }
    final done = read == total;
    return Row(
      children: [
        IconButton(
          tooltip: done ? 'Mark as not read' : 'Mark as read',
          onPressed: () => onToggle(!done),
          icon: Icon(
            done
                ? Icons.check_circle_rounded
                : read > 0
                ? Icons.timelapse_rounded
                : Icons.radio_button_unchecked_rounded,
            color: done
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: available ? onOpen : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Text(
                read > 0 && !done
                    ? '${passage.label}  ·  $read of $total read'
                    : passage.label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                  color: done || !available
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Said once the reader is two days or more behind, and never as a
/// reproach: the fix is one tap, and it marks nothing read.
class _BehindNote extends StatelessWidget {
  const _BehindNote({required this.days, required this.onPickUp});

  final int days;
  final VoidCallback onPickUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You are $days days behind the pace you started with. That is '
            'fine — the plan is waiting where you left it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onPickUp,
              child: const Text('Pick up from today'),
            ),
          ),
        ],
      ),
    );
  }
}

enum _MenuAction { allDays, pickUp, restart, remove }

class _PlanMenu extends StatelessWidget {
  const _PlanMenu({
    required this.progress,
    required this.reading,
    required this.bible,
  });

  final PlanProgress progress;
  final ReadingStore reading;
  final Bible? bible;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Plan options',
      onSelected: (action) => _act(context, action),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _MenuAction.allDays,
          child: ListTile(
            leading: Icon(Icons.calendar_view_day_rounded),
            title: Text('See every day'),
          ),
        ),
        if (progress.behindOn(reading.today) > 0)
          const PopupMenuItem(
            value: _MenuAction.pickUp,
            child: ListTile(
              leading: Icon(Icons.today_rounded),
              title: Text('Pick up from today'),
            ),
          ),
        const PopupMenuItem(
          value: _MenuAction.restart,
          child: ListTile(
            leading: Icon(Icons.restart_alt_rounded),
            title: Text('Start over'),
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.remove,
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded),
            title: Text('Remove plan'),
          ),
        ),
      ],
    );
  }

  Future<void> _act(BuildContext context, _MenuAction action) async {
    final plan = progress.plan;
    switch (action) {
      case _MenuAction.allDays:
        final chosen = await Navigator.of(context).push<PlanReading>(
          MaterialPageRoute(builder: (_) => PlanDaysScreen(planId: plan.id)),
        );
        if (chosen != null && context.mounted) {
          Navigator.of(context).pop(chosen);
        }
      case _MenuAction.pickUp:
        reading.pickUpPlanToday(plan.id);
      case _MenuAction.restart:
        if (await _confirm(
          context,
          title: 'Start ${plan.name} over?',
          body:
              'Every day is marked unread again and day 1 is today. '
              'Your bookmarks, highlights and notes are not touched.',
          action: 'Start over',
        )) {
          reading.startPlan(plan);
        }
      case _MenuAction.remove:
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final saved = progress;
        reading.stopPlan(plan.id);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Removed ${plan.name}'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => reading.restorePlan(saved),
            ),
          ),
        );
    }
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Every day of a plan, ticked or not, opened at the current day.
class PlanDaysScreen extends StatefulWidget {
  const PlanDaysScreen({required this.planId, super.key});

  final String planId;

  @override
  State<PlanDaysScreen> createState() => _PlanDaysScreenState();
}

class _PlanDaysScreenState extends State<PlanDaysScreen> {
  static const double _rowHeight = 72;
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final reading = scope.reading;
    final bible = scope.library.bible;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: reading,
      builder: (context, _) {
        final progress = reading.progressFor(widget.planId);
        if (progress == null) {
          return Scaffold(appBar: AppBar());
        }
        final plan = progress.plan;
        final current = progress.currentDay;
        _scroll ??= ScrollController(
          initialScrollOffset: current == null
              ? 0
              : ((current.number - 3).clamp(0, plan.length) * _rowHeight)
                    .toDouble(),
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(plan.name),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(24),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${progress.daysRead} of ${plan.length} days read',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          body: ListView.builder(
            controller: _scroll,
            itemExtent: _rowHeight,
            itemCount: plan.length,
            itemBuilder: (context, index) {
              final day = plan.days[index];
              final read = progress.readInDay(day);
              final done = read == day.slotCount;
              final isCurrent = day.number == current?.number;
              final first = day.chapters.first;
              return Material(
                color: isCurrent
                    ? theme.colorScheme.secondaryContainer
                    : Colors.transparent,
                child: ListTile(
                  leading: Checkbox(
                    value: done ? true : (read > 0 ? null : false),
                    tristate: true,
                    onChanged: (_) =>
                        reading.setPlanDay(plan.id, day, read: !done),
                  ),
                  title: Text(
                    isCurrent
                        ? 'Day ${day.number} · next'
                        : 'Day ${day.number}',
                  ),
                  subtitle: Text(
                    day.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: !hasChapter(bible, first)
                      ? null
                      : () {
                          var chapter = first;
                          for (var i = 0; i < day.slotCount; i++) {
                            if (!progress.isRead(day.firstSlot + i)) {
                              chapter = day.chapters[i];
                              break;
                            }
                          }
                          Navigator.of(context).pop(
                            PlanReading(
                              planId: plan.id,
                              day: day.number,
                              chapter: chapter,
                            ),
                          );
                        },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
