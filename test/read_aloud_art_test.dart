import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/read_aloud_art.dart';

void main() {
  testWidgets('a chapter cover is a square picture', (tester) async {
    final bytes = await tester.runAsync(
      () => renderChapterArt(
        book: 'Genesis',
        chapter: '1',
        colours: const ArtColours(
          from: Color(0xFFE8DEF8),
          to: Color(0xFFFFD8E4),
          ink: Color(0xFF21005D),
          accent: Color(0xFF6750A4),
        ),
      ),
    );
    expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    final header = ByteData.sublistView(bytes, 16, 24);
    expect((header.getUint32(0), header.getUint32(4)), (600, 600));
  });

  test('covers in different colours are kept apart', () {
    const a = ArtColours(
      from: Colors.white,
      to: Colors.black,
      ink: Colors.red,
      accent: Colors.blue,
    );
    const b = ArtColours(
      from: Colors.black,
      to: Colors.white,
      ink: Colors.red,
      accent: Colors.blue,
    );
    expect(a.key, isNot(b.key));
  });
}
