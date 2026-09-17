import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/atlas.dart';

/// Where the map is looking: a point on the ground in the middle of the
/// canvas, and how many pixels a degree of latitude takes.
///
/// Equirectangular, with longitude squeezed by the cosine of the middle
/// latitude. Over the eastern Mediterranean that is indistinguishable from a
/// proper projection and costs two multiplies, which matters when it runs on
/// every frame of a pinch.
@immutable
class MapCamera {
  const MapCamera({
    required this.centreLon,
    required this.centreLat,
    required this.scale,
    required this.size,
  });

  /// Frames a box in a canvas, leaving a little room around it.
  factory MapCamera.fit(GeoBox box, Size size, {double padding = 1.12}) {
    final squeeze = _squeezeAt(box.centreLat);
    final width = math.max(box.width * squeeze, 1e-6);
    final height = math.max(box.height, 1e-6);
    final scale = math.min(size.width / width, size.height / height) / padding;
    return MapCamera(
      centreLon: box.centreLon,
      centreLat: box.centreLat,
      scale: scale,
      size: size,
    );
  }

  final double centreLon;
  final double centreLat;

  /// Pixels per degree of latitude.
  final double scale;

  final Size size;

  double get squeeze => _squeezeAt(centreLat);

  static double _squeezeAt(double lat) =>
      math.cos(lat * math.pi / 180).abs().clamp(0.2, 1.0);

  Offset toOffset(double lon, double lat) => Offset(
    size.width / 2 + (lon - centreLon) * squeeze * scale,
    size.height / 2 + (centreLat - lat) * scale,
  );

  /// The ground under a point on the canvas.
  (double lon, double lat) toGround(Offset point) => (
    centreLon + (point.dx - size.width / 2) / (squeeze * scale),
    centreLat - (point.dy - size.height / 2) / scale,
  );

  /// The ground the canvas is showing.
  GeoBox get visible {
    final halfLat = size.height / 2 / scale;
    final halfLon = size.width / 2 / (squeeze * scale);
    return GeoBox(
      centreLon - halfLon,
      centreLat - halfLat,
      centreLon + halfLon,
      centreLat + halfLat,
    );
  }

  /// Roughly how many metres a pixel covers, for the scale bar.
  double get metresPerPixel => 111320 / scale;

  MapCamera copyWith({
    double? centreLon,
    double? centreLat,
    double? scale,
    Size? size,
  }) => MapCamera(
    centreLon: centreLon ?? this.centreLon,
    centreLat: centreLat ?? this.centreLat,
    scale: scale ?? this.scale,
    size: size ?? this.size,
  );

  /// Zooms about a point on the canvas, so what is under the fingers stays
  /// under the fingers.
  MapCamera zoomedAt(
    Offset focus,
    double factor, {
    required double min,
    required double max,
  }) {
    final wanted = (scale * factor).clamp(min, max);
    if (wanted == scale) return this;
    final (lon, lat) = toGround(focus);
    var next = copyWith(scale: wanted);
    // Moving the centre changes the latitude the longitude is squeezed by,
    // so the correction is applied until it settles — three rounds is far
    // more than enough at any zoom this map reaches.
    for (var i = 0; i < 3; i++) {
      final (afterLon, afterLat) = next.toGround(focus);
      next = next.copyWith(
        centreLon: next.centreLon + (lon - afterLon),
        centreLat: next.centreLat + (lat - afterLat),
      );
    }
    return next;
  }

  /// Keeps the middle of the map inside the ground the atlas covers, so it
  /// cannot be dragged off into blankness.
  MapCamera clampedTo(GeoBox bounds) {
    if (bounds.width <= 0 || bounds.height <= 0) return this;
    return copyWith(
      centreLon: centreLon.clamp(bounds.west, bounds.east),
      centreLat: centreLat.clamp(bounds.south, bounds.north),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MapCamera &&
      other.centreLon == centreLon &&
      other.centreLat == centreLat &&
      other.scale == scale &&
      other.size == size;

  @override
  int get hashCode => Object.hash(centreLon, centreLat, scale, size);
}

/// A rectangle around a group of places, never so small that one place fills
/// the screen with nothing around it.
GeoBox boxAround(Iterable<Place> places, {double minimumSpan = 0.6}) {
  var west = double.infinity, east = -double.infinity;
  var south = double.infinity, north = -double.infinity;
  for (final place in places) {
    west = math.min(west, place.lon);
    east = math.max(east, place.lon);
    south = math.min(south, place.lat);
    north = math.max(north, place.lat);
  }
  if (west > east) return const GeoBox(34, 31, 36, 33);

  final growX = math.max(0, minimumSpan - (east - west)) / 2;
  final growY = math.max(0, minimumSpan - (north - south)) / 2;
  return GeoBox(west - growX, south - growY, east + growX, north + growY);
}

/// The map: coastline, water and the places of a passage, with the panning
/// and zooming anyone expects of a map.
class AtlasMap extends StatefulWidget {
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
  State<AtlasMap> createState() => AtlasMapState();
}

class AtlasMapState extends State<AtlasMap> {
  /// As far in as the map will go: about half a metre to the pixel. The
  /// coastline runs out of detail long before this, but a reader zooming
  /// into a city should not be stopped by the app.
  static const double maxScale = 220000;

  MapCamera? _camera;
  Size _size = Size.zero;

  /// The camera when a pinch started, so the gesture is applied to it whole
  /// rather than to its own result.
  MapCamera? _gestureStart;
  Offset? _gestureFocus;

  /// Where a double tap landed, so the zoom happens under the finger.
  Offset? _doubleTapAt;

  MapCamera? get camera => _camera;

  @override
  void didUpdateWidget(AtlasMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different passage is a different map; a new selection is not.
    if (!identical(oldWidget.places, widget.places)) _camera = null;
  }

  /// How far out the map will go: the whole of what the atlas covers.
  double _minScale(Size size) {
    final bounds = widget.data.bounds;
    if (bounds.width <= 0 || bounds.height <= 0) return 1;
    return MapCamera.fit(bounds, size, padding: 1).scale;
  }

  MapCamera _cameraFor(Size size) {
    final current = _camera;
    if (current != null && current.size == size) return current;
    if (current != null) return current.copyWith(size: size);
    return MapCamera.fit(boxAround(widget.places), size);
  }

  void _moveTo(MapCamera camera) {
    setState(() {
      _camera = camera.clampedTo(widget.data.bounds);
    });
  }

  void zoomBy(double factor) {
    final camera = _camera;
    if (camera == null) return;
    _moveTo(
      camera.zoomedAt(
        Offset(_size.width / 2, _size.height / 2),
        factor,
        min: _minScale(_size),
        max: maxScale,
      ),
    );
  }

  /// Brings a place to the middle of the map without changing the zoom, for
  /// when it is chosen from the list rather than tapped on the map.
  void centreOn(Place place) {
    final camera = _camera;
    if (camera == null) return;
    _moveTo(camera.copyWith(centreLon: place.lon, centreLat: place.lat));
  }

  /// Back to the passage the map was opened for.
  void reset() {
    setState(() {
      _camera = MapCamera.fit(boxAround(widget.places), _size);
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = _camera;
    _gestureFocus = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final start = _gestureStart;
    final focus = _gestureFocus;
    if (start == null || focus == null) return;

    // Pinch first, about where the fingers landed, then drag.
    final zoomed = details.scale == 1
        ? start
        : start.zoomedAt(
            focus,
            details.scale,
            min: _minScale(start.size),
            max: maxScale,
          );
    final moved = details.localFocalPoint - focus;
    _moveTo(
      zoomed.copyWith(
        centreLon:
            zoomed.centreLon - moved.dx / (zoomed.squeeze * zoomed.scale),
        centreLat: zoomed.centreLat + moved.dy / zoomed.scale,
      ),
    );
  }

  void _zoomAt(Offset focus, double factor) {
    final camera = _camera;
    if (camera == null) return;
    _moveTo(
      camera.zoomedAt(
        focus,
        factor,
        min: _minScale(camera.size),
        max: maxScale,
      ),
    );
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final camera = _camera;
    if (camera == null) return;
    final factor = math.exp(-event.scrollDelta.dy / 320);
    _moveTo(
      camera.zoomedAt(
        event.localPosition,
        factor,
        min: _minScale(camera.size),
        max: maxScale,
      ),
    );
  }

  void _onTap(Offset position) {
    final pick = widget.onSelected;
    final camera = _camera;
    if (pick == null || camera == null) return;
    Place? nearest;
    var best = 30.0;
    for (final place in widget.places) {
      final distance =
          (camera.toOffset(place.lon, place.lat) - position).distance;
      if (distance < best) {
        best = distance;
        nearest = place;
      }
    }
    pick(nearest);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        final camera = _cameraFor(_size);
        // Assigning in build is normally a sin; here it is the camera catching
        // up with a canvas that has just changed size, which must not wait for
        // another frame.
        _camera = camera;

        return Listener(
          onPointerSignal: _onWheel,
          // The recognizers are named and ordered by hand. A tap has to be
          // able to win against the scale gesture that does the panning, and
          // which recognizer wins a pointer that never moved depends on the
          // order they were registered in; a plain GestureDetector picks that
          // order itself, and picks the one that loses the tap.
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (recognizer) {
                      recognizer.onTapUp = (details) {
                        _onTap(details.localPosition);
                      };
                    },
                  ),
              DoubleTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    DoubleTapGestureRecognizer
                  >(DoubleTapGestureRecognizer.new, (recognizer) {
                    recognizer.onDoubleTapDown = (details) {
                      _doubleTapAt = details.localPosition;
                    };
                    recognizer.onDoubleTap = () {
                      _zoomAt(
                        _doubleTapAt ??
                            Offset(_size.width / 2, _size.height / 2),
                        2,
                      );
                    };
                  }),
              ScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                    ScaleGestureRecognizer.new,
                    (recognizer) {
                      recognizer.onStart = _onScaleStart;
                      recognizer.onUpdate = _onScaleUpdate;
                    },
                  ),
            },
            child: CustomPaint(
              size: _size,
              painter: AtlasPainter(
                data: widget.data,
                places: widget.places,
                selected: widget.selected,
                camera: camera,
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
                modern: theme.colorScheme.onSurfaceVariant,
                built: theme.colorScheme.onSurface.withValues(alpha: 0.07),
                textDirection: Directionality.of(context),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AtlasPainter extends CustomPainter {
  AtlasPainter({
    required this.data,
    required this.places,
    required this.selected,
    required this.camera,
    required this.water,
    required this.land,
    required this.coast,
    required this.river,
    required this.marker,
    required this.label,
    required this.labelHalo,
    required this.modern,
    required this.built,
    required this.textDirection,
  });

  /// Below this many degrees across, the fine base map is worth its detail.
  static const double detailBelowDegrees = 14;

  /// And below this, the ground people live on now is worth drawing: the
  /// built-up areas and the towns, so that a close-up of an ancient site is
  /// not a blank page.
  static const double modernBelowDegrees = 2.2;

  final AtlasData data;
  final List<Place> places;
  final Place? selected;
  final MapCamera camera;
  final Color water;
  final Color land;
  final Color coast;
  final Color river;
  final Color marker;
  final Color label;
  final Color labelHalo;
  final Color modern;
  final Color built;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = camera.visible;
    final base = _baseFor(visible);

    canvas.drawRect(Offset.zero & size, Paint()..color = water);

    // Non-zero winding, not even-odd: clipping the coastline to the map
    // leaves rings that share the map's own edges, and even-odd would read
    // the overlap between two of them as a hole and paint land as sea.
    // Islands and inland seas are wound the other way and still come out as
    // holes.
    final landPath = _path(base.land, visible, close: true);
    canvas.drawPath(landPath, Paint()..color = land);
    canvas.drawPath(
      landPath,
      Paint()
        ..color = coast
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    canvas.drawPath(
      _path(base.lakes, visible, close: true),
      Paint()..color = water,
    );
    canvas.drawPath(
      _path(base.rivers, visible, close: false),
      Paint()
        ..color = river
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    if (visible.width <= modernBelowDegrees) {
      canvas.drawPath(
        _path(data.urban, visible, close: true),
        Paint()..color = built,
      );
      _paintTowns(canvas, size, visible);
    }

    _paintPlaces(canvas, size);
    _paintScale(canvas, size);
  }

  /// The fine map once the view is small enough for it to matter, and only
  /// where it has anything — outside that, the coarse one still covers.
  BaseMap _baseFor(GeoBox visible) {
    if (data.fine.isEmpty) return data.coarse;
    if (visible.width > detailBelowDegrees) return data.coarse;
    final detail = data.detail;
    final overlaps =
        visible.west <= detail.east &&
        visible.east >= detail.west &&
        visible.south <= detail.north &&
        visible.north >= detail.south;
    return overlaps ? data.fine : data.coarse;
  }

  Path _path(List<GeoRun> runs, GeoBox visible, {required bool close}) {
    final path = Path();
    for (final run in runs) {
      if (!run.intersects(
        visible.west,
        visible.south,
        visible.east,
        visible.north,
      )) {
        continue;
      }
      final points = run.points;
      if (points.length < 4) continue;
      var started = false;
      for (var i = 0; i < points.length; i += 2) {
        final point = camera.toOffset(points[i], points[i + 1]);
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

  /// The modern towns, under everything the passage is about. Smaller places
  /// appear as the map is zoomed further in, the way an atlas thins its
  /// lettering.
  void _paintTowns(Canvas canvas, Size size, GeoBox visible) {
    final limit = visible.width <= 0.35
        ? 12
        : visible.width <= 1.0
        ? 8
        : 5;
    final taken = <Rect>[];
    // A modern town that shares its name with a place of the passage would
    // only be drawn twice over, in two colours.
    final named = {for (final place in places) place.name.toLowerCase()};

    for (final town in data.towns) {
      if (town.rank > limit) continue;
      if (named.contains(town.name.toLowerCase())) continue;
      if (!visible.contains(town.lon, town.lat)) continue;
      final at = camera.toOffset(town.lon, town.lat);

      final painter = TextPainter(
        text: TextSpan(
          text: town.name,
          style: TextStyle(color: modern, fontSize: 10),
        ),
        textDirection: textDirection,
      )..layout();

      final spot =
          Offset(at.dx + 6, at.dy - painter.height / 2) &
          Size(painter.width, painter.height);
      if (spot.right > size.width ||
          spot.top < 0 ||
          spot.bottom > size.height) {
        continue;
      }
      if (taken.any(spot.inflate(2).overlaps)) continue;
      taken.add(spot);

      canvas.drawCircle(
        at,
        2.5,
        Paint()
          ..color = modern
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      painter.paint(canvas, spot.topLeft);
    }
  }

  void _paintPlaces(Canvas canvas, Size size) {
    // Markers and labels are drawn at a fixed size however far the map is
    // zoomed in, the way a map's lettering behaves rather than a photograph's.
    final taken = <Rect>[];
    final markers = <Place, Rect>{};
    final drawn = <Place, Offset>{};

    final ordered = [
      for (final place in places)
        if (place != selected) place,
      if (selected != null) selected!,
    ];

    for (final place in ordered) {
      final at = camera.toOffset(place.lon, place.lat);
      if (at.dx < -40 ||
          at.dy < -40 ||
          at.dx > size.width + 40 ||
          at.dy > size.height + 40) {
        continue;
      }
      final isSelected = place == selected;
      final radius = isSelected ? 7.0 : 4.0;
      drawn[place] = at;
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

  /// A bar in the corner saying how far it is across the map, which is the
  /// only way to tell one zoom level from another on empty ground.
  void _paintScale(Canvas canvas, Size size) {
    final metres = camera.metresPerPixel;
    if (!metres.isFinite || metres <= 0) return;

    // The roundest distance that fits in about a fifth of the width.
    final wanted = metres * size.width / 5;
    const steps = [
      1.0,
      2,
      5,
      10,
      25,
      50,
      100,
      250,
      500,
      1000,
      2000,
      5000,
      10000,
      25000,
      50000,
      100000,
      250000,
      500000,
      1000000,
      2000000,
    ];
    var distance = steps.last;
    for (final step in steps) {
      if (step >= wanted) {
        distance = step;
        break;
      }
    }

    final length = distance / metres;
    if (length < 20 || length > size.width - 40) return;
    final y = size.height - 16;
    final start = Offset(16, y);
    final end = Offset(16 + length, y);

    final line = Paint()
      ..color = label.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    canvas.drawLine(start, end, line);
    canvas.drawLine(start, start.translate(0, -5), line);
    canvas.drawLine(end, end.translate(0, -5), line);

    final text = distance >= 1000
        ? '${(distance / 1000).round()} km'
        : '${distance.round()} m';
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: label, fontSize: 11),
      ),
      textDirection: textDirection,
    )..layout();
    final at = Offset(16, y - 7 - painter.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (at & Size(painter.width, painter.height)).inflate(3),
        const Radius.circular(4),
      ),
      Paint()..color = labelHalo.withValues(alpha: 0.85),
    );
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(AtlasPainter old) =>
      old.places != places ||
      old.selected != selected ||
      old.camera != camera ||
      old.land != land ||
      old.data != data;
}
