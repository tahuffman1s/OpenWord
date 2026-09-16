// Turns the Aquifer Open Study Notes book introductions into the asset the
// app ships with.
//
//   dart run tool/build_notes.dart <directory-of-NN.content.md-files>
//
// The source is https://github.com/BibleAquifer/AquiferOpenStudyNotesBookIntros
// (eng/md), CC BY-SA 4.0, an adaptation of Tyndale Open Study Notes. Files are
// numbered 01–66 in the order of the Protestant canon.
//
//   for i in $(seq -w 1 66); do
//     curl -sSLO "https://raw.githubusercontent.com/BibleAquifer/\
// AquiferOpenStudyNotesBookIntros/main/eng/md/$i.content.md"
//   done
import 'dart:convert';
import 'dart:io';

import 'package:openword/src/model/book_meta.dart';

/// Kept in step with `BookIntros.assetName`, which cannot be imported here:
/// it reaches for the Flutter asset bundle and this is a plain Dart script.
const String assetName = 'book-intros-eng.json.gz';

void main(List<String> args) {
  final source = Directory(args.isEmpty ? '.' : args.first);
  if (!source.existsSync()) {
    stderr.writeln('no such directory: ${source.path}');
    exitCode = 1;
    return;
  }

  // Files are numbered in canon order, skipping the deuterocanon.
  final canon = [
    for (final book in BookMeta.all)
      if (book.section != BookSection.deuterocanon) book,
  ];

  final intros = <String, String>{};
  for (var number = 1; number <= canon.length; number++) {
    final padded = number.toString().padLeft(2, '0');
    final file = [
      File('${source.path}/$padded.content.md'),
      File('${source.path}/$padded.md'),
    ].firstWhere((f) => f.existsSync(), orElse: () => File(''));
    if (file.path.isEmpty) {
      stderr.writeln(
        'missing introduction $padded (${canon[number - 1].name})',
      );
      exitCode = 1;
      continue;
    }
    final body = _extract(file.readAsStringSync(), canon[number - 1].name);
    if (body == null) {
      stderr.writeln('could not read ${file.path}');
      exitCode = 1;
      continue;
    }
    intros[canon[number - 1].code] = body;
  }

  if (intros.length != canon.length) {
    stderr.writeln('got ${intros.length} of ${canon.length} introductions');
    exitCode = 1;
    return;
  }

  final json = jsonEncode(intros);
  final bytes = gzip.encode(utf8.encode(json));
  final output = File('assets/notes/$assetName')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  stdout.writeln(
    'wrote ${intros.length} introductions, '
    '${_kb(json.length)} of markdown, ${_kb(bytes.length)} gzipped '
    '-> ${output.path}',
  );
}

/// Drops the licence preamble and the title line, leaving the body. The
/// licence is shown by the app from its own copy, so carrying it 66 times in
/// the asset would be dead weight.
///
/// The cut is made at the title line rather than at the rule above it: the
/// files use rules of dashes for sub-headings too, and splitting on those
/// would strip the underlines that make them headings.
String? _extract(String markdown, String bookName) {
  final title = RegExp(
    r'^##\s+(.+?)\s*\(id:\s*\d+\)\s*$',
    multiLine: true,
  ).firstMatch(markdown);
  if (title == null) return null;

  final named = title.group(1)!.toLowerCase();
  if (!named.contains(bookName.split(' ').last.toLowerCase())) {
    stderr.writeln('warning: $bookName does not match "${title.group(1)}"');
  }

  final body = markdown.substring(title.end).trim();
  return body.isEmpty ? null : body;
}

String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(0)} kB';
