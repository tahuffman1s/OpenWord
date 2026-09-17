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
// https://github.com/martynafford/natural-earth-geojson — the 50m land,
// lakes and river centrelines, clipped to the world the Bible names and
// simplified until a phone can draw them without noticing.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Kept in step with `Atlas.assetName`, which cannot be imported here: it
/// reaches for the Flutter asset bundle and this is a plain Dart script.
const String assetName = 'atlas.json.gz';

/// Coordinates are stored as whole thousandths of a degree — about 100 m,
/// far finer than a map this size can show, and much smaller than decimals.
const int _scale = 1000;

/// How far a point may sit from the simplified line, in degrees.
const double _tolerance = 0.02;

/// Rings and lines smaller than this are dropped; at the scale a phone draws
/// them they are a single pixel of noise.
const double _minExtent = 0.15;

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

  // The base map has to cover more than the places themselves: the reader's
  // view is fitted to a chapter's places and then grown to fill the screen,
  // and past the edge of the data there would be nothing to draw.
  final bounds = _Bounds.around(places)..pad(12);

  final physical = '${naturalEarth.path}/50m/physical';
  final land = _readGeometry(
    '$physical/ne_50m_land.json',
    bounds,
    polygons: true,
  );
  final lakes = _readGeometry(
    '$physical/ne_50m_lakes.json',
    bounds,
    polygons: true,
  );
  final rivers = _readGeometry(
    '$physical/ne_50m_rivers_lake_centerlines.json',
    bounds,
    polygons: false,
  );

  final chapters = <String, List<int>>{};
  for (var i = 0; i < places.length; i++) {
    for (final reference in places[i].chapters) {
      (chapters[reference] ??= <int>[]).add(i);
    }
  }

  final atlas = <String, Object?>{
    'version': 1,
    'bounds': [
      _fixed(bounds.west),
      _fixed(bounds.south),
      _fixed(bounds.east),
      _fixed(bounds.north),
    ],
    'places': [
      for (final place in places)
        [
          place.name,
          place.type,
          _fixed(place.lon),
          _fixed(place.lat),
          place.confidence,
        ],
    ],
    'chapters': {for (final entry in chapters.entries) entry.key: entry.value},
    'land': land,
    'lakes': lakes,
    'rivers': rivers,
  };

  final json = jsonEncode(atlas);
  final bytes = gzip.encode(utf8.encode(json));
  final output = File('assets/maps/$assetName')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  stdout.writeln(
    'wrote ${places.length} places over ${chapters.length} chapters, '
    '${land.length} land rings, ${lakes.length} lakes, '
    '${rivers.length} rivers — ${_kb(json.length)} of JSON, '
    '${_kb(bytes.length)} gzipped -> ${output.path}',
  );
}

int _fixed(double degrees) => (degrees * _scale).round();

final RegExp _disambiguator = RegExp(r'\s+\d+$');

String _displayName(String friendlyId) =>
    friendlyId.replaceFirst(_disambiguator, '');

String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(0)} kB';

class _Place {
  _Place({
    required this.name,
    required this.type,
    required this.lat,
    required this.lon,
    required this.confidence,
    required this.chapters,
  });

  final String name;
  final String type;
  final double lat;
  final double lon;

  /// How sure the identification is, 0–1000 as the source scores it.
  final int confidence;

  /// `GEN 12` and so on, one per chapter naming the place.
  final Set<String> chapters;
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

    final lonlat = modern[bestId]?['lonlat'] as String?;
    if (lonlat == null) continue;
    final parts = lonlat.split(',');
    if (parts.length != 2) continue;
    final lon = double.tryParse(parts[0].trim());
    final lat = double.tryParse(parts[1].trim());
    if (lon == null || lat == null) continue;

    final chapters = <String>{};
    for (final verse in verses) {
      final usx = (verse! as Map<String, Object?>)['usx'] as String?;
      if (usx == null) continue;
      final space = usx.indexOf(' ');
      final colon = usx.indexOf(':');
      if (space < 0 || colon < 0) continue;
      chapters.add(
        '${usx.substring(0, space)} '
        '${usx.substring(space + 1, colon)}',
      );
    }
    if (chapters.isEmpty) continue;

    final types = (record['types'] as List<Object?>?) ?? const [];
    places.add(
      _Place(
        // The source numbers the places that share a name — "Bethlehem 1" in
        // Judah, "Bethlehem 2" in Zebulun. On a map they are told apart by
        // where they are, so the number is only clutter.
        name: _displayName(record['friendly_id']! as String),
        type: types.isEmpty ? 'place' : types.first! as String,
        lat: lat,
        lon: lon,
        confidence: bestScore,
        chapters: chapters,
      ),
    );
  }

  places.sort((a, b) => a.name.compareTo(b.name));
  return places;
}

/// Clips a GeoJSON file to [bounds], simplifies what is left and flattens it
/// into lists of thousandths of a degree.
List<List<int>> _readGeometry(
  String path,
  _Bounds bounds, {
  required bool polygons,
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
        final simplified = _simplify(piece, _tolerance);
        if (simplified.length < 2) continue;
        if (_extent(simplified) < _minExtent) continue;
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
