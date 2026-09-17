import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/atlas.dart';
import 'package:openword/src/ui/widgets/atlas_map.dart';

import 'fixtures.dart';

Future<AtlasData> load() => Atlas(bundle: FixtureBundle()).load();

void main() {
  group('reading the asset', () {
    test('places come back with everything known about them', () async {
      final data = await load();

      final bethel = data.places.first;
      expect(bethel.name, 'Bethel');
      expect(bethel.types, ['settlement']);
      expect(bethel.lon, closeTo(35.22, 0.0005));
      expect(bethel.lat, closeTo(31.93, 0.0005));
      expect(bethel.isUncertain, isFalse);
      expect(bethel.modern, 'Beitin');
      expect(bethel.otherNames, ['Beth-el', 'Luz']);
      expect(bethel.comment, contains('north of Jerusalem'));
      expect(bethel.verseCount, 71);
    });

    test('a shaky identification says so', () async {
      final data = await load();

      expect(data.places[1].name, 'Ai');
      expect(data.places[1].isUncertain, isTrue);
      expect(data.places[1].types, ['settlement', 'ruin']);
      expect(data.places[1].otherNames, isEmpty);
    });

    test('a chapter knows which verses name each place', () async {
      final data = await load();

      final first = data.inChapter('GEN', 1);
      expect(first.map((named) => named.place.name), ['Bethel']);
      expect(first.single.verses, [1]);

      final second = data.inChapter('gen', 2);
      expect(second.map((named) => named.place.name), ['Bethel', 'Ai']);
      expect(second.first.verses, [2, 5]);
      expect(second.last.verses, [5]);

      expect(data.inChapter('GEN', 3), isEmpty);
    });

    test('a book gathers its places without repeating them', () async {
      final data = await load();

      expect(data.inBook('GEN').map((place) => place.name), ['Ai', 'Bethel']);
      expect(data.inBook('EXO'), isEmpty);
    });

    test('both levels of the base map are read', () async {
      final data = await load();

      expect(data.coarse.land, hasLength(1));
      expect(data.coarse.rivers, hasLength(1));
      expect(data.fine.land, hasLength(1));
      expect(data.detail.west, closeTo(34, 0.001));
      expect(data.bounds.width, closeTo(10, 0.001));
    });

    test('the modern ground is read too', () async {
      final data = await load();

      expect(data.urban, hasLength(1));
      expect(data.towns.map((town) => town.name), ['Jerusalem', 'Beitin']);
      expect(data.towns.first.rank, 0);
      expect(data.towns.first.lat, closeTo(31.768, 0.0005));
    });

    test('a run knows the box it lives in, for culling', () async {
      final data = await load();

      final coast = data.coarse.land.single;
      expect(coast.west, closeTo(34, 0.001));
      expect(coast.east, closeTo(36, 0.001));
      expect(coast.intersects(35, 32, 35.5, 32.5), isTrue);
      expect(coast.intersects(40, 40, 41, 41), isFalse);
    });

    test('the asset is read once, then kept', () async {
      final bundle = FixtureBundle();
      final atlas = Atlas(bundle: bundle);

      expect(atlas.data, isNull);
      await Future.wait([atlas.load(), atlas.load()]);
      await atlas.load();

      expect(atlas.data, isNotNull);
      expect(bundle.loaded.where((key) => key == Atlas.assetPath).length, 1);
    });

    test('a missing or unreadable asset leaves the map out', () async {
      final missing = Atlas(bundle: FixtureBundle(assets: const {}));
      expect((await missing.load()).isEmpty, isTrue);

      final rubbish = Atlas(
        bundle: FixtureBundle(
          assets: {
            Atlas.assetPath: Uint8List.fromList(
              gzip.encode(utf8.encode('"not an atlas"')),
            ),
          },
        ),
      );
      expect((await rubbish.load()).isEmpty, isTrue);
    });
  });

  group('the camera', () {
    const size = Size(200, 200);
    const box = GeoBox(34, 31, 36, 33);

    test('frames what it is given, north upwards', () {
      final camera = MapCamera.fit(box, size);

      expect(camera.toOffset(35, 33).dy, lessThan(camera.toOffset(35, 31).dy));
      expect(camera.toOffset(34, 32).dx, lessThan(camera.toOffset(36, 32).dx));

      final centre = camera.toOffset(35, 32);
      expect(centre.dx, closeTo(100, 0.5));
      expect(centre.dy, closeTo(100, 0.5));
    });

    test('longitude is squeezed by latitude, so shapes are not stretched', () {
      final camera = MapCamera.fit(box, size);
      final degreeEast =
          camera.toOffset(36, 32).dx - camera.toOffset(35, 32).dx;
      final degreeNorth =
          camera.toOffset(35, 31).dy - camera.toOffset(35, 32).dy;

      expect(degreeEast / degreeNorth, closeTo(0.848, 0.01));
    });

    test('a point on the canvas maps back to the ground it came from', () {
      final camera = MapCamera.fit(box, size);
      final (lon, lat) = camera.toGround(camera.toOffset(35.4, 32.2));

      expect(lon, closeTo(35.4, 0.0001));
      expect(lat, closeTo(32.2, 0.0001));
    });

    test('zooming keeps the ground under the fingers where it was', () {
      final camera = MapCamera.fit(box, size);
      const focus = Offset(40, 160);
      final before = camera.toGround(focus);

      final zoomed = camera.zoomedAt(focus, 4, min: 1, max: 1e6);
      final after = zoomed.toGround(focus);

      expect(zoomed.scale, closeTo(camera.scale * 4, 0.001));
      expect(after.$1, closeTo(before.$1, 0.0001));
      expect(after.$2, closeTo(before.$2, 0.0001));
    });

    test('zoom stops at the limits it is given', () {
      final camera = MapCamera.fit(box, size);

      expect(
        camera.zoomedAt(Offset.zero, 1000, min: 1, max: camera.scale).scale,
        camera.scale,
      );
      expect(
        camera.zoomedAt(Offset.zero, 0.001, min: camera.scale, max: 1e6).scale,
        camera.scale,
      );
    });

    test('the middle of the map stays inside the atlas', () {
      final camera = MapCamera.fit(box, size)
          .copyWith(centreLon: 120, centreLat: 80)
          .clampedTo(const GeoBox(30, 28, 40, 36));

      expect(camera.centreLon, 40);
      expect(camera.centreLat, 36);
    });

    test('a lone place is given some of the world around it', () {
      final box = boxAround(const [
        Place(
          name: 'Bethel',
          types: ['settlement'],
          lon: 35.22,
          lat: 31.93,
          confidence: 1000,
        ),
      ]);

      expect(box.width, closeTo(0.6, 1e-6));
      expect(box.height, closeTo(0.6, 1e-6));
      expect(box.centreLon, closeTo(35.22, 0.001));
      expect(box.centreLat, closeTo(31.93, 0.001));
    });
  });

  group('the map', () {
    Future<List<Place>> pumpMap(
      WidgetTester tester, {
      required void Function(Place?) onSelected,
      Size size = const Size(300, 300),
      GlobalKey<AtlasMapState>? key,
    }) async {
      final data = await load();
      final places = [
        for (final named in data.inChapter('GEN', 2)) named.place,
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: AtlasMap(
                key: key,
                data: data,
                places: places,
                onSelected: onSelected,
              ),
            ),
          ),
        ),
      );
      return places;
    }

    testWidgets('draws, and a marker can be picked', (tester) async {
      Place? picked;
      var picks = 0;
      final key = GlobalKey<AtlasMapState>();
      final places = await pumpMap(
        tester,
        key: key,
        onSelected: (place) {
          picked = place;
          picks++;
        },
      );

      expect(find.byType(CustomPaint), findsWidgets);

      final map = tester.getRect(find.byType(AtlasMap));
      final camera = key.currentState!.camera!;
      final bethel = places.firstWhere((place) => place.name == 'Bethel');

      await tester.tapAt(map.topLeft + camera.toOffset(bethel.lon, bethel.lat));
      // A tap counts as a tap once it is clear it was not the first half of
      // a double tap, so it lands after the double-tap window.
      await tester.pump(const Duration(milliseconds: 400));
      expect(picked?.name, 'Bethel');

      // A tap in the empty corner clears the selection rather than picking
      // whatever happens to be nearest.
      await tester.tapAt(map.topLeft + const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 400));
      expect(picked, isNull);
      expect(picks, 2);
    });

    testWidgets('drags the map without picking anything', (tester) async {
      Place? picked;
      final key = GlobalKey<AtlasMapState>();
      await pumpMap(tester, key: key, onSelected: (place) => picked = place);

      final before = key.currentState!.camera!;
      await tester.drag(find.byType(AtlasMap), const Offset(-60, 0));
      await tester.pumpAndSettle();
      final after = key.currentState!.camera!;

      // Dragging west moves the ground under the map east.
      expect(after.centreLon, greaterThan(before.centreLon));
      expect(after.scale, before.scale);
      expect(picked, isNull);
    });

    testWidgets('a double tap zooms in where it lands', (tester) async {
      final key = GlobalKey<AtlasMapState>();
      await pumpMap(tester, key: key, onSelected: (_) {});

      final before = key.currentState!.camera!;
      final at = tester.getCenter(find.byType(AtlasMap)) + const Offset(30, 20);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      final after = key.currentState!.camera!;
      expect(after.scale, closeTo(before.scale * 2, 0.01));
    });

    testWidgets('two slow taps are two taps, not a zoom', (tester) async {
      final key = GlobalKey<AtlasMapState>();
      await pumpMap(tester, key: key, onSelected: (_) {});

      final before = key.currentState!.camera!;
      final at = tester.getCenter(find.byType(AtlasMap));
      await tester.tapAt(at);
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(key.currentState!.camera!.scale, before.scale);
    });

    testWidgets('a place can be brought to the middle', (tester) async {
      final key = GlobalKey<AtlasMapState>();
      final places = await pumpMap(tester, key: key, onSelected: (_) {});
      final ai = places.firstWhere((place) => place.name == 'Ai');

      final before = key.currentState!.camera!;
      key.currentState!.centreOn(ai);
      await tester.pump();
      final after = key.currentState!.camera!;

      expect(after.centreLon, closeTo(ai.lon, 0.0001));
      expect(after.centreLat, closeTo(ai.lat, 0.0001));
      expect(after.scale, before.scale, reason: 'the zoom is left alone');
    });

    testWidgets('zooms in and out, and back to the passage', (tester) async {
      final key = GlobalKey<AtlasMapState>();
      await pumpMap(tester, key: key, onSelected: (_) {});

      final fitted = key.currentState!.camera!.scale;

      key.currentState!.zoomBy(4);
      await tester.pump();
      expect(key.currentState!.camera!.scale, closeTo(fitted * 4, 0.01));

      key.currentState!.zoomBy(1 / 8);
      await tester.pump();
      expect(key.currentState!.camera!.scale, lessThan(fitted));

      key.currentState!.reset();
      await tester.pump();
      expect(key.currentState!.camera!.scale, closeTo(fitted, 0.01));
    });

    testWidgets('will not zoom out past the ground it has', (tester) async {
      final key = GlobalKey<AtlasMapState>();
      await pumpMap(tester, key: key, onSelected: (_) {});
      final data = await load();

      key.currentState!.zoomBy(1 / 10000);
      await tester.pump();

      // The whole atlas fits on the canvas, and no further out than that.
      final camera = key.currentState!.camera!;
      expect(
        camera.visible.width,
        greaterThanOrEqualTo(data.bounds.width - 0.01),
      );
      expect(camera.visible.width, lessThan(data.bounds.width * 3));
    });

    testWidgets('zooms far enough in to read a street', (tester) async {
      final key = GlobalKey<AtlasMapState>();
      await pumpMap(tester, key: key, onSelected: (_) {});

      key.currentState!.zoomBy(1e9);
      await tester.pump();

      final camera = key.currentState!.camera!;
      expect(camera.scale, AtlasMapState.maxScale);
      expect(camera.metresPerPixel, lessThan(1));
    });
  });

  test('the fine base map is used only when it is worth its detail', () {
    expect(AtlasPainter.detailBelowDegrees, greaterThan(1));
  });
}
