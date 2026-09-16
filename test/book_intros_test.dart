import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/book_intros.dart';

import 'fixtures.dart';

void main() {
  test('reads the introductions out of the bundle', () async {
    final bundle = FixtureBundle();
    final intros = BookIntros(bundle: bundle);

    expect(await intros.forBook('GEN'), contains('beginnings'));
    expect(await intros.forBook('gen'), contains('beginnings'));
  });

  test('has nothing for a book the resource does not cover', () async {
    final intros = BookIntros(bundle: FixtureBundle());

    // The deuterocanon is outside the Aquifer set; the app falls back to its
    // own short notes there.
    expect(await intros.forBook('TOB'), isNull);
  });

  test('reads the asset once, however many books are asked for', () async {
    final bundle = FixtureBundle();
    final intros = BookIntros(bundle: bundle);

    await Future.wait([
      intros.forBook('GEN'),
      intros.forBook('PSA'),
      intros.forBook('GEN'),
    ]);

    expect(bundle.loaded.where((key) => key == BookIntros.assetPath).length, 1);
  });

  test('nothing is loaded until a book is asked for', () async {
    final bundle = FixtureBundle();
    final intros = BookIntros(bundle: bundle);

    expect(intros.loaded('GEN'), isNull);
    expect(bundle.loaded, isEmpty);

    await intros.forBook('GEN');
    expect(intros.loaded('GEN'), isNotNull);
  });

  test('a missing or unreadable asset is not fatal', () async {
    final missing = BookIntros(bundle: FixtureBundle(assets: const {}));
    expect(await missing.forBook('GEN'), isNull);

    final rubbish = BookIntros(
      bundle: FixtureBundle(
        assets: {
          BookIntros.assetPath: Uint8List.fromList(
            gzip.encode(utf8.encode('["not a map"]')),
          ),
        },
      ),
    );
    expect(await rubbish.forBook('GEN'), isNull);
  });
}
