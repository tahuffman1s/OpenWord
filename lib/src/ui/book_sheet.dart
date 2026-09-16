import 'package:flutter/material.dart';

import '../data/book_notes.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';

/// A short orientation for the book being read: where it sits in the canon,
/// how big it is, and a few lines of historical context.
void showBookSheet(BuildContext context, Book book) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _BookSheet(book: book),
  );
}

class _BookSheet extends StatelessWidget {
  const _BookSheet({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = bookNotes[book.code];
    final verses = book.chapters.fold<int>(
      0,
      (sum, chapter) => sum + chapter.verseCount,
    );

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(book.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '${book.meta.division.label} • ${book.section.label}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Fact(
                    label: book.chapterCount == 1 ? 'chapter' : 'chapters',
                    value: '${book.chapterCount}',
                  ),
                  _Fact(label: 'verses', value: '$verses'),
                  if (note != null) _Fact(label: '', value: note.genre),
                ],
              ),
              if (note == null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    'No background note for this book yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else ...[
                const SizedBox(height: 20),
                Text(note.summary, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 18),
                _Row(label: 'Ascribed to', value: note.attribution),
                _Row(label: 'Setting', value: note.setting),
                const SizedBox(height: 18),
                Text(
                  'A brief editorial summary, not a commentary. Traditional '
                  'authorship is noted as tradition; scholarly views on '
                  'authorship and dating differ.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label.isEmpty ? value : '$value $label',
        style: theme.textTheme.labelLarge,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
