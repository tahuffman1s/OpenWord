import 'package:flutter/material.dart';

import '../data/marks.dart';
import '../model/bible.dart';
import '../model/memory_verse.dart';
import '../model/quiz.dart';
import '../model/suggested_verses.dart';
import 'learn_progress_card.dart';
import 'memory_screen.dart';
import 'quiz_screen.dart';

/// The Learn tab: one thing to do today, up top, and under it the verses
/// being learnt, with suggestions when there are none, and the rounds to
/// test yourself with.
///
/// Pops the library with a reference when a verse or passage is opened
/// in the reader from any screen it leads to.
class LearnTab extends StatelessWidget {
  const LearnTab({super.key, required this.reading, required this.bible});

  final ReadingStore reading;
  final Bible? bible;

  /// Questions in a lesson's round: enough to count, short enough to do.
  static const int lessonQuestions = 5;

  Future<void> _open(BuildContext context, Widget screen) async {
    final reference = await Navigator.of(context)
        .push<Reference>(MaterialPageRoute(builder: (_) => screen));
    if (reference != null && context.mounted) {
      Navigator.of(context).pop(reference);
    }
  }

  /// Today's lesson: the verses due, then a short round.
  Future<void> _startLesson(BuildContext context) async {
    final navigator = Navigator.of(context);
    Reference? opened;
    if (reading.memoryDue.isNotEmpty) {
      opened = await navigator.push<Reference>(
        MaterialPageRoute(builder: (_) => const MemoryScreen()),
      );
    }
    if (opened == null && context.mounted) {
      opened = await navigator.push<Reference>(
        MaterialPageRoute(
          builder: (_) =>
              const QuizScreen(kind: QuizKind.mixed, count: lessonQuestions),
        ),
      );
    }
    if (opened != null && context.mounted) navigator.pop(opened);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = reading.today;
    final verses = reading.memoryVerses;
    final due = reading.memoryDue.length;
    final ordered = [...verses]
      ..sort((a, b) {
        final byDue = a.due.compareTo(b.due);
        return byDue != 0 ? byDue : a.added.compareTo(b.added);
      });
    final suggestions = bible == null
        ? const <SuggestedVerse>[]
        : SuggestedVerse.available(
            bible!,
            alreadyLearning: reading.isMemorising,
          );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        GoalStrip(reading: reading),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: _LessonCard(
            due: due,
            goalMet: reading.progress.goalMetOn(today),
            onStart: bible == null ? null : () => _startLesson(context),
          ),
        ),
        _Header(
          'Verses you’re learning',
          trailing: suggestions.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () =>
                      showSuggestionsSheet(context, reading, suggestions),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add'),
                ),
        ),
        if (verses.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Nothing yet. Tap a verse while reading and choose '
              'Memorise, or start with one of these.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final suggestion in suggestions.take(3))
            _SuggestionTile(
              suggestion: suggestion,
              text: _textOf(suggestion.reference),
              onAdd: () => _add(context, suggestion.reference),
            ),
        ] else ...[
          for (final verse in ordered)
            _VerseTile(
              verse: verse,
              text: _textOf(verse.reference),
              today: today,
              onTap: () => _open(context, MemoryScreen(first: verse.reference)),
              onRemove: () {
                reading.removeMemory(verse.reference);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'No longer memorising ${verse.reference.label}',
                    ),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => reading.restoreMemory(verse),
                    ),
                  ),
                );
              },
            ),
        ],
        const _Header('Quiz yourself'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in QuizKind.values)
                ActionChip(
                  avatar: Icon(_iconFor(kind), size: 18),
                  label: Text(kind.label),
                  tooltip: kind.description,
                  onPressed: bible == null
                      ? null
                      : () => _open(context, QuizScreen(kind: kind)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _add(BuildContext context, Reference reference) {
    if (reading.toggleMemorise(reference)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Memorising ${reference.label}')));
    }
  }

  String _textOf(Reference reference) {
    final verse = reference.verse;
    if (bible == null || verse == null) return '';
    return bible!
            .bookByCode(reference.bookCode)
            ?.chapter(reference.chapter)
            ?.verseText(verse) ??
        '';
  }

  static IconData _iconFor(QuizKind kind) => switch (kind) {
    QuizKind.whichBook => Icons.auto_stories_rounded,
    QuizKind.finishVerse => Icons.short_text_rounded,
    QuizKind.bookOrder => Icons.format_list_numbered_rounded,
    QuizKind.mixed => Icons.shuffle_rounded,
  };
}

/// The one thing to do: today's lesson, with what it holds and about how
/// long it takes.
class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.due,
    required this.goalMet,
    required this.onStart,
  });

  final int due;
  final bool goalMet;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parts = [
      if (due > 0) due == 1 ? '1 verse due' : '$due verses due',
      '${LearnTab.lessonQuestions} questions',
    ];
    final minutes = ((due * 20 + LearnTab.lessonQuestions * 10) / 60).ceil();
    return Container(
      key: const Key('lesson'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.play_lesson_rounded, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  goalMet ? 'Another lesson?' : 'Today’s lesson',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${parts.join(' · ')} · about $minutes '
            '${minutes == 1 ? 'minute' : 'minutes'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(goalMet ? 'Keep going' : 'Start'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}

class _VerseTile extends StatelessWidget {
  const _VerseTile({
    required this.verse,
    required this.text,
    required this.today,
    required this.onTap,
    required this.onRemove,
  });

  final MemoryVerse verse;
  final String text;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final due = verse.isDueOn(today);
    return Dismissible(
      key: ValueKey('memory/${verse.key}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_rounded, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => onRemove(),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Icon(
            verse.isLearnt ? Icons.verified_rounded : Icons.psychology_rounded,
            color: due ? scheme.primary : scheme.onSurfaceVariant,
          ),
          title: Text(verse.reference.label),
          subtitle: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(
            memoryDueLabel(verse, today),
            style: theme.textTheme.labelMedium?.copyWith(
              color: due ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.text,
    required this.onAdd,
  });

  final SuggestedVerse suggestion;
  final String text;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Icon(
          Icons.auto_awesome_rounded,
          color: theme.colorScheme.tertiary,
        ),
        title: Text('${suggestion.reference.label} · ${suggestion.theme}'),
        subtitle: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: FilledButton.tonal(
          onPressed: onAdd,
          child: const Text('Add'),
        ),
      ),
    );
  }
}

/// Every suggestion this translation has, grouped by what it is for,
/// each a tap from the ladder.
Future<void> showSuggestionsSheet(
  BuildContext context,
  ReadingStore reading,
  List<SuggestedVerse> suggestions,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, controller) => AnimatedBuilder(
          animation: reading,
          builder: (context, _) {
            final theme = Theme.of(context);
            final themes = <String, List<SuggestedVerse>>{};
            for (final suggestion in suggestions) {
              themes.putIfAbsent(suggestion.theme, () => []).add(suggestion);
            }
            return ListView(
              controller: controller,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                  child: Text(
                    'Verses worth knowing',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    'Tap one to start learning it. Any verse can be added '
                    'from its sheet while reading.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final entry in themes.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Text(
                      entry.key,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  for (final suggestion in entry.value)
                    CheckboxListTile(
                      value: reading.isMemorising(suggestion.reference),
                      title: Text(suggestion.reference.label),
                      controlAffinity: ListTileControlAffinity.trailing,
                      onChanged: (_) =>
                          reading.toggleMemorise(suggestion.reference),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}
