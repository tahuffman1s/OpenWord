/// Platform-specific cache for the parsed Bible.
///
/// Native platforms store a gzipped JSON document in the application support
/// directory. The web build has no comparable durable store of this size, so
/// it re-downloads and relies on the browser's HTTP cache; the interface is
/// the same either way.
library;

export 'bible_cache_io.dart'
    if (dart.library.js_interop) 'bible_cache_web.dart';
