import { gzipSync } from 'fflate';
import { describe, expect, it } from 'vitest';
import { Atlas, type AtlasData, GeoBox, GeoRun, Place } from '../src/data/atlas';
import { FixtureBundle } from './fixtures';
import { FsAssetBundle } from './fsAssets';

const load = (): Promise<AtlasData> => new Atlas(new FixtureBundle()).load();

describe('reading the asset', () => {
  it('places come back with everything known about them', async () => {
    const data = await load();

    const bethel = data.places[0];
    expect(bethel.name).toBe('Bethel');
    expect(bethel.types).toEqual(['settlement']);
    expect(bethel.lon).toBeCloseTo(35.22, 3);
    expect(bethel.lat).toBeCloseTo(31.93, 3);
    expect(bethel.isUncertain).toBe(false);
    expect(bethel.modern).toBe('Beitin');
    expect(bethel.otherNames).toEqual(['Beth-el', 'Luz']);
    expect(bethel.comment).toContain('north of Jerusalem');
    expect(bethel.verseCount).toBe(71);
    expect(bethel.type).toBe('settlement');
  });

  it('a shaky identification says so', async () => {
    const data = await load();

    expect(data.places[1].name).toBe('Ai');
    expect(data.places[1].isUncertain).toBe(true);
    expect(data.places[1].types).toEqual(['settlement', 'ruin']);
    expect(data.places[1].otherNames).toEqual([]);
  });

  it('a chapter knows which verses name each place', async () => {
    const data = await load();

    const first = data.inChapter('GEN', 1);
    expect(first.map((named) => named.place.name)).toEqual(['Bethel']);
    expect(first[0].verses).toEqual([1]);

    const second = data.inChapter('gen', 2);
    expect(second.map((named) => named.place.name)).toEqual(['Bethel', 'Ai']);
    expect(second[0].verses).toEqual([2, 5]);
    expect(second[1].verses).toEqual([5]);

    expect(data.inChapter('GEN', 3)).toEqual([]);
  });

  it('a book gathers its places without repeating them', async () => {
    const data = await load();

    expect(data.inBook('GEN').map((place) => place.name)).toEqual(['Ai', 'Bethel']);
    expect(data.inBook('EXO')).toEqual([]);
  });

  it('both levels of the base map are read', async () => {
    const data = await load();

    expect(data.coarse.land).toHaveLength(1);
    expect(data.coarse.rivers).toHaveLength(1);
    expect(data.fine.land).toHaveLength(1);
    expect(data.detail.west).toBeCloseTo(34, 3);
    expect(data.bounds.width).toBeCloseTo(10, 3);
  });

  it('the modern ground is read too', async () => {
    const data = await load();

    expect(data.urban).toHaveLength(1);
    expect(data.towns.map((town) => town.name)).toEqual(['Jerusalem', 'Beitin']);
    expect(data.towns[0].rank).toBe(0);
    expect(data.towns[0].lat).toBeCloseTo(31.768, 3);
  });

  it('a run knows the box it lives in, for culling', async () => {
    const data = await load();

    const coast = data.coarse.land[0];
    expect(coast.west).toBeCloseTo(34, 3);
    expect(coast.east).toBeCloseTo(36, 3);
    expect(coast.intersects(35, 32, 35.5, 32.5)).toBe(true);
    expect(coast.intersects(40, 40, 41, 41)).toBe(false);
  });

  it('the asset is read once, then kept', async () => {
    const bundle = new FixtureBundle();
    const atlas = new Atlas(bundle);

    expect(atlas.data).toBeNull();
    await Promise.all([atlas.load(), atlas.load()]);
    await atlas.load();

    expect(atlas.data).not.toBeNull();
    expect(bundle.loaded.filter((key) => key === Atlas.assetPath)).toHaveLength(1);
  });

  it('a missing or unreadable asset leaves the map out', async () => {
    const missing = new Atlas(new FixtureBundle({ assets: new Map() }));
    expect((await missing.load()).isEmpty).toBe(true);

    const rubbish = new Atlas(
      new FixtureBundle({
        assets: new Map([[Atlas.assetPath, gzipSync(new TextEncoder().encode('"not an atlas"'))]]),
      }),
    );
    expect((await rubbish.load()).isEmpty).toBe(true);

    const misshapen = new Atlas(
      new FixtureBundle({
        assets: new Map([[Atlas.assetPath, gzipSync(new TextEncoder().encode('{"places":[["Bethel"]]}'))]]),
      }),
    );
    expect((await misshapen.load()).isEmpty).toBe(true);
  });
});

describe('the geometry', () => {
  it('a box knows its size and middle', () => {
    const box = new GeoBox(34, 31, 36, 33);
    expect(box.width).toBe(2);
    expect(box.height).toBe(2);
    expect(box.centreLon).toBe(35);
    expect(box.centreLat).toBe(32);
    expect(box.contains(35, 32)).toBe(true);
    expect(box.contains(37, 32)).toBe(false);
    expect(GeoBox.empty.width).toBe(0);
  });

  it('an empty run has an inside-out box, which intersects nothing', () => {
    const run = new GeoRun(new Float32Array(0));
    expect(run.west).toBe(Number.POSITIVE_INFINITY);
    expect(run.east).toBe(Number.NEGATIVE_INFINITY);
    expect(run.intersects(-180, -90, 180, 90)).toBe(false);
  });

  it('a place with no type is just a place', () => {
    const place = new Place({ name: 'Somewhere', types: [], lon: 0, lat: 0, confidence: 1000 });
    expect(place.type).toBe('place');
    expect(place.modern).toBe('');
    expect(place.verseCount).toBe(0);
  });
});

describe('the asset that ships', () => {
  it('names Jerusalem and knows the chapters that name it', async () => {
    const atlas = new Atlas(new FsAssetBundle());
    const data = await atlas.load();

    expect(data.isEmpty).toBe(false);
    expect(data.places.length).toBeGreaterThan(1000);
    const jerusalem = data.places.find((place) => place.name === 'Jerusalem');
    expect(jerusalem).toBeDefined();
    expect(jerusalem!.lat).toBeCloseTo(31.78, 1);
    expect(jerusalem!.lon).toBeCloseTo(35.22, 1);
    expect(jerusalem!.verseCount).toBeGreaterThan(100);

    // 2 Samuel 5 is where David takes the city.
    expect(data.inChapter('2SA', 5).some((named) => named.place.name === 'Jerusalem')).toBe(true);
    expect(data.inBook('2SA').some((place) => place.name === 'Jerusalem')).toBe(true);

    expect(data.coarse.isEmpty).toBe(false);
    expect(data.fine.isEmpty).toBe(false);
    expect(data.towns.length).toBeGreaterThan(0);
    expect(data.bounds.contains(jerusalem!.lon, jerusalem!.lat)).toBe(true);
  });
});
