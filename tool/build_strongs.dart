// Builds the original-language layer: every word of the Hebrew Bible and the
// Greek New Testament, with its Strong's number and parsing, keyed by the
// English verse it belongs to, plus Strong's dictionaries.
//
//   dart run tool/build_strongs.dart <morphhb> <byzantine-majority-text> <strongs>
//
// Sources, all free to redistribute:
//   morphhb   Open Scriptures Hebrew Bible, CC BY 4.0 — the Hebrew, its
//             Strong's numbers and parsing, plus VerseMap.xml, which is how
//             Hebrew verse numbering is turned into English.
//   byztxt    Byzantine Majority Text (Robinson–Pierpont), public domain —
//             the Greek, in two files that align word for word: one accented
//             and one carrying Strong's numbers and parsing.
//   strongs   Strong's dictionaries of Hebrew and Greek, CC BY-SA.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:openword/src/model/book_meta.dart';
import 'package:openword/src/model/strongs_codec.dart';

/// OSHB names its files by an OSIS abbreviation; the app uses USFM codes.
const Map<String, String> _osisToCode = {
  'Gen': 'GEN',
  'Exod': 'EXO',
  'Lev': 'LEV',
  'Num': 'NUM',
  'Deut': 'DEU',
  'Josh': 'JOS',
  'Judg': 'JDG',
  'Ruth': 'RUT',
  '1Sam': '1SA',
  '2Sam': '2SA',
  '1Kgs': '1KI',
  '2Kgs': '2KI',
  '1Chr': '1CH',
  '2Chr': '2CH',
  'Ezra': 'EZR',
  'Neh': 'NEH',
  'Esth': 'EST',
  'Job': 'JOB',
  'Ps': 'PSA',
  'Prov': 'PRO',
  'Eccl': 'ECC',
  'Song': 'SNG',
  'Isa': 'ISA',
  'Jer': 'JER',
  'Lam': 'LAM',
  'Ezek': 'EZK',
  'Dan': 'DAN',
  'Hos': 'HOS',
  'Joel': 'JOL',
  'Amos': 'AMO',
  'Obad': 'OBA',
  'Jonah': 'JON',
  'Mic': 'MIC',
  'Nah': 'NAM',
  'Hab': 'HAB',
  'Zeph': 'ZEP',
  'Hag': 'HAG',
  'Zech': 'ZEC',
  'Mal': 'MAL',
};

/// The Greek files are named by a three-letter code of their own.
const Map<String, String> _byzToCode = {
  'MAT': 'MAT',
  'MAR': 'MRK',
  'LUK': 'LUK',
  'JOH': 'JHN',
  'ACT': 'ACT',
  'ROM': 'ROM',
  '1CO': '1CO',
  '2CO': '2CO',
  'GAL': 'GAL',
  'EPH': 'EPH',
  'PHP': 'PHP',
  'COL': 'COL',
  '1TH': '1TH',
  '2TH': '2TH',
  '1TI': '1TI',
  '2TI': '2TI',
  'TIT': 'TIT',
  'PHM': 'PHM',
  'HEB': 'HEB',
  'JAM': 'JAS',
  '1PE': '1PE',
  '2PE': '2PE',
  '1JO': '1JN',
  '2JO': '2JN',
  '3JO': '3JN',
  'JUD': 'JUD',
  'REV': 'REV',
};

final List<String> canon = [
  for (final meta in BookMeta.all)
    if (meta.section != BookSection.deuterocanon) meta.code,
];

int keyFor(String code, int chapter, int verse) {
  final book = canon.indexOf(code);
  if (book < 0) throw StateError('$code is not in the canon');
  return StrongsCodec.verseKey(book, chapter, verse);
}

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln('usage: build_strongs.dart <morphhb> <byztxt> <strongs>');
    exitCode = 1;
    return;
  }
  final hebrewDir = Directory('${args[0]}/wlc');
  final greekDir = Directory(args[1]);
  final strongsDir = Directory(args[2]);

  final writer = StrongsWriter();
  final report = StringBuffer();

  final morphology = _readMorphologyTable(File('${args[0]}/parsing/Oshm.xml'));
  report.writeln('hebrew parsings known: ${morphology.length}');

  final map = _readVerseMap(File('${hebrewDir.path}/VerseMap.xml'));
  report.writeln('versification corrections: ${map.length}');

  final hebrew = _readHebrew(hebrewDir, morphology, map, report);
  report.writeln('hebrew verses: ${hebrew.$1}  words: ${hebrew.$2}');
  hebrew.$3.forEach(writer.addVerse);

  final greek = _readGreek(greekDir, report);
  report.writeln('greek verses: ${greek.$1}  words: ${greek.$2}');
  greek.$3.forEach(writer.addVerse);

  final entries = _readLexicon(strongsDir, report);
  for (final entry in entries) {
    writer.addEntry(entry);
  }

  final bytes = writer.build();
  final out = Directory('assets/strongs')..createSync(recursive: true);
  final file = File('${out.path}/originals.ows.gz')
    ..writeAsBytesSync(gzip.encode(bytes));

  // Read it back before calling it done.
  final reader = StrongsReader.parse(Uint8List.fromList(bytes));
  final check = reader.wordsAt(keyFor('GEN', 1, 1));
  report
    ..writeln('verses=${writer.verseCount} entries=${writer.entryCount}')
    ..writeln(
      'raw=${(bytes.length / 1048576).toStringAsFixed(2)} MB '
      'gz=${(file.lengthSync() / 1048576).toStringAsFixed(2)} MB',
    )
    ..writeln(
      'Genesis 1:1 = ${check.length} words: '
      '${check.map((w) => '${w.text}(${w.strongs?.label})').join(' ')}',
    );

  final john = reader.wordsAt(keyFor('JHN', 3, 16));
  report.writeln(
    'John 3:16 = ${john.length} words: '
    '${john.take(5).map((w) => '${w.text}(${w.strongs?.label})').join(' ')}',
  );

  final god = reader.entryFor(const StrongsNumber('H', 430));
  report.writeln(
    'H430 = ${god?.lemma} ${god?.transliteration} '
    'renders="${god?.renderedAs}" '
    'occurrences=${reader.occurrenceCount(const StrongsNumber('H', 430))}',
  );
  final theos = reader.entryFor(const StrongsNumber('G', 2316));
  report.writeln(
    'G2316 = ${theos?.lemma} ${theos?.transliteration} '
    'occurrences=${reader.occurrenceCount(const StrongsNumber('G', 2316))}',
  );

  stdout.write(report);
  stdout.writeln('-> ${file.path}');
}

/// Morphology code → the parsing spelled out, from the OSHB key file.
Map<String, String> _readMorphologyTable(File file) {
  if (!file.existsSync()) return {};
  final out = <String, String>{};
  final pattern = RegExp(r'<entryFree n="([^"]+)">([^<]*)</entryFree>');
  for (final match in pattern.allMatches(file.readAsStringSync())) {
    out[match.group(1)!] = match.group(2)!.trim();
  }
  return out;
}

/// Hebrew verse reference → the English one, where they differ.
///
/// VerseMap.xml lists only the verses that move. Everything it does not
/// mention is numbered the same in both.
Map<String, String> _readVerseMap(File file) {
  final out = <String, String>{};
  if (!file.existsSync()) return out;
  final pattern = RegExp(r'<verse wlc="([^"]+)" kjv="([^"]+)"');
  for (final match in pattern.allMatches(file.readAsStringSync())) {
    out[match.group(1)!] = match.group(2)!;
  }
  return out;
}

(int, int, Map<int, List<OriginalWord>>) _readHebrew(
  Directory dir,
  Map<String, String> morphology,
  Map<String, String> verseMap,
  StringBuffer report,
) {
  final verses = <int, List<OriginalWord>>{};
  var words = 0;
  var unmapped = 0;
  var untagged = 0;

  final versePattern = RegExp(
    r'<verse osisID="([^"]+)">(.*?)</verse>',
    dotAll: true,
  );
  final wordPattern = RegExp(r'<w\b([^>]*)>(.*?)</w>', dotAll: true);

  for (final file in dir.listSync().whereType<File>()) {
    final name = file.path.split('/').last;
    if (!name.endsWith('.xml') || name == 'VerseMap.xml') continue;
    final osis = name.substring(0, name.length - 4);
    final code = _osisToCode[osis];
    if (code == null) {
      report.writeln('skipped $name: no book code');
      continue;
    }

    final text = file.readAsStringSync();
    for (final verse in versePattern.allMatches(text)) {
      final hebrewRef = verse.group(1)!;
      // Where VerseMap moves a verse, follow it; otherwise the numbering is
      // already English.
      final englishRef = verseMap[hebrewRef] ?? hebrewRef;
      final parts = englishRef.split('.');
      if (parts.length != 3) {
        unmapped++;
        continue;
      }
      final englishCode = _osisToCode[parts[0]] ?? code;
      final chapter = int.tryParse(parts[1]);
      final number = int.tryParse(parts[2]);
      if (chapter == null || number == null) {
        unmapped++;
        continue;
      }

      final list = <OriginalWord>[];
      for (final word in wordPattern.allMatches(verse.group(2)!)) {
        final attributes = word.group(1)!;
        final surface = _plainHebrew(word.group(2)!);
        if (surface.isEmpty) continue;
        final lemma = _attribute(attributes, 'lemma');
        final morph = _attribute(attributes, 'morph');
        final strongs = _hebrewStrongs(lemma);
        if (strongs == null) untagged++;
        list.add(
          OriginalWord(
            text: surface,
            strongs: strongs,
            morphology: morphology[morph] ?? '',
          ),
        );
      }
      if (list.isEmpty) continue;

      final key = keyFor(englishCode, chapter, number);
      // Two Hebrew verses can map onto one English verse; the words join.
      verses.putIfAbsent(key, () => []).addAll(list);
      words += list.length;
    }
  }

  report.writeln('hebrew words with no Strong\'s number: $untagged');
  if (unmapped > 0) report.writeln('hebrew verses not placed: $unmapped');
  return (verses.length, words, verses);
}

/// The word as it is read: OSHB separates prefixes with a slash, which is
/// grammar rather than spelling.
String _plainHebrew(String raw) => raw
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('/', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _attribute(String attributes, String name) =>
    RegExp('$name="([^"]*)"').firstMatch(attributes)?.group(1) ?? '';

/// The Strong's number of the word itself, past any prefixes.
///
/// OSHB writes the lemma as its morphemes: "c/d/776" is "and"+"the"+earth,
/// and the word is 776. Homonyms carry a letter — "1254 a" — which Strong's
/// dictionary does not distinguish.
StrongsNumber? _hebrewStrongs(String lemma) {
  if (lemma.isEmpty) return null;
  final parts = lemma.split('/');
  for (final part in parts.reversed) {
    final match = RegExp(r'(\d+)').firstMatch(part);
    if (match == null) continue;
    final number = int.parse(match.group(1)!);
    // 9000-series numbers are OSHB's own markers for suffixes and
    // punctuation, not Strong's numbers.
    if (number >= 9000 || number == 0) continue;
    return StrongsNumber('H', number);
  }
  return null;
}

(int, int, Map<int, List<OriginalWord>>) _readGreek(
  Directory root,
  StringBuffer report,
) {
  final verses = <int, List<OriginalWord>>{};
  var words = 0;
  var unaligned = 0;

  final taggedDir = Directory('${root.path}/csv-unicode/strongs/with-parsing');
  final accentDirs = [
    Directory('${root.path}/csv-unicode/ccat/no-variants'),
    Directory('${root.path}/csv-unicode/ccat/with-variants'),
  ];
  if (!taggedDir.existsSync()) {
    report.writeln('no Greek at ${taggedDir.path}');
    return (0, 0, verses);
  }

  final wordPattern = RegExp(r'(\S+)\s+(\d+)\s+\{([^}]*)\}');
  final punctuation = RegExp(r'[^\w\sͰ-Ͽἀ-῿]', unicode: true);

  for (final file in taggedDir.listSync().whereType<File>()) {
    final name = file.path.split('/').last;
    if (!name.endsWith('.csv')) continue;
    final code = _byzToCode[name.substring(0, name.length - 4)];
    if (code == null) {
      report.writeln('skipped $name: no book code');
      continue;
    }

    final tagged = _readCsv(file);
    Map<(int, int), String> accented = {};
    for (final dir in accentDirs) {
      final candidate = File('${dir.path}/$name');
      if (candidate.existsSync()) {
        accented = _readCsv(candidate);
        break;
      }
    }

    tagged.forEach((at, text) {
      final matches = wordPattern.allMatches(text).toList();
      if (matches.isEmpty) return;

      // The accented text is the same words in the same order, so the two
      // line up one for one — checked here rather than assumed.
      final pretty = accented[at];
      List<String>? surfaces;
      if (pretty != null) {
        final cleaned = pretty
            .replaceAll('¶', ' ')
            .replaceAll(punctuation, ' ')
            .split(RegExp(r'\s+'))
            .where((word) => word.isNotEmpty)
            .toList();
        if (cleaned.length == matches.length) {
          surfaces = cleaned;
        } else {
          unaligned++;
        }
      }

      final list = <OriginalWord>[];
      for (var i = 0; i < matches.length; i++) {
        final match = matches[i];
        final number = int.parse(match.group(2)!);
        list.add(
          OriginalWord(
            text: surfaces?[i] ?? match.group(1)!,
            strongs: number > 0 ? StrongsNumber('G', number) : null,
            morphology: _greekParsing(match.group(3)!),
          ),
        );
      }

      verses[keyFor(code, at.$1, at.$2)] = list;
      words += list.length;
    });
  }

  if (unaligned > 0) {
    report.writeln(
      'greek verses left unaccented (word counts differed): '
      '$unaligned',
    );
  }
  return (verses.length, words, verses);
}

Map<(int, int), String> _readCsv(File file) {
  final out = <(int, int), String>{};
  final lines = const LineSplitter().convert(file.readAsStringSync());
  for (final line in lines.skip(1)) {
    final first = line.indexOf(',');
    if (first < 0) continue;
    final second = line.indexOf(',', first + 1);
    if (second < 0) continue;
    final chapter = int.tryParse(line.substring(0, first));
    final verse = int.tryParse(line.substring(first + 1, second));
    if (chapter == null || verse == null) continue;
    var text = line.substring(second + 1);
    if (text.startsWith('"') && text.endsWith('"') && text.length >= 2) {
      text = text.substring(1, text.length - 1).replaceAll('""', '"');
    }
    out[(chapter, verse)] = text;
  }
  return out;
}

/// "V-AAI-3S" spelled out. The codes are positional, so this reads them
/// rather than listing every combination.
String _greekParsing(String code) {
  const parts = {
    'N': 'Noun',
    'A': 'Adjective',
    'T': 'Article',
    'V': 'Verb',
    'P': 'Personal pronoun',
    'R': 'Relative pronoun',
    'C': 'Reciprocal pronoun',
    'D': 'Demonstrative pronoun',
    'K': 'Correlative pronoun',
    'I': 'Interrogative pronoun',
    'X': 'Indefinite pronoun',
    'Q': 'Correlative or interrogative pronoun',
    'F': 'Reflexive pronoun',
    'S': 'Possessive pronoun',
    'ADV': 'Adverb',
    'CONJ': 'Conjunction',
    'COND': 'Conditional',
    'PRT': 'Particle',
    'PREP': 'Preposition',
    'INJ': 'Interjection',
    'ARAM': 'Aramaic',
    'HEB': 'Hebrew',
    'N-PRI': 'Proper noun (indeclinable)',
    'A-NUI': 'Numeral (indeclinable)',
    'N-LI': 'Letter (indeclinable)',
    'N-OI': 'Noun (indeclinable)',
  };
  const cases = {
    'N': 'nominative',
    'V': 'vocative',
    'G': 'genitive',
    'D': 'dative',
    'A': 'accusative',
  };
  const numbers = {'S': 'singular', 'P': 'plural'};
  const genders = {'M': 'masculine', 'F': 'feminine', 'N': 'neuter'};
  const tenses = {
    'P': 'present',
    'I': 'imperfect',
    'F': 'future',
    'A': 'aorist',
    '2A': 'second aorist',
    'R': 'perfect',
    '2R': 'second perfect',
    'L': 'pluperfect',
    '2L': 'second pluperfect',
    '2F': 'second future',
    'X': 'no tense',
  };
  const voices = {
    'A': 'active',
    'M': 'middle',
    'P': 'passive',
    'E': 'middle or passive',
    'D': 'deponent',
    'O': 'passive deponent',
    'N': 'middle deponent',
    'Q': 'impersonal active',
    'X': 'no voice',
  };
  const moods = {
    'I': 'indicative',
    'S': 'subjunctive',
    'O': 'optative',
    'M': 'imperative',
    'N': 'infinitive',
    'P': 'participle',
    'R': 'imperative participle',
  };
  const persons = {
    '1': 'first person',
    '2': 'second person',
    '3': 'third person',
  };

  final trimmed = code.trim();
  if (trimmed.isEmpty) return '';
  if (parts.containsKey(trimmed)) return parts[trimmed]!;

  final segments = trimmed.split('-');
  final head = segments.first;
  final said = <String>[];

  if (parts.containsKey(trimmed)) return parts[trimmed]!;
  said.add(parts[head] ?? head);

  if (head == 'V') {
    if (segments.length > 1) {
      final tvm = segments[1];
      // Tense may be two characters ("2A"), so it is read from the front.
      var at = 0;
      String take(Map<String, String> table) {
        for (final length in [2, 1]) {
          if (at + length <= tvm.length) {
            final piece = tvm.substring(at, at + length);
            if (table.containsKey(piece)) {
              at += length;
              return table[piece]!;
            }
          }
        }
        return '';
      }

      for (final word in [take(tenses), take(voices), take(moods)]) {
        if (word.isNotEmpty) said.add(word);
      }
    }
    if (segments.length > 2) {
      final pn = segments[2];
      if (pn.isNotEmpty && persons.containsKey(pn[0])) {
        said.add(persons[pn[0]]!);
      }
      for (final letter in pn.split('')) {
        if (numbers.containsKey(letter)) said.add(numbers[letter]!);
        if (cases.containsKey(letter) && !persons.containsKey(pn[0])) {
          said.add(cases[letter]!);
        }
        if (genders.containsKey(letter)) said.add(genders[letter]!);
      }
    }
  } else if (segments.length > 1) {
    for (final letter in segments[1].split('')) {
      if (cases.containsKey(letter)) {
        said.add(cases[letter]!);
      } else if (numbers.containsKey(letter)) {
        said.add(numbers[letter]!);
      } else if (genders.containsKey(letter)) {
        said.add(genders[letter]!);
      }
    }
  }
  return said.where((word) => word.isNotEmpty).join(' ');
}

List<StrongsEntry> _readLexicon(Directory dir, StringBuffer report) {
  final out = <StrongsEntry>[];
  for (final language in ['hebrew', 'greek']) {
    final file = File('${dir.path}/$language/strongs-$language-dictionary.js');
    if (!file.existsSync()) {
      report.writeln('no $language dictionary at ${file.path}');
      continue;
    }
    final text = file.readAsStringSync();
    final start = text.indexOf('{"');
    final end = text.lastIndexOf('}');
    if (start < 0 || end < start) {
      report.writeln('$language dictionary could not be read');
      continue;
    }
    final decoded =
        jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
    var count = 0;
    decoded.forEach((key, value) {
      final number = StrongsNumber.parse(key);
      if (number == null || value is! Map) return;
      out.add(
        StrongsEntry(
          number: number,
          lemma: (value['lemma'] ?? '').toString(),
          // Hebrew calls it xlit, Greek calls it translit, and the Greek
          // has no pronunciation guide at all.
          transliteration: (value['xlit'] ?? value['translit'] ?? '')
              .toString(),
          pronunciation: (value['pron'] ?? '').toString(),
          derivation: (value['derivation'] ?? '').toString(),
          definition: (value['strongs_def'] ?? '').toString(),
          kjvUsage: (value['kjv_def'] ?? '').toString(),
        ),
      );
      count++;
    });
    report.writeln('$language dictionary entries: $count');
  }
  return out;
}
