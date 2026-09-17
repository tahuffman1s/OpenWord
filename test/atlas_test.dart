import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openword/src/data/atlas.dart';
import 'package:openword/src/ui/widgets/atlas_map.dart';

import 'fixtures.dart';

void main() {
  group('reading the asset', () {
    test('places come back with their coordinates in degrees', () async {
      final data = await Atlas(bundle: FixtureBundle()).load();

      final bethel = data.places.first;
      expect(bethel.name, 'Bethel');
      expect(bethel.type, 'settlement');
      expect(bethel.lon, closeTo(35.22, 0.0005));
      expect(bethel.lat, closeTo(31.93, 0.0005));
      expect(bethel.isUncertain, isFalse);
    });

    test('a shaky identification says so', () async {
      final data = await Atlas(bundle: FixtureBundle()).load();

      expect(data.places[1].name, 'Ai');
      expect(data.places[1].isUncertain, isTrue);
    });

    test('chapters and books resolve to their places', () async {
      final data = await Atlas(bundle: FixtureBundle()).load();

      expect(data.inChapter('GEN', 1).map((p) => p.name), ['Bethel']);
      expect(data.inChapter('gen', 2).map((p) => p.name), ['Bethel', 'Ai']);
      expect(data.inChapter('GEN', 3), isEmpty);
      expect(data.inBook('GEN').map((p) => p.name), ['Bethel', 'Ai']);
      expect(data.inBook('EXO'), isEmpty);
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

  group('projection', () {
    test('fits the places it is given, north upwards', () {
      final bounds = const MapBounds(34, 31, 36, 33);
      final projection = MapProjection.fit(bounds, const Size(200, 200));

      final north = projection.toOffset(35, 33);
      final south = projection.toOffset(35, 31);
      expect(north.dy, lessThan(south.dy));

      final west = projection.toOffset(34, 32);
      final east = projection.toOffset(36, 32);
      expect(west.dx, lessThan(east.dx));

      // The centre of the ground lands in the centre of the canvas.
      final centre = projection.toOffset(35, 32);
      expect(centre.dx, closeTo(100, 0.5));
      expect(centre.dy, closeTo(100, 0.5));
    });

    test('longitude is squeezed by latitude, so shapes are not stretched', () {
      final projection = MapProjection.fit(
        const MapBounds(34, 31, 36, 33),
        const Size(400, 400),
      );

      // A degree of longitude at 32°N is about cos(32°) of a degree of
      // latitude on the ground, and should be drawn that way.
      expect(projection.scaleX / projection.scaleY, closeTo(0.848, 0.01));
    });

    test('one place is given a sensible amount of the world around it', () {
      final bounds = MapBounds.around(const [
        Place(
          name: 'Bethel',
          type: 'settlement',
          lon: 35.22,
          lat: 31.93,
          confidence: 1000,
        ),
      ]);

      expect(bounds.width, greaterThanOrEqualTo(MapBounds.minimumSpan));
      expect(bounds.height, greaterThanOrEqualTo(MapBounds.minimumSpan));
      expect(bounds.centreLon, closeTo(35.22, 0.001));
      expect(bounds.centreLat, closeTo(31.93, 0.001));
    });

    test('a group of places is framed with room around it', () {
      final bounds = MapBounds.around(const [
        Place(
          name: 'West',
          type: 'settlement',
          lon: 30,
          lat: 31,
          confidence: 1000,
        ),
        Place(
          name: 'East',
          type: 'settlement',
          lon: 40,
          lat: 35,
          confidence: 1000,
        ),
      ]);

      expect(bounds.west, lessThan(30));
      expect(bounds.east, greaterThan(40));
      expect(bounds.south, lessThan(31));
      expect(bounds.north, greaterThan(35));
    });
  });

  testWidgets('the map draws, and a marker can be picked', (tester) async {
    final data = await Atlas(bundle: FixtureBundle()).load();
    final places = data.inChapter('GEN', 2);
    Place? picked;
    var picks = 0;

    const size = Size(300, 300);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: AtlasMap(
              data: data,
              places: places,
              onSelected: (place) {
                picked = place;
                picks++;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);

    final map = tester.getRect(find.byType(AtlasMap));
    final projection = MapProjection.fit(MapBounds.around(places), size);
    final bethel = places.firstWhere((place) => place.name == 'Bethel');

    await tester.tapAt(
      map.topLeft + projection.toOffset(bethel.lon, bethel.lat),
    );
    await tester.pump();
    expect(picked?.name, 'Bethel');

    // A tap in the empty corner of the map clears the selection rather than
    // picking whatever happens to be nearest.
    await tester.tapAt(map.topLeft + const Offset(4, 4));
    await tester.pump();
    expect(picked, isNull);
    expect(picks, 2);
  });
}
