// Turns the CrossReferences.org export into the cross-reference asset.
//
//   dart run tool/build_xrefs.dart <directory-with-the-json-export>
//
// The export is the Treasury of Scripture Knowledge, re-anchored so that each
// translation has its own phrases and versification (CC BY 4.0). This reads
// the Berean Standard Bible columns, since that is one of the translations
// the app ships, and writes assets/refs/xrefs.owx.gz.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:openword/src/model/book_meta.dart';
import 'package:openword/src/model/xref_codec.dart';

void main(List<String> args) {
  final source = Directory(args.isEmpty ? '.' : args.first);
  final versesFile = File('${source.path}/bible_verses.json');
  final refsFile = File('${source.path}/cross_references.json');
  for (final file in [versesFile, refsFile]) {
    if (!file.existsSync()) {
      stderr.writeln('missing ${file.path}');
      exitCode = 1;
      return;
    }
  }

  // The export numbers the books 1–66, in the order of the Protestant canon.
  final canon = [
    for (final meta in BookMeta.all)
      if (meta.section != BookSection.deuterocanon) meta.code,
  ];

  // verse id → where that verse is, in the Berean versification.
  final where = <int, (int book, int chapter, int verse)>{};
  final verses = jsonDecode(versesFile.readAsStringSync()) as List<dynamic>;
  for (final row in verses.cast<Map<String, dynamic>>()) {
    final chapter = row['bsb_ch'];
    final verse = row['bsb_vs'];
    if (chapter is! int || verse is! int) continue;
    where[row['id'] as int] = (row['book_id'] as int, chapter, verse);
  }

  final entries = <XrefEntry>[];
  var anchors = 0;
  var passages = 0;
  var dropped = 0;

  // The export is one row per anchor phrase, in reading order.
  XrefEntry? current;
  final rows = jsonDecode(refsFile.readAsStringSync()) as List<dynamic>;
  for (final row in rows.cast<Map<String, dynamic>>()) {
    final at = where[row['verse_id'] as int];
    if (at == null || at.$1 < 1 || at.$1 > canon.length) {
      dropped++;
      continue;
    }

    final phrase = (row['bsb'] as String? ?? '').trim();
    final ranges = <XrefRange>[];
    for (final group in (row['refs'] as List<dynamic>).cast<List<dynamic>>()) {
      if (group.isEmpty) continue;
      final first = where[group.first as int];
      final last = where[group.last as int];
      if (first == null || last == null) {
        dropped++;
        continue;
      }
      // A group is one reference; where it spans verses it is a range, and
      // where it spans chapters only its opening is kept — "Genesis 1:31 to
      // 2:3" reads as Genesis 1:31 rather than as nonsense.
      final end = (last.$1 == first.$1 && last.$2 == first.$2)
          ? last.$3
          : first.$3;
      ranges.add(
        XrefRange(
          book: first.$1 - 1,
          chapter: first.$2,
          verse: first.$3,
          endVerse: end < first.$3 ? first.$3 : end,
        ),
      );
    }
    if (ranges.isEmpty) continue;

    if (current == null ||
        current.book != at.$1 - 1 ||
        current.chapter != at.$2 ||
        current.verse != at.$3) {
      current = XrefEntry(
        book: at.$1 - 1,
        chapter: at.$2,
        verse: at.$3,
        anchors: [],
      );
      entries.add(current);
    }
    current.anchors.add(XrefAnchor(phrase: phrase, ranges: ranges));
    anchors++;
    passages += ranges.length;
  }

  entries.sort((a, b) => a.key.compareTo(b.key));

  final bytes = XrefCodec.encode(entries);
  final out = Directory('assets/refs')..createSync(recursive: true);
  final file = File('${out.path}/xrefs.owx.gz')
    ..writeAsBytesSync(gzip.encode(bytes));

  // Read it back: an asset that does not decode is worse than none.
  final restored = XrefCodec.decode(Uint8List.fromList(bytes));
  if (restored.length != entries.length) {
    stderr.writeln(
      'round trip mismatch: ${restored.length} != '
      '${entries.length}',
    );
    exitCode = 1;
  }

  stdout.writeln(
    'verses=${entries.length} anchors=$anchors passages=$passages '
    'dropped=$dropped '
    'raw=${(bytes.length / 1048576).toStringAsFixed(2)} MB '
    'gz=${(file.lengthSync() / 1048576).toStringAsFixed(2)} MB '
    '-> ${file.path}',
  );
}
