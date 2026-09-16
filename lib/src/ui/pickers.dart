import 'package:flutter/material.dart';

import '../data/settings.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';
import 'widgets/niagara_picker.dart';

/// Builds the rail groups for the book, chapter and verse pickers.
class PickerGroups {
  const PickerGroups._();

  static const String _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// A–Z: every letter gets a rail slot so the alphabet stays in a fixed
  /// place, and letters with no books are drawn dimmed.
  static List<PickerGroup<String>> booksByLetter(
    List<Book> books, {
    String? currentCode,
    Set<String> markedCodes = const {},
  }) {
    final byLetter = <String, List<PickerEntry<String>>>{
      for (final letter in _letters.split('')) letter: [],
    };
    final sorted = books.toList()
      ..sort(
        (a, b) => a.meta.sortName.toLowerCase().compareTo(
          b.meta.sortName.toLowerCase(),
        ),
      );
    for (final book in sorted) {
      (byLetter[book.meta.initial] ??= []).add(
        PickerEntry(
          label: book.name,
          value: book.code,
          subtitle: '${book.chapterCount} chapters',
          selected: book.code == currentCode,
          marked: markedCodes.contains(book.code),
        ),
      );
    }
    return [
      for (final letter in _letters.split(''))
        PickerGroup(key: letter, entries: byLetter[letter] ?? const []),
    ];
  }

  /// Genesis to Revelation, grouped by the traditional divisions.
  static List<PickerGroup<String>> booksByDivision(
    List<Book> books, {
    String? currentCode,
    Set<String> markedCodes = const {},
  }) {
    final groups = <BookDivision, List<PickerEntry<String>>>{};
    for (final book in books) {
      (groups[book.meta.division] ??= []).add(
        PickerEntry(
          label: book.name,
          value: book.code,
          subtitle: '${book.chapterCount} chapters',
          selected: book.code == currentCode,
          marked: markedCodes.contains(book.code),
        ),
      );
    }
    return [
      for (final division in BookDivision.values)
        if (groups[division] != null)
          PickerGroup(key: division.shortLabel, entries: groups[division]!),
    ];
  }

  /// Numbers 1..[count] in rail groups of [groupSize].
  static List<PickerGroup<int>> numbers(
    int count, {
    int groupSize = 10,
    int? current,
    Set<int> marked = const {},
  }) {
    final groups = <PickerGroup<int>>[];
    for (var start = 1; start <= count; start += groupSize) {
      final end = (start + groupSize - 1).clamp(1, count);
      groups.add(
        PickerGroup(
          key: '$start',
          entries: [
            for (var n = start; n <= end; n++)
              PickerEntry(
                label: '$n',
                value: n,
                selected: n == current,
                marked: marked.contains(n),
              ),
          ],
        ),
      );
    }
    return groups;
  }
}

/// Shows the book picker and resolves to the chosen book code.
Future<String?> showBookPicker(
  BuildContext context, {
  required List<Book> books,
  required Settings settings,
  String? currentCode,
  Set<String> markedCodes = const {},
}) {
  return _showPickerSheet<String>(
    context,
    title: 'Books',
    builder: (context, onSelected) => AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<BookOrder>(
              segments: [
                for (final order in BookOrder.values)
                  ButtonSegment(value: order, label: Text(order.label)),
              ],
              selected: {settings.bookOrder},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  settings.bookOrder = selection.first,
            ),
          ),
          Expanded(
            child: NiagaraPicker<String>(
              groups: settings.bookOrder == BookOrder.alphabetical
                  ? PickerGroups.booksByLetter(
                      books,
                      currentCode: currentCode,
                      markedCodes: markedCodes,
                    )
                  : PickerGroups.booksByDivision(
                      books,
                      currentCode: currentCode,
                      markedCodes: markedCodes,
                    ),
              onSelected: onSelected,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shows the chapter picker for [book].
Future<int?> showChapterPicker(
  BuildContext context, {
  required Book book,
  int? current,
  Set<int> marked = const {},
}) {
  return _showNumberPicker(
    context,
    title: book.name,
    count: book.chapterCount,
    current: current,
    marked: marked,
  );
}

/// Shows the verse picker for [chapter].
Future<int?> showVersePicker(
  BuildContext context, {
  required Book book,
  required Chapter chapter,
  int? current,
  Set<int> marked = const {},
}) {
  return _showNumberPicker(
    context,
    title: '${book.name} ${chapter.number}',
    count: chapter.verseCount,
    current: current,
    marked: marked,
  );
}

Future<int?> _showNumberPicker(
  BuildContext context, {
  required String title,
  required int count,
  int? current,
  Set<int> marked = const {},
}) {
  // Short books do not need a rail — a grid of chips is quicker to hit.
  if (count <= 10) {
    return _showPickerSheet<int>(
      context,
      title: title,
      height: 0.5,
      builder: (context, onSelected) => _NumberGrid(
        count: count,
        current: current,
        marked: marked,
        onSelected: onSelected,
      ),
    );
  }
  return _showPickerSheet<int>(
    context,
    title: title,
    builder: (context, onSelected) => NiagaraPicker<int>(
      groups: PickerGroups.numbers(count, current: current, marked: marked),
      layout: PickerLayout.grid,
      onSelected: onSelected,
    ),
  );
}

class _NumberGrid extends StatelessWidget {
  const _NumberGrid({
    required this.count,
    required this.current,
    required this.marked,
    required this.onSelected,
  });

  final int count;
  final int? current;
  final Set<int> marked;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var n = 1; n <= count; n++)
            SizedBox(
              width: 58,
              height: 52,
              child: Material(
                color: n == current
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onSelected(n),
                  child: Center(
                    child: Text(
                      '$n',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: n == current
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        fontWeight: marked.contains(n)
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<T?> _showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext, ValueChanged<T>) builder,
  double height = 0.92,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: builder(
              sheetContext,
              (value) => Navigator.of(sheetContext).pop(value),
            ),
          ),
        ],
      ),
    ),
  );
}
