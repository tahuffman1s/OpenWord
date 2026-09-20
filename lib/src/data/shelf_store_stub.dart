import 'shelf_store.dart';

/// The web has no filesystem to keep translations on, so there is no shelf.
ShelfStore? openShelfStore(String directory) => null;
