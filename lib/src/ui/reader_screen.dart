import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show ShareParams;

import '../app_scope.dart';
import '../data/library.dart';
import '../data/atlas.dart';
import '../data/book_intros.dart';
import '../data/cross_references.dart';
import '../data/originals.dart';
import '../data/marks.dart';
import '../data/neural_voices.dart';
import '../data/plan_progress.dart';
import '../data/read_aloud.dart';
import '../data/read_aloud_art.dart';
import '../data/read_aloud_session.dart';
import '../data/reference_search.dart';
import '../data/settings.dart';
import '../data/updates.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';
import '../model/reading_plan.dart';
import '../model/strongs_codec.dart';
import '../model/verse_selection.dart';
import '../model/xref_codec.dart';
import 'book_sheet.dart';
import 'concordance_screen.dart';
import 'cross_reference_sheet.dart';
import 'original_sheet.dart';
import 'map_sheet.dart';
import 'update_sheet.dart';
import 'display_sheet.dart';
import 'library_screen.dart';
import 'navigator_sheet.dart';
import 'plans_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'verse_share.dart';
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

  /// The plan day the reader was last sent to read, so the end of each of
  /// its chapters can offer to tick it off — and keep offering Undo after
  /// the day is finished and the plan has moved on to the next.
  PlanReading? _planFocus;

  /// Verses chosen together to copy, share or highlight, and the page they
  /// are on. A selection belongs to one chapter; turning the page ends it.
  final Set<int> _selected = {};
  int? _selectionPage;

  bool get _selecting => _selected.isNotEmpty;

  /// Reading aloud: made once, and following the translation that is open.
  ReadAloud? _readAloud;
  ReadAloud get _voice => _readAloud ??= _makeReadAloud();

  ReadAloud _makeReadAloud() {
    final voice = ReadAloud(
      engine: createSpeechEngine(),
      chapterFor: (reference) =>
          _bible.bookByCode(reference.bookCode)?.chapter(reference.chapter),
      nextChapter: _chapterAfterListening,
      onChapterHeard: _heardChapter,
      onPlace: (place) => _reading.listeningPlace = place?.encode(),
    );
    voice.addListener(_followVoice);
    return voice;
  }

  /// Whether this platform can read aloud at all.
  bool get _canListen => _voice.engine.isAvailable;

  /// What to read after [chapter]: the rest of the plan day it belongs to,
  /// where it belongs to one, and otherwise simply the next chapter.
  Reference? _chapterAfterListening(Reference chapter) {
    final hit = _planSlotFor(chapter);
    if (hit != null) {
      final day = hit.day;
      for (var i = hit.slot - day.firstSlot + 1; i < day.slotCount; i++) {
        if (hasChapter(_bible, day.chapters[i])) return day.chapters[i];
      }
      // The day is heard; that is where a plan's listening stops.
      return null;
    }
    final page = _pageFor(chapter);
    return page + 1 < _index.length ? _index[page + 1] : null;
  }

  /// A plan chapter heard from its first verse to its last counts as read,
  /// since nobody listening can reach the button at the end of it.
  void _heardChapter(Reference chapter) {
    final hit = _planSlotFor(chapter);
    if (hit == null) return;
    _reading.setPlanSlot(hit.progress.plan.id, hit.slot, read: true);
    _planFocus = PlanReading(
      planId: hit.progress.plan.id,
      day: hit.day.number,
      chapter: chapter,
    );
  }

  /// Keeps the page on the chapter being read.
  void _followVoice() {
    if (!mounted) return;
    final current = _voice.current;
    if (current != null &&
        (current.bookCode != _current.bookCode ||
            current.chapter != _current.chapter)) {
      final page = _pageFor(current);
      setState(() {
        _page = page;
        _pendingPage = page;
        _pendingVerse = null;
      });
      if (_pages.hasClients) _pages.jumpToPage(page);
      _reading.savePosition(current.withVerse(null));
    } else {
      setState(() {});
    }
    final error = _voice.error;
    if (error != null && !_voice.isActive) {
      _voice.error = null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _configureVoice() {
    // One of OpenWord's own voices has a model to load, and it is loaded
    // now rather than when Listen is tapped, so that it speaks at once.
    final own = NeuralModel.parse(_settings.speechVoice) != null;
    final voice = own && _canListen ? _voice : _readAloud;
    voice?.configure(
      language: _bible.translation.language,
      rate: _settings.speechRate,
      voice: _settings.speechVoice,
    );
    if (own) voice?.prepare();
  }

  /// Said once, when the voice chosen turns out to be too slow for this
  /// device to keep up with, which is heard only as pauses.
  NeuralModel? _toldTooSlow;
  NeuralVoices? _neural;

  void _onNeuralVoices() {
    final slow = _neural?.fallingBehind;
    if (!mounted ||
        slow == null ||
        slow == _toldTooSlow ||
        NeuralModel.parse(_settings.speechVoice)?.$1 != slow) {
      return;
    }
    _toldTooSlow = slow;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          slow == NeuralModel.kitten
              ? 'This device makes ${slow.title}’s speech more slowly than '
                    'it is heard, so it pauses between sentences. The '
                    'device’s own voices do not.'
              : 'This device makes ${slow.title}’s speech more slowly than '
                    'it is heard, so it pauses between sentences. Kitten '
                    'is quicker.',
        ),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(label: 'Voices', onPressed: _openVoiceSettings),
      ),
    );
  }

  /// Where listening got to in [chapter] before, if it got anywhere.
  ListeningPlace? _keptPlaceIn(Reference chapter) {
    final place = ListeningPlace.decode(_reading.listeningPlace);
    if (place == null ||
        place.atTop ||
        place.verse.bookCode != chapter.bookCode ||
        place.verse.chapter != chapter.chapter) {
      return null;
    }
    return place;
  }

  /// What the chapter's own Listen does: pauses or resumes what is being
  /// read of it, takes up where listening to it stopped before, or starts
  /// it from the top.
  void _listenToChapter(Reference chapter) {
    final voice = _readAloud;
    final current = voice?.current;
    if (voice != null &&
        current != null &&
        current.bookCode == chapter.bookCode &&
        current.chapter == chapter.chapter) {
      voice.isPlaying ? voice.pause() : voice.resume();
      return;
    }
    final kept = _keptPlaceIn(chapter);
    if (kept != null) {
      _listen(kept.verse, offset: kept.offset, fromTop: kept.fromTop);
    } else {
      _listen(chapter);
    }
  }

  /// What the chapter's Listen says it will do.
  String _listenLabel(Reference chapter) {
    final voice = _readAloud;
    final current = voice?.current;
    if (voice != null &&
        current != null &&
        current.bookCode == chapter.bookCode &&
        current.chapter == chapter.chapter) {
      return voice.isPlaying ? 'PAUSE' : 'RESUME';
    }
    return _keptPlaceIn(chapter) != null ? 'RESUME' : 'LISTEN';
  }

  void _listen(
    Reference from, {
    Set<int>? only,
    int offset = 0,
    bool fromTop = false,
  }) {
    _configureVoice();
    _voice.play(from, only: only, offset: offset, fromTop: fromTop);
    // Handed to the system as well, so it goes on with the screen off and
    // answers the lock screen. Started the first time it is wanted rather
    // than at launch, and never in the way if it cannot be had.
    final scheme = Theme.of(context).colorScheme;
    final colours = ArtColours(
      from: scheme.primaryContainer,
      to: scheme.tertiaryContainer,
      ink: scheme.onPrimaryContainer,
      accent: scheme.primary,
    );
    startReadAloudSession(
      _voice,
      () => _bible.translation.name,
      artwork: (chapter) => chapterArtFile(chapter, colours: colours),
    ).then((session) {
      if (!mounted) return;
      _session = session;
      final error = readAloudSessionError;
      if (session == null && error != null && !_toldAboutSession) {
        // Said once, so that a lock screen that stays blank has a reason
        // someone can pass on, rather than silence.
        _toldAboutSession = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lock-screen controls could not start, so reading aloud '
              'stops when the screen does. ($error)',
            ),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    });
  }

  bool _toldAboutSession = false;

  /// The system's media session, once reading aloud has started it.
  ReadAloudHandler? _session;

  Future<void> _openVoiceSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _VoiceSheet(
        settings: _settings,
        engine: _voice.engine,
        neural: neuralVoices,
        language: _bible.translation.language,
      ),
    );
    _configureVoice();
  }

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
  CrossReferences? _xrefs;
  Originals? _originals;

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

  /// Reads the cross-references in the background, for the same reason as
  /// the atlas: nothing should wait on them to open a chapter.
  void _loadCrossReferences(AssetBundle bundle) {
    if (_xrefs != null) return;
    final xrefs = CrossReferences(bundle: bundle);
    _xrefs = xrefs;
    xrefs.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Reads the Hebrew and Greek in the background. Four megabytes, so it
  /// is never waited on: the verse sheet offers it once it is there.
  void _loadOriginals(AssetBundle bundle) {
    if (_originals != null) return;
    final originals = Originals(bundle: bundle);
    _originals = originals;
    originals.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _library = scope.library;
    _intros ??= BookIntros(bundle: scope.library.bundle);
    _loadAtlas(scope.library.bundle);
    _loadCrossReferences(scope.library.bundle);
    _loadOriginals(scope.library.bundle);
    if (!_askedAboutUpdates) {
      _askedAboutUpdates = true;
      _announceUpdate(scope.updates);
    }
    if (!identical(_matcherFor, scope.library.bible)) {
      _matcherFor = scope.library.bible;
      _matcher = ReferenceMatcher(scope.library.bible!.books);
    }
    if (_readAloud != null && !identical(_bible, scope.library.bible)) {
      // A different translation: what was being read is not this one.
      _readAloud!.stop();
    }
    _bible = scope.library.bible!;
    _loadOwnOriginals();
    _settings = scope.settings;
    _reading = scope.reading;
    _rebuildIndex();
    if (!_restored) {
      _restored = true;
      _settings.addListener(_onSettingsChanged);
      _neural = neuralVoices..addListener(_onNeuralVoices);
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
        // A voice of OpenWord's own starts loading as the app opens.
        if (mounted && NeuralModel.parse(_settings.speechVoice) != null) {
          _configureVoice();
        }
      });
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _neural?.removeListener(_onNeuralVoices);
    _readAloud?.removeListener(_followVoice);
    if (_readAloud case final voice?) _session?.release(voice);
    _readAloud?.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    _configureVoice();
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
          // From the outline: flattening the Bible must not unpack it.
          for (final number in book.chapterNumbers)
            Reference(book.code, number),
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

  /// The verse being read aloud, where it is on this page.
  int? _speakingVerseOn(Reference chapter) {
    final current = _readAloud?.current;
    if (current == null ||
        current.bookCode != chapter.bookCode ||
        current.chapter != chapter.chapter) {
      return null;
    }
    return current.verse;
  }

  /// A page's highlights with the selection laid over them, so a
  /// selected verse shows as selected whatever colour it already had.
  Map<int, Color> _withSelection(
    int page,
    Map<int, Color> highlights,
    ColorScheme scheme,
  ) {
    if (page != _selectionPage || _selected.isEmpty) return highlights;
    final tint = scheme.primary.withValues(alpha: 0.28);
    return {
      ...highlights,
      for (final verse in _selected)
        verse: highlights[verse] == null
            ? tint
            : Color.alphaBlend(tint, highlights[verse]!),
    };
  }

  Future<void> _openPlans() async {
    final result = await Navigator.of(
      context,
    ).push<PlanReading>(MaterialPageRoute(builder: (_) => const PlansScreen()));
    if (result == null || !mounted) return;
    setState(() => _planFocus = result);
    if (hasChapter(_bible, result.chapter)) {
      _goTo(result.chapter);
    }
  }

  /// Where [chapter] falls in a plan the reader is following: the day they
  /// were sent to first, then each plan's current day.
  ({PlanProgress progress, PlanDay day, int slot})? _planSlotFor(
    Reference chapter,
  ) {
    final candidates = <(PlanProgress, PlanDay)>[];
    final focus = _planFocus;
    if (focus != null) {
      final progress = _reading.progressFor(focus.planId);
      if (progress != null &&
          focus.day >= 1 &&
          focus.day <= progress.plan.length) {
        candidates.add((progress, progress.plan.days[focus.day - 1]));
      }
    }
    for (final progress in _reading.plans) {
      final day = progress.currentDay;
      if (day != null) candidates.add((progress, day));
    }
    for (final (progress, day) in candidates) {
      for (var i = 0; i < day.slotCount; i++) {
        final entry = day.chapters[i];
        if (entry.bookCode == chapter.bookCode &&
            entry.chapter == chapter.chapter) {
          return (progress: progress, day: day, slot: day.firstSlot + i);
        }
      }
    }
    return null;
  }

  /// The next chapter of the day still to read after [slot], skipping any
  /// this translation does not have.
  Reference? _nextInDay(PlanProgress progress, PlanDay day, int slot) {
    for (var i = 0; i < day.slotCount; i++) {
      final candidate = day.firstSlot + i;
      if (candidate == slot || progress.isRead(candidate)) continue;
      final chapter = day.chapters[i];
      if (hasChapter(_bible, chapter)) return chapter;
    }
    return null;
  }

  Widget? _planCardFor(Reference chapter) {
    final hit = _planSlotFor(chapter);
    if (hit == null) return null;
    final (:progress, :day, :slot) = hit;
    final next = _nextInDay(progress, day, slot);
    final plan = progress.plan;
    return PlanChapterCard(
      planName: plan.name,
      day: day.number,
      read: progress.isRead(slot),
      nextLabel: next == null ? null : Passage.labelFor(next),
      onDone: () {
        _reading.setPlanSlot(plan.id, slot, read: true);
        _planFocus = PlanReading(
          planId: plan.id,
          day: day.number,
          chapter: chapter,
        );
        if (next != null) {
          _goTo(next);
          return;
        }
        final after = _reading.progressFor(plan.id);
        final finishedDay = after != null && after.isDayRead(day);
        if (!finishedDay) {
          // Everything else in the day is in a book this translation
          // lacks; the plan page says so.
          setState(() {});
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              after.isComplete
                  ? 'You finished ${plan.name}. Well done.'
                  : 'Day ${day.number} done. That’s today’s reading.',
            ),
            action: SnackBarAction(label: 'Plans', onPressed: _openPlans),
          ),
        );
        setState(() {});
      },
      onUndo: () => _reading.setPlanSlot(plan.id, slot, read: false),
      onNext: next == null ? null : () => _goTo(next),
    );
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

  /// Holding a verse starts a selection, or adds to the one under way.
  void _onVerseLongPress(int verse) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectionPage != _page) _selected.clear();
      _selectionPage = _page;
      _selected.add(verse);
    });
  }

  /// Runs a selection action on one verse, from the verse's own sheet.
  void _startWith(int verse, Future<void> Function() action) {
    setState(() {
      _selected
        ..clear()
        ..add(verse);
      _selectionPage = _page;
    });
    action();
  }

  void _toggleSelected(int verse) {
    setState(() {
      if (!_selected.remove(verse)) _selected.add(verse);
      if (_selected.isEmpty) _selectionPage = null;
    });
  }

  void _clearSelection() {
    if (!_selecting) return;
    setState(() {
      _selected.clear();
      _selectionPage = null;
    });
  }

  String get _selectionCitation => VerseSelection.citation(_current, _selected);

  String get _selectionQuotation => VerseSelection.quotation(
    chapter: _currentChapter,
    reference: _current,
    verses: _selected,
    translation: _bible.translation.abbreviation,
  );

  Future<void> _copySelection() async {
    final citation = _selectionCitation;
    await Clipboard.setData(ClipboardData(text: _selectionQuotation));
    if (!mounted) return;
    _clearSelection();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Copied $citation')));
  }

  Future<void> _shareSelection() async {
    final params = ShareParams(
      text: _selectionQuotation,
      subject: _selectionCitation,
    );
    _clearSelection();
    try {
      await VerseSharing.share(params);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not share: $error')));
    }
  }

  Future<void> _shareSelectionAsImage() async {
    final text = VerseSelection.text(_currentChapter, _selected);
    final citation = _selectionCitation;
    if (text.isEmpty) return;
    await showVerseImageSheet(
      context,
      text: text,
      citation: citation,
      translation: _bible.translation.name,
    );
    _clearSelection();
  }

  Future<void> _highlightSelection() async {
    final verses = [..._selected];
    final chapter = _current;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Highlight ${VerseSelection.citation(chapter, verses)}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < ReadingStore.paletteSize; i++)
                    _Swatch(
                      color: AppTheme.highlightSwatch(i),
                      name: AppTheme.highlightNames[i],
                      selected: false,
                      onTap: () => Navigator.of(sheetContext).pop(i),
                    ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop(-1),
                    icon: const Icon(Icons.format_color_reset_rounded),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    for (final verse in verses) {
      _reading.setHighlight(
        chapter.withVerse(verse),
        chosen < 0 ? null : chosen,
      );
    }
    _clearSelection();
  }

  void _onVerseTap(int verse) {
    if (_selecting) {
      _toggleSelected(verse);
      return;
    }
    final reference = _current.withVerse(verse);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // The sheet grew a row of study tools; on a short screen it has to be
      // able to scroll rather than overflow.
      isScrollControlled: true,
      builder: (_) => _VerseSheet(
        reference: reference,
        text: _currentChapter.verseText(verse),
        // Matthew 17:21 and the others the critical texts leave out are
        // numbered in the tradition and absent from the text. Saying so
        // beats an empty sheet with no explanation.
        omitted: _currentChapter.isOmitted(verse),
        reading: _reading,
        crossReferences: _references?.forVerse(reference) ?? const [],
        onCrossReferences: () => _openCrossReferences(reference),
        originalWords: _originalLanguages?.wordsFor(reference) ?? const [],
        onOriginal: () => _openOriginal(reference),
        onSelect: () => _onVerseLongPress(verse),
        onListen: _canListen ? () => _listen(reference) : null,
        onShare: () => _startWith(verse, _shareSelection),
        onImage: () => _startWith(verse, _shareSelectionAsImage),
      ),
    );
  }

  /// The translation's own cross-references, where its file brought them.
  /// Rebuilt whenever the translation changes.
  CrossReferences? _ownXrefs;
  String? _ownXrefsFor;

  /// The cross-references to use: the translation's own where it has them,
  /// the bundled English set where its numbering allows, and none at all
  /// otherwise.
  CrossReferences? get _references {
    final id = _bible.translation.id;
    if (_ownXrefsFor != id) {
      _ownXrefsFor = id;
      final chunk = _bible.extras[CrossReferences.chunkTag];
      _ownXrefs = chunk == null ? null : CrossReferences.fromChunk(chunk);
    }
    return _ownXrefs ?? (_anchored ? _xrefs : null);
  }

  /// Whether this translation numbers its verses the way the bundled
  /// cross-references and original-language layer do.
  ///
  /// Both are anchored to one numbering. Against a Bible that numbers
  /// differently they would not fail — they would land on the wrong verse,
  /// confidently — so where an import has been measured and does not
  /// match, they are not offered. A translation that never said gets the
  /// benefit of the doubt, which is every file written before this was
  /// checked; and a reader who wants them regardless can say so in
  /// Settings, which is the one judgement the app is in no position to
  /// make for them.
  bool get _anchored => _settings.offersVerseKeyedLayers(_bible.translation);

  /// The translation's own Hebrew and Greek, where its file brought them.
  /// Loaded off the main isolate, so it appears once it is ready.
  Originals? _ownOriginals;
  String? _ownOriginalsFor;

  /// Starts reading a translation's own layer, where its file brought one.
  ///
  /// Eagerly, when the translation changes, rather than when a verse is
  /// first tapped: unpacking is measured in megabytes, and a verse sheet
  /// already on screen does not gain the Hebrew when it arrives — it was
  /// built with what there was.
  void _loadOwnOriginals() {
    final id = _bible.translation.id;
    if (_ownOriginalsFor == id) return;
    _ownOriginalsFor = id;
    _ownOriginals = null;
    final chunk = _bible.extras[Originals.chunkTag];
    if (chunk == null) return;
    Originals.fromChunk(chunk).then((own) {
      // The reader may have moved on to another translation while those
      // megabytes were being unpacked.
      if (!mounted || _ownOriginalsFor != id || own == null) return;
      setState(() => _ownOriginals = own);
    });
  }

  /// The original-language layer to use: the translation's own where its
  /// file carries one, the bundled layer where its numbering allows, and
  /// none at all otherwise.
  Originals? get _originalLanguages =>
      _ownOriginals ?? (_anchored ? _originals : null);

  /// The Hebrew or Greek of a verse, and from there its dictionary entry
  /// and everywhere else the word is used.
  Future<void> _openOriginal(Reference reference) async {
    final originals = _originalLanguages;
    if (originals == null) return;
    final words = originals.wordsFor(reference);
    if (words.isEmpty) return;
    final verse = reference.verse;
    final wanted = await showOriginal(
      context,
      reference: reference,
      english: verse == null ? '' : _currentChapter.verseText(verse),
      words: words,
      originals: originals,
    );
    if (wanted == null || !mounted) return;
    await _openConcordance(wanted);
  }

  /// Every verse a Strong's number occurs in; choosing one goes there.
  Future<void> _openConcordance(StrongsNumber number) async {
    final originals = _originalLanguages;
    if (originals == null) return;
    final chosen = await showConcordance(
      context,
      number: number,
      originals: originals,
      bible: _bible,
    );
    if (chosen == null || !mounted) return;
    if (_bible.bookByCode(chosen.bookCode) == null) return;
    _goTo(chosen);
  }

  /// Opens the cross-references of a verse, and goes wherever one of them
  /// leads.
  Future<void> _openCrossReferences(Reference reference) async {
    final anchors = _references?.forVerse(reference) ?? const <XrefAnchor>[];
    if (anchors.isEmpty) return;
    final chosen = await showCrossReferences(
      context,
      reference: reference,
      anchors: anchors,
      bible: _bible,
    );
    if (chosen == null || !mounted) return;
    if (_bible.bookByCode(chosen.bookCode) == null) return;
    _goTo(chosen);
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
        const SingleActivator(LogicalKeyboardKey.keyP): _openPlans,
        const SingleActivator(LogicalKeyboardKey.escape): _clearSelection,
      },
      child: Focus(
        autofocus: true,
        // Back ends a selection before it leaves anything.
        child: PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _clearSelection();
          },
          child: Scaffold(
            bottomNavigationBar: _selecting
                ? _SelectionBar(
                    citation: _selectionCitation,
                    count: _selected.length,
                    onClose: _clearSelection,
                    onCopy: _copySelection,
                    onShare: _shareSelection,
                    onImage: _shareSelectionAsImage,
                    onHighlight: _highlightSelection,
                  )
                : (_readAloud?.isActive ?? false)
                ? _PlayerBar(
                    voice: _voice,
                    rate: _settings.speechRate,
                    onSettings: _openVoiceSettings,
                  )
                : null,
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
                AnimatedBuilder(
                  animation: _reading,
                  builder: (context, _) => IconButton(
                    // A dot while today's reading in a plan is still to do;
                    // nothing louder than that.
                    icon: Badge(
                      isLabelVisible: _reading.hasPlanReadingDue,
                      smallSize: 8,
                      // The theme's colour, not the error red a badge
                      // defaults to: a reading waiting is not a fault.
                      backgroundColor: theme.colorScheme.primary,
                      child: const Icon(Icons.event_note_rounded),
                    ),
                    tooltip: 'Reading plans (P)',
                    onPressed: _openPlans,
                  ),
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
              animation: Listenable.merge([
                _settings,
                _reading,
                _library,
                ?_readAloud,
              ]),
              builder: (context, _) {
                final comparison = _library.comparison;
                return PageView.builder(
                  controller: _pages,
                  itemCount: _index.length,
                  onPageChanged: (page) {
                    final programmatic = page == _pendingPage;
                    setState(() {
                      _page = page;
                      if (_selectionPage != page) {
                        _selected.clear();
                        _selectionPage = null;
                      }
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
                      direction: _bible.translation.direction,
                      style: ScriptureStyle.of(context, _settings),
                      highlights: _withSelection(page, {
                        for (final entry
                            in _reading
                                .highlightsIn(book.code, chapter.number)
                                .entries)
                          entry.key: AppTheme.highlights(
                            theme.colorScheme,
                          )[entry.value % ReadingStore.paletteSize],
                      }, theme.colorScheme),
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
                      comparisonLabel:
                          comparison?.translation.abbreviation ?? '',
                      primaryLabel: _bible.translation.abbreviation,
                      scrollToVerse: page == _pendingPage
                          ? _pendingVerse
                          : null,
                      onVerseTap: _onVerseTap,
                      onVerseLongPress: _onVerseLongPress,
                      onNoteTap: _onNoteTap,
                      onTopVerseChanged: (verse) {
                        if (page != _page) return;
                        _reading.savePosition(
                          Reference(book.code, chapter.number, verse),
                        );
                      },
                      onStep: _step,
                      planCard: _planCardFor(reference),
                      onListen: _canListen && comparison == null
                          ? () => _listenToChapter(reference)
                          : null,
                      listenLabel: _listenLabel(reference),
                      speakingVerse: _speakingVerseOn(reference),
                      hasPrevious: page > 0,
                      hasNext: page < _index.length - 1,
                    );
                  },
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
    required this.direction,
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
    this.onVerseLongPress,
    required this.onStep,
    required this.hasPrevious,
    required this.hasNext,
    this.planCard,
    this.onListen,
    this.listenLabel = 'LISTEN',
    this.speakingVerse,
    super.key,
  });

  final Book book;
  final Chapter chapter;

  /// Which way this translation runs. Everything shipped here runs
  /// left-to-right; an imported Hebrew or Arabic Bible does not, and the
  /// file says so.
  final ReadingDirection direction;

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
  final ValueChanged<int>? onVerseLongPress;
  final ValueChanged<int> onNoteTap;
  final ValueChanged<int> onTopVerseChanged;
  final ValueChanged<int> onStep;
  final bool hasPrevious;
  final bool hasNext;

  /// Where the chapter is part of a reading plan, the card that ticks it
  /// off; it sits where the reader finishes the chapter.
  final Widget? planCard;

  /// Starts reading the chapter aloud, where the platform can.
  final VoidCallback? onListen;

  /// LISTEN, or PAUSE or RESUME while it is being read or has been begun.
  final String listenLabel;

  /// The verse being read aloud, which is marked and kept in view.
  final int? speakingVerse;

  @override
  State<_ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<_ChapterPage>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();

  /// Twice, because once reads as a trick of the eye and three times is
  /// fussing. The whole point is to be noticed and then to be over.
  static const int _flashes = 2;
  static const Duration _flashLength = Duration(milliseconds: 1100);

  /// The verse the reader was sent to, while it is being pointed out.
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: _flashLength,
  );
  int? _flashVerse;

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
    _flash.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _flashVerse = null);
      }
    });
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
    final speaking = widget.speakingVerse;
    if (speaking != null && speaking != oldWidget.speakingVerse) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _keepInView(speaking),
      );
    }
  }

  /// Follows the voice down the page, gently: the verse being read is
  /// brought a third of the way down, not snapped to the top.
  void _keepInView(int verse) {
    if (!mounted) return;
    final target = _anchorFor(verse)?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: _reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
      alignment: 0.3,
    );
  }

  /// The highlights with the verse being read aloud laid over them.
  Map<int, Color> get _highlightsNow {
    final verse = widget.speakingVerse;
    if (verse == null) return widget.highlights;
    final tint = Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.22);
    final under = widget.highlights[verse];
    return {
      ...widget.highlights,
      verse: under == null ? tint : Color.alphaBlend(tint, under),
    };
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flash.dispose();
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
    if (verse == null || verse < 1) return;
    _pointOut(verse);
    // Verse 1 is already at the top of the chapter; there is nowhere to
    // scroll to, which is not a reason to leave it unmarked.
    if (verse == 1) return;
    final context = _anchorFor(verse)?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  /// Marks a verse the reader was sent to, so they do not have to hunt for
  /// it.
  ///
  /// Scrolling a verse into view is not the same as showing it: in prose a
  /// verse is a sentence or two in the middle of a paragraph, with nothing
  /// but a small number to find it by. This puts a colour behind it and
  /// takes it away again, twice, and then the page is as it was.
  void _pointOut(int verse) {
    setState(() => _flashVerse = verse);
    _flash.forward(from: 0);
  }

  /// How strong the mark is now: nothing, to full, to nothing, twice over.
  double get _flashStrength {
    if (_flashVerse == null) return 0;
    // Where the platform is set to reduce motion, hold the colour steady
    // rather than blinking it, and let it fade at the end.
    if (_reduceMotion) {
      return _flash.value > 0.75 ? (1 - _flash.value) * 4 : 1;
    }
    return (1 - math.cos(_flashes * 2 * math.pi * _flash.value)) / 2;
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// The highlights to draw with, the pointed-out verse among them.
  ///
  /// A reader's own highlight stays under it: the mark is laid over
  /// whatever colour the verse already had, and is gone a second later.
  Map<int, Color> _highlightsWith(int verse, double strength) {
    // Exactly zero twice during the pulse, and floating point will not
    // land on it; below this there is nothing to see anyway.
    if (strength <= 0.01) return widget.highlights;
    final mark = Theme.of(context).colorScheme.primary
        .withValues(alpha: 0.30 * strength);
    final under = widget.highlights[verse];
    return {
      ...widget.highlights,
      verse: under == null ? mark : Color.alphaBlend(mark, under),
    };
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
      final marked = _flashVerse;
      for (var i = 0; i < blocks.length; i++) {
        final block = blocks[i];
        final firstOfBlock = isFirst;
        ScriptureBlock build(Map<int, Color> highlights) => ScriptureBlock(
          block: block,
          labelFor: widget.chapter.labelFor,
          style: widget.style,
          highlights: highlights,
          flagged: widget.flagged,
          isFirst: firstOfBlock,
          matcher: widget.matcher,
          onReferenceTap: widget.onReferenceTap,
          onVerseTap: widget.onVerseTap,
          onVerseLongPress: widget.onVerseLongPress,
          onNoteTap: widget.onNoteTap,
        );
        // Only the block holding the verse is rebuilt as the mark comes
        // and goes. Animating the whole chapter would rebuild every
        // paragraph of it sixty times a second to colour one sentence.
        final Widget blockWidget =
            marked != null &&
                block.segments.any((segment) => segment.verse == marked)
            ? AnimatedBuilder(
                animation: _flash,
                builder: (_, _) =>
                    build(_highlightsWith(marked, _flashStrength)),
              )
            : build(_highlightsNow);
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

    if (widget.planCard != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 28),
          // The card is the app talking, not the text, so it keeps the
          // device's direction even under a right-to-left translation.
          child: Directionality(
            textDirection: Directionality.of(this.context),
            child: widget.planCard!,
          ),
        ),
      );
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
            // The page runs the way the translation does. The chrome around
            // it keeps following the device, which is the reader's own
            // language rather than the text's.
            child: Directionality(
              textDirection: widget.direction == ReadingDirection.rtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
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
          // Wraps rather than runs off a narrow phone: a long book name,
          // its places and Listen do not always fit on one line.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
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
              if (widget.onListen != null) ...[
                const SizedBox(width: 10),
                InkWell(
                  onTap: widget.onListen,
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
                          switch (widget.listenLabel) {
                            'PAUSE' => Icons.pause_rounded,
                            'RESUME' => Icons.play_arrow_rounded,
                            _ => Icons.headphones_rounded,
                          },
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.listenLabel,
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
            // What the translation calls it, where it says: the Psalter
            // has psalms, not chapters.
            widget.chapter.label.isNotEmpty
                ? widget.chapter.label
                : widget.book.chapterCount > 1
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
          Widget row(Map<int, Color> highlights) {
            final tint = highlights[verse];
            final left = _compareCell(theme, style, verse, mine, tint, true);
            final right = _compareCell(
              theme,
              style,
              verse,
              theirs,
              tint,
              false,
            );
            return columns
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
                  );
          }

          final marked = _flashVerse;
          rows.add(
            KeyedSubtree(
              key: _verseKeys[verse],
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: marked == verse
                    ? AnimatedBuilder(
                        animation: _flash,
                        builder: (_, _) =>
                            row(_highlightsWith(verse, _flashStrength)),
                      )
                    : row(widget.highlights),
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
      onLongPress: primary && widget.onVerseLongPress != null
          ? () => widget.onVerseLongPress!(verse)
          : null,
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

/// The end of a chapter that belongs to a plan: one tap marks it read and
/// goes on to the next chapter of the day.
class PlanChapterCard extends StatelessWidget {
  const PlanChapterCard({
    required this.planName,
    required this.day,
    required this.read,
    required this.nextLabel,
    required this.onDone,
    required this.onUndo,
    required this.onNext,
    super.key,
  });

  final String planName;
  final int day;
  final bool read;

  /// The next chapter of the day still to read, or null when this is the
  /// last.
  final String? nextLabel;
  final VoidCallback onDone;
  final VoidCallback onUndo;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  read ? Icons.check_circle_rounded : Icons.event_note_rounded,
                  size: 18,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$planName · day $day',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!read)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onDone,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    nextLabel == null
                        ? 'Done — that’s day $day'
                        : 'Done — next: $nextLabel',
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Read',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  TextButton(onPressed: onUndo, child: const Text('Undo')),
                  if (onNext != null) ...[
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: onNext,
                      child: Text('Next: $nextLabel'),
                    ),
                  ],
                ],
              ),
          ],
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
    required this.crossReferences,
    required this.onCrossReferences,
    required this.originalWords,
    required this.onOriginal,
    required this.onSelect,
    required this.onShare,
    required this.onImage,
    this.onListen,
    this.omitted = false,
  });

  final Reference reference;
  final String text;

  /// Whether this translation leaves the verse out on purpose.
  final bool omitted;
  final ReadingStore reading;
  final List<XrefAnchor> crossReferences;
  final VoidCallback onCrossReferences;
  final List<OriginalWord> originalWords;
  final VoidCallback onOriginal;

  /// Starts a selection with this verse, to add more to it.
  final VoidCallback onSelect;
  final VoidCallback onShare;
  final VoidCallback onImage;

  /// Reads aloud from this verse on, where the platform can.
  final VoidCallback? onListen;

  int _passageCount() {
    var total = 0;
    for (final anchor in crossReferences) {
      total += anchor.ranges.length;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: reading,
      builder: (context, _) {
        final mark = reading.markFor(reference);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reference.label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  omitted && text.isEmpty
                      ? 'This translation does not include this verse. It is '
                            'numbered in the tradition and absent from the '
                            'manuscripts this edition follows.'
                      : text,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: omitted && text.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
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
                    if (originalWords.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onOriginal();
                        },
                        icon: const Icon(Icons.translate_rounded),
                        label: Text(
                          originalWords.any(
                                (word) => word.strongs?.isHebrew ?? false,
                              )
                              ? 'Hebrew'
                              : 'Greek',
                        ),
                      ),
                    if (crossReferences.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onCrossReferences();
                        },
                        icon: const Icon(Icons.hub_outlined),
                        label: Text('${_passageCount()} cross-references'),
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
                    if (text.isNotEmpty && onListen != null)
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onListen!();
                        },
                        icon: const Icon(Icons.headphones_rounded),
                        label: const Text('Listen from here'),
                      ),
                    if (text.isNotEmpty) ...[
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onShare();
                        },
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onImage();
                        },
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Image'),
                      ),
                    ],
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onSelect();
                      },
                      icon: const Icon(Icons.checklist_rounded),
                      label: const Text('Select more'),
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

/// Reading aloud, along the bottom of the reader while it goes on: where
/// it has got to, and the few controls a listener needs.
class _PlayerBar extends StatelessWidget {
  const _PlayerBar({
    required this.voice,
    required this.rate,
    required this.onSettings,
  });

  final ReadAloud voice;
  final double rate;
  final VoidCallback onSettings;

  /// "1×", "1.25×", "1.5×".
  static String rateLabel(double rate) =>
      '${rate.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}×';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = voice.current;
    final where = current == null
        ? ''
        : current.verse == null
        ? ReadAloud.announcement(current).replaceAll('.', '')
        : current.label;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Stop reading aloud',
                onPressed: voice.stop,
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      where,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      voice.isPlaying
                          ? 'Reading aloud · ${rateLabel(rate)}'
                          : 'Paused',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Previous verse',
                onPressed: () => voice.skip(-1),
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              IconButton.filled(
                tooltip: voice.isPlaying ? 'Pause' : 'Resume',
                onPressed: voice.isPlaying ? voice.pause : voice.resume,
                icon: Icon(
                  voice.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                tooltip: 'Next verse',
                onPressed: () => voice.skip(1),
                icon: const Icon(Icons.skip_next_rounded),
              ),
              IconButton(
                tooltip: 'Speed and voice',
                onPressed: onSettings,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How fast, and in whose voice.
class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet({
    required this.settings,
    required this.engine,
    required this.neural,
    required this.language,
  });

  final Settings settings;
  final SpeechEngine engine;
  final NeuralVoices neural;
  final String language;

  static const List<double> rates = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  late Future<List<SpeechVoice>> _voices = _listVoices();

  Future<List<SpeechVoice>> _listVoices() => widget.engine
      .voices(widget.language)
      .catchError((Object _) => const <SpeechVoice>[]);

  /// Which models were installed when the voices were last listed.
  String _installed = '';

  String _installedNow() => [
    for (final model in NeuralModel.catalog)
      if (widget.neural.isInstalled(model)) model.id,
  ].join(',');

  bool get _offersOwnVoices =>
      widget.neural.isSupported && NeuralModel.speaks(widget.language);

  @override
  void initState() {
    super.initState();
    _installed = _installedNow();
    widget.neural.addListener(_onModels);
  }

  @override
  void dispose() {
    widget.neural.removeListener(_onModels);
    super.dispose();
  }

  /// A model downloaded or removed changes the voices to choose from.
  void _onModels() {
    final installed = _installedNow();
    if (installed == _installed) return;
    setState(() {
      _installed = installed;
      _voices = _listVoices();
    });
  }

  Future<void> _download(NeuralModel model) async {
    await widget.neural.install(model);
    // Downloaded to be heard: its first voice is chosen, unless one of
    // OpenWord's own already was.
    if (widget.neural.isInstalled(model) &&
        NeuralModel.parse(widget.settings.speechVoice) == null) {
      widget.settings.speechVoice = model.voiceName(model.speakers.first);
    }
  }

  Future<void> _remove(NeuralModel model) async {
    if (NeuralModel.parse(widget.settings.speechVoice)?.$1 == model) {
      widget.settings.speechVoice = null;
    }
    await widget.neural.remove(model);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.settings;
    return AnimatedBuilder(
      animation: Listenable.merge([settings, widget.neural]),
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Speed', style: theme.textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final rate in _VoiceSheet.rates)
                    ChoiceChip(
                      label: Text(_PlayerBar.rateLabel(rate)),
                      selected: settings.speechRate == rate,
                      onSelected: (_) => settings.speechRate = rate,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Voice', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              FutureBuilder<List<SpeechVoice>>(
                future: _voices,
                builder: (context, snapshot) {
                  final voices = snapshot.data ?? const <SpeechVoice>[];
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        _voiceTile(
                          null,
                          'The most natural voice on this device',
                          voices
                              .where((v) => !v.online && !v.builtIn)
                              .firstOrNull
                              ?.name,
                        ),
                        for (final voice in voices)
                          _voiceTile(
                            voice.name,
                            voice.title ?? voice.name,
                            [
                              voice.qualityLabel,
                              if (voice.builtIn) 'OpenWord',
                              if (voice.online) 'Online',
                              voice.locale,
                            ].whereType<String>().join(' · '),
                          ),
                        if (voices.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              'This device offers no other voices for this '
                              'translation’s language.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        if (voices.any((v) => v.online))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                            child: Text(
                              'Online voices send the words to their '
                              'provider to be spoken, and need a connection. '
                              'Every other voice speaks on this device.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (!voices.any((v) => v.quality >= 3 && !v.online) &&
                            !_offersOwnVoices)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Text(
                              _betterVoicesHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              if (_offersOwnVoices) ..._ownVoices(theme),
            ],
          ),
        ),
      ),
    );
  }

  /// OpenWord's own voices: open neural models, each downloaded once and
  /// then run on the device.
  List<Widget> _ownVoices(ThemeData theme) {
    final neural = widget.neural;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return [
      const SizedBox(height: 20),
      Text('Natural voices for OpenWord', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Open neural voices that run on this device. Each is downloaded '
        'once, from GitHub, and from then on reads with no connection.',
        style: muted,
      ),
      for (final model in NeuralModel.catalog)
        Builder(
          builder: (context) {
            final progress = neural.progress(model);
            final error = neural.error(model);
            final installed = neural.isInstalled(model);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.record_voice_over_rounded),
              title: Text(model.title),
              subtitle: progress != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: progress < 1 ? progress : null,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          progress < 1
                              ? 'Downloading · ${(progress * 100).round()}%'
                              : 'Unpacking…',
                        ),
                      ],
                    )
                  : Text(
                      [
                        installed
                            ? '${model.speakers.length} voices'
                            : '${model.size} download',
                        model.blurb,
                        ?error,
                      ].join(' · '),
                      style: error == null
                          ? null
                          : TextStyle(color: theme.colorScheme.error),
                    ),
              trailing: progress != null
                  ? IconButton(
                      tooltip: 'Stop downloading',
                      onPressed: progress < 1
                          ? () => neural.cancel(model)
                          : null,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : installed
                  ? IconButton(
                      tooltip: 'Remove ${model.title}',
                      onPressed: () => _remove(model),
                      icon: const Icon(Icons.delete_outline_rounded),
                    )
                  : FilledButton.tonal(
                      onPressed: () => _download(model),
                      child: const Text('Download'),
                    ),
            );
          },
        ),
      Text(
        'KittenTTS and Kokoro, both Apache-2.0, run with sherpa-onnx.',
        style: muted,
      ),
    ];
  }

  /// Where a more natural voice comes from. The system's own voices are
  /// all an app can use, and the best of them are a download away.
  static String get _betterVoicesHint => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS =>
      'For a more natural voice, download an Enhanced or Premium one: '
          'Settings → Accessibility → Spoken Content → Voices → English. '
          'It then appears here.',
    TargetPlatform.android =>
      'For a more natural voice, install one: Settings → System → '
          'Languages → Text-to-speech output → the engine’s settings → '
          'Install voice data. It then appears here.',
    _ =>
      'The voices here are the ones this device has installed; installing '
          'a better one in its settings adds it to this list.',
  };

  Widget _voiceTile(String? name, String title, String? locale) {
    final selected = widget.settings.speechVoice == name;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
      ),
      title: Text(title),
      subtitle: locale == null ? null : Text(locale),
      onTap: () => widget.settings.speechVoice = name,
    );
  }
}

/// What can be done with the verses selected, along the bottom of the
/// reader while there are any.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.citation,
    required this.count,
    required this.onClose,
    required this.onCopy,
    required this.onShare,
    required this.onImage,
    required this.onHighlight,
  });

  final String citation;
  final int count;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onImage;
  final VoidCallback onHighlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Clear selection',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      citation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      count == 1
                          ? '1 verse · tap more to add'
                          : '$count verses',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton(
                tooltip: 'Share',
                onPressed: onShare,
                icon: const Icon(Icons.share_rounded),
              ),
              IconButton(
                tooltip: 'Share as an image',
                onPressed: onImage,
                icon: const Icon(Icons.image_outlined),
              ),
              IconButton(
                tooltip: 'Highlight',
                onPressed: onHighlight,
                icon: const Icon(Icons.format_color_fill_rounded),
              ),
            ],
          ),
        ),
      ),
    );
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
