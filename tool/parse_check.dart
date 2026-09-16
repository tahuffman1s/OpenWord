// Developer utility: parse a local USFX file and print a structural summary.
// Usage: dart run tool/parse_check.dart <path-to-usfx.xml>
import 'dart:io';

import 'package:openword/src/data/usfx_parser.dart';
import 'package:openword/src/model/bible.dart';

void main(List<String> args) {
  final path = args.isEmpty ? 'eng-web.usfx.xml' : args.first;
  final xml = File(path).readAsStringSync();
  final started = DateTime.now();
  final bible = UsfxParser.parse(
    xml,
    const TranslationInfo(
      id: 'eng-web',
      name: 'World English Bible',
      abbreviation: 'WEB',
      license: 'Public Domain',
      sourceUrl: 'https://ebible.org/web/',
    ),
  );
  final elapsed = DateTime.now().difference(started);
  stdout.writeln('parsed in ${elapsed.inMilliseconds} ms');
  stdout.writeln('books: ${bible.books.length}  verses: ${bible.verseCount}');
  for (final code in ['GEN', 'PSA', 'MAT', 'REV', 'JHN']) {
    final book = bible.bookByCode(code);
    stdout.writeln('$code -> ${book?.chapterCount} chapters');
  }
  void dump(String code, int chapter, {int blocks = 6}) {
    final c = bible.bookByCode(code)!.chapter(chapter)!;
    stdout.writeln(
      '\n=== $code $chapter (${c.verseCount} verses, '
      '${c.notes.length} notes) ===',
    );
    for (final block in c.blocks.take(blocks)) {
      final body = block.segments
          .map(
            (s) =>
                '${s.startsVerse ? "[${s.verse}]" : "(${s.verse})"}'
                '${s.text}',
          )
          .join(' | ');
      stdout.writeln('${block.style.key}${block.indent}  $body');
    }
  }

  dump('GEN', 1);
  dump('PSA', 3);
  dump('PSA', 23);
  dump('MAT', 5, blocks: 4);
  dump('JHN', 3, blocks: 4);
  dump('PRO', 1, blocks: 4);

  // Sanity: every book/chapter/verse should have text.
  var missing = 0;
  for (final book in bible.books) {
    for (final chapter in book.chapters) {
      for (var v = 1; v <= chapter.verseCount; v++) {
        if (chapter.verseText(v).isEmpty) {
          missing++;
          if (missing < 12) {
            stdout.writeln('EMPTY ${book.code} ${chapter.number}:$v');
          }
        }
      }
    }
  }
  stdout.writeln('\nempty verses: $missing');
}
