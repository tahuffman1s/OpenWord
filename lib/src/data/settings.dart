import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bible_source.dart';

/// How the book picker is organised.
enum BookOrder {
  /// A–Z with the Niagara-style letter rail.
  alphabetical('A–Z'),

  /// Genesis to Revelation, grouped by testament.
  canonical('Canon');

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
      BookOrder.values[_prefs.getInt(_kBookOrder) ??
          BookOrder.alphabetical.index];
  set bookOrder(BookOrder value) => _write(_kBookOrder, value.index);

  String get translationId =>
      _prefs.getString(_kTranslation) ?? BibleSource.worldEnglishBible.id;
  set translationId(String value) => _write(_kTranslation, value);

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
