import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The book introductions bundled with the app.
///
/// These are the Aquifer Open Study Notes book introductions — an adaptation
/// by Mission Mutual of Tyndale Open Study Notes, both under CC BY-SA 4.0.
/// They are loaded on demand rather than at start-up: they are only wanted
/// when someone opens a book's background sheet, and there is no reason to
/// spend the memory before that.
class BookIntros {
  BookIntros({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetName = 'book-intros-eng.json.gz';
  static const String assetPath = 'assets/notes/$assetName';

  /// Shown wherever the introductions are, as the licence requires.
  static const String attribution =
      'Aquifer Open Study Notes (Book Intros) © Mission Mutual, an adaptation '
      'of Tyndale Open Study Notes © 2023 Tyndale House Publishers. Both are '
      'licensed CC BY-SA 4.0.';

  static const String licenceUrl =
      'https://creativecommons.org/licenses/by-sa/4.0/';

  final AssetBundle _bundle;
  Map<String, String>? _intros;
  Future<Map<String, String>>? _loading;

  /// The introduction for a book, or null where there is none — the
  /// deuterocanonical books are not covered by this resource.
  Future<String?> forBook(String bookCode) async {
    final intros = _intros ?? await _load();
    return intros[bookCode.toUpperCase()];
  }

  /// Already-loaded introductions, for a synchronous check.
  String? loaded(String bookCode) => _intros?[bookCode.toUpperCase()];

  Future<Map<String, String>> _load() {
    return _loading ??= _read().then((intros) {
      _intros = intros;
      return intros;
    });
  }

  Future<Map<String, String>> _read() async {
    try {
      final data = await _bundle.load(assetPath);
      final raw = const GZipDecoder().decodeBytes(Uint8List.sublistView(data));
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value.toString(),
      };
    } on Object catch (error) {
      debugPrint('OpenWord: could not read book introductions: $error');
      return const {};
    }
  }
}
