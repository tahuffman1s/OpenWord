/// Web build: there is no durable multi-megabyte store available through the
/// packages this app depends on, so the text is fetched each session and the
/// browser's HTTP cache does the heavy lifting.
class BibleCache {
  const BibleCache();

  bool get isPersistent => false;

  Future<bool> exists(String id) async => false;

  Future<String?> read(String id) async => null;

  Future<void> write(String id, String json) async {}

  Future<void> delete(String id) async {}
}
