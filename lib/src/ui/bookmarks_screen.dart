import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/bookmarks.dart';
import '../model/bible.dart';

/// Saved verses, newest first. Returns the chosen [Reference] to the reader.
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final reading = scope.reading;
    final bible = scope.library.bible;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks'),
        actions: [
          AnimatedBuilder(
            animation: reading,
            builder: (context, _) => reading.bookmarks.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Remove all',
                    icon: const Icon(Icons.delete_sweep_rounded),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Remove all bookmarks?'),
                          content: const Text('This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: const Text('Remove all'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed ?? false) reading.clearBookmarks();
                    },
                  ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: reading,
        builder: (context, _) {
          final bookmarks = reading.bookmarks;
          final history = reading.history;
          if (bookmarks.isEmpty && history.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Tap a verse while reading to bookmark it.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (history.isNotEmpty) ...[
                _SectionHeader(title: 'Recently read'),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final reference in history)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(reference.label),
                            onPressed: () =>
                                Navigator.of(context).pop(reference),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (bookmarks.isNotEmpty) _SectionHeader(title: 'Bookmarks'),
              for (final bookmark in bookmarks)
                Dismissible(
                  key: ValueKey(bookmark.key),
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
                  onDismissed: (_) => reading.remove(bookmark),
                  child: ListTile(
                    leading: Icon(
                      Icons.bookmark_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(bookmark.reference.label),
                    subtitle: Text(
                      bookmark.note.isNotEmpty
                          ? bookmark.note
                          : _preview(bible, bookmark),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Note',
                      icon: Icon(
                        bookmark.note.isEmpty
                            ? Icons.note_add_outlined
                            : Icons.edit_note_rounded,
                      ),
                      onPressed: () => _editNote(context, reading, bookmark),
                    ),
                    onTap: () => Navigator.of(context).pop(bookmark.reference),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _preview(Bible? bible, Bookmark bookmark) {
    final verse = bookmark.reference.verse;
    if (bible == null || verse == null) return '';
    final chapter = bible
        .bookByCode(bookmark.reference.bookCode)
        ?.chapter(bookmark.reference.chapter);
    return chapter?.verseText(verse) ?? '';
  }

  static Future<void> _editNote(
    BuildContext context,
    ReadingStore reading,
    Bookmark bookmark,
  ) async {
    final controller = TextEditingController(text: bookmark.note);
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(bookmark.reference.label),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Your note',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;
    reading.update(bookmark.copyWith(note: note));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
