import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the places named in the text are, what is known about them, and
/// enough coastline, lake and river to recognise them by.
///
/// Read on demand and kept afterwards: it is only wanted when someone opens
/// the map for a chapter.
class Atlas {
  Atlas({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetName = 'atlas.json.gz';
  static const String assetPath = 'assets/maps/$assetName';

  /// Shown on the map and in Settings, as both licences require.
  static const String attribution =
      'Place locations from OpenBible.info Bible Geocoding, CC BY 4.0. Base '
      'map from Natural Earth, public domain.';

  /// Assets smaller than this are decoded where they are.
  static const int isolateAbove = 64 * 1024;

  final AssetBundle _bundle;
  AtlasData? _data;
  Future<AtlasData>? _loading;

  AtlasData? get data => _data;

  Future<AtlasData> load() {
    final loaded = _data;
    if (loaded != null) return Future.value(loaded);
    return _loading ??= _read().then((data) {
      _data = data;
      return data;
    });
  }

  Future<AtlasData> _read() async {
    try {
      final data = await _bundle.load(assetPath);
      final bytes = Uint8List.sublistView(data);
      // A megabyte and a half of JSON is too much to unpack on the thread
      // that is drawing, so the real asset goes to a worker — which on the
      // web is the same thread, but everywhere else is not. Anything small
      // enough to be a fixture is not worth starting an isolate for.
      if (bytes.length < isolateAbove) return decodeAtlas(bytes);
      return await compute(decodeAtlas, bytes);
    } on Object catch (error) {
      debugPrint('OpenWord: could not read the atlas: $error');
      return AtlasData.empty;
    }
  }
}

/// Unpacks the asset. Top-level, because it runs in another isolate.
AtlasData decodeAtlas(Uint8List bytes) {
  final raw = const GZipDecoder().decodeBytes(bytes);
  final decoded = jsonDecode(utf8.decode(raw));
  if (decoded is! Map) return AtlasData.empty;
  return AtlasData.fromJson(decoded);
}

/// A place named in the text, at the location its identification favours.
@immutable
class Place {
  const Place({
    required this.name,
    required this.types,
    required this.lon,
    required this.lat,
    required this.confidence,
    this.modern = '',
    this.otherNames = const [],
    this.comment = '',
    this.verseCount = 0,
  });

  final String name;

  /// settlement, region, mountain, river and so on, as the source classes it.
  final List<String> types;

  final double lon;
  final double lat;

  /// How sure the identification is, 0–1000 as the source scores it. Below
  /// [uncertain] the map says so rather than pretending.
  final int confidence;

  /// The modern place it is identified with, where the source names one.
  final String modern;

  /// What translations call it, where they differ from [name].
  final List<String> otherNames;

  /// The source's own note: what it is near, which of two places it is, and
  /// so on.
  final String comment;

  /// How many verses name it in the whole Bible.
  final int verseCount;

  static const int uncertain = 500;

  bool get isUncertain => confidence < uncertain;

  String get type => types.isEmpty ? 'place' : types.first;
}

/// A place as a chapter names it: which verses of that chapter mention it.
@immutable
class ChapterPlace {
  const ChapterPlace({required this.place, required this.verses});

  final Place place;

  /// Verse numbers within the chapter, in order.
  final List<int> verses;
}

/// A run of coastline, lake shore or river, with the box it lives in so that
/// the map can skip what is off screen without walking every point.
class GeoRun {
  GeoRun(this.points)
    : west = _min(points, 0),
      east = _max(points, 0),
      south = _min(points, 1),
      north = _max(points, 1);

  /// Longitude and latitude in turn: `[lon, lat, lon, lat, …]`.
  final Float32List points;

  final double west;
  final double east;
  final double south;
  final double north;

  bool intersects(double w, double s, double e, double n) =>
      west <= e && east >= w && south <= n && north >= s;

  static double _min(Float32List points, int offset) {
    var value = double.infinity;
    for (var i = offset; i < points.length; i += 2) {
      if (points[i] < value) value = points[i];
    }
    return value;
  }

  static double _max(Float32List points, int offset) {
    var value = double.negativeInfinity;
    for (var i = offset; i < points.length; i += 2) {
      if (points[i] > value) value = points[i];
    }
    return value;
  }
}

/// A town that is there now, drawn once the map is zoomed in far enough for
/// the ancient site to need somewhere to sit.
@immutable
class Town {
  const Town({
    required this.name,
    required this.lon,
    required this.lat,
    required this.rank,
  });

  final String name;
  final double lon;
  final double lat;

  /// Natural Earth's own ranking: 0 for a capital, higher for smaller places.
  final int rank;
}

/// One level of the base map: the shapes drawn at a given range of zoom.
class BaseMap {
  const BaseMap({
    required this.land,
    required this.lakes,
    required this.rivers,
  });

  static const BaseMap empty = BaseMap(land: [], lakes: [], rivers: []);

  final List<GeoRun> land;
  final List<GeoRun> lakes;
  final List<GeoRun> rivers;

  bool get isEmpty => land.isEmpty && lakes.isEmpty && rivers.isEmpty;
}

/// A rectangle of the world, in degrees.
@immutable
class GeoBox {
  const GeoBox(this.west, this.south, this.east, this.north);

  static const GeoBox empty = GeoBox(0, 0, 0, 0);

  final double west;
  final double south;
  final double east;
  final double north;

  double get width => east - west;
  double get height => north - south;
  double get centreLon => (west + east) / 2;
  double get centreLat => (south + north) / 2;

  bool contains(double lon, double lat) =>
      lon >= west && lon <= east && lat >= south && lat <= north;
}

class AtlasData {
  const AtlasData({
    required this.places,
    required this.chapters,
    required this.coarse,
    required this.fine,
    required this.urban,
    required this.towns,
    required this.bounds,
    required this.detail,
  });

  static const AtlasData empty = AtlasData(
    places: [],
    chapters: {},
    coarse: BaseMap.empty,
    fine: BaseMap.empty,
    urban: [],
    towns: [],
    bounds: GeoBox.empty,
    detail: GeoBox.empty,
  );

  final List<Place> places;

  /// `GEN 12` to the places that chapter names, with their verses.
  final Map<String, List<ChapterPlace>> chapters;

  /// The whole region, drawn when zoomed out.
  final BaseMap coarse;

  /// Ten times the detail over the ground the Bible actually covers, drawn
  /// once the reader zooms in past a country or two.
  final BaseMap fine;

  /// Where people live now, for the close-up view.
  final List<GeoRun> urban;

  /// The towns that are there now, biggest first.
  final List<Town> towns;

  /// Everything the coarse map covers, and so how far out the map can zoom.
  final GeoBox bounds;

  /// Where [fine] has anything to say.
  final GeoBox detail;

  bool get isEmpty => places.isEmpty;

  /// The places named in a chapter, with the verses naming them.
  List<ChapterPlace> inChapter(String bookCode, int chapter) =>
      chapters['${bookCode.toUpperCase()} $chapter'] ?? const [];

  /// Every place named anywhere in a book.
  List<Place> inBook(String bookCode) {
    final code = bookCode.toUpperCase();
    final seen = <Place>{};
    for (final entry in chapters.entries) {
      if (!entry.key.startsWith('$code ')) continue;
      for (final named in entry.value) {
        seen.add(named.place);
      }
    }
    final found = seen.toList()..sort((a, b) => a.name.compareTo(b.name));
    return found;
  }

  static AtlasData fromJson(Map<Object?, Object?> json) {
    // Coordinates are stored as whole thousandths of a degree.
    const scale = 1000.0;

    GeoRun run(Object? raw) {
      final numbers = raw! as List<Object?>;
      final points = Float32List(numbers.length);
      for (var i = 0; i < numbers.length; i++) {
        points[i] = (numbers[i]! as num) / scale;
      }
      return GeoRun(points);
    }

    List<GeoRun> runs(Object? raw) => [
      for (final line in (raw as List<Object?>?) ?? const []) run(line),
    ];

    GeoBox box(Object? raw, GeoBox fallback) {
      final numbers = (raw as List<Object?>?) ?? const [];
      if (numbers.length != 4) return fallback;
      return GeoBox(
        (numbers[0]! as num) / scale,
        (numbers[1]! as num) / scale,
        (numbers[2]! as num) / scale,
        (numbers[3]! as num) / scale,
      );
    }

    List<String> split(Object? raw) {
      final text = (raw as String?) ?? '';
      if (text.isEmpty) return const [];
      return text.split('|');
    }

    final places = <Place>[];
    for (final raw in (json['places'] as List<Object?>?) ?? const []) {
      final fields = raw! as List<Object?>;
      places.add(
        Place(
          name: fields[0]! as String,
          types: split(fields[1]),
          lon: (fields[2]! as num) / scale,
          lat: (fields[3]! as num) / scale,
          confidence: (fields[4]! as num).toInt(),
          modern: fields.length > 5 ? (fields[5] as String? ?? '') : '',
          otherNames: fields.length > 6 ? split(fields[6]) : const [],
          comment: fields.length > 7 ? (fields[7] as String? ?? '') : '',
          verseCount: fields.length > 8
              ? ((fields[8] as num?)?.toInt() ?? 0)
              : 0,
        ),
      );
    }

    final chapters = <String, List<ChapterPlace>>{};
    final rawChapters =
        (json['chapters'] as Map<Object?, Object?>?) ?? const {};
    for (final entry in rawChapters.entries) {
      final named = <ChapterPlace>[];
      for (final raw in entry.value! as List<Object?>) {
        // [place index, verse, verse, …]
        final fields = raw! as List<Object?>;
        if (fields.isEmpty) continue;
        final index = (fields.first! as num).toInt();
        if (index < 0 || index >= places.length) continue;
        named.add(
          ChapterPlace(
            place: places[index],
            verses: [
              for (final verse in fields.skip(1)) (verse! as num).toInt(),
            ],
          ),
        );
      }
      chapters[entry.key.toString()] = named;
    }

    final bounds = box(json['bounds'], GeoBox.empty);
    return AtlasData(
      places: places,
      chapters: chapters,
      coarse: BaseMap(
        land: runs(json['land']),
        lakes: runs(json['lakes']),
        rivers: runs(json['rivers']),
      ),
      fine: BaseMap(
        land: runs(json['fineLand']),
        lakes: runs(json['fineLakes']),
        rivers: runs(json['fineRivers']),
      ),
      urban: runs(json['urban']),
      towns: [
        for (final raw in (json['towns'] as List<Object?>?) ?? const [])
          if (raw is List<Object?> && raw.length >= 4)
            Town(
              name: raw[3]! as String,
              lon: (raw[0]! as num) / scale,
              lat: (raw[1]! as num) / scale,
              rank: (raw[2]! as num).toInt(),
            ),
      ],
      bounds: bounds,
      detail: box(json['detail'], bounds),
    );
  }
}
