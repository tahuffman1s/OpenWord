import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/marks.dart';
import '../model/bible.dart';
import 'theme.dart';

/// Everything the reader has saved: bookmarks, highlights, notes and the
/// chapters they have been in lately. Returns the chosen reference.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final reading = scope.reading;
    final bible = scope.library.bible;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My library'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Bookmarks'),
              Tab(text: 'Highlights'),
              Tab(text: 'Notes'),
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
