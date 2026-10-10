import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/bible.dart';
import '../model/achievements.dart';
import '../model/book_meta.dart';
import '../model/learn_progress.dart';
import '../model/memory_verse.dart';
import '../model/reading_plan.dart';
import '../model/sleep_policy.dart';
import '../model/streak.dart';
import 'plan_progress.dart';

/// Everything a reader has attached to one verse: a bookmark, a highlight
/// colour, a note, or any combination.
@immutable
class Mark {
  const Mark({
    required this.reference,
    required this.updated,
    this.bookmarked = false,
    this.colorIndex,
    this.note = '',
  });

  final Reference reference;
  final DateTime updated;
  final bool bookmarked;

  /// Index into the reader's highlight palette, or null for no highlight.
  final int? colorIndex;

  final String note;

  bool get isEmpty => !bookmarked && colorIndex == null && note.isEmpty;
  bool get hasNote => note.isNotEmpty;
  bool get highlighted => colorIndex != null;

  String get key => keyFor(reference);

  static String keyFor(Reference reference) =>
      '${reference.bookCode}/${reference.chapter}/${reference.verse ?? 0}';

  Mark copyWith({
    bool? bookmarked,
    int? colorIndex,
    bool clearColor = false,
    String? note,
    DateTime? updated,
  }) {
    return Mark(
      reference: reference,
      updated: updated ?? DateTime.now(),
      bookmarked: bookmarked ?? this.bookmarked,
      colorIndex: clearColor ? null : (colorIndex ?? this.colorIndex),
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() => {
    'b': reference.bookCode,
    'c': reference.chapter,
    'v': reference.verse ?? 0,
    't': updated.millisecondsSinceEpoch,
    if (bookmarked) 'm': true,
    if (colorIndex != null) 'k': colorIndex,
    if (note.isNotEmpty) 'n': note,
  };

  static Mark? fromJson(Map<String, Object?> json) {
    final book = json['b'];
    final chapter = json['c'];
    if (book is! String || chapter is! int) return null;
    if (BookMeta.lookup(book) == null) return null;
    final verse = json['v'];
    final color = json['k'];
    final mark = Mark(
      reference: Reference(
        book,
        chapter,
        verse is int && verse > 0 ? verse : null,
      ),
      updated: DateTime.fromMillisecondsSinceEpoch(
        json['t'] is int ? json['t']! as int : 0,
      ),
      bookmarked: json['m'] == true,
      colorIndex: color is int ? color : null,
      note: json['n'] is String ? json['n']! as String : '',
    );
    return mark.isEmpty ? null : mark;
  }
}

/// What an import did, so the user can be told.
@immutable
class ImportResult {
  const ImportResult({required this.added, required this.updated});

  const ImportResult.failed() : added = -1, updated = -1;

  final int added;
  final int updated;

  bool get ok => added >= 0;
  int get total => added + updated;
}

/// Marks, reading position and history, persisted with [SharedPreferences].
class ReadingStore extends ChangeNotifier {
  ReadingStore._(this._prefs, this._clock, this._random) {
    _load();
  }

  static const _kMarks = 'marks';
  static const _kLegacyBookmarks = 'bookmarks';
  static const _kPosition = 'lastPosition';
  static const _kListening = 'listeningPlace';
  static const _kHistory = 'history';
  static const _kPlans = 'plans';
  static const _kMemory = 'memory';
  static const _kStreak = 'streak';
  static const _kProgress = 'progress';
  static const _kSleep = 'sleep';
  static const _historyLimit = 20;

  /// Number of colours in the highlight palette.
  static const int paletteSize = 5;

  final SharedPreferences _prefs;
  final Map<String, Mark> _marks = {};
  List<Reference> _history = [];

  /// Reading plans in progress, in the order they were started.
  final Map<String, PlanProgress> _plans = {};

  /// Verses being learnt by heart, in the order they were added.
  final Map<String, MemoryVerse> _memory = {};

  Streak _streak = Streak.none;
  LearnProgress _progress = LearnProgress.none;

  /// What "today" is. A test sets it; the app reads the clock.
  final DateTime Function() _clock;

  /// Allots new verses to a night or a day; a test fixes it.
  final Random _random;

  SleepPolicy _sleep = SleepPolicy.standard;

  static Future<ReadingStore> load({
    DateTime Function()? clock,
    Random? random,
  }) async => ReadingStore._(
    await SharedPreferences.getInstance(),
    clock ?? DateTime.now,
    random ?? Random(),
  );

  DateTime get today => _clock();

  void _load() {
    final raw = _prefs.getString(_kMarks);
    if (raw != null) {
      _decodeInto(raw, _marks);
    } else {
      _migrateLegacyBookmarks();
    }
    _history = [
      for (final entry in _prefs.getStringList(_kHistory) ?? const <String>[])
        if (Reference.decode(entry) case final reference?) reference,
    ];
    final plans = _prefs.getString(_kPlans);
    if (plans != null) _decodePlansInto(plans, _plans);
    final memory = _prefs.getString(_kMemory);
    if (memory != null) _decodeMemoryInto(memory, _memory);
    _streak = _decodeStreak(_prefs.getString(_kStreak)) ?? Streak.none;
    _progress =
        _decodeProgress(_prefs.getString(_kProgress)) ?? LearnProgress.none;
    final sleep = _prefs.getString(_kSleep);
    if (sleep != null) {
      final decoded = jsonDecode(sleep);
      if (decoded is Map) {
        _sleep = SleepPolicy.fromJson(decoded.cast<String, Object?>());
      }
    }
  }

  static LearnProgress? _decodeProgress(Object? raw) {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) return null;
    return LearnProgress.fromJson(decoded.cast<String, Object?>());
  }

  static Streak? _decodeStreak(Object? raw) {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) return null;
    return Streak.fromJson(decoded.cast<String, Object?>());
  }

  static int _decodeMemoryInto(Object? raw, Map<String, MemoryVerse> into) {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! List) return 0;
    var count = 0;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final verse = MemoryVerse.fromJson(entry.cast<String, Object?>());
      if (verse == null) continue;
      into[verse.key] = verse;
      count++;
    }
    return count;
  }

  static int _decodePlansInto(Object? raw, Map<String, PlanProgress> into) {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! List) return 0;
    var count = 0;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final progress = PlanProgress.fromJson(entry.cast<String, Object?>());
      if (progress == null) continue;
      into[progress.plan.id] = progress;
      count++;
    }
    return count;
  }

  /// Version 1.0 stored plain bookmarks under another key.
  void _migrateLegacyBookmarks() {
    final legacy = _prefs.getString(_kLegacyBookmarks);
    if (legacy == null) return;
    final decoded = jsonDecode(legacy);
    if (decoded is! List) return;
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final json = entry.cast<String, Object?>();
      final mark = Mark.fromJson({...json, 'm': true, 'k': null});
      if (mark != null) _marks[mark.key] = mark;
    }
    if (_marks.isNotEmpty) _persist();
  }

  int _decodeInto(String raw, Map<String, Mark> into) {
    final decoded = jsonDecode(raw);
    final entries = decoded is List
        ? decoded
        : decoded is Map
        ? (decoded['marks'] as List? ?? const [])
        : const [];
    var count = 0;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final mark = Mark.fromJson(entry.cast<String, Object?>());
      if (mark == null) continue;
      into[mark.key] = mark;
      count++;
    }
    return count;
  }

  // --- reading ---------------------------------------------------------

  Mark? markFor(Reference reference) => _marks[Mark.keyFor(reference)];

  bool isBookmarked(Reference reference) =>
      markFor(reference)?.bookmarked ?? false;

  /// Every mark, most recently touched first.
  List<Mark> get all {
    final list = _marks.values.toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return List.unmodifiable(list);
  }

  List<Mark> get bookmarks =>
      List.unmodifiable(all.where((mark) => mark.bookmarked));

  List<Mark> get highlights =>
      List.unmodifiable(all.where((mark) => mark.highlighted));

  List<Mark> get notes => List.unmodifiable(all.where((mark) => mark.hasNote));

  List<Reference> get history => List.unmodifiable(_history);

  /// Highlight colour index per verse for one chapter.
  Map<int, int> highlightsIn(String bookCode, int chapter) => {
    for (final mark in _marks.values)
      if (mark.reference.bookCode == bookCode &&
          mark.reference.chapter == chapter &&
          mark.reference.verse != null &&
          mark.colorIndex != null)
        mark.reference.verse!: mark.colorIndex!,
  };

  /// Verses in one chapter carrying a bookmark or a note, for the gutter and
  /// the pickers.
  Set<int> flaggedVersesIn(String bookCode, int chapter) => {
    for (final mark in _marks.values)
      if (mark.reference.bookCode == bookCode &&
          mark.reference.chapter == chapter &&
          mark.reference.verse != null &&
          (mark.bookmarked || mark.hasNote))
        mark.reference.verse!,
  };

  /// Chapters of a book that carry any mark.
  Set<int> markedChaptersIn(String bookCode) => {
    for (final mark in _marks.values)
      if (mark.reference.bookCode == bookCode) mark.reference.chapter,
  };

  Set<String> get markedBookCodes => {
    for (final mark in _marks.values) mark.reference.bookCode,
  };

  // --- writing ---------------------------------------------------------

  /// Adds a bookmark, or removes it if the verse already has one. Returns
  /// true when a bookmark was added.
  bool toggleBookmark(Reference reference) {
    final existing = markFor(reference);
    final next = (existing ?? _blank(reference)).copyWith(
      bookmarked: !(existing?.bookmarked ?? false),
      updated: _nextTimestamp(),
    );
    _write(next);
    return next.bookmarked;
  }

  /// Sets or clears the highlight colour on a verse.
  void setHighlight(Reference reference, int? colorIndex) {
    final existing = markFor(reference) ?? _blank(reference);
    _write(
      existing.copyWith(
        colorIndex: colorIndex,
        clearColor: colorIndex == null,
        updated: _nextTimestamp(),
      ),
    );
  }

  void setNote(Reference reference, String note) {
    final existing = markFor(reference) ?? _blank(reference);
    _write(existing.copyWith(note: note.trim(), updated: _nextTimestamp()));
  }

  void remove(Reference reference) {
    if (_marks.remove(Mark.keyFor(reference)) != null) _persist();
  }

  /// Removes every mark and every verse being learnt.
  void clearAll() {
    if (_memory.isNotEmpty) {
      _memory.clear();
      _persistMemory();
    }
    if (_marks.isEmpty) return;
    _marks.clear();
    _persist();
  }

  Mark _blank(Reference reference) =>
      Mark(reference: reference, updated: DateTime.now());

  void _write(Mark mark) {
    if (mark.isEmpty) {
      _marks.remove(mark.key);
    } else {
      _marks[mark.key] = mark;
    }
    _persist();
  }

  /// Marks are ordered by when they were touched, so two saved inside the
  /// same millisecond — which the web's clock resolution makes easy — would
  /// otherwise sort arbitrarily.
  DateTime _nextTimestamp() {
    final now = DateTime.now();
    var latest = 0;
    for (final mark in _marks.values) {
      final stamp = mark.updated.millisecondsSinceEpoch;
      if (stamp > latest) latest = stamp;
    }
    if (now.millisecondsSinceEpoch > latest) return now;
    return DateTime.fromMillisecondsSinceEpoch(latest + 1);
  }

  void _persist() {
    _prefs.setString(
      _kMarks,
      jsonEncode([for (final mark in _marks.values) mark.toJson()]),
    );
    notifyListeners();
  }

  // --- reading plans ---------------------------------------------------

  /// Plans in progress, finished ones included until the reader removes
  /// them, in the order they were started.
  List<PlanProgress> get plans => List.unmodifiable(_plans.values);

  PlanProgress? progressFor(String planId) => _plans[planId];

  /// Starts a plan with day 1 today. Starting one already under way starts
  /// it over.
  void startPlan(ReadingPlan plan) {
    _plans.remove(plan.id);
    _plans[plan.id] = PlanProgress(
      plan: plan,
      startedOn: PlanProgress.dateOnly(today),
      done: const {},
      updated: DateTime.now(),
    );
    _persistPlans();
  }

  void stopPlan(String planId) {
    if (_plans.remove(planId) != null) _persistPlans();
  }

  /// Puts back a plan just removed, ticks and all: what Undo does.
  void restorePlan(PlanProgress progress) {
    _plans[progress.plan.id] = progress;
    _persistPlans();
  }

  /// Marks one chapter of a plan read or unread.
  void setPlanSlot(String planId, int slot, {required bool read}) {
    final progress = _plans[planId];
    if (progress == null || slot < 0 || slot >= progress.plan.slotCount) {
      return;
    }
    if (progress.isRead(slot) == read) return;
    final done = {...progress.done};
    read ? done.add(slot) : done.remove(slot);
    _plans[planId] = progress.copyWith(done: done);
    _persistPlans();
  }

  /// Marks every chapter of a day read or unread.
  void setPlanDay(String planId, PlanDay day, {required bool read}) {
    final progress = _plans[planId];
    if (progress == null) return;
    final done = {...progress.done};
    for (final slot in day.slots) {
      read ? done.add(slot) : done.remove(slot);
    }
    _plans[planId] = progress.copyWith(done: done);
    _persistPlans();
  }

  /// Moves a plan's pace so its current day is today, the way a reader who
  /// has been away would want. Nothing is marked read that was not.
  void pickUpPlanToday(String planId) {
    final progress = _plans[planId];
    if (progress == null) return;
    _plans[planId] = progress.pickedUpOn(today);
    _persistPlans();
  }

  /// Whether any plan has a reading due today that is not yet read.
  bool get hasPlanReadingDue =>
      _plans.values.any((progress) => progress.hasReadingDueOn(today));

  void _persistPlans() {
    _prefs.setString(
      _kPlans,
      jsonEncode([for (final progress in _plans.values) progress.toJson()]),
    );
    notifyListeners();
  }

  // --- memory verses ---------------------------------------------------

  /// Verses being learnt, in the order they were added.
  List<MemoryVerse> get memoryVerses => List.unmodifiable(_memory.values);

  MemoryVerse? memoryFor(Reference reference) =>
      reference.verse == null ? null : _memory[reference.encode()];

  bool isMemorising(Reference reference) => memoryFor(reference) != null;

  /// Whether [verse] is offered for practice at [now]: a first recall
  /// once its time has come, a verse on the ladder on its day, and a
  /// verse still to be learnt when the sleep policy says so.
  bool isOffered(MemoryVerse verse, DateTime now) => switch (verse.stage) {
    MemoryStage.introduced => verse.recallOfferedAt(now),
    MemoryStage.onLadder => verse.isDueOn(now),
    MemoryStage.waiting =>
      verse.isDueOn(now) && _sleep.offersLearning(verse.arm, now),
  };

  /// Verses offered for practice now: first recalls first, then the
  /// ladder's due verses, longest waiting first, then the new ones.
  List<MemoryVerse> get memoryDue {
    final now = today;
    int rank(MemoryVerse v) => switch (v.stage) {
      MemoryStage.introduced => 0,
      MemoryStage.onLadder => 1,
      MemoryStage.waiting => 2,
    };
    final due = _memory.values.where((verse) => isOffered(verse, now)).toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.due.compareTo(b.due);
      });
    return List.unmodifiable(due);
  }

  /// Verses still to be learnt that the sleep policy holds back for now:
  /// a night verse by day, a day verse too late in the day.
  List<MemoryVerse> get memoryHeldBack {
    final now = today;
    return List.unmodifiable([
      for (final verse in _memory.values)
        if (verse.stage == MemoryStage.waiting &&
            verse.isDueOn(now) &&
            !_sleep.offersLearning(verse.arm, now))
          verse,
    ]);
  }

  /// Whether any verse is waiting to be practised now: what the library
  /// button carries a dot for.
  bool get hasMemoryDue {
    final now = today;
    return _memory.values.any((verse) => isOffered(verse, now));
  }

  /// How the app times a new verse against sleep.
  SleepPolicy get sleepPolicy => _sleep;

  void setSleepPolicy(SleepPolicy policy) {
    if (policy == _sleep) return;
    _sleep = policy;
    _prefs.setString(_kSleep, jsonEncode(policy.toJson()));
    notifyListeners();
  }

  /// What the trial has found about this reader so far.
  SleepTrialReport get sleepTrialReport => SleepTrialReport.of(_memory.values);

  /// Starts learning a verse, or stops if it is being learnt already.
  /// Returns true when the verse was added.
  bool toggleMemorise(Reference reference) {
    if (reference.verse == null) return false;
    final key = reference.encode();
    if (_memory.remove(key) != null) {
      _persistMemory();
      return false;
    }
    _memory[key] = MemoryVerse.start(
      reference,
      today,
      arm: _sleep.armForNew(_random),
    );
    _persistMemory();
    return true;
  }

  /// Records a practice. A verse learnt for the first time is set its
  /// first recall by the sleep policy; a first recall is recorded for
  /// the trial, with whether the reader [slept] since; and from then on
  /// the verse moves up the ladder when recalled and back to the bottom
  /// when not. A review six days or more after learning is kept as the
  /// later recall. A miss made while [sure] is counted.
  void reviewMemory(
    Reference reference, {
    required bool remembered,
    bool? slept,
    bool sure = false,
  }) {
    final verse = memoryFor(reference);
    if (verse == null) return;
    final now = today;
    var next = switch (verse.stage) {
      // A verse with no timing — added before this, or with it off —
      // climbs the ladder as it always did, with no trial to record.
      MemoryStage.waiting when verse.arm == null || remembered == false =>
        verse.reviewed(remembered: remembered, today: now),
      MemoryStage.waiting => verse.introducedAt(
        now,
        _sleep.recallAfter(now, verse.arm),
      ),
      MemoryStage.introduced => verse.firstRecalled(
        now,
        right: remembered,
        slept: slept,
      ),
      MemoryStage.onLadder => verse.reviewed(
        remembered: remembered,
        today: now,
      ),
    };
    if (next.isLaterRecallAt(now) && verse.stage == MemoryStage.onLadder) {
      next = next.laterRecalled(now, right: remembered);
    }
    if (sure && !remembered) {
      next = next.copyWith(confidentMisses: next.confidentMisses + 1);
    }
    _memory[verse.key] = next;
    _persistMemory();
  }

  void removeMemory(Reference reference) {
    if (_memory.remove(reference.encode()) != null) _persistMemory();
  }

  /// Puts back a verse just removed, its place on the ladder and all:
  /// what Undo does.
  void restoreMemory(MemoryVerse verse) {
    _memory[verse.key] = verse;
    _persistMemory();
  }

  // --- streak ----------------------------------------------------------

  /// Days in a row with learning done.
  Streak get streak => _streak;

  /// Counts today as a day with learning done: a verse answered, or a
  /// round finished. Once a day is enough; calling it again does nothing.
  void recordPractice() {
    final next = _streak.extendedOn(today);
    if (next == _streak) return;
    _streak = next;
    _prefs.setString(_kStreak, jsonEncode(next.toJson()));
    notifyListeners();
  }

  // --- points and badges -----------------------------------------------

  /// Points earned, the level, the day's goal and the badges won.
  LearnProgress get progress => _progress;

  /// Verses on the ladder that have been recalled after a month away.
  int get versesLearnt => _memory.values.where((v) => v.isLearnt).length;

  /// Records what an answer or a round earned: the points go on today's
  /// count, today counts towards the streak, and any badge whose
  /// condition now holds is won. Returns the badges newly won.
  List<Achievement> recordLearning({
    required int xp,
    bool? right,
    bool perfectRound = false,
    bool scribed = false,
    bool heard = false,
    Confidence? confidence,
  }) {
    final now = today;
    _progress = _progress.earned(
      xp,
      now,
      right: right,
      perfectRound: perfectRound,
      scribed: scribed,
      heard: heard,
      confidence: confidence,
    );
    recordPractice();
    final won = <Achievement>[];
    for (final achievement in Achievement.values) {
      if (_progress.badges.containsKey(achievement.id)) continue;
      final earned = achievement.earnedBy(
        progress: _progress,
        streak: _streak.currentOn(now),
        versesOnLadder: _memory.length,
        versesLearnt: versesLearnt,
        today: now,
      );
      if (!earned) continue;
      _progress = _progress.awarded(achievement.id, now);
      won.add(achievement);
    }
    _persistProgress();
    return won;
  }

  void setDailyGoal(DailyGoal goal) {
    if (goal == _progress.goal) return;
    _progress = _progress.copyWith(goal: goal);
    _persistProgress();
  }

  void _persistProgress() {
    _prefs.setString(_kProgress, jsonEncode(_progress.toJson()));
    notifyListeners();
  }

  /// Two copies of the progress put together: each day's points the
  /// higher of the two, the totals likewise, and every badge either has,
  /// from the earlier day it was won.
  static LearnProgress _mergeProgress(
    LearnProgress mine,
    LearnProgress theirs,
  ) {
    int most(int a, int b) => a > b ? a : b;
    final daily = {...mine.daily};
    for (final entry in theirs.daily.entries) {
      daily[entry.key] = most(daily[entry.key] ?? 0, entry.value);
    }
    final badges = {...mine.badges};
    for (final entry in theirs.badges.entries) {
      final have = badges[entry.key];
      if (have == null || entry.value.isBefore(have)) {
        badges[entry.key] = entry.value;
      }
    }
    return LearnProgress(
      xp: most(mine.xp, theirs.xp),
      daily: daily,
      right: most(mine.right, theirs.right),
      wrong: most(mine.wrong, theirs.wrong),
      perfectRounds: most(mine.perfectRounds, theirs.perfectRounds),
      scribed: most(mine.scribed, theirs.scribed),
      heard: most(mine.heard, theirs.heard),
      goal: mine.goal,
      badges: badges,
      confidence: {
        for (final level in Confidence.values)
          if (mine.confidence[level] ?? theirs.confidence[level] case final _?)
            level: (
              most(
                mine.confidence[level]?.$1 ?? 0,
                theirs.confidence[level]?.$1 ?? 0,
              ),
              most(
                mine.confidence[level]?.$2 ?? 0,
                theirs.confidence[level]?.$2 ?? 0,
              ),
            ),
      },
      confidentMisses: most(mine.confidentMisses, theirs.confidentMisses),
    );
  }

  void _persistMemory() {
    _prefs.setString(
      _kMemory,
      jsonEncode([for (final verse in _memory.values) verse.toJson()]),
    );
    notifyListeners();
  }

  // --- position --------------------------------------------------------

  /// Where the reader was last looking, used to resume on launch.
  Reference? get lastPosition => Reference.decode(_prefs.getString(_kPosition));

  Future<void> savePosition(Reference reference) async {
    final previous = lastPosition;
    await _prefs.setString(_kPosition, reference.encode());
    if (previous == null ||
        previous.bookCode != reference.bookCode ||
        previous.chapter != reference.chapter) {
      _pushHistory(reference.withVerse(null));
    }
  }

  /// Where listening aloud last got to, as `ListeningPlace.encode` puts
  /// it, so that it can be taken up after the app has been closed.
  String? get listeningPlace => _prefs.getString(_kListening);

  set listeningPlace(String? value) {
    if (value == null) {
      _prefs.remove(_kListening);
    } else {
      _prefs.setString(_kListening, value);
    }
  }

  void _pushHistory(Reference reference) {
    _history
      ..removeWhere(
        (entry) =>
            entry.bookCode == reference.bookCode &&
            entry.chapter == reference.chapter,
      )
      ..insert(0, reference);
    if (_history.length > _historyLimit) {
      _history = _history.sublist(0, _historyLimit);
    }
    _prefs.setStringList(_kHistory, [
      for (final entry in _history) entry.encode(),
    ]);
    notifyListeners();
  }

  void clearHistory() {
    _history = [];
    _prefs.setStringList(_kHistory, const []);
    notifyListeners();
  }

  // --- backup ----------------------------------------------------------

  /// Everything the reader has added, as JSON they can keep anywhere.
  String export() => const JsonEncoder.withIndent('  ').convert({
    'app': 'openword',
    'version': 1,
    'exported': DateTime.now().toIso8601String(),
    'position': lastPosition?.encode(),
    'marks': [for (final mark in _marks.values) mark.toJson()],
    if (_plans.isNotEmpty)
      'plans': [for (final progress in _plans.values) progress.toJson()],
    if (_memory.isNotEmpty)
      'memory': [for (final verse in _memory.values) verse.toJson()],
    if (_streak.last != null) 'streak': _streak.toJson(),
    if (_progress.xp > 0) 'progress': _progress.toJson(),
    'sleep': _sleep.toJson(),
  });

  /// Whether there is anything a backup would hold.
  bool get hasBackupContent =>
      _marks.isNotEmpty ||
      _plans.isNotEmpty ||
      _memory.isNotEmpty ||
      _streak.last != null ||
      _progress.xp > 0;

  /// Merges exported JSON back in, keeping whichever copy of a verse was
  /// touched more recently. Existing marks are never dropped.
  ///
  /// A reading plan is merged the same way: the copy touched more recently
  /// wins, since a plan's ticks only make sense together. So is a verse
  /// being learnt, with its place on the ladder. Of two streaks the one
  /// practised more recently is kept, and the better best of the two.
  ImportResult import(String raw) {
    final incoming = <String, Mark>{};
    final incomingPlans = <String, PlanProgress>{};
    final incomingMemory = <String, MemoryVerse>{};
    Streak? incomingStreak;
    LearnProgress? incomingProgress;
    try {
      final marks = _decodeInto(raw, incoming);
      final decoded = jsonDecode(raw);
      final plans = decoded is Map
          ? _decodePlansInto(decoded['plans'], incomingPlans)
          : 0;
      final memory = decoded is Map
          ? _decodeMemoryInto(decoded['memory'], incomingMemory)
          : 0;
      if (decoded is Map) {
        incomingStreak = _decodeStreak(decoded['streak']);
        incomingProgress = _decodeProgress(decoded['progress']);
      }
      if (marks == 0 &&
          plans == 0 &&
          memory == 0 &&
          incomingStreak == null &&
          incomingProgress == null) {
        return const ImportResult.failed();
      }
    } on Object {
      return const ImportResult.failed();
    }
    var added = 0;
    var updated = 0;
    if (incomingProgress case final theirs?) {
      final merged = _mergeProgress(_progress, theirs);
      if (merged != _progress) {
        _progress = merged;
        _prefs.setString(_kProgress, jsonEncode(merged.toJson()));
        updated++;
        notifyListeners();
      }
    }
    if (incomingStreak case final theirs? when theirs.last != null) {
      final mine = _streak;
      final newer = mine.last == null || theirs.last!.isAfter(mine.last!)
          ? theirs
          : mine;
      final merged = Streak(
        count: newer.count,
        best: theirs.best > mine.best ? theirs.best : mine.best,
        last: newer.last,
        freezes: newer.freezes,
      );
      if (merged != mine) {
        _streak = merged;
        _prefs.setString(_kStreak, jsonEncode(merged.toJson()));
        updated++;
        notifyListeners();
      }
    }
    var memoryChanged = false;
    for (final verse in incomingMemory.values) {
      final existing = _memory[verse.key];
      if (existing == null) {
        _memory[verse.key] = verse;
        added++;
        memoryChanged = true;
      } else if (verse.updated.isAfter(existing.updated)) {
        _memory[verse.key] = verse;
        updated++;
        memoryChanged = true;
      }
    }
    if (memoryChanged) _persistMemory();
    var plansChanged = false;
    for (final progress in incomingPlans.values) {
      final existing = _plans[progress.plan.id];
      if (existing == null) {
        _plans[progress.plan.id] = progress;
        added++;
        plansChanged = true;
      } else if (progress.updated.isAfter(existing.updated)) {
        _plans[progress.plan.id] = progress;
        updated++;
        plansChanged = true;
      }
    }
    if (plansChanged) _persistPlans();
    for (final mark in incoming.values) {
      final existing = _marks[mark.key];
      if (existing == null) {
        _marks[mark.key] = mark;
        added++;
      } else if (mark.updated.isAfter(existing.updated)) {
        _marks[mark.key] = mark;
        updated++;
      }
    }
    if (added + updated > 0) _persist();
    return ImportResult(added: added, updated: updated);
  }
}
