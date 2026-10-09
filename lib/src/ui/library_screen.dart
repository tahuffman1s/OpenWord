import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/marks.dart';
import '../model/bible.dart';
import 'learn_progress_card.dart';
import 'learn_tab.dart';
import 'theme.dart';

/// Learning first, then the rest: a Learn tab with today's lesson, the
/// verses being learnt and the rounds; a Progress tab with the level,
/// the week and the badges; and Saved, where bookmarks, highlights,
/// notes and the chapters read lately live. Returns the chosen
/// reference.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, this.initialTab = 0});

  /// The tab to open on: Learn, Progress or Saved.
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final reading = scope.reading;
    final bible = scope.library.bible;

    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Learn', icon: Icon(Icons.school_rounded)),
              Tab(text: 'Progress', icon: Icon(Icons.insights_rounded)),
              Tab(text: 'Saved', icon: Icon(Icons.bookmarks_rounded)),
            ],
          ),
        ),
        body: AnimatedBuilder(
          animation: reading,
          builder: (context, _) => TabBarView(
            children: [
              LearnTab(reading: reading, bible: bible),
              _ProgressTab(reading: reading),
              _SavedTab(reading: reading, bible: bible),
            ],
          ),
        ),
      ),
    );
  }
}

/// Level, the week, badges, and the numbers behind them.
class _ProgressTab extends StatelessWidget {
  const _ProgressTab({required this.reading});

  final ReadingStore reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = reading.progress;
    final streak = reading.streak;
    final stats = <(String, String)>[
      ('Points', '${progress.xp} XP'),
      ('Level', '${progress.level}'),
      ('Verses learning', '${reading.memoryVerses.length}'),
      ('Verses learnt', '${reading.versesLearnt}'),
      ('Right answers', '${progress.right}'),
      ('Best streak', '${streak.best} ${streak.best == 1 ? 'day' : 'days'}'),
      ('Perfect rounds', '${progress.perfectRounds}'),
      ('Streak freezes', '${streak.freezes}'),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        LearnProgressCard(reading: reading),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('In numbers', style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final (label, value) in stats)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        value,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _Saved { bookmarks, highlights, notes, recent }

/// Bookmarks, highlights, notes and recent chapters behind one row of
/// choices, one list at a time.
class _SavedTab extends StatefulWidget {
  const _SavedTab({required this.reading, required this.bible});

  final ReadingStore reading;
  final Bible? bible;

  @override
  State<_SavedTab> createState() => _SavedTabState();
}

class _SavedTabState extends State<_SavedTab> {
  _Saved _showing = _Saved.bookmarks;

  @override
  Widget build(BuildContext context) {
    final reading = widget.reading;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<_Saved>(
              segments: const [
                ButtonSegment(
                  value: _Saved.bookmarks,
                  label: Text('Bookmarks'),
                  icon: Icon(Icons.bookmark_rounded),
                ),
                ButtonSegment(
                  value: _Saved.highlights,
                  label: Text('Highlights'),
                  icon: Icon(Icons.format_color_fill_rounded),
                ),
                ButtonSegment(
                  value: _Saved.notes,
                  label: Text('Notes'),
                  icon: Icon(Icons.sticky_note_2_rounded),
                ),
                ButtonSegment(
                  value: _Saved.recent,
                  label: Text('Recent'),
                  icon: Icon(Icons.history_rounded),
                ),
              ],
              selected: {_showing},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _showing = selection.first),
            ),
          ),
        ),
        Expanded(
          child: switch (_showing) {
            _Saved.bookmarks => _MarkList(
              marks: reading.bookmarks,
              bible: widget.bible,
              reading: reading,
              emptyMessage: 'Tap a verse while reading to bookmark it.',
            ),
            _Saved.highlights => _MarkList(
              marks: reading.highlights,
              bible: widget.bible,
              reading: reading,
              emptyMessage: 'Tap a verse and pick a colour to highlight it.',
            ),
            _Saved.notes => _MarkList(
              marks: reading.notes,
              bible: widget.bible,
              reading: reading,
              emptyMessage: 'Tap a verse and choose Add note.',
              showNotesFirst: true,
            ),
            _Saved.recent => _RecentList(reading: reading),
          },
        ),
      ],
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
