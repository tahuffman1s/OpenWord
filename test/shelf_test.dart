import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/library.dart';
import 'package:openword/src/data/shelf.dart';
import 'package:openword/src/data/translations.dart';
import 'package:openword/src/model/bib_file.dart';

import 'epub_import_test.dart' show epub;
import 'fixtures.dart';

void main() {
  late Directory directory;
  late Shelf shelf;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('openword-shelf');
    shelf = Shelf.at(directory.path)!;
    await shelf.refresh();
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Uint8List someEpub({String title = 'Test Standard Version'}) => epub(
    title: title,
    documents: [
      (
        'gen.xhtml',
        '<h1>Genesis</h1><h2>1</h2>'
            '<p><sup>1</sup>In the beginning God created.</p>'
            '<p><sup>2</sup>The earth was formless.</p>',
      ),
    ],
  );

  test('an empty directory is an empty shelf', () {
    expect(shelf.isEmpty, isTrue);
    expect(shelf.loaded, isTrue);
    expect(shelf.has('anything'), isFalse);
  });

  test('an EPUB is converted and kept as a .bib', () async {
    final result = await shelf.add(someEpub(), fileName: 'tsv.epub');

    expect(result.ok, isTrue);
    expect(result.failure, isNull);
    final id = result.bible!.translation.id;
    expect(shelf.has(id), isTrue);

    final file = File(shelf.byId(id)!.path);
    expect(file.path, endsWith('.bib'));
    expect(BibFile.looksLikeBib(await file.readAsBytes()), isTrue);
    expect(shelf.byId(id)!.bytes, file.statSync().size);
    expect(shelf.byId(id)!.readableSize, isNotEmpty);
  });

  test('what was written reads back as the same Scripture', () async {
    final result = await shelf.add(someEpub(), fileName: 'tsv.epub');
    final read = await shelf.read(result.bible!.translation.id);

    expect(read.books.single.code, 'GEN');
    expect(
      read.books.single.chapter(1)!.verseText(2),
      'The earth was formless.',
    );
    expect(read.translation.name, 'Test Standard Version');
  });

  test('a .bib is taken as it is, without conversion', () async {
    final bytes = BibFile.encode(parseFixture());

    final result = await shelf.add(bytes, fileName: 'test.bib');

    expect(result.ok, isTrue);
    expect(result.warnings, isEmpty);
    expect(shelf.byId(testTranslation.id), isNotNull);
    // Copied byte for byte rather than re-encoded.
    expect(
      await File(shelf.byId(testTranslation.id)!.path).readAsBytes(),
      bytes,
    );
  });

  test('a new shelf finds what an earlier one left', () async {
    await shelf.add(BibFile.encode(parseFixture()), fileName: 'test.bib');

    final reopened = Shelf.at(directory.path)!;
    await reopened.refresh();

    expect(reopened.translations.single.info.abbreviation, 'TST');
    expect(reopened.translations.single.info.name, testTranslation.name);
  });

  test('the shelf is listed by name', () async {
    await shelf.add(someEpub(title: 'Zebra Version'), fileName: 'z.epub');
    await shelf.add(someEpub(title: 'Alpha Version'), fileName: 'a.epub');

    expect(shelf.translations.map((shelved) => shelved.info.name), [
      'Alpha Version',
      'Zebra Version',
    ]);
  });

  test('importing the same file twice keeps one copy', () async {
    await shelf.add(someEpub(), fileName: 'tsv.epub');
    await shelf.add(someEpub(), fileName: 'tsv-again.epub');

    expect(shelf.translations, hasLength(1));
  });

  test('removing takes the file with it', () async {
    final result = await shelf.add(someEpub(), fileName: 'tsv.epub');
    final id = result.bible!.translation.id;
    final path = shelf.byId(id)!.path;

    await shelf.remove(id);

    expect(shelf.has(id), isFalse);
    expect(File(path).existsSync(), isFalse);
    // Removing what is not there is not an error.
    await shelf.remove(id);
  });

  test('a copy can be kept somewhere else', () async {
    final result = await shelf.add(someEpub(), fileName: 'tsv.epub');
    final id = result.bible!.translation.id;
    final destination = '${directory.path}/backup.bib';

    await shelf.copyTo(id, destination);

    expect(
      BibFile.decode(File(destination).readAsBytesSync()).books,
      hasLength(1),
    );
    expect(await shelf.fileBytes(id), File(destination).readAsBytesSync());
    expect(await shelf.fileBytes('nope'), isNull);
  });

  test('a file that is neither is refused with a reason', () async {
    final result = await shelf.add(
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      fileName: 'notes.txt',
    );

    expect(result.ok, isFalse);
    expect(result.failure, contains('not an EPUB'));
    expect(shelf.isEmpty, isTrue);
  });

  test('a .bib of a version this app cannot read is refused', () async {
    final bytes = BibFile.encode(parseFixture());
    bytes[3] = BibFile.version + 1;

    final result = await shelf.add(bytes, fileName: 'future.bib');

    expect(result.ok, isFalse);
    expect(result.failure, contains('version'));
    expect(shelf.isEmpty, isTrue);
  });

  test('a stray file in the directory is passed over, not fatal', () async {
    await shelf.add(someEpub(), fileName: 'tsv.epub');
    File('${directory.path}/rubbish.bib').writeAsStringSync('not scripture');
    File('${directory.path}/notes.txt').writeAsStringSync('nor this');

    await shelf.refresh();

    expect(shelf.translations, hasLength(1));
  });

  test('reading a translation that is not there says so', () {
    expect(shelf.read('nope'), throwsA(isA<BibFormatException>()));
  });

  group('reading a big file off the UI thread', () {
    // Only bytes come back from the isolate. A Bible read from a .bib file
    // keeps a closure for unpacking each book on demand, and no isolate can
    // send a closure to another — so what crosses is the file, and the
    // caller opens it on its own side.
    test('the file crosses the isolate boundary, and reopens', () async {
      final imported = await compute(importFile, (
        BibFile.encode(parseFixture()),
        'test.bib',
      ));

      expect(imported.failure, isNull);
      expect(imported.bytes, isNotNull);

      final bible = BibFile.decode(imported.bytes!);
      expect(bible.books, hasLength(3));
      expect(bible.verseCount, parseFixture().verseCount);
      expect(
        bible.bookByCode('GEN')!.chapter(1)!.verseText(1),
        'In the beginning, God created the heavens.',
      );
    });

    test('an EPUB comes back converted, with its warnings', () async {
      final imported = await compute(importFile, (someEpub(), 'tsv.epub'));

      expect(BibFile.decode(imported.bytes!).books.single.code, 'GEN');
    });

    test('a refusal comes back as a reason, not an exception', () async {
      final imported = await compute(importFile, (
        Uint8List.fromList([1, 2, 3, 4]),
        'notes.txt',
      ));

      expect(imported.bytes, isNull);
      expect(imported.failure, contains('not an EPUB'));
    });

    test(
      'a damaged .bib is caught on the way in, not on the way out',
      () async {
        final bytes = BibFile.encode(parseFixture());
        bytes[bytes.length - 30] ^= 0x01;

        final imported = await compute(importFile, (bytes, 'broken.bib'));

        expect(imported.bytes, isNull);
        expect(imported.failure, isNotNull);
      },
    );
  });

  group('the library reads the shelf like anything else', () {
    test('an imported translation can be loaded and compared', () async {
      final bundle = FixtureBundle();
      final library = LibraryController(bundle: bundle, shelf: shelf);
      final result = await shelf.add(someEpub(), fileName: 'tsv.epub');
      final id = result.bible!.translation.id;

      expect(library.knows(id), isTrue);
      expect(library.isImported(id), isTrue);
      expect(library.infoFor(id).name, 'Test Standard Version');
      expect(
        library.available.map((translation) => translation.id),
        containsAll([Translations.fallback.id, id]),
      );

      await library.load(id);
      expect(library.isReady, isTrue);
      expect(library.bible!.books.single.code, 'GEN');
      // Nothing was asked of the asset bundle: the text came off the shelf.
      expect(bundle.loaded, isEmpty);

      await library.loadComparison(testTranslation.id);
      expect(library.comparison!.translation.abbreviation, 'TST');
    });

    test('a library with no shelf is unchanged', () async {
      final library = LibraryController(bundle: FixtureBundle());

      expect(library.shelf, isNull);
      expect(library.isImported('whatever'), isFalse);
      expect(library.available, Translations.all);
    });
  });
}
