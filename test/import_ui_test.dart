import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/app_scope.dart';
import 'package:openword/src/data/library.dart';
import 'package:openword/src/data/marks.dart';
import 'package:openword/src/data/settings.dart';
import 'package:openword/src/data/shelf.dart';
import 'package:openword/src/data/updates.dart';
import 'package:openword/src/model/bib_file.dart';
import 'package:openword/src/ui/reader_screen.dart';
import 'package:openword/src/ui/settings_screen.dart';
import 'package:openword/src/ui/widgets/scripture_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'epub_import_test.dart' show epub;
import 'fixtures.dart';

/// Anything that touches the disk has to run on the real event loop: a
/// widget test's clock is a fake one, and a file read would never complete
/// under it.
Future<T> onDisk<T>(WidgetTester tester, Future<T> Function() work) async {
  final result = await tester.runAsync(work);
  return result as T;
}

/// Lets the work a button started on the disk finish before looking at what
/// it did.
Future<void> settleDisk(WidgetTester tester) async {
  // The work alternates between the two clocks — the read happens on the
  // real one, what it feeds happens on the test's — so both are given a few
  // turns.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

/// An EPUB with enough in it to read, search and bookmark.
final _epub = epub(
  title: 'Imported Version',
  documents: [
    (
      'gen.xhtml',
      '<h1>Genesis</h1><h2>1</h2>'
          '<p><sup>1</sup>In the beginning God created the heavens.</p>'
          '<p><sup>2</sup>The earth was waste and void.</p>',
    ),
  ],
);

void main() {
  late Directory directory;
  late Shelf shelf;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('openword-import');
    shelf = Shelf.at(directory.path)!;
    await shelf.refresh();
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<(Settings, LibraryController)> pumpSettings(
    WidgetTester tester, {
    Shelf? withShelf,
  }) async {
    // Settings is a long list; a tall window puts the translation section on
    // screen, where a finder can reach it.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final settings = await Settings.load();
    final reading = await ReadingStore.load();
    final library = LibraryController(
      bundle: FixtureBundle(),
      shelf: withShelf,
    );
    await onDisk(tester, () => library.load(testTranslation.id));

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        library: library,
        reading: reading,
        updates: UpdateService(
          settings: settings,
          backend: FakeUpdateBackend(isSupported: false),
          currentVersion: '1.0.0',
        ),
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (settings, library);
  }

  /// The translation picker, as opposed to the credits further down, which
  /// name every translation a second time.
  Finder pickerText(String label) => find.descendant(
    of: find.byType(RadioListTile<String>),
    matching: find.text(label),
  );

  testWidgets('an imported translation is listed beside the bundled ones', (
    tester,
  ) async {
    await onDisk(tester, () => shelf.add(_epub, fileName: 'imported.epub'));
    final (settings, library) = await pumpSettings(tester, withShelf: shelf);

    expect(find.text('Add a translation'), findsOneWidget);
    // Once to choose it, once again where the credits are: a translation
    // the reader brought is attributed like everything else.
    expect(find.text('Imported Version'), findsNWidgets(2));
    expect(pickerText('Imported Version'), findsOneWidget);
    // Imported ones carry the box that offers to remove them; everything
    // can be saved out, so everything has a menu.
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);

    await tester.tap(pickerText('Imported Version'));
    await settleDisk(tester);

    final id = shelf.translations.single.info.id;
    expect(settings.translationId, id);
    expect(library.bible!.translation.name, 'Imported Version');
  });

  testWidgets('a bundled translation can be saved out, but not removed', (
    tester,
  ) async {
    await pumpSettings(tester);

    // Every translation carries a menu, because every one can be handed to
    // another reader as a .bib.
    final menus = find.byType(PopupMenuButton<String>);
    expect(menus, findsNWidgets(3));

    await tester.tap(menus.first);
    await tester.pumpAndSettle();

    expect(find.text('Save a copy…'), findsOneWidget);
    // And one that carries the app's cross-references inside it, so the
    // file stands on its own wherever it is opened.
    expect(find.text('Save a copy with cross-references…'), findsOneWidget);
    // This one numbers its verses the English way, so there is nothing to
    // overrule and nothing offering to.
    expect(find.text('Cross-references and originals anyway'), findsNothing);
    // Nothing on the shelf to take off it.
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('with nowhere to keep files there is nothing to import', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text('Add a translation'), findsNothing);
    expect(find.byIcon(Icons.inventory_2_outlined), findsNothing);
  });

  testWidgets('removing the translation being read falls back', (tester) async {
    await onDisk(tester, () => shelf.add(_epub, fileName: 'imported.epub'));
    final id = shelf.translations.single.info.id;
    final (settings, library) = await pumpSettings(tester, withShelf: shelf);

    await tester.tap(pickerText('Imported Version'));
    await settleDisk(tester);
    expect(settings.translationId, id);

    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await settleDisk(tester);

    expect(shelf.isEmpty, isTrue);
    expect(settings.translationId, testTranslation.id);
    expect(library.bible!.translation.abbreviation, 'TST');
    expect(find.text('Imported Version'), findsNothing);
  });

  testWidgets('an imported translation reads like any other', (tester) async {
    final result = await onDisk(
      tester,
      () => shelf.add(_epub, fileName: 'imported.epub'),
    );
    final id = result.bible!.translation.id;

    SharedPreferences.setMockInitialValues(const {});
    final settings = await Settings.load();
    final reading = await ReadingStore.load();
    final library = LibraryController(bundle: FixtureBundle(), shelf: shelf);
    await onDisk(tester, () => library.load(id));

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        library: library,
        reading: reading,
        updates: UpdateService(
          settings: settings,
          backend: FakeUpdateBackend(isSupported: false),
          currentVersion: '1.0.0',
        ),
        child: const MaterialApp(home: ReaderScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Genesis 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('In the beginning', findRichText: true),
      findsOneWidget,
    );

    // Search runs over the imported text too.
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'waste');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('1 verse in 1 book'), findsOneWidget);
    expect(find.text('1:2'), findsOneWidget);
    expect(find.textContaining('waste', findRichText: true), findsWidgets);
  });

  testWidgets('an imported translation gets the bundled study layers', (
    tester,
  ) async {
    // The cross-references and the original languages are keyed to the
    // verse, not to an edition's wording, so a translation the reader
    // brought gets them the same as the three that ship.
    final result = await onDisk(
      tester,
      () => shelf.add(_epub, fileName: 'imported.epub'),
    );
    final id = result.translation!.info.id;

    SharedPreferences.setMockInitialValues(const {});
    final settings = await Settings.load();
    final reading = await ReadingStore.load();
    final library = LibraryController(bundle: FixtureBundle(), shelf: shelf);
    await onDisk(tester, () => library.load(id));

    await tester.pumpWidget(
      AppScope(
        settings: settings,
        library: library,
        reading: reading,
        updates: UpdateService(
          settings: settings,
          backend: FakeUpdateBackend(isSupported: false),
          currentVersion: '1.0.0',
        ),
        child: const MaterialApp(home: ReaderScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Genesis 1:1 of the imported text.
    await tester.tap(
      find
          .descendant(of: find.byType(ScriptureBlock), matching: find.text('1'))
          .first,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('2 cross-references'),
      findsOneWidget,
      reason: 'the bundled cross-references are keyed to the verse',
    );
    expect(
      find.text('Hebrew'),
      findsOneWidget,
      reason: 'so is the original-language layer',
    );

    await tester.tap(find.text('2 cross-references'));
    await tester.pumpAndSettle();

    // And the passages they point at are quoted in the imported wording,
    // not in a bundled translation's.
    expect(find.text('Psalms 1:1'), findsOneWidget);
    expect(find.text('Matthew 1:1'), findsOneWidget);
  });

  testWidgets('a .bib exported from the shelf imports again unchanged', (
    tester,
  ) async {
    await onDisk(tester, () => shelf.add(_epub, fileName: 'imported.epub'));
    final id = shelf.translations.single.info.id;
    final bytes = (await onDisk(tester, () => shelf.fileBytes(id)))!;

    final elsewhere = Shelf.at('${directory.path}/other')!;
    final result = await onDisk(tester, () async {
      await elsewhere.refresh();
      return elsewhere.add(bytes, fileName: 'copy.bib');
    });

    expect(result.ok, isTrue);
    expect(BibFile.readInfo(bytes).id, id);
    expect(elsewhere.translations.single.info.name, 'Imported Version');
    expect(
      (await onDisk(tester, () => elsewhere.read(id))).books.single.code,
      'GEN',
    );
  });
}
