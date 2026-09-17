import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/atlas.dart';

/// Turns degrees into pixels and back, for one size of canvas.
///
/// Equirectangular, with longitude squeezed by the cosine of the middle
/// latitude: over a few hundred miles of the eastern Mediterranean that is
/// indistinguishable from a proper projection, and it costs two multiplies.
@immutable
class MapProjection {
  const MapProjection({
    required this.west,
    required this.north,
    required this.scaleX,
    required this.scaleY,
    required this.size,
  });

  /// Fits [bounds] into [size], keeping the aspect ratio of the ground.
  factory MapProjection.fit(MapBounds bounds, Size size) {
    final squeeze = math
        .cos(bounds.centreLat * math.pi / 180)
        .abs()
        .clamp(0.2, 1.0);
    final groundWidth = bounds.width * squeeze;
    final groundHeight = bounds.height;
    final scale = math.min(
      size.width / groundWidth,
      size.height / groundHeight,
    );

    // Centre whatever is left over, so a tall group of places is not stuck
    // against the left edge of a wide map.
    final usedWidth = groundWidth * scale;
    final usedHeight = groundHeight * scale;
    final west = bounds.west - (size.width - usedWidth) / 2 / scale / squeeze;
    final north = bounds.north + (size.height - usedHeight) / 2 / scale;

    return MapProjection(
      west: west,
      north: north,
      scaleX: scale * squeeze,
      scaleY: scale,
      size: size,
    );
  }

  final double west;
  final double north;
  final double scaleX;
  final double scaleY;
  final Size size;

  Offset toOffset(double lon, double lat) =>
      Offset((lon - west) * scaleX, (north - lat) * scaleY);

  /// How many degrees of longitude a pixel covers, for culling.
  double get degreesPerPixelX => 1 / scaleX;
}

/// A rectangle of the world.
@immutable
class MapBounds {
  const MapBounds(this.west, this.south, this.east, this.north);

  /// The rectangle holding every place, never smaller than [minimumSpan] so
  /// that a chapter naming one place is not magnified into meaninglessness.
  factory MapBounds.around(Iterable<Place> places, {double padding = 0.18}) {
    var west = double.infinity, east = -double.infinity;
    var south = double.infinity, north = -double.infinity;
    for (final place in places) {
      west = math.min(west, place.lon);
      east = math.max(east, place.lon);
      south = math.min(south, place.lat);
      north = math.max(north, place.lat);
    }
    if (west > east) return const MapBounds(34, 31, 36, 33);

    var bounds = MapBounds(west, south, east, north);
    bounds = bounds.padded(
      math.max(bounds.width, bounds.height) * padding + 0.05,
    );
    return bounds.atLeast(minimumSpan);
  }

  static const double minimumSpan = 1.2;

  final double west;
  final double south;
  final double east;
  final double north;

  double get width => east - west;
  double get height => north - south;
  double get centreLat => (north + south) / 2;
  double get centreLon => (east + west) / 2;

  MapBounds padded(double degrees) => MapBounds(
    west - degrees,
    south - degrees,
    east + degrees,
    north + degrees,
  );

  /// Grows the rectangle about its centre until it spans at least [span].
  MapBounds atLeast(double span) {
    final growX = math.max(0, span - width) / 2;
    final growY = math.max(0, span - height) / 2;
    return MapBounds(west - growX, south - growY, east + growX, north + growY);
  }
}

/// The map itself: coastline, water and the places of a passage.
class AtlasMap extends StatelessWidget {
  const AtlasMap({
    required this.data,
    required this.places,
    this.selected,
    this.onSelected,
    super.key,
  });

  final AtlasData data;
  final List<Place> places;
  final Place? selected;
  final ValueChanged<Place?>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bounds = MapBounds.around(places);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final projection = MapProjection.fit(bounds, size);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _tapped(details.localPosition, projection),
          child: CustomPaint(
            size: size,
            painter: _AtlasPainter(
              data: data,
              places: places,
              selected: selected,
              projection: projection,
              // A little of the seed colour in the water, so land and sea
              // are told apart at a glance whatever the palette.
              water: Color.alphaBlend(
                theme.colorScheme.primary.withValues(alpha: 0.16),
                theme.colorScheme.surfaceContainerHighest,
              ),
              land: theme.colorScheme.surface,
              coast: theme.colorScheme.outline,
              river: theme.colorScheme.primary.withValues(alpha: 0.45),
              marker: theme.colorScheme.primary,
              label: theme.colorScheme.onSurface,
              labelHalo: theme.colorScheme.surface,
              textDirection: Directionality.of(context),
            ),
          ),
        );
      },
    );
  }

  void _tapped(Offset position, MapProjection projection) {
    final pick = onSelected;
    if (pick == null) return;
    Place? nearest;
    var best = 28.0;
    for (final place in places) {
      final distance =
          (projection.toOffset(place.lon, place.lat) - position).distance;
      if (distance < best) {
        best = distance;
        nearest = place;
      }
    }
    pick(nearest);
  }
}

class _AtlasPainter extends CustomPainter {
  _AtlasPainter({
    required this.data,
    required this.places,
    required this.selected,
    required this.projection,
    required this.water,
    required this.land,
    required this.coast,
    required this.river,
    required this.marker,
    required this.label,
    required this.labelHalo,
    required this.textDirection,
  });

  final AtlasData data;
  final List<Place> places;
  final Place? selected;
  final MapProjection projection;
  final Color water;
  final Color land;
  final Color coast;
  final Color river;
  final Color marker;
  final Color label;
  final Color labelHalo;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = water);

    // Non-zero winding, not even-odd: clipping the coastline to the map
    // leaves rings that share the map's own edges, and even-odd would read
    // the overlap between two of them as a hole and paint the land as sea.
    // Islands and inland seas are wound the other way and still come out as
    // holes.
    final landPath = _path(data.land, close: true);
    canvas.drawPath(
      landPath,
      Paint()
        ..color = land
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      landPath,
      Paint()
        ..color = coast
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    canvas.drawPath(_path(data.lakes, close: true), Paint()..color = water);
    canvas.drawPath(
      _path(data.rivers, close: false),
      Paint()
        ..color = river
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    _paintPlaces(canvas, size);
  }

  Path _path(List<Float32List> runs, {required bool close}) {
    final path = Path();
    for (final run in runs) {
      if (run.length < 4) continue;
      var started = false;
      for (var i = 0; i < run.length; i += 2) {
        final point = projection.toOffset(run[i], run[i + 1]);
        if (!started) {
          path.moveTo(point.dx, point.dy);
          started = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      if (close) path.close();
    }
    return path;
  }

  void _paintPlaces(Canvas canvas, Size size) {
    // Labels are laid out one at a time and skipped where they would sit on
    // one already drawn: a legible map with a few names beats an illegible
    // one with all of them.
    final taken = <Rect>[];
    final ordered = [
      for (final place in places)
        if (place != selected) place,
      if (selected != null) selected!,
    ];

    final drawn = <Place, Offset>{};
    final markers = <Place, Rect>{};
    for (final place in ordered) {
      final at = projection.toOffset(place.lon, place.lat);
      if (at.dx < -20 ||
          at.dy < -20 ||
          at.dx > size.width + 20 ||
          at.dy > size.height + 20) {
        continue;
      }
      final isSelected = place == selected;
      final radius = isSelected ? 7.0 : 4.0;
      drawn[place] = at;
      // Markers are reserved before any label is placed, so that a marker
      // drawn later cannot land on top of a name already written. A place's
      // own marker is skipped when its label is placed, or every label would
      // collide with the dot it belongs to.
      markers[place] = Rect.fromCircle(
        center: at,
        radius: isSelected ? radius + 6 : radius + 2,
      );

      canvas.drawCircle(at, radius + 2, Paint()..color = labelHalo);
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..color = marker
          ..style = place.isUncertain && !isSelected
              ? PaintingStyle.stroke
              : PaintingStyle.fill
          ..strokeWidth = 2,
      );
      if (isSelected) {
        // A ring around the marker rather than a hole through it: a hollow
        // marker already means the location is disputed.
        canvas.drawCircle(
          at,
          radius + 4,
          Paint()
            ..color = marker
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    for (final entry in drawn.entries) {
      final place = entry.key;
      final at = entry.value;
      final isSelected = place == selected;
      final radius = isSelected ? 7.0 : 4.0;

      final painter = TextPainter(
        text: TextSpan(
          text: place.name,
          style: TextStyle(
            color: label,
            fontSize: isSelected ? 13 : 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: textDirection,
      )..layout();

      final candidates = <Offset>[
        Offset(at.dx + radius + 4, at.dy - painter.height / 2),
        Offset(at.dx - radius - 4 - painter.width, at.dy - painter.height / 2),
        Offset(at.dx - painter.width / 2, at.dy + radius + 3),
        Offset(at.dx - painter.width / 2, at.dy - radius - 3 - painter.height),
      ];
      Rect? spot;
      for (final candidate in candidates) {
        final rect = candidate & Size(painter.width, painter.height);
        if (rect.left < 0 ||
            rect.top < 0 ||
            rect.right > size.width ||
            rect.bottom > size.height) {
          continue;
        }
        final padded = rect.inflate(1);
        if (taken.any(padded.overlaps)) continue;
        if (markers.entries.any(
          (entry) => entry.key != place && entry.value.overlaps(padded),
        )) {
          continue;
        }
        spot = rect;
        break;
      }
      if (spot == null && !isSelected) continue;
      spot ??= candidates.first & Size(painter.width, painter.height);
      taken.add(spot);

      canvas.drawRRect(
        RRect.fromRectAndRadius(spot.inflate(2), const Radius.circular(4)),
        Paint()..color = labelHalo.withValues(alpha: 0.85),
      );
      painter.paint(canvas, spot.topLeft);
    }
  }

  @override
  bool shouldRepaint(_AtlasPainter old) =>
      old.places != places ||
      old.selected != selected ||
      old.projection.size != projection.size ||
      old.land != land;
}
