import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/bible.dart';
import 'translations.dart';

/// How the book picker lists books.
enum BookOrder {
  /// Genesis to Revelation, grouped by division.
  canonical('Canon'),

  /// Alphabetical, with numbered books under their name.
  alphabetical('A–Z');

  const BookOrder(this.label);

  final String label;
}

/// Reading typeface. Literata is bundled with the app; "Sans" follows the
/// platform's own UI font.
enum ReadingFont {
  serif('Serif', 'Literata'),
  sans('Sans', null);

  const ReadingFont(this.label, this.family);

  final String label;
  final String? family;
}

/// User preferences, persisted with [SharedPreferences].
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static const _kThemeMode = 'themeMode';
  static const _kDynamicColor = 'dynamicColor';
  static const _kSeedColor = 'seedColor';
  static const _kFontScale = 'fontScale';
  static const _kLineHeight = 'lineHeight';
  static const _kFont = 'readingFont';
  static const _kRedLetter = 'redLetter';
  static const _kFootnotes = 'footnotes';
  static const _kParagraphs = 'paragraphs';
  static const _kVerseNumbers = 'verseNumbers';
  static const _kDeuterocanon = 'deuterocanon';
  static const _kBookOrder = 'bookOrder';
  static const _kTranslation = 'translation';
  static const _kCompare = 'compareTranslation';
  static const _kCheckUpdates = 'checkForUpdates';
  static const _kLastCheck = 'lastUpdateCheck';
  static const _kSkippedUpdate = 'skippedUpdate';
  static const _kAnchorAnyway = 'anchorAnyway';
  static const _kSpeechPace = 'speechPace';
  static const _kOldSpeechRate = 'speechRate';
  static const _kSpeechVoice = 'speechVoice';

  /// Fallback palette seeds offered where the platform has no Material You
  /// palette of its own (desktop, web, older Android, iOS).
  static const List<Color> seedChoices = [
    Color(0xFF6750A4),
    Color(0xFF1B6C4F),
    Color(0xFF8C4A2F),
    Color(0xFF2D5FA8),
    Color(0xFF7D5260),
    Color(0xFF4E5B31),
    Color(0xFF5B5891),
    Color(0xFF8A5100),
  ];

  final SharedPreferences _prefs;

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

  ThemeMode get themeMode =>
      ThemeMode.values[_prefs.getInt(_kThemeMode) ?? ThemeMode.system.index];
  set themeMode(ThemeMode value) => _write(_kThemeMode, value.index);

  bool get useDynamicColor => _prefs.getBool(_kDynamicColor) ?? true;
  set useDynamicColor(bool value) => _write(_kDynamicColor, value);

  Color get seedColor =>
      Color(_prefs.getInt(_kSeedColor) ?? seedChoices.first.toARGB32());
  set seedColor(Color value) => _write(_kSeedColor, value.toARGB32());

  double get fontScale => _prefs.getDouble(_kFontScale) ?? 1.0;
  set fontScale(double value) => _write(_kFontScale, value);

  double get lineHeight => _prefs.getDouble(_kLineHeight) ?? 1.6;
  set lineHeight(double value) => _write(_kLineHeight, value);

  /// The speeds reading aloud offers.
  static const List<double> speechRates = [0.75, 1.0, 1.25, 1.5, 2.0];

  /// How fast reading aloud goes, as a multiple of the voice's natural
  /// pace.
  ///
  /// Before 1.23 a multiple of a pace a fifth slower than that — the
  /// voice's own "speed prior", which made 1× drag — and kept under
  /// another name. A speed chosen then is carried over as the nearest
  /// that sounds the same.
  double get speechRate {
    final pace = _prefs.getDouble(_kSpeechPace);
    if (pace != null) return pace;
    final before = _prefs.getDouble(_kOldSpeechRate);
    if (before == null) return 1.0;
    final same = before * 0.8;
    return speechRates.reduce(
      (a, b) => (a - same).abs() <= (b - same).abs() ? a : b,
    );
  }

  set speechRate(double value) => _write(_kSpeechPace, value);

  /// The voice chosen for reading aloud, by the name it is kept by, or
  /// null for the first.
  String? get speechVoice => _prefs.getString(_kSpeechVoice);
  set speechVoice(String? value) {
    if (value == null) {
      _prefs.remove(_kSpeechVoice);
      notifyListeners();
    } else {
      _write(_kSpeechVoice, value);
    }
  }

  ReadingFont get readingFont =>
      ReadingFont.values[_prefs.getInt(_kFont) ?? ReadingFont.serif.index];
  set readingFont(ReadingFont value) => _write(_kFont, value.index);

  bool get redLetter => _prefs.getBool(_kRedLetter) ?? true;
  set redLetter(bool value) => _write(_kRedLetter, value);

  bool get showFootnotes => _prefs.getBool(_kFootnotes) ?? true;
  set showFootnotes(bool value) => _write(_kFootnotes, value);

  /// True: verses flow together in paragraphs, as in a printed Bible.
  /// False: every verse starts on its own line.
  bool get paragraphLayout => _prefs.getBool(_kParagraphs) ?? true;
  set paragraphLayout(bool value) => _write(_kParagraphs, value);

  bool get showVerseNumbers => _prefs.getBool(_kVerseNumbers) ?? true;
  set showVerseNumbers(bool value) => _write(_kVerseNumbers, value);

  bool get showDeuterocanon => _prefs.getBool(_kDeuterocanon) ?? false;
  set showDeuterocanon(bool value) => _write(_kDeuterocanon, value);

  BookOrder get bookOrder =>
      BookOrder.values[_prefs.getInt(_kBookOrder) ?? BookOrder.canonical.index];
  set bookOrder(BookOrder value) => _write(_kBookOrder, value.index);

  String get translationId =>
      _prefs.getString(_kTranslation) ?? Translations.fallback.id;
  set translationId(String value) => _write(_kTranslation, value);

  /// The translation shown beside the main one, or null when not comparing.
  String? get compareTranslationId {
    final id = _prefs.getString(_kCompare);
    return (id == null || id.isEmpty || id == translationId) ? null : id;
  }

  set compareTranslationId(String? value) {
    if (value == null || value.isEmpty) {
      _prefs.remove(_kCompare);
      notifyListeners();
      return;
    }
    _write(_kCompare, value);
  }

  /// Whether to ask GitHub, once a day, whether there is a newer release.
  /// This is the only thing in the app that uses the network; turning it off
  /// leaves OpenWord entirely offline again.
  bool get checkForUpdates => _prefs.getBool(_kCheckUpdates) ?? true;
  set checkForUpdates(bool value) => _write(_kCheckUpdates, value);

  DateTime? get lastUpdateCheck {
    final millis = _prefs.getInt(_kLastCheck);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  set lastUpdateCheck(DateTime? value) {
    if (value == null) {
      _prefs.remove(_kLastCheck);
      notifyListeners();
      return;
    }
    _write(_kLastCheck, value.millisecondsSinceEpoch);
  }

  /// A version the reader has told the app not to nag about again.
  String? get skippedUpdate => _prefs.getString(_kSkippedUpdate);
  set skippedUpdate(String? value) {
    if (value == null) {
      _prefs.remove(_kSkippedUpdate);
      notifyListeners();
      return;
    }
    _write(_kSkippedUpdate, value);
  }

  /// Translations the reader has asked to have the verse-keyed layers on
  /// regardless of what their numbering was measured to be.
  Set<String> get anchoredAnyway =>
      (_prefs.getStringList(_kAnchorAnyway) ?? const <String>[]).toSet();

  /// Whether the cross-references and the Hebrew and Greek are offered for
  /// a translation.
  ///
  /// Both are keyed to the verse, so they apply to any translation whose
  /// numbering agrees with the one they were anchored to; against a Bible
  /// numbered otherwise they do not fail, they land on the wrong verse.
  /// A translation measured as numbering differently is therefore not
  /// offered them — unless the reader has asked for them anyway, which is
  /// their call to make: they can see the verse in front of them, and a
  /// reference that is out by one is more use to them than none at all.
  bool offersVerseKeyedLayers(TranslationInfo translation) =>
      Versification.mayAnchorEnglish(translation.versification) ||
      anchoredAnyway.contains(translation.id);

  void setAnchoredAnyway(String id, bool value) {
    final ids = anchoredAnyway;
    if (value ? !ids.add(id) : !ids.remove(id)) return;
    _prefs.setStringList(_kAnchorAnyway, ids.toList()..sort());
    notifyListeners();
  }

  void _write(String key, Object value) {
    switch (value) {
      case final int v:
        _prefs.setInt(key, v);
      case final double v:
        _prefs.setDouble(key, v);
      case final bool v:
        _prefs.setBool(key, v);
      case final String v:
        _prefs.setString(key, v);
    }
    notifyListeners();
  }
}
