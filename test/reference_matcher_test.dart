import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/reference_search.dart';
import 'package:openword/src/model/bible.dart';

import 'fixtures.dart';

void main() {
  final matcher = ReferenceMatcher(parseFixture().books);

  List<Reference> refs(String text) =>
      matcher.findAll(text).map((match) => match.reference).toList();

  test('finds a citation inside a footnote', () {
    expect(refs('Cited in Genesis 1:3 and elsewhere'), [
      const Reference('GEN', 1, 3),
    ]);
  });

  test('finds several in one line, as a parallel-passage note has', () {
    expect(refs('(Genesis 1:1–5; Psalms 1:2; Matthew 1)'), [
      const Reference('GEN', 1, 1),
      const Reference('PSA', 1, 2),
      const Reference('MAT', 1),
    ]);
  });

  test('reports where each one sits so it can be tapped', () {
    final match = matcher.findAll('see Genesis 2:1 now').single;
    expect(match.start, 4);
    expect(match.end, 15);
  });

  test('accepts abbreviations and a full stop between numbers', () {
    expect(refs('Gen 1:1'), [const Reference('GEN', 1, 1)]);
    expect(refs('Gen. 1.2'), [const Reference('GEN', 1, 2)]);
    expect(refs('PSA 1'), [const Reference('PSA', 1)]);
  });

  test('leaves ordinary prose alone', () {
    expect(refs('He went up onto the mountain and sat down.'), isEmpty);
    // A book name with no number is not a citation.
    expect(refs('The book of Genesis tells of creation.'), isEmpty);
    // Nor is a number with no book.
    expect(refs('about 300 years'), isEmpty);
  });

  test('does not match a book name inside a longer word', () {
    expect(refs('Genesisx 1:1'), isEmpty);
    expect(refs('regenesis 2'), isEmpty);
  });

  test('ignores chapters and verses the book does not have', () {
    // Genesis has two chapters in the fixture.
    expect(refs('Genesis 40:2'), isEmpty);
    // An over-long verse is clamped rather than dropped.
    expect(refs('Genesis 1:99'), [const Reference('GEN', 1, 5)]);
  });
}
