import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/bible.dart';
import '../model/book_meta.dart';

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
  ReadingStore._(this._prefs) {
    _load();
  }

  static const _kMarks = 'marks';
  static const _kLegacyBookmarks = 'bookmarks';
  static const _kPosition = 'lastPosition';
  static const _kHistory = 'history';
  static const _historyLimit = 20;

  /// Number of colours in the highlight palette.
  static const int paletteSize = 5;

  final SharedPreferences _prefs;
  final Map<String, Mark> _marks = {};
  List<Reference> _history = [];

  static Future<ReadingStore> load() async =>
      ReadingStore._(await SharedPreferences.getInstance());

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

  void clearAll() {
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
  });

  /// Merges exported JSON back in, keeping whichever copy of a verse was
  /// touched more recently. Existing marks are never dropped.
  ImportResult import(String raw) {
    final incoming = <String, Mark>{};
    try {
      if (_decodeInto(raw, incoming) == 0) return const ImportResult.failed();
    } on Object {
      return const ImportResult.failed();
    }
    var added = 0;
    var updated = 0;
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
