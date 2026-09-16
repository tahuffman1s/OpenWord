import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openword/src/data/bible_cache.dart';
import 'package:openword/src/data/bible_source.dart';
import 'package:openword/src/data/library.dart';

import 'fixtures.dart';

/// Stands in for the on-disk cache.
class _MemoryCache implements BibleCache {
  final Map<String, String> entries = {};

  @override
  bool get isPersistent => true;

  @override
  Future<bool> exists(String id) async => entries.containsKey(id);

  @override
  Future<String?> read(String id) async => entries[id];

  @override
  Future<void> write(String id, String json) async => entries[id] = json;

  @override
  Future<void> delete(String id) async => entries.remove(id);
}

void main() {
  final source = BibleSource.worldEnglishBible;

  test('a first launch asks for a download', () async {
    final controller = LibraryController(
      cache: _MemoryCache(),
      client: MockClient((_) async => http.Response('', 500)),
    );
    await controller.initialize(source.id);
    expect(controller.status, LibraryStatus.needsDownload);
    expect(controller.isReady, isFalse);
  });

  test('downloads, parses and caches the text', () async {
    final cache = _MemoryCache();
    var requests = 0;
    final controller = LibraryController(
      cache: cache,
      client: MockClient((request) async {
        requests++;
        expect(request.url.toString(), source.mirrors.first);
        return http.Response(usfxFixture, 200);
      }),
    );

    await controller.initialize(source.id);
    await controller.download(source);

    expect(controller.status, LibraryStatus.ready);
    expect(controller.progress, 1);
    expect(requests, 1);
    expect(controller.bible!.bookByCode('GEN')!.chapterCount, 2);
    expect(cache.entries.keys, [source.id]);
  });

  test('a second launch reads the cache instead of the network', () async {
    final cache = _MemoryCache();
    final first = LibraryController(
      cache: cache,
      client: MockClient((_) async => http.Response(usfxFixture, 200)),
    );
    await first.download(source);

    final second = LibraryController(
      cache: cache,
      client: MockClient((_) async => fail('should not hit the network')),
    );
    await second.initialize(source.id);
    expect(second.status, LibraryStatus.ready);
    expect(second.bible!.books.length, 3);
  });

  test('falls through to the next mirror, then reports failure', () async {
    final attempts = <String>[];
    final controller = LibraryController(
      cache: _MemoryCache(),
      client: MockClient((request) async {
        attempts.add(request.url.host);
        return http.Response('nope', 404);
      }),
    );
    await controller.download(source);
    expect(attempts.length, source.mirrors.length);
    expect(controller.status, LibraryStatus.failed);
    expect(controller.errorMessage, isNotNull);
  });

  test('deleting the download returns to the first-launch state', () async {
    final cache = _MemoryCache();
    final controller = LibraryController(
      cache: cache,
      client: MockClient((_) async => http.Response(usfxFixture, 200)),
    );
    await controller.download(source);
    expect(controller.isReady, isTrue);

    await controller.deleteDownload();
    expect(controller.status, LibraryStatus.needsDownload);
    expect(controller.bible, isNull);
    expect(cache.entries, isEmpty);
  });
}
