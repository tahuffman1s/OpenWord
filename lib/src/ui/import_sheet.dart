import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library.dart';
import '../data/settings.dart';
import '../data/shelf.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';

/// Brings a translation in from a file: a `.bib`, or an EPUB to convert.
///
/// The conversion is the interesting part, so the sheet shows its work — what
/// it found, and what it could not place — rather than reporting "done".
void showImportSheet(
  BuildContext context, {
  required Shelf shelf,
  required LibraryController library,
  required Settings settings,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _ImportSheet(shelf: shelf, library: library, settings: settings),
    ),
  );
}

enum _Stage { waiting, reading, done, failed }

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({
    required this.shelf,
    required this.library,
    required this.settings,
  });

  final Shelf shelf;
  final LibraryController library;
  final Settings settings;

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  _Stage _stage = _Stage.waiting;
  String _what = '';
  String? _error;
  ShelfResult? _result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a translation', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'An EPUB of a Bible, or a .bib file — the format this app '
              'converts them to.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(child: _body(theme)),
            const SizedBox(height: 12),
            _actions(theme),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    switch (_stage) {
      case _Stage.reading:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Reading $_what…', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              'A whole Bible takes a few seconds.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

      case _Stage.failed:
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error ?? 'That file could not be read.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'An EPUB can be read when its headings name the books of the '
                'Bible and its verses are numbered — as a superscript, in a '
                'span of their own, or as a number at the head of each '
                'paragraph. Anything else is a book, not a Bible, and the app '
                'would only be guessing.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );

      case _Stage.done:
        return _Summary(result: _result!);

      case _Stage.waiting:
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Point(
                icon: Icons.menu_book_rounded,
                title: 'EPUB',
                body:
                    'Converted to .bib as it is read: the books, chapters and '
                    'verses are found from the markup, and poetry, headings '
                    'and italics are kept.',
              ),
              _Point(
                icon: Icons.inventory_2_rounded,
                title: '.bib',
                body:
                    'A whole translation in one file — the app’s own '
                    'format. Copied onto the shelf as it is.',
              ),
              _Point(
                icon: Icons.wifi_off_rounded,
                title: 'Nothing leaves the device',
                body:
                    'The file is read where it sits. Once imported, the '
                    'translation reads, searches, compares and takes '
                    'bookmarks like the ones that ship with the app.',
              ),
            ],
          ),
        );
    }
  }

  Widget _actions(ThemeData theme) {
    if (_stage == _Stage.reading) return const SizedBox.shrink();
    if (_stage == _Stage.done) {
      final result = _result!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => _readNow(result),
            icon: const Icon(Icons.auto_stories_rounded),
            label: const Text('Read it now'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(
            _stage == _Stage.failed ? 'Choose another file' : 'Choose a file',
          ),
        ),
      ],
    );
  }

  Future<void> _pick() async {
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(dialogTitle: 'Choose a Bible to import');
    } on Object catch (error) {
      setState(() {
        _stage = _Stage.failed;
        _error = 'The file picker would not open: $error';
      });
      return;
    }
    if (file == null) return;

    setState(() {
      _stage = _Stage.reading;
      _what = file!.name;
      _error = null;
    });

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = 'That file could not be read: $error';
      });
      return;
    }

    final result = await widget.shelf.add(bytes, fileName: file.name);
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _stage = _Stage.done;
        _result = result;
      } else {
        _stage = _Stage.failed;
        _error = result.failure;
      }
    });
  }

  void _readNow(ShelfResult result) {
    final id = result.bible!.translation.id;
    widget.settings.translationId = id;
    widget.library.load(id);
    Navigator.of(context).pop();
  }
}

/// What the import found, in the terms the reader cares about.
class _Summary extends StatelessWidget {
  const _Summary({required this.result});

  final ShelfResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bible = result.bible!;
    final books = bible.books.length;
    final verses = bible.verseCount;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(bible.translation.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(
            '${bible.translation.abbreviation} • '
            '${bible.translation.license}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Fact(value: '$books', label: books == 1 ? 'book' : 'books'),
              _Fact(value: '$verses', label: 'verses'),
              if (result.translation != null)
                _Fact(
                  value: result.translation!.readableSize,
                  label: 'on disk',
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(_coverage(bible), style: theme.textTheme.bodyMedium),
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              result.warnings.length == 1
                  ? 'One thing could not be placed:'
                  : '${result.warnings.length} things could not be placed:',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            for (final warning in result.warnings.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $warning',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Which parts of the canon came through, since an EPUB is often only a
  /// Testament or a single book.
  String _coverage(Bible bible) {
    final codes = bible.books.map((book) => book.code).toSet();
    final old = bible.books
        .where((book) => book.section == BookSection.oldTestament)
        .length;
    final newer = bible.books
        .where((book) => book.section == BookSection.newTestament)
        .length;
    final deutero = codes.length - old - newer;

    final parts = <String>[
      if (old > 0) '$old of the 39 books of the Old Testament',
      if (newer > 0) '$newer of the 27 of the New',
      if (deutero > 0) '$deutero deuterocanonical',
    ];
    if (parts.isEmpty) return 'Nothing of the canon was recognised.';
    return 'Found ${parts.join(', ')}.';
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$value $label', style: theme.textTheme.labelLarge),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
