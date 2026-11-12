import { describe, expect, it, vi } from 'vitest';

// The map's colours come from the Material kit, whose colour library does
// not load under Node; nothing tested here draws, so the kit is stood in
// for.
vi.mock('../src/ui/m3', () => ({
  currentScheme: () => ({}),
  hexOf: () => '#000000',
  rgba: () => 'rgb(0 0 0 / 1)',
}));

import { GeoBox, Place } from '../src/data/atlas';
import { AtlasPainter, MapCamera, boxAround, maxScale } from '../src/ui/widgets/atlasMap';

// The camera and the framing of `test/atlas_test.dart`; the asset's own
// tests are in atlas.test.ts, and the widget's gestures are tried in a
// browser rather than here.
describe('the camera', () => {
  const size = { width: 200, height: 200 };
  const box = new GeoBox(34, 31, 36, 33);

  it('frames what it is given, north upwards', () => {
    const camera = MapCamera.fit(box, size);

    expect(camera.toOffset(35, 33).y).toBeLessThan(camera.toOffset(35, 31).y);
    expect(camera.toOffset(34, 32).x).toBeLessThan(camera.toOffset(36, 32).x);

    const centre = camera.toOffset(35, 32);
    expect(Math.abs(centre.x - 100)).toBeLessThanOrEqual(0.5);
    expect(Math.abs(centre.y - 100)).toBeLessThanOrEqual(0.5);
  });

  it('longitude is squeezed by latitude, so shapes are not stretched', () => {
    const camera = MapCamera.fit(box, size);
    const degreeEast = camera.toOffset(36, 32).x - camera.toOffset(35, 32).x;
    const degreeNorth = camera.toOffset(35, 31).y - camera.toOffset(35, 32).y;

    expect(Math.abs(degreeEast / degreeNorth - 0.848)).toBeLessThanOrEqual(0.01);
  });

  it('a point on the canvas maps back to the ground it came from', () => {
    const camera = MapCamera.fit(box, size);
    const [lon, lat] = camera.toGround(camera.toOffset(35.4, 32.2));

    expect(lon).toBeCloseTo(35.4, 4);
    expect(lat).toBeCloseTo(32.2, 4);
  });

  it('zooming keeps the ground under the fingers where it was', () => {
    const camera = MapCamera.fit(box, size);
    const focus = { x: 40, y: 160 };
    const before = camera.toGround(focus);

    const zoomed = camera.zoomedAt(focus, 4, { min: 1, max: 1e6 });
    const after = zoomed.toGround(focus);

    expect(Math.abs(zoomed.scale - camera.scale * 4)).toBeLessThanOrEqual(0.001);
    expect(Math.abs(after[0] - before[0])).toBeLessThanOrEqual(0.0001);
    expect(Math.abs(after[1] - before[1])).toBeLessThanOrEqual(0.0001);
  });

  it('zoom stops at the limits it is given', () => {
    const camera = MapCamera.fit(box, size);
    const corner = { x: 0, y: 0 };

    expect(camera.zoomedAt(corner, 1000, { min: 1, max: camera.scale }).scale).toBe(camera.scale);
    expect(camera.zoomedAt(corner, 0.001, { min: camera.scale, max: 1e6 }).scale).toBe(camera.scale);
  });

  it('the middle of the map stays inside the atlas', () => {
    const camera = MapCamera.fit(box, size)
      .copyWith({ centreLon: 120, centreLat: 80 })
      .clampedTo(new GeoBox(30, 28, 40, 36));

    expect(camera.centreLon).toBe(40);
    expect(camera.centreLat).toBe(36);
  });

  it('two cameras looking at the same thing are the same camera', () => {
    const camera = MapCamera.fit(box, size);

    expect(camera.equals(camera.copyWith({}))).toBe(true);
    expect(camera.equals(camera.copyWith({ scale: camera.scale * 2 }))).toBe(false);
    expect(camera.equals(camera.copyWith({ size: { width: 201, height: 200 } }))).toBe(false);
  });

  it('says what ground it is showing, and how far a pixel goes', () => {
    const camera = MapCamera.fit(box, size, { padding: 1 });
    const visible = camera.visible;

    // Two degrees of latitude fill two hundred pixels.
    expect(camera.scale).toBeCloseTo(100, 6);
    expect(visible.south).toBeCloseTo(31, 6);
    expect(visible.north).toBeCloseTo(33, 6);
    expect(visible.centreLon).toBeCloseTo(35, 6);
    expect(camera.metresPerPixel).toBeCloseTo(1113.2, 3);
  });

  it('a lone place is given some of the world around it', () => {
    const around = boxAround([
      new Place({ name: 'Bethel', types: ['settlement'], lon: 35.22, lat: 31.93, confidence: 1000 }),
    ]);

    expect(around.width).toBeCloseTo(0.6, 6);
    expect(around.height).toBeCloseTo(0.6, 6);
    expect(Math.abs(around.centreLon - 35.22)).toBeLessThanOrEqual(0.001);
    expect(Math.abs(around.centreLat - 31.93)).toBeLessThanOrEqual(0.001);
  });

  it('places already far apart are framed as they are', () => {
    const around = boxAround([
      new Place({ name: 'Ur', types: ['settlement'], lon: 46.1, lat: 30.96, confidence: 900 }),
      new Place({ name: 'Haran', types: ['settlement'], lon: 39.03, lat: 36.86, confidence: 900 }),
    ]);

    expect(around.west).toBeCloseTo(39.03, 6);
    expect(around.east).toBeCloseTo(46.1, 6);
    expect(around.south).toBeCloseTo(30.96, 6);
    expect(around.north).toBeCloseTo(36.86, 6);
  });

  it('no places at all still frames somewhere', () => {
    const around = boxAround([]);

    expect([around.west, around.south, around.east, around.north]).toEqual([34, 31, 36, 33]);
  });
});

describe('the map', () => {
  it('zooms far enough in to read a street', () => {
    const camera = MapCamera.fit(new GeoBox(34, 31, 36, 33), { width: 300, height: 300 }).zoomedAt({ x: 150, y: 150 }, 1e9, {
      min: 1,
      max: maxScale,
    });

    expect(camera.scale).toBe(maxScale);
    expect(camera.metresPerPixel).toBeLessThan(1);
  });

  it('the fine base map is used only when it is worth its detail', () => {
    expect(AtlasPainter.detailBelowDegrees).toBeGreaterThan(1);
  });
});
