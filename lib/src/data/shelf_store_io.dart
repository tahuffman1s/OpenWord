import 'dart:io';
import 'dart:typed_data';

import 'shelf_store.dart';

ShelfStore? openShelfStore(String directory) => _Files(Directory(directory));

/// The shelf as a directory of files.
class _Files implements ShelfStore {
  _Files(this.directory);

  final Directory directory;

  @override
  Future<List<ShelfFile>> list({
    required String extension,
    required int headLength,
  }) async {
    if (!directory.existsSync()) return const [];
    final found = <ShelfFile>[];
    for (final entry in directory.listSync()) {
      if (entry is! File) continue;
      if (!entry.path.toLowerCase().endsWith(extension)) continue;
      final stat = entry.statSync();
      final handle = await entry.open();
      try {
        found.add(
          ShelfFile(
            path: entry.path,
            head: await handle.read(headLength),
            size: stat.size,
            modified: stat.modified,
          ),
        );
      } finally {
        await handle.close();
      }
    }
    return found;
  }

  @override
  Future<Uint8List> read(String path) => File(path).readAsBytes();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    directory.createSync(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> delete(String path) => File(path).delete();

  @override
  Future<void> copy(String path, String destination) async {
    await File(path).copy(destination);
  }
}
