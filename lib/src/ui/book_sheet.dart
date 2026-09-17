import 'package:flutter/material.dart';

import '../data/book_intros.dart';
import '../data/book_notes.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';
import 'widgets/simple_markdown.dart';

/// A background sheet for the book being read: where it sits in the canon,
/// how big it is, and an introduction to it.
void showBookSheet(BuildContext context, Book book, {BookIntros? intros}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.88,
      child: _BookSheet(book: book, intros: intros),
    ),
  );
}

class _BookSheet extends StatelessWidget {
  const _BookSheet({required this.book, this.intros});

  final Book book;
  final BookIntros? intros;

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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
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
              const SizedBox(height: 20),
              _Introduction(book: book, intros: intros, fallback: note),
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

/// The bundled introduction for a book, or the app's own short note where
/// there is none — the deuterocanonical books are not covered by the
/// introductions resource.
class _Introduction extends StatelessWidget {
  const _Introduction({
    required this.book,
    required this.intros,
    required this.fallback,
  });

  final Book book;
  final BookIntros? intros;
  final BookNote? fallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = intros;
    if (source == null) return _fallback(theme);

    final alreadyLoaded = source.loaded(book.code);
    if (alreadyLoaded != null) return _intro(theme, alreadyLoaded);

    return FutureBuilder<String?>(
      future: source.forBook(book.code),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final markdown = snapshot.data;
        if (markdown == null || markdown.isEmpty) return _fallback(theme);
        return _intro(theme, markdown);
      },
    );
  }

  Widget _intro(ThemeData theme, String markdown) {
    final intro = BookIntro.parse(markdown);
    if (intro.isEmpty) return _fallback(theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (intro.lead.isNotEmpty)
          SimpleMarkdown(
            source: intro.lead,
            baseStyle: theme.textTheme.bodyLarge,
          ),
        if (intro.sections.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < intro.sections.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Section(
                section: intro.sections[i],
                // Where there is a lead, it is already the summary and the
                // sections below it are an outline to choose from; where
                // there is not, the first section is opened so the sheet
                // does not read as a row of shut doors.
                initiallyExpanded: i == 0 && intro.lead.isEmpty,
              ),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          BookIntros.attribution,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _fallback(ThemeData theme) {
    final note = fallback;
    if (note == null) {
      return Text(
        'No background note for this book yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(note.summary, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 18),
        _Row(label: 'Ascribed to', value: note.attribution),
        _Row(label: 'Setting', value: note.setting),
        const SizedBox(height: 18),
        Text(
          'A brief editorial summary written for this app, not a commentary. '
          'Traditional authorship is noted as tradition; scholarly views on '
          'authorship and dating differ.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// One section of an introduction, folded away until it is wanted.
class _Section extends StatelessWidget {
  const _Section({required this.section, this.initiallyExpanded = false});

  final IntroSection section;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // ExpansionTile draws a hairline above and below itself by default,
        // which fights with the rounded card it sits in.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: theme.colorScheme.primary,
          collapsedIconColor: theme.colorScheme.onSurfaceVariant,
          title: Text(
            section.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          children: [
            SimpleMarkdown(
              source: section.body,
              baseStyle: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
