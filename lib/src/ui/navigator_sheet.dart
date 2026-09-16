import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/marks.dart';
import '../data/reference_search.dart';
import '../data/settings.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';

/// Opens the navigator and resolves to the chosen place, or null.
Future<Reference?> showBibleNavigator(
  BuildContext context, {
  required List<Book> books,
  required Settings settings,
  required ReadingStore reading,
  Reference? current,
}) {
  return showModalBottomSheet<Reference>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _NavigatorSheet(
        books: books,
        settings: settings,
        reading: reading,
        current: current,
      ),
    ),
  );
}

enum _Step { books, chapters, verses }

/// Book, chapter and verse navigation in one sheet.
///
/// The field at the top does double duty: it filters the book list as you
/// type, and if what you typed reads as a reference — `jn 3:16`, `1 co 13`,
/// `psalm 23` — it offers to jump straight there.
class _NavigatorSheet extends StatefulWidget {
  const _NavigatorSheet({
    required this.books,
    required this.settings,
    required this.reading,
    this.current,
  });

  final List<Book> books;
  final Settings settings;
  final ReadingStore reading;
  final Reference? current;

  @override
  State<_NavigatorSheet> createState() => _NavigatorSheetState();
}

class _NavigatorSheetState extends State<_NavigatorSheet> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  _Step _step = _Step.books;
  Book? _book;
  int _chapter = 1;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    if (current != null) {
      _book = widget.books.firstWhere(
        (book) => book.code == current.bookCode,
        orElse: () => widget.books.first,
      );
      _chapter = current.chapter;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _text => _query.text.trim();

  Reference? get _parsed =>
      _text.isEmpty ? null : ReferenceSearch.parse(_text, widget.books);

  /// Books matching what was typed, ignoring any chapter and verse, so that
  /// `jn 3:16` still lists John underneath the jump button.
  List<Book> get _matches => ReferenceSearch.matchBooks(
    ReferenceSearch.split(_text).name,
    widget.books,
  );

  void _pop(Reference reference) => Navigator.of(context).pop(reference);

  void _chooseBook(Book book) {
    if (book.chapterCount == 1) {
      _pop(Reference(book.code, 1));
      return;
    }
    _focus.unfocus();
    setState(() {
      _book = book;
      _step = _Step.chapters;
      _query.clear();
    });
  }

  void _chooseChapter(int chapter) {
    setState(() {
      _chapter = chapter;
      _step = _Step.verses;
    });
  }

  void _back() {
    setState(() {
      _step = _step == _Step.verses ? _Step.chapters : _Step.books;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _header(theme),
        if (_step == _Step.books) _searchField(theme),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (_step) {
              _Step.books => _bookList(theme),
              _Step.chapters => _chapterGrid(theme),
              _Step.verses => _verseGrid(theme),
            },
          ),
        ),
      ],
    );
  }

  Widget _header(ThemeData theme) {
    final title = switch (_step) {
      _Step.books => 'Go to',
      _Step.chapters => _book?.name ?? '',
      _Step.verses => '${_book?.name ?? ''} $_chapter',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 4),
      child: Row(
        children: [
          if (_step == _Step.books)
            const SizedBox(width: 12)
          else
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: _back,
            ),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_step == _Step.chapters && _book != null)
            TextButton(
              onPressed: () => _pop(Reference(_book!.code, _chapter)),
              child: const Text('Keep reading'),
            ),
          if (_step == _Step.verses && _book != null)
            TextButton(
              onPressed: () => _pop(Reference(_book!.code, _chapter)),
              child: const Text('Whole chapter'),
            ),
        ],
      ),
    );
  }

  Widget _searchField(ThemeData theme) {
    final parsed = _parsed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _query,
            focusNode: _focus,
            autofocus: false,
            textInputAction: TextInputAction.go,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              filled: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Book, or a reference like Jn 3:16',
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(_query.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              final reference = _parsed;
              if (reference != null) {
                _pop(reference);
              } else if (_matches.length == 1) {
                _chooseBook(_matches.single);
              }
            },
          ),
          if (parsed != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Material(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _pop(parsed),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: theme.colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Go to ${parsed.label}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bookList(ThemeData theme) {
    final marked = widget.reading.markedBookCodes;
    final matches = _matches;
    if (matches.isEmpty) {
      return Center(
        child: Text(
          'No book matches “${ReferenceSearch.split(_text).name.trim()}”',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // While filtering, a flat ranked list is what the reader wants to see.
    if (_text.isNotEmpty) {
      return ListView.builder(
        key: const ValueKey('filtered'),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: matches.length,
        itemBuilder: (context, index) =>
            _bookTile(theme, matches[index], marked),
      );
    }

    final alphabetical = widget.settings.bookOrder == BookOrder.alphabetical;
    final ordered = alphabetical
        ? (matches.toList()..sort(
            (a, b) => a.meta.sortName.toLowerCase().compareTo(
              b.meta.sortName.toLowerCase(),
            ),
          ))
        : matches;

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SegmentedButton<BookOrder>(
          segments: [
            for (final order in BookOrder.values)
              ButtonSegment(value: order, label: Text(order.label)),
          ],
          selected: {widget.settings.bookOrder},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              setState(() => widget.settings.bookOrder = selection.first),
        ),
      ),
    ];

    String? group;
    for (final book in ordered) {
      final heading = alphabetical
          ? book.meta.initial
          : book.meta.division.label;
      if (heading != group) {
        group = heading;
        children.add(_groupHeading(theme, heading));
      }
      children.add(_bookTile(theme, book, marked));
    }

    return ListView(
      key: ValueKey(alphabetical),
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  Widget _groupHeading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _bookTile(ThemeData theme, Book book, Set<String> marked) {
    final selected = book.code == widget.current?.bookCode;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: selected,
      title: Text(book.name),
      subtitle: Text(
        book.chapterCount == 1 ? '1 chapter' : '${book.chapterCount} chapters',
      ),
      trailing: marked.contains(book.code)
          ? Icon(
              Icons.bookmark_rounded,
              size: 16,
              color: theme.colorScheme.primary,
            )
          : null,
      onTap: () => _chooseBook(book),
    );
  }

  Widget _chapterGrid(ThemeData theme) {
    final book = _book;
    if (book == null) return const SizedBox.shrink();
    final marked = widget.reading.markedChaptersIn(book.code);
    return _NumberGrid(
      key: ValueKey('chapters-${book.code}'),
      count: book.chapterCount,
      current: book.code == widget.current?.bookCode
          ? widget.current?.chapter
          : null,
      marked: marked,
      onSelected: _chooseChapter,
    );
  }

  Widget _verseGrid(ThemeData theme) {
    final book = _book;
    final chapter = book?.chapter(_chapter);
    if (book == null || chapter == null) return const SizedBox.shrink();
    return _NumberGrid(
      key: ValueKey('verses-${book.code}-$_chapter'),
      count: chapter.verseCount,
      current:
          book.code == widget.current?.bookCode &&
              _chapter == widget.current?.chapter
          ? widget.current?.verse
          : null,
      marked: widget.reading.flaggedVersesIn(book.code, _chapter),
      onSelected: (verse) => _pop(Reference(book.code, _chapter, verse)),
    );
  }
}

/// A grid of numbers, used for both chapters and verses.
class _NumberGrid extends StatelessWidget {
  const _NumberGrid({
    required this.count,
    required this.onSelected,
    this.current,
    this.marked = const {},
    super.key,
  });

  final int count;
  final ValueChanged<int> onSelected;
  final int? current;
  final Set<int> marked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 76,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.15,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final number = index + 1;
        final isCurrent = number == current;
        return Material(
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.selectionClick();
              onSelected(number);
            },
            child: Stack(
              children: [
                Center(
                  child: Text(
                    '$number',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isCurrent
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (marked.contains(number))
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(
                      Icons.bookmark_rounded,
                      size: 11,
                      color: isCurrent
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
