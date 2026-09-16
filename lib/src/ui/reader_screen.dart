import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/bookmarks.dart';
import '../data/settings.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';
import 'bookmarks_screen.dart';
import 'pickers.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'widgets/scripture_text.dart';

/// The main reading surface: one swipeable page per chapter.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final PageController _pages = PageController();

  List<Reference> _index = const [];
  int _page = 0;
  int? _pendingVerse;
  bool _restored = false;

  // Held directly rather than looked up on demand, so they are still
  // reachable from dispose().
  late Bible _bible;
  late Settings _settings;
  late ReadingStore _reading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _bible = scope.library.bible!;
    _settings = scope.settings;
    _reading = scope.reading;
    _rebuildIndex();
    if (!_restored) {
      _restored = true;
      _settings.addListener(_onSettingsChanged);
      final resume = _reading.lastPosition;
      final target =
          resume != null && _bible.bookByCode(resume.bookCode) != null
          ? resume
          : const Reference('GEN', 1);
      _page = _pageFor(target);
      _pendingVerse = target.verse;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pages.hasClients) _pages.jumpToPage(_page);
      });
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _pages.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    final current = _index.isEmpty ? null : _index[_page];
    setState(_rebuildIndex);
    if (current != null) {
      final page = _pageFor(current);
      if (page != _page && _pages.hasClients) {
        _page = page;
        _pages.jumpToPage(page);
      }
    }
  }

  /// Flattens the Bible into one list of chapters so a [PageView] can carry
  /// the whole book-to-book flow.
  void _rebuildIndex() {
    final showDeuterocanon = _settings.showDeuterocanon;
    _index = [
      for (final book in _bible.books)
        if (showDeuterocanon || book.section != BookSection.deuterocanon)
          for (final chapter in book.chapters)
            Reference(book.code, chapter.number),
    ];
    if (_page >= _index.length) _page = _index.isEmpty ? 0 : _index.length - 1;
  }

  int _pageFor(Reference reference) {
    final exact = _index.indexWhere(
      (entry) =>
          entry.bookCode == reference.bookCode &&
          entry.chapter == reference.chapter,
    );
    if (exact >= 0) return exact;
    final book = _index.indexWhere(
      (entry) => entry.bookCode == reference.bookCode,
    );
    return book >= 0 ? book : 0;
  }

  Reference get _current =>
      _index.isEmpty ? const Reference('GEN', 1) : _index[_page];

  Book get _currentBook => _bible.bookByCode(_current.bookCode)!;

  Chapter get _currentChapter =>
      _currentBook.chapter(_current.chapter) ?? _currentBook.chapters.first;

  void _goTo(Reference reference, {bool animate = false}) {
    final page = _pageFor(reference);
    setState(() {
      _page = page;
      _pendingVerse = reference.verse;
    });
    if (!_pages.hasClients) return;
    if (animate && (page - (_pages.page?.round() ?? page)).abs() == 1) {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pages.jumpToPage(page);
    }
    _reading.savePosition(reference);
  }

  void _step(int delta) {
    final next = _page + delta;
    if (next < 0 || next >= _index.length) return;
    _goTo(_index[next], animate: true);
  }

  Future<void> _openBookPicker() async {
    final marked = {
      for (final bookmark in _reading.bookmarks) bookmark.reference.bookCode,
    };
    final code = await showBookPicker(
      context,
      books: [
        for (final book in _bible.books)
          if (_settings.showDeuterocanon ||
              book.section != BookSection.deuterocanon)
            book,
      ],
      settings: _settings,
      currentCode: _current.bookCode,
      markedCodes: marked,
    );
    if (code == null || !mounted) return;
    final book = _bible.bookByCode(code);
    if (book == null) return;
    if (book.chapterCount == 1) {
      _goTo(Reference(code, 1));
      return;
    }
    final chapter = await showChapterPicker(
      context,
      book: book,
      marked: {
        for (final bookmark in _reading.bookmarks)
          if (bookmark.reference.bookCode == code) bookmark.reference.chapter,
      },
    );
    if (!mounted) return;
    _goTo(Reference(code, chapter ?? 1));
  }

  Future<void> _openChapterPicker() async {
    final book = _currentBook;
    final chapter = await showChapterPicker(
      context,
      book: book,
      current: _current.chapter,
      marked: {
        for (final bookmark in _reading.bookmarks)
          if (bookmark.reference.bookCode == book.code)
            bookmark.reference.chapter,
      },
    );
    if (chapter == null || !mounted) return;
    _goTo(Reference(book.code, chapter));
  }

  Future<void> _openVersePicker() async {
    final verse = await showVersePicker(
      context,
      book: _currentBook,
      chapter: _currentChapter,
      current: _pendingVerse,
      marked: _reading.bookmarkedVerses(_current.bookCode, _current.chapter),
    );
    if (verse == null || !mounted) return;
    _goTo(_current.withVerse(verse));
  }

  void _onVerseTap(int verse) {
    final reference = _current.withVerse(verse);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _VerseSheet(
        reference: reference,
        text: _currentChapter.verseText(verse),
        reading: _reading,
      ),
    );
  }

  void _onNoteTap(int index) {
    final notes = _currentChapter.notes;
    if (index < 0 || index >= notes.length) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Note on ${_current.label}',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              notes[index],
              style: Theme.of(sheetContext).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _step(-1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: Row(
              children: [
                Flexible(
                  child: _NavChip(
                    label: _currentBook.name,
                    onTap: _openBookPicker,
                  ),
                ),
                const SizedBox(width: 8),
                _NavChip(
                  label: '${_current.chapter}',
                  onTap: _currentBook.chapterCount > 1
                      ? _openChapterPicker
                      : null,
                ),
                const SizedBox(width: 8),
                _NavChip(
                  icon: Icons.format_list_numbered_rounded,
                  onTap: _openVersePicker,
                  tooltip: 'Go to verse',
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Search',
                onPressed: () async {
                  final result = await Navigator.of(context).push<Reference>(
                    MaterialPageRoute(
                      builder: (_) => SearchScreen(bible: _bible),
                    ),
                  );
                  if (result != null && mounted) _goTo(result);
                },
              ),
              IconButton(
                icon: const Icon(Icons.bookmarks_rounded),
                tooltip: 'Bookmarks',
                onPressed: () async {
                  final result = await Navigator.of(context).push<Reference>(
                    MaterialPageRoute(builder: (_) => const BookmarksScreen()),
                  );
                  if (result != null && mounted) _goTo(result);
                },
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Display and settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: AnimatedBuilder(
            animation: Listenable.merge([_settings, _reading]),
            builder: (context, _) => PageView.builder(
              controller: _pages,
              itemCount: _index.length,
              onPageChanged: (page) {
                setState(() {
                  _page = page;
                  _pendingVerse = null;
                });
                _reading.savePosition(_index[page]);
              },
              itemBuilder: (context, page) {
                final reference = _index[page];
                final book = _bible.bookByCode(reference.bookCode)!;
                final chapter = book.chapter(reference.chapter)!;
                return _ChapterPage(
                  key: ValueKey('${reference.bookCode}/${reference.chapter}'),
                  book: book,
                  chapter: chapter,
                  style: ScriptureStyle.of(context, _settings),
                  highlights: {
                    for (final verse in _reading.bookmarkedVerses(
                      book.code,
                      chapter.number,
                    ))
                      verse: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.55,
                      ),
                  },
                  scrollToVerse: page == _page ? _pendingVerse : null,
                  onVerseTap: _onVerseTap,
                  onNoteTap: _onNoteTap,
                  onTopVerseChanged: (verse) {
                    if (page != _page) return;
                    _reading.savePosition(
                      Reference(book.code, chapter.number, verse),
                    );
                  },
                  onStep: _step,
                  hasPrevious: page > 0,
                  hasNext: page < _index.length - 1,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One chapter, scrollable, with the position-tracking that powers resume.
class _ChapterPage extends StatefulWidget {
  const _ChapterPage({
    required this.book,
    required this.chapter,
    required this.style,
    required this.highlights,
    required this.scrollToVerse,
    required this.onVerseTap,
    required this.onNoteTap,
    required this.onTopVerseChanged,
    required this.onStep,
    required this.hasPrevious,
    required this.hasNext,
    super.key,
  });

  final Book book;
  final Chapter chapter;
  final ScriptureStyle style;
  final Map<int, Color> highlights;
  final int? scrollToVerse;
  final ValueChanged<int> onVerseTap;
  final ValueChanged<int> onNoteTap;
  final ValueChanged<int> onTopVerseChanged;
  final ValueChanged<int> onStep;
  final bool hasPrevious;
  final bool hasNext;

  @override
  State<_ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<_ChapterPage> {
  final ScrollController _scroll = ScrollController();

  /// Scroll anchors: the verse a block starts, to the key on that block. Built
  /// once per chapter — a fresh [GlobalKey] on every build would re-inflate
  /// the whole chapter.
  final Map<int, GlobalKey> _verseKeys = {};

  /// One entry per block, holding its anchor key where it has one.
  List<GlobalKey?> _blockKeys = const [];

  Timer? _debounce;
  int _reportedVerse = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _buildAnchors();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToVerse());
  }

  @override
  void didUpdateWidget(_ChapterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chapter != oldWidget.chapter) {
      _buildAnchors();
      _reportedVerse = 0;
    }
    if (widget.scrollToVerse != oldWidget.scrollToVerse) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToVerse());
    }
  }

  void _buildAnchors() {
    _verseKeys.clear();
    final keys = <GlobalKey?>[];
    for (final block in widget.chapter.blocks) {
      final firstVerse = block.segments
          .where((segment) => segment.startsVerse && segment.verse > 0)
          .map((segment) => segment.verse)
          .firstOrNull;
      if (firstVerse != null && !_verseKeys.containsKey(firstVerse)) {
        final key = GlobalKey();
        _verseKeys[firstVerse] = key;
        keys.add(key);
      } else {
        keys.add(null);
      }
    }
    _blockKeys = keys;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToVerse() {
    final verse = widget.scrollToVerse;
    if (verse == null || verse <= 1) return;
    final key = _verseKeys[verse];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  void _onScroll() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _reportTopVerse);
  }

  /// Finds the verse nearest the top of the viewport so the app can resume
  /// exactly where the reader left off, independent of font size.
  void _reportTopVerse() {
    if (!mounted || !_scroll.hasClients) return;
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    var best = 0;
    for (final entry in _verseKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= top + 24) {
        if (entry.key > best) best = entry.key;
      }
    }
    if (best > 0 && best != _reportedVerse) {
      _reportedVerse = best;
      widget.onTopVerseChanged(best);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style;

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.book.name.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.book.chapterCount > 1
                  ? 'Chapter ${widget.chapter.number}'
                  : widget.book.name,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    ];

    var isFirst = true;
    final blocks = widget.chapter.blocks;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final blockWidget = ScriptureBlock(
        block: block,
        style: style,
        highlights: widget.highlights,
        isFirst: isFirst,
        onVerseTap: widget.onVerseTap,
        onNoteTap: widget.onNoteTap,
      );
      final key = i < _blockKeys.length ? _blockKeys[i] : null;
      children.add(
        key == null ? blockWidget : KeyedSubtree(key: key, child: blockWidget),
      );
      if (block.style == BlockStyle.paragraph ||
          block.style == BlockStyle.poetry) {
        isFirst = false;
      }
    }

    children.add(
      _ChapterFooter(
        hasPrevious: widget.hasPrevious,
        hasNext: widget.hasNext,
        onStep: widget.onStep,
      ),
    );

    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterFooter extends StatelessWidget {
  const _ChapterFooter({
    required this.hasPrevious,
    required this.hasNext,
    required this.onStep,
  });

  final bool hasPrevious;
  final bool hasNext;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: hasPrevious ? () => onStep(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Previous'),
          ),
          TextButton.icon(
            onPressed: hasNext ? () => onStep(1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            iconAlignment: IconAlignment.end,
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

/// A book / chapter / verse button in the app bar.
class _NavChip extends StatelessWidget {
  const _NavChip({this.label, this.icon, this.onTap, this.tooltip});

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 8 : 12,
            vertical: 8,
          ),
          child: label == null
              ? Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label!,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Actions for a tapped verse.
class _VerseSheet extends StatelessWidget {
  const _VerseSheet({
    required this.reference,
    required this.text,
    required this.reading,
  });

  final Reference reference;
  final String text;
  final ReadingStore reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bookmarked = reading.isBookmarked(reference);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reference.label, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () {
                    final added = reading.toggle(reference);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          added
                              ? 'Bookmarked ${reference.label}'
                              : 'Removed ${reference.label}',
                        ),
                      ),
                    );
                  },
                  icon: Icon(
                    bookmarked
                        ? Icons.bookmark_remove_rounded
                        : Icons.bookmark_add_rounded,
                  ),
                  label: Text(bookmarked ? 'Remove bookmark' : 'Bookmark'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: '${reference.label} — $text'),
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Verse copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
