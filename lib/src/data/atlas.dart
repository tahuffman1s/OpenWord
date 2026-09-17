import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the places named in the text are, and enough coastline, lake and
/// river to recognise them by.
///
/// Like the book introductions this is read on demand and kept afterwards:
/// it is only wanted when someone opens the map for a chapter.
class Atlas {
  Atlas({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const String assetName = 'atlas.json.gz';
  static const String assetPath = 'assets/maps/$assetName';

  /// Shown on the map and in Settings, as both licences require.
  static const String attribution =
      'Place locations from OpenBible.info Bible Geocoding, CC BY 4.0. Base '
      'map from Natural Earth, public domain.';

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
      final bytes = await _bundle.load(assetPath);
      final raw = const GZipDecoder().decodeBytes(Uint8List.sublistView(bytes));
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map) return AtlasData.empty;
      return AtlasData.fromJson(decoded);
    } on Object catch (error) {
      debugPrint('OpenWord: could not read the atlas: $error');
      return AtlasData.empty;
    }
  }
}

/// A place named in the text, at the location its identification favours.
class Place {
  const Place({
    required this.name,
    required this.type,
    required this.lon,
    required this.lat,
    required this.confidence,
  });

  final String name;

  /// settlement, region, mountain, river and so on.
  final String type;

  final double lon;
  final double lat;

  /// How sure the identification is, 0–1000 as the source scores it. Below
  /// [uncertain] the map says so rather than pretending.
  final int confidence;

  static const int uncertain = 500;

  bool get isUncertain => confidence < uncertain;
}

class AtlasData {
  const AtlasData({
    required this.places,
    required this.chapters,
    required this.land,
    required this.lakes,
    required this.rivers,
  });

  static const AtlasData empty = AtlasData(
    places: [],
    chapters: {},
    land: [],
    lakes: [],
    rivers: [],
  );

  final List<Place> places;

  /// `GEN 12` to the places named in that chapter.
  final Map<String, List<int>> chapters;

  /// Coastlines and water, as flat `[lon, lat, lon, lat, …]` runs.
  final List<Float32List> land;
  final List<Float32List> lakes;
  final List<Float32List> rivers;

  bool get isEmpty => places.isEmpty;

  /// The places named in a chapter, in the order the source lists them.
  List<Place> inChapter(String bookCode, int chapter) =>
      _lookup('${bookCode.toUpperCase()} $chapter');

  /// Every place named anywhere in a book.
  List<Place> inBook(String bookCode) {
    final code = bookCode.toUpperCase();
    final seen = <int>{};
    for (final entry in chapters.entries) {
      if (entry.key.startsWith('$code ')) seen.addAll(entry.value);
    }
    final found = seen.toList()..sort();
    return [for (final index in found) places[index]];
  }

  List<Place> _lookup(String key) {
    final indexes = chapters[key];
    if (indexes == null) return const [];
    return [for (final index in indexes) places[index]];
  }

  static AtlasData fromJson(Map<Object?, Object?> json) {
    // Coordinates are stored as whole thousandths of a degree.
    const scale = 1000.0;

    Float32List run(Object? raw) {
      final numbers = raw! as List<Object?>;
      final out = Float32List(numbers.length);
      for (var i = 0; i < numbers.length; i++) {
        out[i] = (numbers[i]! as num) / scale;
      }
      return out;
    }

    List<Float32List> runs(Object? raw) => [
      for (final line in (raw as List<Object?>?) ?? const []) run(line),
    ];

    final places = <Place>[];
    for (final raw in (json['places'] as List<Object?>?) ?? const []) {
      final fields = raw! as List<Object?>;
      places.add(
        Place(
          name: fields[0]! as String,
          type: fields[1]! as String,
          lon: (fields[2]! as num) / scale,
          lat: (fields[3]! as num) / scale,
          confidence: (fields[4]! as num).toInt(),
        ),
      );
    }

    final chapters = <String, List<int>>{};
    final rawChapters =
        (json['chapters'] as Map<Object?, Object?>?) ?? const {};
    for (final entry in rawChapters.entries) {
      chapters[entry.key.toString()] = [
        for (final index in entry.value! as List<Object?>)
          (index! as num).toInt(),
      ];
    }

    return AtlasData(
      places: places,
      chapters: chapters,
      land: runs(json['land']),
      lakes: runs(json['lakes']),
      rivers: runs(json['rivers']),
    );
  }
}
