import 'package:flutter/foundation.dart';

import '../model/bib_file.dart';
import '../model/bible.dart';
import 'epub_import.dart';
import 'shelf_store.dart';

/// A translation the reader brought themselves, as it sits on the shelf.
@immutable
class ShelvedTranslation {
  const ShelvedTranslation({
    required this.info,
    required this.path,
    required this.bytes,
    required this.added,
  });

  final TranslationInfo info;

  /// Where the `.bib` file is.
  final String path;

  /// How big the file is, for the reader deciding what to keep.
  final int bytes;

  final DateTime added;

  String get readableSize {
    const mb = 1024 * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} kB';
  }
}

/// The translations the reader has imported.
///
/// Each one is a `.bib` file in a directory of its own; the shelf is whatever
/// is in that directory. There is no database and no index file to fall out
/// of step: a `.bib` says what it holds in its own header, so listing the
/// shelf is reading a few dozen bytes of each file.
class Shelf extends ChangeNotifier {
  Shelf({required this.store});

  /// Opens the shelf kept in [directory], or answers null on a platform with
  /// no filesystem — the web, where translations cannot be kept at all.
  static Shelf? at(String directory) {
    final store = ShelfStore.at(directory);
    return store == null ? null : Shelf(store: store);
  }

  /// Where the `.bib` files live. The app passes a directory inside its own
  /// documents; tests pass a temporary one.
  final ShelfStore store;

  List<ShelvedTranslation> _translations = const [];
  bool _loaded = false;

  List<ShelvedTranslation> get translations => _translations;
  bool get isEmpty => _translations.isEmpty;
  bool get loaded => _loaded;

  /// Reads the directory. Cheap: only the header of each file.
  Future<void> refresh() async {
    final found = <ShelvedTranslation>[];
    try {
      final files = await store.list(
        extension: BibFile.extension,
        // The header is a few bytes plus the metadata it declares.
        headLength: BibFile.maxHeaderLength,
      );
      for (final file in files) {
        final shelved = _describe(file);
        if (shelved != null) found.add(shelved);
      }
    } on Object catch (error) {
      debugPrint('OpenWord: could not read the shelf: $error');
    }

    found.sort(
      (a, b) => a.info.name.toLowerCase().compareTo(b.info.name.toLowerCase()),
    );
    _translations = List.unmodifiable(found);
    _loaded = true;
    notifyListeners();
  }

  ShelvedTranslation? byId(String id) {
    for (final translation in _translations) {
      if (translation.info.id == id) return translation;
    }
    return null;
  }

  bool has(String id) => byId(id) != null;

  /// Reads one of the shelved translations in full.
  Future<Bible> read(String id) async {
    final shelved = byId(id);
    if (shelved == null) {
      throw BibFormatException('$id is not on the shelf');
    }
    return BibFile.decode(await store.read(shelved.path));
  }

  /// A file this big is read on an isolate of its own. Below it the work is
  /// a few milliseconds, and staying put keeps widget tests — whose clock is
  /// a fake one — from waiting on an isolate that never reports back.
  static const int isolateAbove = 128 * 1024;

  /// Takes a file the reader chose — a `.bib` or an EPUB — and puts a `.bib`
  /// on the shelf. The EPUB is converted; a `.bib` is checked and copied.
  Future<ShelfResult> add(Uint8List bytes, {required String fileName}) async {
    final request = (bytes, fileName);
    final imported = bytes.length >= isolateAbove
        ? await compute(importFile, request)
        : importFile(request);

    final bible = imported.bible;
    if (bible == null) {
      return ShelfResult.failed(
        imported.failure ?? 'That file cannot be read.',
      );
    }

    try {
      await store.write(_fileName(bible.translation.id), imported.bytes!);
    } on Object catch (error) {
      return ShelfResult.failed('That translation could not be kept: $error');
    }
    await refresh();
    return ShelfResult(
      translation: byId(bible.translation.id),
      bible: bible,
      warnings: imported.warnings,
    );
  }

  /// The `.bib` file itself, for handing to a file picker or a share sheet.
  Future<Uint8List?> fileBytes(String id) async {
    final shelved = byId(id);
    if (shelved == null) return null;
    return store.read(shelved.path);
  }

  /// Writes a copy of a shelved translation somewhere else — sharing it, or
  /// keeping it where a backup will find it.
  Future<void> copyTo(String id, String path) async {
    final shelved = byId(id);
    if (shelved == null) return;
    await store.copy(shelved.path, path);
  }

  Future<void> remove(String id) async {
    final shelved = byId(id);
    if (shelved == null) return;
    try {
      await store.delete(shelved.path);
    } on Object catch (error) {
      debugPrint('OpenWord: could not remove $id: $error');
    }
    await refresh();
  }

  ShelvedTranslation? _describe(ShelfFile file) {
    try {
      return ShelvedTranslation(
        info: BibFile.readInfo(file.head),
        path: file.path,
        bytes: file.size,
        added: file.modified,
      );
    } on Object catch (error) {
      debugPrint('OpenWord: ${file.path} is not a readable .bib: $error');
      return null;
    }
  }

  static String _fileName(String id) {
    final safe = id.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
    return '$safe${BibFile.extension}';
  }
}

/// A translation read off a file, with the `.bib` bytes to write for it.
///
/// [importFile] does the reading and the encoding together so that both can
/// happen on one isolate; this is what comes back from it.
@immutable
class ImportedBible {
  const ImportedBible({
    this.bible,
    this.bytes,
    this.warnings = const [],
    this.failure,
  });

  final Bible? bible;
  final Uint8List? bytes;
  final List<String> warnings;
  final String? failure;
}

/// Reads a file the reader chose and encodes what it holds.
///
/// Top-level, and doing both halves of the work, because a whole Bible takes
/// long enough at either to drop a second of frames: [Shelf.add] hands this
/// to [compute] for anything but a small file.
ImportedBible importFile((Uint8List, String) request) {
  final (bytes, fileName) = request;
  try {
    if (BibFile.looksLikeBib(bytes)) {
      // Already in the app's own format: check it reads, then keep the file
      // byte for byte rather than encoding it afresh.
      return ImportedBible(bible: BibFile.decode(bytes), bytes: bytes);
    }

    final result = EpubImport.convert(bytes, fileName: fileName);
    final bible = result.bible;
    if (bible == null) {
      return ImportedBible(
        failure: result.failure ?? 'That file cannot be read.',
        warnings: result.warnings,
      );
    }
    return ImportedBible(
      bible: bible,
      bytes: BibFile.encode(bible),
      warnings: result.warnings,
    );
  } on BibFormatException catch (error) {
    return ImportedBible(failure: error.message);
  } on Object catch (error) {
    return ImportedBible(failure: 'That file could not be read: $error');
  }
}

/// What came of putting a file on the shelf.
class ShelfResult {
  const ShelfResult({
    this.translation,
    this.bible,
    this.warnings = const [],
    this.failure,
  });

  const ShelfResult.failed(String reason) : this(failure: reason);

  final ShelvedTranslation? translation;

  /// The Bible that was read, so the app can start reading it at once rather
  /// than going back to the file it has just written.
  final Bible? bible;

  /// What the conversion had to leave out, if anything.
  final List<String> warnings;

  /// Null when it worked.
  final String? failure;

  bool get ok => bible != null;
}
