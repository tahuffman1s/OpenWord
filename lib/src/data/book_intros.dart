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

/// A book introduction, split into its sections.
///
/// The source is consistent about its shape: a paragraph or two of lead, then
/// top-level sections — Setting, Summary, Author, Date, Meaning and Message —
/// some with sub-headings of their own. Splitting on those headings lets the
/// sheet show the outline at a glance rather than several screens of prose.
class BookIntro {
  const BookIntro({required this.lead, required this.sections});

  /// What comes before the first section heading.
  final String lead;

  final List<IntroSection> sections;

  bool get isEmpty => lead.isEmpty && sections.isEmpty;

  static BookIntro parse(String markdown) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final lead = <String>[];
    final sections = <IntroSection>[];
    String? title;
    final body = <String>[];

    void close() {
      final heading = title;
      if (heading == null) return;
      sections.add(IntroSection(title: heading, body: body.join('\n').trim()));
      body.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // A line of `=` underneath text makes it a top-level heading; the
      // source uses `-` for the level below, which stays inside its section.
      final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
      final underlined = trimmed.isNotEmpty && RegExp(r'^=+$').hasMatch(next);
      final hashed = RegExp(r'^#\s+(.*)$').firstMatch(trimmed);

      if (underlined || hashed != null) {
        close();
        title = hashed?.group(1)?.trim() ?? trimmed;
        if (underlined) i++;
        continue;
      }

      if (title == null) {
        lead.add(line);
      } else {
        body.add(line);
      }
    }
    close();

    return BookIntro(lead: lead.join('\n').trim(), sections: sections);
  }
}

class IntroSection {
  const IntroSection({required this.title, required this.body});

  final String title;
  final String body;
}
