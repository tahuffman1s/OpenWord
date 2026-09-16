import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/bible.dart';

/// A saved place, optionally with a note and a highlight colour.
@immutable
class Bookmark {
  const Bookmark({
    required this.reference,
    required this.created,
    this.note = '',
    this.colorIndex = 0,
  });

  final Reference reference;
  final DateTime created;
  final String note;

  /// Index into the reader's highlight palette.
  final int colorIndex;

  /// Stable identity: one bookmark per verse.
  String get key =>
      '${reference.bookCode}/${reference.chapter}/'
      '${reference.verse ?? 0}';

  Bookmark copyWith({String? note, int? colorIndex}) => Bookmark(
    reference: reference,
    created: created,
    note: note ?? this.note,
    colorIndex: colorIndex ?? this.colorIndex,
  );

  Map<String, Object?> toJson() => {
    'b': reference.bookCode,
    'c': reference.chapter,
    'v': reference.verse ?? 0,
    't': created.millisecondsSinceEpoch,
    if (note.isNotEmpty) 'n': note,
    if (colorIndex != 0) 'k': colorIndex,
  };

  static Bookmark? fromJson(Map<String, Object?> json) {
    final book = json['b'];
    final chapter = json['c'];
    if (book is! String || chapter is! int) return null;
    final verse = json['v'];
    return Bookmark(
      reference: Reference(
        book,
        chapter,
        verse is int && verse > 0 ? verse : null,
      ),
      created: DateTime.fromMillisecondsSinceEpoch(
        json['t'] is int ? json['t']! as int : 0,
      ),
      note: json['n'] is String ? json['n']! as String : '',
      colorIndex: json['k'] is int ? json['k']! as int : 0,
    );
  }
}

/// Bookmarks plus the reading position the app resumes from.
class ReadingStore extends ChangeNotifier {
  ReadingStore._(this._prefs) {
    _load();
  }

  static const _kBookmarks = 'bookmarks';
  static const _kPosition = 'lastPosition';
  static const _kHistory = 'history';
  static const _historyLimit = 12;

  final SharedPreferences _prefs;
  final Map<String, Bookmark> _bookmarks = {};
  List<Reference> _history = [];

  static Future<ReadingStore> load() async =>
      ReadingStore._(await SharedPreferences.getInstance());

  void _load() {
    final raw = _prefs.getString(_kBookmarks);
    if (raw != null) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is! Map) continue;
          final bookmark = Bookmark.fromJson(entry.cast<String, Object?>());
          if (bookmark != null) _bookmarks[bookmark.key] = bookmark;
        }
      }
    }
    _history = [
      for (final entry in _prefs.getStringList(_kHistory) ?? const <String>[])
        if (Reference.decode(entry) case final reference?) reference,
    ];
  }

  /// Most recently saved first.
  List<Bookmark> get bookmarks {
    final list = _bookmarks.values.toList()
      ..sort((a, b) => b.created.compareTo(a.created));
    return List.unmodifiable(list);
  }

  List<Reference> get history => List.unmodifiable(_history);

  bool isBookmarked(Reference reference) =>
      _bookmarks.containsKey(_keyFor(reference));

  Bookmark? bookmarkFor(Reference reference) => _bookmarks[_keyFor(reference)];

  /// Verses of [chapter] in [bookCode] that carry a bookmark.
  Set<int> bookmarkedVerses(String bookCode, int chapter) => {
    for (final bookmark in _bookmarks.values)
      if (bookmark.reference.bookCode == bookCode &&
          bookmark.reference.chapter == chapter &&
          bookmark.reference.verse != null)
        bookmark.reference.verse!,
  };

  /// Adds a bookmark, or removes it when the verse is already bookmarked.
  /// Returns true when a bookmark was added.
  bool toggle(Reference reference, {int colorIndex = 0}) {
    final key = _keyFor(reference);
    if (_bookmarks.remove(key) != null) {
      _persistBookmarks();
      return false;
    }
    _bookmarks[key] = Bookmark(
      reference: reference,
      created: _nextTimestamp(),
      colorIndex: colorIndex,
    );
    _persistBookmarks();
    return true;
  }

  void remove(Bookmark bookmark) {
    if (_bookmarks.remove(bookmark.key) != null) _persistBookmarks();
  }

  void update(Bookmark bookmark) {
    _bookmarks[bookmark.key] = bookmark;
    _persistBookmarks();
  }

  void clearBookmarks() {
    _bookmarks.clear();
    _persistBookmarks();
  }

  /// Where the reader was last looking, used to resume on launch.
  Reference? get lastPosition => Reference.decode(_prefs.getString(_kPosition));

  /// Records the current position. Writes are cheap enough to call on every
  /// chapter change; the scroll anchor is stored as the top visible verse.
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

  /// Bookmarks are ordered by creation time, so two saved inside the same
  /// millisecond — which the web's clock resolution makes easy — would
  /// otherwise sort arbitrarily.
  DateTime _nextTimestamp() {
    final now = DateTime.now();
    var latest = 0;
    for (final bookmark in _bookmarks.values) {
      final stamp = bookmark.created.millisecondsSinceEpoch;
      if (stamp > latest) latest = stamp;
    }
    if (now.millisecondsSinceEpoch > latest) return now;
    return DateTime.fromMillisecondsSinceEpoch(latest + 1);
  }

  static String _keyFor(Reference reference) =>
      '${reference.bookCode}/${reference.chapter}/${reference.verse ?? 0}';

  void _persistBookmarks() {
    _prefs.setString(
      _kBookmarks,
      jsonEncode([for (final bookmark in _bookmarks.values) bookmark.toJson()]),
    );
    notifyListeners();
  }
}
