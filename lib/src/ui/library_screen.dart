import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/marks.dart';
import '../model/bible.dart';
import '../model/memory_verse.dart';
import '../model/quiz.dart';
import 'memory_screen.dart';
import 'quiz_screen.dart';
import 'theme.dart';

/// Everything the reader has saved: bookmarks, highlights, notes, what
/// they are learning and the chapters they have been in lately. Returns
/// the chosen reference.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final reading = scope.reading;
    final bible = scope.library.bible;

    return DefaultTabController(
      length: 5,
      // Learn first when something is due, so the dot on the library
      // button leads somewhere.
      initialIndex: reading.hasMemoryDue ? 3 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My library'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Bookmarks'),
              Tab(text: 'Highlights'),
              Tab(text: 'Notes'),
              Tab(text: 'Learn'),
              Tab(text: 'Recent'),
            ],
          ),
        ),
        body: AnimatedBuilder(
          animation: reading,
          builder: (context, _) => TabBarView(
            children: [
              _MarkList(
                marks: reading.bookmarks,
                bible: bible,
                reading: reading,
                emptyMessage: 'Tap a verse while reading to bookmark it.',
              ),
              _MarkList(
                marks: reading.highlights,
                bible: bible,
                reading: reading,
                emptyMessage: 'Tap a verse and pick a colour to highlight it.',
              ),
              _MarkList(
                marks: reading.notes,
                bible: bible,
                reading: reading,
                emptyMessage: 'Tap a verse and choose Add note.',
                showNotesFirst: true,
              ),
              _LearnTab(reading: reading, bible: bible),
              _RecentList(reading: reading),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkList extends StatelessWidget {
  const _MarkList({
    required this.marks,
    required this.bible,
    required this.reading,
    required this.emptyMessage,
    this.showNotesFirst = false,
  });

  final List<Mark> marks;
  final Bible? bible;
  final ReadingStore reading;
  final String emptyMessage;
  final bool showNotesFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (marks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: marks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final mark = marks[index];
        final verseText = _verseText(mark);
        final subtitle = showNotesFirst && mark.hasNote
            ? mark.note
            : (verseText.isEmpty ? mark.note : verseText);
        return Dismissible(
          key: ValueKey(mark.key),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: theme.colorScheme.errorContainer,
            child: Icon(
              Icons.delete_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          onDismissed: (_) {
            reading.remove(mark.reference);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Removed ${mark.reference.label}')),
            );
          },
          // Its own Material, so the tap highlight scrolls with the row
          // instead of being drawn on the screen behind the list.
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: _leading(theme, mark),
              title: Text(mark.reference.label),
              subtitle: Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: mark.hasNote && !showNotesFirst
                  ? const Icon(Icons.sticky_note_2_outlined, size: 18)
                  : null,
              onTap: () => Navigator.of(context).pop(mark.reference),
            ),
          ),
        );
      },
    );
  }

  Widget _leading(ThemeData theme, Mark mark) {
    if (mark.highlighted) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppTheme.highlightSwatch(mark.colorIndex!),
          shape: BoxShape.circle,
        ),
      );
    }
    return Icon(
      mark.bookmarked ? Icons.bookmark_rounded : Icons.sticky_note_2_rounded,
      color: theme.colorScheme.primary,
    );
  }

  String _verseText(Mark mark) {
    final verse = mark.reference.verse;
    if (bible == null || verse == null) return '';
    return bible!
            .bookByCode(mark.reference.bookCode)
            ?.chapter(mark.reference.chapter)
            ?.verseText(verse) ??
        '';
  }
}

/// Learning: a round of questions to test yourself with, and the verses
/// being learnt by heart, the due ones first, with a button to practise
/// what is due. Tapping a verse practises it, due or not.
class _LearnTab extends StatelessWidget {
  const _LearnTab({required this.reading, required this.bible});

  final ReadingStore reading;
  final Bible? bible;

  Future<void> _practise(BuildContext context, {Reference? first}) async {
    final reference = await Navigator.of(context).push<Reference>(
      MaterialPageRoute(builder: (_) => MemoryScreen(first: first)),
    );
    if (reference != null && context.mounted) {
      Navigator.of(context).pop(reference);
    }
  }

  Future<void> _quiz(BuildContext context, QuizKind kind) async {
    final reference = await Navigator.of(context).push<Reference>(
      MaterialPageRoute(builder: (_) => QuizScreen(kind: kind)),
    );
    if (reference != null && context.mounted) {
      Navigator.of(context).pop(reference);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verses = reading.memoryVerses;
    final today = reading.today;
    final due = reading.memoryDue.length;
    final ordered = [...verses]
      ..sort((a, b) {
        final byDue = a.due.compareTo(b.due);
        return byDue != 0 ? byDue : a.added.compareTo(b.added);
      });

    final streak = reading.streak;
    final days = streak.currentOn(today);
    final streakLine = streak.practisedOn(today)
        ? 'Practised today.'
        : days > 0
        ? 'Practise today to keep it going.'
        : streak.best > 0
        ? 'Practise today to start a new streak. Best so far: '
              '${streak.best} ${streak.best == 1 ? 'day' : 'days'}.'
        : 'Practise on two days running to start a streak.';

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              if (days > 0) ...[
                StreakBadge(days: days),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  streakLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Test yourself', style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Ten questions drawn from the translation you are reading, '
            'never the same round twice.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final kind in QuizKind.values)
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: Icon(switch (kind) {
                QuizKind.whichBook => Icons.auto_stories_rounded,
                QuizKind.finishVerse => Icons.short_text_rounded,
                QuizKind.bookOrder => Icons.format_list_numbered_rounded,
                QuizKind.mixed => Icons.shuffle_rounded,
              }, color: theme.colorScheme.primary),
              title: Text(kind.label),
              subtitle: Text(kind.description),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: bible == null ? null : () => _quiz(context, kind),
            ),
          ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('Memory verses', style: theme.textTheme.titleMedium),
        ),
        if (verses.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Tap a verse and choose Memorise to learn it by heart. It is '
              'asked for today, then after a day, three days, a week, and '
              'longer each time you have it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    due == 0
                        ? 'Nothing due today'
                        : due == 1
                        ? '1 verse due today'
                        : '$due verses due today',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: due == 0 ? null : () => _practise(context),
                  icon: const Icon(Icons.psychology_rounded),
                  label: const Text('Practise'),
                ),
              ],
            ),
          ),
          for (final verse in ordered)
            Dismissible(
              key: ValueKey('memory/${verse.key}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                color: theme.colorScheme.errorContainer,
                child: Icon(
                  Icons.delete_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) {
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
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Icon(
                    verse.isLearnt
                        ? Icons.verified_rounded
                        : Icons.psychology_rounded,
                    color: verse.isDueOn(today)
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(verse.reference.label),
                  subtitle: Text(
                    _verseText(verse),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    memoryDueLabel(verse, today),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: verse.isDueOn(today)
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () => _practise(context, first: verse.reference),
                ),
              ),
            ),
        ],
      ],
    );
  }

  String _verseText(MemoryVerse verse) {
    final reference = verse.reference;
    if (bible == null || reference.verse == null) return '';
    return bible!
            .bookByCode(reference.bookCode)
            ?.chapter(reference.chapter)
            ?.verseText(reference.verse!) ??
        '';
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.reading});

  final ReadingStore reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = reading.history;
    if (history.isEmpty) {
      return Center(
        child: Text(
          'Chapters you read will show up here.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final reference in history)
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(reference.label),
              onTap: () => Navigator.of(context).pop(reference),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: reading.clearHistory,
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Clear history'),
          ),
        ),
      ],
    );
  }
}
