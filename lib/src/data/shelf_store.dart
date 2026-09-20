import 'dart:typed_data';

import 'shelf_store_stub.dart'
    if (dart.library.io) 'shelf_store_io.dart'
    as platform;

/// One file on the shelf, as the filesystem describes it.
class ShelfFile {
  const ShelfFile({
    required this.path,
    required this.head,
    required this.size,
    required this.modified,
  });

  final String path;

  /// The first bytes of the file — enough for a `.bib` header, no more.
  final Uint8List head;

  final int size;
  final DateTime modified;
}

/// The little the shelf needs of a filesystem.
///
/// Pulling it out of [Shelf] keeps `dart:io` out of the widget tree, so the
/// app still compiles for the web — where there is no shelf, and [at]
/// answers null.
abstract class ShelfStore {
  /// Opens the directory the shelf keeps its files in, or null where the
  /// platform has no filesystem.
  static ShelfStore? at(String directory) => platform.openShelfStore(directory);

  /// Files ending in [extension], each with its first [headLength] bytes.
  Future<List<ShelfFile>> list({
    required String extension,
    required int headLength,
  });

  Future<Uint8List> read(String path);

  /// Writes [bytes] as [name] in the shelf's directory and answers its path.
  Future<String> write(String name, Uint8List bytes);

  Future<void> delete(String path);

  Future<void> copy(String path, String destination);
}
