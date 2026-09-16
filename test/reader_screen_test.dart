import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/app_scope.dart';
import 'package:openword/src/data/bookmarks.dart';
import 'package:openword/src/data/library.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/model/bible.dart';
import 'package:openword/src/ui/reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// The book / chapter buttons live in the app bar; verse numbers in the text
/// carry the same digits, so the finders are scoped.
Finder appBarText(String label) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(label));

Future<ReadingStore> pumpReader(
  WidgetTester tester, {
  Reference? resume,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    ...prefs,
    if (resume != null) 'lastPosition': resume.encode(),
  });
  final settings = await Settings.load();
  final reading = await ReadingStore.load();
  final library = LibraryController.withBible(parseFixture());
  await tester.pumpWidget(
    AppScope(
      settings: settings,
      library: library,
      reading: reading,
      child: const MaterialApp(home: ReaderScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return reading;
}

void main() {
  testWidgets('opens at Genesis 1 on a fresh install', (tester) async {
    await pumpReader(tester);
    expect(appBarText('Genesis'), findsOneWidget);
    expect(
      find.textContaining('In the beginning', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('resumes where the reader left off', (tester) async {
    await pumpReader(tester, resume: const Reference('PSA', 1, 2));
    expect(appBarText('Psalms'), findsOneWidget);
    expect(
      find.textContaining('Blessed is the man', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('lays poetry out line by line with its indents', (tester) async {
    await pumpReader(tester, resume: const Reference('PSA', 1));
    // The section heading and psalm title are plain text, not verses.
    expect(find.text('BOOK 1'), findsOneWidget);
    expect(find.text('A Psalm by David.'), findsOneWidget);
    final indents = tester
        .widgetList<Padding>(find.byType(Padding))
        .map((padding) => padding.padding.resolve(TextDirection.ltr).left)
        .where((left) => left > 0 && left < 60)
        .toSet();
    // Level 1 poetry sits at 8, level 2 one 18pt step further in.
    expect(indents.contains(8.0), isTrue);
    expect(indents.contains(26.0), isTrue);
  });

  testWidgets('the chapter chip navigates within a book', (tester) async {
    await pumpReader(tester);
    await tester.tap(appBarText('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The second chapter', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('the book chip opens the A–Z picker and jumps', (tester) async {
    await pumpReader(tester);
    await tester.tap(appBarText('Genesis'));
    await tester.pumpAndSettle();
    // The full alphabet is on the rail, even for letters with no books.
    expect(find.text('X'), findsOneWidget);
    expect(find.text('M'), findsWidgets);

    await tester.tap(find.text('Matthew').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Follow me', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('saves the position when the chapter changes', (tester) async {
    final reading = await pumpReader(tester);
    await tester.tap(appBarText('1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    expect(reading.lastPosition?.bookCode, 'GEN');
    expect(reading.lastPosition?.chapter, 2);
    expect(reading.history.first.label, 'Genesis 2');
  });
}
