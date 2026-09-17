// Builds the atlas asset: where the places named in the text are, and enough
// coastline to recognise them by.
//
//   dart run tool/build_maps.dart <bible-geocoding-data> <natural-earth-geojson>
//
// The places come from OpenBible.info's Bible Geocoding data (CC BY 4.0),
// https://github.com/openbibleinfo/Bible-Geocoding-Data — data/ancient.jsonl
// holds each ancient place with the verses naming it, data/modern.jsonl the
// modern identifications it resolves to, with coordinates.
//
// The base map is Natural Earth (public domain), by way of
// https://github.com/martynafford/natural-earth-geojson. Two levels of it:
// the 1:50m land, lakes and rivers for the whole padded region, drawn when
// the map is zoomed out, and the 1:10m ones over the ground the Bible
// actually covers, drawn once the reader zooms past a country or two. Both
// are clipped and simplified, because a phone redraws them on every frame of
// a pinch.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Kept in step with `Atlas.assetName`, which cannot be imported here: it
/// reaches for the Flutter asset bundle and this is a plain Dart script.
const String assetName = 'atlas.json.gz';

/// Coordinates are stored as whole thousandths of a degree — about 100 m,
/// far finer than a map this size can show, and much smaller than decimals.
const int _scale = 1000;

/// How far a point may sit from the simplified line, in degrees: coarse for
/// the zoomed-out map, fine for the detail drawn over the Levant and its
/// neighbours.
const double _coarseTolerance = 0.02;
const double _fineTolerance = 0.0025;

/// Rings and lines smaller than this are dropped; at the scale they are drawn
/// they would be a single pixel of noise.
const double _coarseMinExtent = 0.15;
const double _fineMinExtent = 0.02;

/// How far around the places the fine detail reaches. Wide enough for Rome,
/// Babylon and the Nile without carrying the whole of Europe at 1:10m.
const double _finePad = 4.0;

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/build_maps.dart '
      '<bible-geocoding-data> <natural-earth-geojson>',
    );
    exitCode = 1;
    return;
  }
  final geocoding = Directory(args[0]);
  final naturalEarth = Directory(args[1]);
  for (final directory in [geocoding, naturalEarth]) {
    if (!directory.existsSync()) {
      stderr.writeln('no such directory: ${directory.path}');
      exitCode = 1;
      return;
    }
  }

  final places = _readPlaces(geocoding);
  if (places.isEmpty) {
    stderr.writeln('no places found in ${geocoding.path}');
    exitCode = 1;
    return;
  }

  // The coarse map has to cover more than the places themselves: the reader
  // can pan and zoom out, and past the edge of the data there would be
  // nothing to draw.
  final coarseBounds = _Bounds.around(places)..pad(12);
  final fineBounds = _Bounds.around(places)..pad(_finePad);

  final coarse = _baseMap(
    naturalEarth,
    scale: '50m',
    bounds: coarseBounds,
    tolerance: _coarseTolerance,
    minExtent: _coarseMinExtent,
  );
  final fine = _baseMap(
    naturalEarth,
    scale: '10m',
    bounds: fineBounds,
    tolerance: _fineTolerance,
    minExtent: _fineMinExtent,
  );

  // Modern ground, for the reader who zooms all the way in: the towns that
  // are there now, and the shape of the built-up areas. Without them the
  // close-up view of an inland site is a blank page.
  final towns = _readTowns(naturalEarth, fineBounds);
  final urban = _readGeometry(
    '${naturalEarth.path}/10m/cultural/ne_10m_urban_areas.json',
    fineBounds,
    polygons: true,
    tolerance: _fineTolerance,
    minExtent: 0.004,
  );

  // Each chapter lists the places it names and the verses that name them, so
  // the map can offer "1 Kings 1:9" as somewhere to go.
  final chapters = <String, List<List<int>>>{};
  for (var i = 0; i < places.length; i++) {
    for (final entry in places[i].verses.entries) {
      final verses = entry.value.toList()..sort();
      (chapters[entry.key] ??= <List<int>>[]).add([i, ...verses]);
    }
  }

  final atlas = <String, Object?>{
    'version': 2,
    'bounds': [
      _fixed(coarseBounds.west),
      _fixed(coarseBounds.south),
      _fixed(coarseBounds.east),
      _fixed(coarseBounds.north),
    ],
    'detail': [
      _fixed(fineBounds.west),
      _fixed(fineBounds.south),
      _fixed(fineBounds.east),
      _fixed(fineBounds.north),
    ],
    // Fixed positions, read back in the same order by AtlasData.fromJson:
    // name, kind, longitude, latitude, confidence, modern identification,
    // other names, the source's note, how many verses name it in all.
    'places': [
      for (final place in places)
        [
          place.name,
          place.types.join('|'),
          _fixed(place.lon),
          _fixed(place.lat),
          place.confidence,
          place.modern,
          place.otherNames.join('|'),
          place.comment,
          place.verseCount,
        ],
    ],
    'chapters': chapters,
    'land': coarse.land,
    'lakes': coarse.lakes,
    'rivers': coarse.rivers,
    'fineLand': fine.land,
    'fineLakes': fine.lakes,
    'fineRivers': fine.rivers,
    'urban': urban,
    // longitude, latitude, how important Natural Earth rates it, its name.
    'towns': [
      for (final town in towns)
        [_fixed(town.lon), _fixed(town.lat), town.rank, town.name],
    ],
  };

  final json = jsonEncode(atlas);
  final bytes = gzip.encode(utf8.encode(json));
  final output = File('assets/maps/$assetName')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  stdout.writeln(
    'wrote ${places.length} places over ${chapters.length} chapters, '
    '${towns.length} modern towns, ${urban.length} built-up areas; '
    'coarse ${coarse.land.length}/${coarse.lakes.length}/'
    '${coarse.rivers.length}, fine ${fine.land.length}/${fine.lakes.length}/'
    '${fine.rivers.length} (land/lakes/rivers) — ${_kb(json.length)} of JSON, '
    '${_kb(bytes.length)} gzipped -> ${output.path}',
  );
}

int _fixed(double degrees) => (degrees * _scale).round();

final RegExp _disambiguator = RegExp(r'\s+\d+$');

String _displayName(String friendlyId) =>
    friendlyId.replaceFirst(_disambiguator, '');

String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(0)} kB';

/// One level of the base map.
class _BaseMap {
  const _BaseMap(this.land, this.lakes, this.rivers);

  final List<List<int>> land;
  final List<List<int>> lakes;
  final List<List<int>> rivers;
}

_BaseMap _baseMap(
  Directory naturalEarth, {
  required String scale,
  required _Bounds bounds,
  required double tolerance,
  required double minExtent,
}) {
  final physical = '${naturalEarth.path}/$scale/physical';
  List<List<int>> read(String name, {required bool polygons}) => _readGeometry(
    '$physical/ne_${scale}_$name.json',
    bounds,
    polygons: polygons,
    tolerance: tolerance,
    minExtent: minExtent,
  );

  return _BaseMap(
    read('land', polygons: true),
    read('lakes', polygons: true),
    read('rivers_lake_centerlines', polygons: false),
  );
}

class _Town {
  const _Town(this.name, this.lon, this.lat, this.rank);

  final String name;
  final double lon;
  final double lat;

  /// Natural Earth's own ranking, 0 for a capital and up for smaller places.
  final int rank;
}

/// The towns that are there now, so that zooming in on a biblical site shows
/// the country around it rather than an empty page.
List<_Town> _readTowns(Directory naturalEarth, _Bounds bounds) {
  final file = File(
    '${naturalEarth.path}/10m/cultural/ne_10m_populated_places.json',
  );
  if (!file.existsSync()) {
    stderr.writeln('missing ${file.path}');
    exitCode = 1;
    return const [];
  }

  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final towns = <_Town>[];
  for (final feature in (decoded['features'] as List<Object?>?) ?? const []) {
    final record = feature! as Map<String, Object?>;
    final geometry = record['geometry'] as Map<String, Object?>?;
    final properties = record['properties'] as Map<String, Object?>?;
    if (geometry == null || properties == null) continue;
    final coordinates = geometry['coordinates'] as List<Object?>?;
    if (coordinates == null || coordinates.length < 2) continue;

    final lon = (coordinates[0]! as num).toDouble();
    final lat = (coordinates[1]! as num).toDouble();
    if (!bounds.contains(lon, lat)) continue;

    final name =
        properties['NAME_EN'] as String? ?? properties['NAME'] as String?;
    if (name == null || name.isEmpty) continue;
    towns.add(
      _Town(name, lon, lat, (properties['SCALERANK'] as num?)?.toInt() ?? 10),
    );
  }

  towns.sort((a, b) => a.rank.compareTo(b.rank));
  return towns;
}

class _Place {
  _Place({
    required this.name,
    required this.types,
    required this.lat,
    required this.lon,
    required this.confidence,
    required this.modern,
    required this.otherNames,
    required this.comment,
    required this.verses,
    required this.verseCount,
  });

  final String name;

  /// settlement, region, spring and so on, as the source classes them.
  final List<String> types;
  final double lat;
  final double lon;

  /// How sure the identification is, 0–1000 as the source scores it.
  final int confidence;

  /// The modern place it is identified with, where there is one.
  final String modern;

  /// What translations call it, where they differ from the name used here.
  final List<String> otherNames;

  /// The source's own note on the place, with its markup stripped.
  final String comment;

  /// `1KI 1` to the verses of that chapter naming the place.
  final Map<String, Set<int>> verses;

  /// How many verses name it in the whole Bible.
  final int verseCount;
}

/// Reads the ancient places, keeping those that resolve to a point on the
/// ground and are named somewhere in the text.
List<_Place> _readPlaces(Directory geocoding) {
  final modern = <String, Map<String, Object?>>{};
  for (final line in _lines('${geocoding.path}/data/modern.jsonl')) {
    final record = jsonDecode(line) as Map<String, Object?>;
    modern[record['id']! as String] = record;
  }

  final places = <_Place>[];
  for (final line in _lines('${geocoding.path}/data/ancient.jsonl')) {
    final record = jsonDecode(line) as Map<String, Object?>;
    final verses = record['verses'] as List<Object?>?;
    if (verses == null || verses.isEmpty) continue;

    // Several modern identifications may compete; the score is the source's
    // own weighing of them, so take the one it is surest of.
    final associations =
        (record['modern_associations'] as Map<String, Object?>?) ?? const {};
    String? bestId;
    var bestScore = -1;
    for (final entry in associations.entries) {
      final score =
          ((entry.value! as Map<String, Object?>)['score'] as num?)?.toInt() ??
          0;
      if (score > bestScore) {
        bestScore = score;
        bestId = entry.key;
      }
    }
    if (bestId == null) continue;

    final identification = modern[bestId];
    final lonlat = identification?['lonlat'] as String?;
    if (lonlat == null) continue;
    final parts = lonlat.split(',');
    if (parts.length != 2) continue;
    final lon = double.tryParse(parts[0].trim());
    final lat = double.tryParse(parts[1].trim());
    if (lon == null || lat == null) continue;

    final byChapter = <String, Set<int>>{};
    for (final verse in verses) {
      final usx = (verse! as Map<String, Object?>)['usx'] as String?;
      final reference = _reference(usx);
      if (reference == null) continue;
      (byChapter[reference.chapter] ??= <int>{}).add(reference.verse);
    }
    if (byChapter.isEmpty) continue;

    // The source numbers the places that share a name — "Bethlehem 1" in
    // Judah, "Bethlehem 2" in Zebulun. On a map they are told apart by where
    // they are, so the number is only clutter.
    final name = _displayName(record['friendly_id']! as String);
    final types = [
      for (final type in (record['types'] as List<Object?>?) ?? const [])
        type! as String,
    ];

    places.add(
      _Place(
        name: name,
        types: types.isEmpty ? const ['place'] : types,
        lat: lat,
        lon: lon,
        confidence: bestScore,
        modern:
            (associations[bestId]! as Map<String, Object?>)['name']
                as String? ??
            '',
        otherNames: _otherNames(record, name),
        comment: _plainText(record['comment'] as String? ?? ''),
        verses: byChapter,
        verseCount: verses.length,
      ),
    );
  }

  places.sort((a, b) => a.name.compareTo(b.name));
  return places;
}

/// What the translations call a place, commonest first, leaving out the name
/// already shown and anything that is only a spelling away from it.
List<String> _otherNames(Map<String, Object?> record, String name) {
  final counts =
      (record['translation_name_counts'] as Map<String, Object?>?) ?? const {};
  final entries = counts.entries.toList()
    ..sort(
      (a, b) => ((b.value as num?) ?? 0).compareTo((a.value as num?) ?? 0),
    );

  String flatten(String text) =>
      text.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

  final seen = <String>{flatten(name)};
  final names = <String>[];
  for (final entry in entries) {
    if (seen.add(flatten(entry.key))) names.add(entry.key);
    if (names.length == 3) break;
  }
  return names;
}

/// `GEN 12:1` to its chapter key and verse number.
({String chapter, int verse})? _reference(String? usx) {
  if (usx == null) return null;
  final space = usx.indexOf(' ');
  final colon = usx.indexOf(':');
  if (space < 0 || colon < 0) return null;
  final verse = int.tryParse(usx.substring(colon + 1).split('-').first.trim());
  if (verse == null) return null;
  return (
    chapter: '${usx.substring(0, space)} ${usx.substring(space + 1, colon)}',
    verse: verse,
  );
}

/// The source's notes carry markup linking other places and Wikidata. The app
/// is offline and has no use for the links, but the words are worth keeping.
String _plainText(String markup) => markup
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Clips a GeoJSON file to [bounds], simplifies what is left and flattens it
/// into lists of thousandths of a degree.
List<List<int>> _readGeometry(
  String path,
  _Bounds bounds, {
  required bool polygons,
  required double tolerance,
  required double minExtent,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('missing ${file.path}');
    exitCode = 1;
    return const [];
  }

  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final features = (decoded['features'] as List<Object?>?) ?? const [];
  final out = <List<int>>[];

  for (final feature in features) {
    final geometry =
        (feature! as Map<String, Object?>)['geometry'] as Map<String, Object?>?;
    if (geometry == null) continue;
    for (final line in _rings(geometry, polygons: polygons)) {
      // A ring is clipped as a polygon so it comes back closed and can be
      // filled; a river is cut into the runs of it that are on the map.
      final pieces = polygons
          ? [if (_clipRing(line, bounds) case final ring?) ring]
          : _clipLine(line, bounds);
      for (final piece in pieces) {
        final simplified = _simplify(piece, tolerance);
        if (simplified.length < 2) continue;
        if (_extent(simplified) < minExtent) continue;
        out.add([
          for (final point in simplified) ...[
            _fixed(point[0]),
            _fixed(point[1]),
          ],
        ]);
      }
    }
  }
  return out;
}

/// Every ring or line string in a geometry, whatever its type.
Iterable<List<List<double>>> _rings(
  Map<String, Object?> geometry, {
  required bool polygons,
}) sync* {
  final type = geometry['type'] as String?;
  final coordinates = geometry['coordinates'];
  List<List<double>> toLine(Object? raw) => [
    for (final point in raw! as List<Object?>)
      [
        ((point! as List<Object?>)[0]! as num).toDouble(),
        ((point as List<Object?>)[1]! as num).toDouble(),
      ],
  ];

  switch (type) {
    case 'Polygon':
      for (final ring in coordinates! as List<Object?>) {
        yield toLine(ring);
      }
    case 'MultiPolygon':
      for (final polygon in coordinates! as List<Object?>) {
        for (final ring in polygon! as List<Object?>) {
          yield toLine(ring);
        }
      }
    case 'LineString':
      if (!polygons) yield toLine(coordinates);
    case 'MultiLineString':
      if (!polygons) {
        for (final line in coordinates! as List<Object?>) {
          yield toLine(line);
        }
      }
  }
}

/// Sutherland–Hodgman: cuts a ring against each edge of the map in turn, so
/// what comes back is still a closed ring and can be filled as land or water.
/// Returns null for a ring that falls outside the map altogether.
List<List<double>>? _clipRing(List<List<double>> ring, _Bounds bounds) {
  var output = ring;
  for (var edge = 0; edge < 4; edge++) {
    if (output.length < 3) return null;
    final input = output;
    output = <List<double>>[];
    for (var i = 0; i < input.length; i++) {
      final current = input[i];
      final previous = input[(i - 1 + input.length) % input.length];
      final currentIn = _inside(current, edge, bounds);
      final previousIn = _inside(previous, edge, bounds);
      if (currentIn) {
        if (!previousIn) {
          output.add(_intersect(previous, current, edge, bounds));
        }
        output.add(current);
      } else if (previousIn) {
        output.add(_intersect(previous, current, edge, bounds));
      }
    }
  }
  if (output.length < 3) return null;
  // Close it, so the drawing side does not have to know it was clipped.
  if (output.first[0] != output.last[0] || output.first[1] != output.last[1]) {
    output.add(output.first);
  }
  return output;
}

/// Edges in the order left, right, bottom, top.
bool _inside(List<double> point, int edge, _Bounds bounds) => switch (edge) {
  0 => point[0] >= bounds.west,
  1 => point[0] <= bounds.east,
  2 => point[1] >= bounds.south,
  _ => point[1] <= bounds.north,
};

List<double> _intersect(
  List<double> from,
  List<double> to,
  int edge,
  _Bounds bounds,
) {
  final dx = to[0] - from[0];
  final dy = to[1] - from[1];
  switch (edge) {
    case 0 || 1:
      final x = edge == 0 ? bounds.west : bounds.east;
      final t = dx == 0 ? 0.0 : (x - from[0]) / dx;
      return [x, from[1] + t * dy];
    default:
      final y = edge == 2 ? bounds.south : bounds.north;
      final t = dy == 0 ? 0.0 : (y - from[1]) / dy;
      return [from[0] + t * dx, y];
  }
}

/// Splits a line into the runs of it that are inside [bounds], keeping one
/// point either side so the line still reaches the edge of the map.
List<List<List<double>>> _clipLine(List<List<double>> line, _Bounds bounds) {
  final pieces = <List<List<double>>>[];
  var current = <List<double>>[];
  for (var i = 0; i < line.length; i++) {
    final point = line[i];
    final inside = bounds.contains(point[0], point[1]);
    if (inside) {
      if (current.isEmpty && i > 0) current.add(line[i - 1]);
      current.add(point);
    } else if (current.isNotEmpty) {
      current.add(point);
      pieces.add(current);
      current = <List<double>>[];
    }
  }
  if (current.length > 1) pieces.add(current);
  return pieces;
}

double _extent(List<List<double>> line) {
  var west = double.infinity, east = -double.infinity;
  var south = double.infinity, north = -double.infinity;
  for (final point in line) {
    west = math.min(west, point[0]);
    east = math.max(east, point[0]);
    south = math.min(south, point[1]);
    north = math.max(north, point[1]);
  }
  return math.max(east - west, north - south);
}

/// Ramer–Douglas–Peucker, iteratively so a long coastline cannot overflow
/// the stack.
List<List<double>> _simplify(List<List<double>> line, double tolerance) {
  if (line.length < 3) return line;
  final keep = List<bool>.filled(line.length, false);
  keep[0] = true;
  keep[line.length - 1] = true;

  final stack = <List<int>>[
    [0, line.length - 1],
  ];
  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    final first = range[0], last = range[1];
    var farthest = -1;
    var distance = tolerance;
    for (var i = first + 1; i < last; i++) {
      final d = _distanceToSegment(line[i], line[first], line[last]);
      if (d > distance) {
        distance = d;
        farthest = i;
      }
    }
    if (farthest < 0) continue;
    keep[farthest] = true;
    stack.add([first, farthest]);
    stack.add([farthest, last]);
  }

  return [
    for (var i = 0; i < line.length; i++)
      if (keep[i]) line[i],
  ];
}

double _distanceToSegment(
  List<double> point,
  List<double> start,
  List<double> end,
) {
  final dx = end[0] - start[0];
  final dy = end[1] - start[1];
  if (dx == 0 && dy == 0) {
    return math.sqrt(
      math.pow(point[0] - start[0], 2) + math.pow(point[1] - start[1], 2),
    );
  }
  final t =
      ((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) /
      (dx * dx + dy * dy);
  final clamped = t.clamp(0.0, 1.0);
  final nearestX = start[0] + clamped * dx;
  final nearestY = start[1] + clamped * dy;
  return math.sqrt(
    math.pow(point[0] - nearestX, 2) + math.pow(point[1] - nearestY, 2),
  );
}

class _Bounds {
  _Bounds(this.west, this.south, this.east, this.north);

  factory _Bounds.around(List<_Place> places) {
    var west = double.infinity, east = -double.infinity;
    var south = double.infinity, north = -double.infinity;
    for (final place in places) {
      west = math.min(west, place.lon);
      east = math.max(east, place.lon);
      south = math.min(south, place.lat);
      north = math.max(north, place.lat);
    }
    return _Bounds(west, south, east, north);
  }

  double west, south, east, north;

  void pad(double degrees) {
    west -= degrees;
    south -= degrees;
    east += degrees;
    north += degrees;
  }

  bool contains(double lon, double lat) =>
      lon >= west && lon <= east && lat >= south && lat <= north;
}

Iterable<String> _lines(String path) sync* {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('missing ${file.path}');
    exitCode = 1;
    return;
  }
  for (final line in const LineSplitter().convert(file.readAsStringSync())) {
    if (line.trim().isEmpty) continue;
    yield line;
  }
}
