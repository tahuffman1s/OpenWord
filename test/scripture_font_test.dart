@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/ui/scripture_type.dart';

/// The codepoints in a font's `cmap`, read out of the file itself.
///
/// The bundled face is the only thing standing between the Hebrew and a row
/// of empty boxes, and it is a binary: nothing in the source says what is in
/// it. So the test reads it.
Set<int> _codepoints(File file) {
  final bytes = ByteData.sublistView(
    Uint8List.fromList(file.readAsBytesSync()),
  );

  int? cmapAt;
  final tables = bytes.getUint16(4);
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes([
      for (var b = 0; b < 4; b++) bytes.getUint8(record + b),
    ]);
    if (tag == 'cmap') cmapAt = bytes.getUint32(record + 8);
  }
  expect(cmapAt, isNotNull, reason: 'the font has no cmap');

  // Pick the Windows Unicode BMP subtable; every subset here is BMP.
  int? subtableAt;
  final subtables = bytes.getUint16(cmapAt! + 2);
  for (var i = 0; i < subtables; i++) {
    final record = cmapAt + 4 + i * 8;
    if (bytes.getUint16(record) == 3 && bytes.getUint16(record + 2) == 1) {
      subtableAt = cmapAt + bytes.getUint32(record + 4);
    }
  }
  expect(subtableAt, isNotNull, reason: 'no Windows Unicode subtable');
  expect(bytes.getUint16(subtableAt!), 4, reason: 'expected a format 4 cmap');

  final segments = bytes.getUint16(subtableAt + 6) ~/ 2;
  final endAt = subtableAt + 14;
  final startAt = endAt + segments * 2 + 2;
  final deltaAt = startAt + segments * 2;
  final rangeAt = deltaAt + segments * 2;

  final covered = <int>{};
  for (var s = 0; s < segments; s++) {
    final end = bytes.getUint16(endAt + s * 2);
    final start = bytes.getUint16(startAt + s * 2);
    if (start == 0xFFFF) continue;
    final delta = bytes.getInt16(deltaAt + s * 2);
    final range = bytes.getUint16(rangeAt + s * 2);
    for (var cp = start; cp <= end; cp++) {
      int glyph;
      if (range == 0) {
        glyph = (cp + delta) & 0xFFFF;
      } else {
        final at = rangeAt + s * 2 + range + (cp - start) * 2;
        if (at + 1 >= bytes.lengthInBytes) continue;
        glyph = bytes.getUint16(at);
        if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
      }
      if (glyph != 0) covered.add(cp);
    }
  }
  return covered;
}

void main() {
  group('the bundled scripture face', () {
    late Set<int> covered;

    setUpAll(() {
      final file = File('assets/fonts/ScriptureSerif-Subset.ttf');
      expect(file.existsSync(), isTrue, reason: 'the face is not in the tree');
      covered = _codepoints(file);
    });

    test('carries every Hebrew letter', () {
      // Alef to tav, with the five final forms among them.
      for (var cp = 0x05D0; cp <= 0x05EA; cp++) {
        expect(covered, contains(cp), reason: 'missing U+${_hex(cp)}');
      }
    });

    test('carries the vowel points', () {
      // Sheva through qamats qatan, less the two holes the block itself has.
      for (var cp = 0x05B0; cp <= 0x05C7; cp++) {
        if (cp == 0x05BE || cp == 0x05C0) continue; // maqaf and paseq
        if (cp == 0x05C3 || cp == 0x05C6) continue; // sof pasuq, nun hafukha
        expect(covered, contains(cp), reason: 'missing U+${_hex(cp)}');
      }
    });

    test('carries all thirty-one cantillation marks', () {
      final accents = covered.where((cp) => cp >= 0x0591 && cp <= 0x05AF);
      expect(accents.length, 31);
    });

    test('carries the marks Strong\'s transliterates with', () {
      // Without these a transliteration comes out as "râqîya" and a box.
      for (final cp in const [
        0x02BB, // ʻ  ayin
        0x02BC, // ʼ  aleph
        0x02E2, // ˢ
        0x1D49, // ᵉ
        0x1E15, 0x1E16, 0x1E17, // ḕ Ḗ ḗ
        0x1E2F, // ḯ
        0x1E51, 0x1E53, // ṑ ṓ
        0x1E6C, 0x1E6D, // Ṭ ṭ
      ]) {
        expect(covered, contains(cp), reason: 'missing U+${_hex(cp)}');
      }
    });

    test('is small enough to bundle', () {
      final size = File('assets/fonts/ScriptureSerif-Subset.ttf').lengthSync();
      expect(size, lessThan(64 * 1024));
    });

    test('is declared in the pubspec, under the name the code asks for', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- family: $scriptureSerif'));
      expect(pubspec, contains('assets/fonts/ScriptureSerif-Subset.ttf'));
    });
  });

  group('scriptureStyle', () {
    const literata = TextStyle(fontFamily: 'Literata');

    test(
      'puts the scripture face first for Hebrew, the reading face behind',
      () {
        final style = scriptureStyle(literata, hebrew: true)!;
        expect(style.fontFamily, scriptureSerif);
        expect(style.fontFamilyFallback, ['Literata']);
      },
    );

    test('leaves the reading face in front for everything else', () {
      final style = scriptureStyle(literata, hebrew: false)!;
      expect(style.fontFamily, 'Literata');
      expect(style.fontFamilyFallback, [scriptureSerif]);
    });

    test('names no fallback when the style named no face', () {
      final style = scriptureStyle(const TextStyle(), hebrew: true)!;
      expect(style.fontFamily, scriptureSerif);
      expect(style.fontFamilyFallback, isNull);
    });

    test('passes a null style through', () {
      expect(scriptureStyle(null, hebrew: true), isNull);
    });
  });
}

String _hex(int cp) => cp.toRadixString(16).toUpperCase().padLeft(4, '0');
