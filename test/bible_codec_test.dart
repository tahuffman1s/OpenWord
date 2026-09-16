import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/model/bible_codec.dart';

import 'fixtures.dart';

void main() {
  final original = parseFixture();

  test('survives a binary round trip', () {
    final restored = BibleCodec.decode(BibleCodec.encode(original));

    expect(restored.translation.id, original.translation.id);
    expect(restored.translation.abbreviation, 'TST');
    expect(
      restored.books.map((b) => b.code),
      original.books.map((b) => b.code),
    );
    expect(restored.verseCount, original.verseCount);

    final psalm = restored.bookByCode('PSA')!.chapter(1)!;
    expect(
      psalm.blocks.map((block) => '${block.style.key}${block.indent}'),
      original
          .bookByCode('PSA')!
          .chapter(1)!
          .blocks
          .map((block) => '${block.style.key}${block.indent}'),
    );
    expect(psalm.blocks[3].segments.first.startsVerse, isFalse);

    final genesis = restored.bookByCode('GEN')!.chapter(1)!;
    expect(genesis.notes, ['Elohim.']);
    expect(genesis.verseText(1), 'In the beginning, God created the heavens.');
    expect(
      genesis.blocks
          .firstWhere((b) => b.style == BlockStyle.reference)
          .segments
          .first
          .text,
      '(John 1:1–5)',
    );
  });

  test('keeps inline markers byte for byte', () {
    final restored = BibleCodec.decode(BibleCodec.encode(original));
    final matthew = restored.bookByCode('MAT')!.chapter(1)!;
    expect(
      matthew.blocks.first.segments.first.text,
      original.bookByCode('MAT')!.chapter(1)!.blocks.first.segments.first.text,
    );
    expect(
      matthew.blocks.first.segments.first.text,
      contains('${Markup.wjStart}Follow me.${Markup.wjEnd}'),
    );
  });

  test('rejects data that is not a Bible file', () {
    expect(
      () => BibleCodec.decode(Uint8List.fromList([1, 2, 3, 4, 5])),
      throwsFormatException,
    );
  });

  test('rejects a truncated file', () {
    final encoded = BibleCodec.encode(original);
    expect(
      () => BibleCodec.decode(Uint8List.sublistView(encoded, 0, 64)),
      throwsFormatException,
    );
  });

  test('rejects a future format version', () {
    final encoded = BibleCodec.encode(original);
    final tampered = Uint8List.fromList(encoded)..[3] = 99;
    expect(() => BibleCodec.decode(tampered), throwsFormatException);
  });

  test('is smaller than the text it carries', () {
    final encoded = BibleCodec.encode(original);
    final textLength = original.books
        .expand((book) => book.chapters)
        .expand((chapter) => chapter.blocks)
        .expand((block) => block.segments)
        .fold<int>(0, (sum, segment) => sum + segment.text.length);
    // Framing is a few bytes per segment, not a multiple of the text.
    expect(encoded.length, lessThan(textLength * 2));
  });
}
