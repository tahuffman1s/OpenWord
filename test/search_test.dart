import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/ui/search_screen.dart';

import 'fixtures.dart';

void main() {
  final bible = parseFixture();

  test('finds verses regardless of case', () {
    final hits = searchBible(bible, 'god');
    expect(hits.map((hit) => hit.reference.label), [
      'Genesis 1:1',
      'Genesis 1:3',
    ]);
    expect(hits.first.text, startsWith('In the beginning'));
  });

  test('ignores queries shorter than two letters', () {
    expect(searchBible(bible, 'a'), isEmpty);
    expect(searchBible(bible, ' '), isEmpty);
  });

  test('reports where the match is, for highlighting', () {
    final hit = searchBible(bible, 'beginning').single;
    expect(hit.text.substring(hit.matchStart, hit.matchEnd), 'beginning');
  });

  test('whole-word search does not match inside a word', () {
    // "light" is also inside "delight" in Psalm 1:2.
    expect(searchBible(bible, 'light').length, 2);
    expect(
      searchBible(bible, 'light', wholeWord: true).single.reference.label,
      'Genesis 1:3',
    );
    expect(searchBible(bible, 'ligh').length, 2);
    expect(searchBible(bible, 'ligh', wholeWord: true), isEmpty);
  });

  test('scopes to a testament or a single book', () {
    expect(searchBible(bible, 'he', scope: SearchScope.all), isNotEmpty);
    expect(
      searchBible(bible, 'follow', scope: SearchScope.oldTestament),
      isEmpty,
    );
    expect(
      searchBible(
        bible,
        'follow',
        scope: SearchScope.newTestament,
      ).single.reference.bookCode,
      'MAT',
    );
    expect(
      searchBible(
        bible,
        'god',
        scope: SearchScope.currentBook,
        currentBookCode: 'PSA',
      ),
      isEmpty,
    );
    expect(
      searchBible(
        bible,
        'god',
        scope: SearchScope.currentBook,
        currentBookCode: 'GEN',
      ).length,
      2,
    );
  });

  test('searches the plain text, not the inline markers', () {
    // "Follow me." is wrapped in words-of-Jesus markers in the source.
    expect(
      searchBible(bible, 'Follow me').single.reference.label,
      'Matthew 1:1',
    );
    expect(
      searchBible(bible, 'formless and empty').single.reference.label,
      'Genesis 1:2',
    );
  });

  test('stops at the limit', () {
    expect(searchBible(bible, 'the', limit: 2).length, 2);
  });
}
