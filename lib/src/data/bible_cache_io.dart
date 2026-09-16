import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Stores the parsed Bible as gzipped JSON next to the app's other data.
class BibleCache {
  const BibleCache();

  bool get isPersistent => true;

  Future<File> _file(String id) async {
    final directory = await getApplicationSupportDirectory();
    final bibles = Directory('${directory.path}/bibles');
    if (!bibles.existsSync()) {
      await bibles.create(recursive: true);
    }
    return File('${bibles.path}/$id.json.gz');
  }

  Future<bool> exists(String id) async => (await _file(id)).existsSync();

  Future<String?> read(String id) async {
    final file = await _file(id);
    if (!file.existsSync()) return null;
    try {
      final bytes = await file.readAsBytes();
      return utf8.decode(gzip.decode(bytes));
    } on Object {
      // A truncated or corrupt cache is not worth keeping.
      await file.delete();
      return null;
    }
  }

  Future<void> write(String id, String json) async {
    final file = await _file(id);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(gzip.encode(utf8.encode(json)), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> delete(String id) async {
    final file = await _file(id);
    if (file.existsSync()) await file.delete();
  }
}
