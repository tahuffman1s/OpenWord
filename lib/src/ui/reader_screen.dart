import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/library.dart';
import '../data/atlas.dart';
import '../data/book_intros.dart';
import '../data/marks.dart';
import '../data/reference_search.dart';
import '../data/settings.dart';
import '../data/updates.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';
import 'book_sheet.dart';
import 'map_sheet.dart';
import 'update_sheet.dart';
import 'display_sheet.dart';
import 'library_screen.dart';
import 'navigator_sheet.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
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

  /// A verse to scroll to, and the page it belongs to. Pairing them matters:
  /// jumping to another chapter fires onPageChanged, and without the page a
  /// pending verse would be cleared before the chapter had a chance to use
  /// it.
  int? _pendingVerse;
  int? _pendingPage;

  bool _restored = false;
  Bible? _matcherFor;

  // Held directly rather than looked up on demand, so they are still
  // reachable from dispose().
  late Bible _bible;

  /// Built once per translation; finds citations inside notes and
  /// parallel-passage lines.
  ReferenceMatcher? _matcher;

  /// Book introductions, read from the bundle the first time one is opened.
  BookIntros? _intros;

  /// The atlas, read once in the background: the chapter heading has to know
  /// whether there is anything to show before it can offer a map.
  Atlas? _atlas;
  AtlasData? _atlasData;

  /// The launch check runs once per session, not on every rebuild.
  bool _askedAboutUpdates = false;

  late Settings _settings;
  late ReadingStore _reading;
  late LibraryController _library;

  /// Looks for a newer release, at most once a day and only while the reader
  /// leaves the switch on, and mentions one in passing rather than standing
  /// in the way of the text.
  Future<void> _announceUpdate(UpdateService updates) async {
    await updates.check();
    if (!mounted || !updates.shouldAnnounce) return;
    final release = updates.release!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('OpenWord ${release.version} is out'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'See what’s new',
          onPressed: () => showUpdateSheet(context, updates),
        ),
      ),
    );
  }

  /// Reads the atlas in the background and rebuilds once it is there, so
  /// opening a chapter never waits on it.
  void _loadAtlas(AssetBundle bundle) {
    if (_atlas != null) return;
    final atlas = Atlas(bundle: bundle);
    _atlas = atlas;
    atlas.load().then((data) {
      if (!mounted || data.isEmpty) return;
      setState(() => _atlasData = data);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _library = scope.library;
    _intros ??= BookIntros(bundle: scope.library.bundle);
    _loadAtlas(scope.library.bundle);
    if (!_askedAboutUpdates) {
      _askedAboutUpdates = true;
      _announceUpdate(scope.updates);
    }
    if (!identical(_matcherFor, scope.library.bible)) {
      _matcherFor = scope.library.bible;
      _matcher = ReferenceMatcher(scope.library.bible!.books);
    }
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
      _pendingPage = _page;
      _pendingVerse = target.verse;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pages.hasClients) _pages.jumpToPage(_page);
        _syncComparison();
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
    _syncComparison();
  }

  /// Loads or drops the side-by-side translation to match the setting.
  void _syncComparison() {
    final wanted = _settings.compareTranslationId;
    if (wanted == null) {
      _library.clearComparison();
    } else if (_library.comparison?.translation.id != wanted) {
      _library.loadComparison(wanted);
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
      _pendingPage = page;
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

  Future<void> _openNavigator() async {
    final reference = await showBibleNavigator(
      context,
      books: [
        for (final book in _bible.books)
          if (_settings.showDeuterocanon ||
              book.section != BookSection.deuterocanon)
            book,
      ],
      settings: _settings,
      reading: _reading,
      current: _current.withVerse(_pendingVerse),
    );
    if (reference == null || !mounted) return;
    _goTo(reference);
  }

  Future<void> _openSearch() async {
    final result = await Navigator.of(context).push<Reference>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(bible: _bible, from: _current),
      ),
    );
    if (result != null && mounted) _goTo(result);
  }

  Future<void> _openLibrary() async {
    final result = await Navigator.of(
      context,
    ).push<Reference>(MaterialPageRoute(builder: (_) => const LibraryScreen()));
    if (result != null && mounted) _goTo(result);
  }

  void _openDisplay() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          DisplaySheet(settings: _settings, current: _bible.translation),
    );
  }

  void _onVerseTap(int verse) {
    final reference = _current.withVerse(verse);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _VerseSheet(
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
            LinkedText(
              text: notes[index],
              style:
                  Theme.of(sheetContext).textTheme.bodyLarge ??
                  const TextStyle(),
              matcher: _matcher,
              onTap: (reference) {
                Navigator.of(sheetContext).pop();
                _goTo(reference);
              },
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
        const SingleActivator(LogicalKeyboardKey.keyG): _openNavigator,
        const SingleActivator(LogicalKeyboardKey.slash): _openSearch,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: _ReferenceButton(
              label: '${_currentBook.name} ${_current.chapter}',
              badge: _library.comparison?.translation.abbreviation,
              onTap: _openNavigator,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Search (/)',
                onPressed: _openSearch,
              ),
              IconButton(
                icon: const Icon(Icons.bookmarks_rounded),
                tooltip: 'Bookmarks, highlights and notes',
                onPressed: _openLibrary,
              ),
              IconButton(
                icon: const Icon(Icons.text_fields_rounded),
                tooltip: 'Display',
                onPressed: _openDisplay,
              ),
              IconButton(
                icon: const Icon(Icons.settings_rounded),
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: AnimatedBuilder(
            animation: Listenable.merge([_settings, _reading, _library]),
            builder: (context, _) {
              final comparison = _library.comparison;
              return PageView.builder(
                controller: _pages,
                itemCount: _index.length,
                onPageChanged: (page) {
                  final programmatic = page == _pendingPage;
                  setState(() {
                    _page = page;
                    if (!programmatic) {
                      _pendingPage = null;
                      _pendingVerse = null;
                    }
                  });
                  // A jump has already saved its own position, verse and all.
                  if (!programmatic) _reading.savePosition(_index[page]);
                },
                itemBuilder: (context, page) {
                  final reference = _index[page];
                  final book = _bible.bookByCode(reference.bookCode)!;
                  final chapter = book.chapter(reference.chapter)!;
                  return _ChapterPage(
                    key: ValueKey(
                      '${reference.bookCode}/${reference.chapter}'
                      '/${comparison?.translation.id ?? ''}',
                    ),
                    book: book,
                    chapter: chapter,
                    style: ScriptureStyle.of(context, _settings),
                    highlights: {
                      for (final entry
                          in _reading
                              .highlightsIn(book.code, chapter.number)
                              .entries)
                        entry.key: AppTheme.highlights(
                          theme.colorScheme,
                        )[entry.value % ReadingStore.paletteSize],
                    },
                    flagged: _reading.flaggedVersesIn(
                      book.code,
                      chapter.number,
                    ),
                    matcher: _matcher,
                    onReferenceTap: _goTo,
                    intros: _intros,
                    atlas: _atlasData,
                    comparison: comparison
                        ?.bookByCode(book.code)
                        ?.chapter(chapter.number),
                    comparisonLabel: comparison?.translation.abbreviation ?? '',
                    primaryLabel: _bible.translation.abbreviation,
                    scrollToVerse: page == _pendingPage ? _pendingVerse : null,
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
              );
            },
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
    required this.flagged,
    required this.matcher,
    required this.onReferenceTap,
    required this.intros,
    required this.atlas,
    required this.comparison,
    required this.comparisonLabel,
    required this.primaryLabel,
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
  final Set<int> flagged;
  final ReferenceMatcher? matcher;
  final ValueChanged<Reference>? onReferenceTap;
  final BookIntros? intros;

  /// Read once the atlas asset is decoded; null until then.
  final AtlasData? atlas;

  /// The same chapter in a second translation, when comparing.
  final Chapter? comparison;
  final String comparisonLabel;
  final String primaryLabel;

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
    if (widget.chapter != oldWidget.chapter ||
        widget.comparison != oldWidget.comparison) {
      _buildAnchors();
      _reportedVerse = 0;
    }
    if (widget.scrollToVerse != oldWidget.scrollToVerse) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToVerse());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  bool get _comparing => widget.comparison != null;

  void _buildAnchors() {
    _verseKeys.clear();
    if (_comparing) {
      // The compare view is one row per verse, so every verse is an anchor.
      _blockKeys = const [];
      for (var verse = 1; verse <= widget.chapter.verseCount; verse++) {
        _verseKeys[verse] = GlobalKey();
      }
      return;
    }
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

  /// The anchor for [verse], or the paragraph it sits inside. Only verses
  /// that begin a block carry an anchor, and in prose most verses do not.
  GlobalKey? _anchorFor(int verse) {
    final exact = _verseKeys[verse];
    if (exact != null) return exact;
    var best = 0;
    for (final candidate in _verseKeys.keys) {
      if (candidate < verse && candidate > best) best = candidate;
    }
    return best == 0 ? null : _verseKeys[best];
  }

  void _jumpToVerse() => _scrollToVerse(widget.scrollToVerse);

  /// Scrolls the chapter to a verse, or to its paragraph where the verse
  /// itself carries no anchor. Used by the pending-jump machinery and by the
  /// map, where tapping a reference should land on the words.
  void _scrollToVerse(int? verse) {
    if (verse == null || verse <= 1) return;
    final context = _anchorFor(verse)?.currentContext;
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
    final children = <Widget>[_chapterHeading(theme)];

    if (_comparing) {
      children.add(_compareBody(theme));
    } else {
      var isFirst = true;
      final blocks = widget.chapter.blocks;
      for (var i = 0; i < blocks.length; i++) {
        final block = blocks[i];
        final blockWidget = ScriptureBlock(
          block: block,
          style: widget.style,
          highlights: widget.highlights,
          flagged: widget.flagged,
          isFirst: isFirst,
          matcher: widget.matcher,
          onReferenceTap: widget.onReferenceTap,
          onVerseTap: widget.onVerseTap,
          onNoteTap: widget.onNoteTap,
        );
        final key = i < _blockKeys.length ? _blockKeys[i] : null;
        children.add(
          key == null
              ? blockWidget
              : KeyedSubtree(key: key, child: blockWidget),
        );
        // A heading, title or stanza break starts a new passage, and the
        // paragraph opening it is set flush like the chapter's first.
        isFirst = !block.style.isVerseText;
      }
    }

    children.add(
      _ChapterFooter(
        hasPrevious: widget.hasPrevious,
        hasNext: widget.hasNext,
        onStep: widget.onStep,
      ),
    );

    // No scrollbar over the text: a page of Scripture is read, not scrubbed,
    // and the desktop and web defaults would draw one down the margin.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _comparing ? 1000 : 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  /// The places this chapter names, with their verses, once the atlas has
  /// been read.
  List<ChapterPlace> get _places =>
      widget.atlas?.inChapter(widget.book.code, widget.chapter.number) ??
      const [];

  Widget _chapterHeading(ThemeData theme) {
    final places = _places;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Tapping the book's name opens its background note.
              InkWell(
                onTap: () =>
                    showBookSheet(context, widget.book, intros: widget.intros),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.book.name.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              // Offered only where the chapter names somewhere on the map.
              if (places.isNotEmpty) ...[
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => showMapSheet(
                    context,
                    data: widget.atlas!,
                    title: '${widget.book.name} ${widget.chapter.number}',
                    places: places,
                    // A verse tapped on the map is somewhere to read, so the
                    // map gets out of the way and the chapter scrolls to it.
                    onVerse: (verse) => _scrollToVerse(verse),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.map_outlined,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          places.length == 1
                              ? '1 PLACE'
                              : '${places.length} PLACES',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
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
    );
  }

  /// Verse-by-verse view of two translations. Wide windows put them in
  /// columns; narrow ones stack each pair.
  Widget _compareBody(ThemeData theme) {
    final other = widget.comparison!;
    final style = widget.style;
    final count = widget.chapter.verseCount > other.verseCount
        ? widget.chapter.verseCount
        : other.verseCount;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620;
        final rows = <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                _translationChip(theme, widget.primaryLabel, true),
                const SizedBox(width: 8),
                _translationChip(theme, widget.comparisonLabel, false),
              ],
            ),
          ),
        ];

        for (var verse = 1; verse <= count; verse++) {
          final mine = widget.chapter.verseText(verse);
          final theirs = other.verseText(verse);
          if (mine.isEmpty && theirs.isEmpty) continue;
          final tint = widget.highlights[verse];
          final left = _compareCell(theme, style, verse, mine, tint, true);
          final right = _compareCell(theme, style, verse, theirs, tint, false);
          rows.add(
            KeyedSubtree(
              key: _verseKeys[verse],
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: columns
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: left),
                          const SizedBox(width: 20),
                          Expanded(child: right),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [left, const SizedBox(height: 6), right],
                      ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _translationChip(ThemeData theme, String label, bool primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: primary
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: primary
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _compareCell(
    ThemeData theme,
    ScriptureStyle style,
    int verse,
    String text,
    Color? tint,
    bool primary,
  ) {
    return GestureDetector(
      onTap: primary ? () => widget.onVerseTap(verse) : null,
      child: Container(
        decoration: BoxDecoration(
          color: primary ? tint : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.top,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text('$verse', style: style.verseNumber),
                ),
              ),
              TextSpan(text: text.isEmpty ? '—' : text),
            ],
          ),
          style: primary
              ? style.body
              : style.body.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

/// The book-and-chapter button in the app bar.
class _ReferenceButton extends StatelessWidget {
  const _ReferenceButton({
    required this.label,
    required this.onTap,
    this.badge,
  });

  final String label;
  final VoidCallback onTap;

  /// Abbreviation of the translation being compared, when there is one.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Actions for a tapped verse: highlight, bookmark, note, copy.
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
    return AnimatedBuilder(
      animation: reading,
      builder: (context, _) {
        final mark = reading.markFor(reference);
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
                Row(
                  children: [
                    for (var i = 0; i < ReadingStore.paletteSize; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _Swatch(
                          color: AppTheme.highlightSwatch(i),
                          name: AppTheme.highlightNames[i],
                          selected: mark?.colorIndex == i,
                          onTap: () => reading.setHighlight(
                            reference,
                            mark?.colorIndex == i ? null : i,
                          ),
                        ),
                      ),
                    if (mark?.highlighted ?? false)
                      IconButton(
                        tooltip: 'Remove highlight',
                        icon: const Icon(Icons.format_color_reset_rounded),
                        onPressed: () => reading.setHighlight(reference, null),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        final added = reading.toggleBookmark(reference);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              added
                                  ? 'Bookmarked ${reference.label}'
                                  : 'Bookmark removed',
                            ),
                          ),
                        );
                      },
                      icon: Icon(
                        (mark?.bookmarked ?? false)
                            ? Icons.bookmark_remove_rounded
                            : Icons.bookmark_add_rounded,
                      ),
                      label: Text(
                        (mark?.bookmarked ?? false) ? 'Bookmarked' : 'Bookmark',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _editNote(context),
                      icon: Icon(
                        (mark?.hasNote ?? false)
                            ? Icons.edit_note_rounded
                            : Icons.note_add_outlined,
                      ),
                      label: Text(
                        (mark?.hasNote ?? false) ? 'Note' : 'Add note',
                      ),
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
                if (mark?.hasNote ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        mark!.note,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editNote(BuildContext context) async {
    final controller = TextEditingController(
      text: reading.markFor(reference)?.note ?? '',
    );
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(reference.label),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
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
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;
    reading.setNote(reference, note);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: selected ? 'Remove $name highlight' : 'Highlight $name',
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface
                  : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.black87)
              : null,
        ),
      ),
    );
  }
}
