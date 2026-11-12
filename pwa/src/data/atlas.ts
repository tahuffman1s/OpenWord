import { gunzipIfNeeded } from '../infra/gunzip';
import { type AssetBundle, rootBundle } from '../infra/assets';
import { FormatException, utf8 } from '../model/byteIo';
import { compareCodeUnits } from '../model/searchIndex';

/**
 * Where the places named in the text are, what is known about them, and
 * enough coastline, lake and river to recognise them by.
 *
 * Read on demand and kept afterwards: it is only wanted when someone opens
 * the map for a chapter.
 */
export class Atlas {
  constructor(bundle?: AssetBundle) {
    this.bundle = bundle ?? rootBundle;
  }

  static readonly assetName = 'atlas.json.gz';
  static readonly assetPath = `assets/maps/${Atlas.assetName}`;

  /** Shown on the map and in Settings, as both licences require. */
  static readonly attribution =
    'Place locations from OpenBible.info Bible Geocoding, CC BY 4.0. Base map from Natural Earth, public domain.';

  /**
   * The size above which decoding would be worth a worker of its own.
   * Nothing uses it yet: the asset is decoded inline whatever its size,
   * and the threshold is kept for whoever adds a worker.
   */
  static readonly isolateAbove = 64 * 1024;

  private readonly bundle: AssetBundle;
  private _data: AtlasData | null = null;
  private loading: Promise<AtlasData> | null = null;

  get data(): AtlasData | null {
    return this._data;
  }

  load(): Promise<AtlasData> {
    const loaded = this._data;
    if (loaded !== null) return Promise.resolve(loaded);
    return (this.loading ??= this.read().then((data) => {
      this._data = data;
      return data;
    }));
  }

  private async read(): Promise<AtlasData> {
    try {
      const bytes = await this.bundle.load(Atlas.assetPath);
      // A megabyte and a half of JSON is a lot to unpack on the thread
      // that is drawing. It is decoded inline all the same, and a caller
      // that wants a worker imports `decodeAtlas` from one.
      return decodeAtlas(bytes);
    } catch (error) {
      console.warn(`OpenWord: could not read the atlas: ${error}`);
      return AtlasData.empty;
    }
  }
}

/** Unpacks the asset. Top-level and free of the DOM, so a worker can import it. */
export function decodeAtlas(bytes: Uint8Array): AtlasData {
  const raw = gunzipIfNeeded(bytes);
  const decoded: unknown = JSON.parse(utf8.decode(raw));
  if (!isRecord(decoded)) return AtlasData.empty;
  return AtlasData.fromJson(decoded);
}

/** A place named in the text, at the location its identification favours. */
export class Place {
  readonly name: string;

  /** settlement, region, mountain, river and so on, as the source classes it. */
  readonly types: readonly string[];

  readonly lon: number;
  readonly lat: number;

  /**
   * How sure the identification is, 0–1000 as the source scores it. Below
   * `uncertain` the map says so rather than pretending.
   */
  readonly confidence: number;

  /** The modern place it is identified with, where the source names one. */
  readonly modern: string;

  /** What translations call it, where they differ from `name`. */
  readonly otherNames: readonly string[];

  /**
   * The source's own note: what it is near, which of two places it is, and
   * so on.
   */
  readonly comment: string;

  /** How many verses name it in the whole Bible. */
  readonly verseCount: number;

  constructor(init: {
    name: string;
    types: readonly string[];
    lon: number;
    lat: number;
    confidence: number;
    modern?: string;
    otherNames?: readonly string[];
    comment?: string;
    verseCount?: number;
  }) {
    this.name = init.name;
    this.types = init.types;
    this.lon = init.lon;
    this.lat = init.lat;
    this.confidence = init.confidence;
    this.modern = init.modern ?? '';
    this.otherNames = init.otherNames ?? [];
    this.comment = init.comment ?? '';
    this.verseCount = init.verseCount ?? 0;
  }

  static readonly uncertain = 500;

  get isUncertain(): boolean {
    return this.confidence < Place.uncertain;
  }

  get type(): string {
    return this.types.length === 0 ? 'place' : this.types[0];
  }
}

/** A place as a chapter names it: which verses of that chapter mention it. */
export class ChapterPlace {
  readonly place: Place;

  /** Verse numbers within the chapter, in order. */
  readonly verses: readonly number[];

  constructor(init: { place: Place; verses: readonly number[] }) {
    this.place = init.place;
    this.verses = init.verses;
  }
}

/**
 * A run of coastline, lake shore or river, with the box it lives in so that
 * the map can skip what is off screen without walking every point.
 */
export class GeoRun {
  /** Longitude and latitude in turn: `[lon, lat, lon, lat, …]`. */
  readonly points: Float32Array;

  readonly west: number;
  readonly east: number;
  readonly south: number;
  readonly north: number;

  constructor(points: Float32Array) {
    this.points = points;
    this.west = GeoRun.min(points, 0);
    this.east = GeoRun.max(points, 0);
    this.south = GeoRun.min(points, 1);
    this.north = GeoRun.max(points, 1);
  }

  intersects(w: number, s: number, e: number, n: number): boolean {
    return this.west <= e && this.east >= w && this.south <= n && this.north >= s;
  }

  private static min(points: Float32Array, offset: number): number {
    let value = Number.POSITIVE_INFINITY;
    for (let i = offset; i < points.length; i += 2) {
      if (points[i] < value) value = points[i];
    }
    return value;
  }

  private static max(points: Float32Array, offset: number): number {
    let value = Number.NEGATIVE_INFINITY;
    for (let i = offset; i < points.length; i += 2) {
      if (points[i] > value) value = points[i];
    }
    return value;
  }
}

/**
 * A town that is there now, drawn once the map is zoomed in far enough for
 * the ancient site to need somewhere to sit.
 */
export class Town {
  readonly name: string;
  readonly lon: number;
  readonly lat: number;

  /** Natural Earth's own ranking: 0 for a capital, higher for smaller places. */
  readonly rank: number;

  constructor(init: { name: string; lon: number; lat: number; rank: number }) {
    this.name = init.name;
    this.lon = init.lon;
    this.lat = init.lat;
    this.rank = init.rank;
  }
}

/** One level of the base map: the shapes drawn at a given range of zoom. */
export class BaseMap {
  readonly land: readonly GeoRun[];
  readonly lakes: readonly GeoRun[];
  readonly rivers: readonly GeoRun[];

  constructor(init: { land: readonly GeoRun[]; lakes: readonly GeoRun[]; rivers: readonly GeoRun[] }) {
    this.land = init.land;
    this.lakes = init.lakes;
    this.rivers = init.rivers;
  }

  static readonly empty = new BaseMap({ land: [], lakes: [], rivers: [] });

  get isEmpty(): boolean {
    return this.land.length === 0 && this.lakes.length === 0 && this.rivers.length === 0;
  }
}

/** A rectangle of the world, in degrees. */
export class GeoBox {
  constructor(
    readonly west: number,
    readonly south: number,
    readonly east: number,
    readonly north: number,
  ) {}

  static readonly empty = new GeoBox(0, 0, 0, 0);

  get width(): number {
    return this.east - this.west;
  }

  get height(): number {
    return this.north - this.south;
  }

  get centreLon(): number {
    return (this.west + this.east) / 2;
  }

  get centreLat(): number {
    return (this.south + this.north) / 2;
  }

  contains(lon: number, lat: number): boolean {
    return lon >= this.west && lon <= this.east && lat >= this.south && lat <= this.north;
  }
}

export class AtlasData {
  readonly places: readonly Place[];

  /** `GEN 12` to the places that chapter names, with their verses. */
  readonly chapters: ReadonlyMap<string, readonly ChapterPlace[]>;

  /** The whole region, drawn when zoomed out. */
  readonly coarse: BaseMap;

  /**
   * Ten times the detail over the ground the Bible actually covers, drawn
   * once the reader zooms in past a country or two.
   */
  readonly fine: BaseMap;

  /** Where people live now, for the close-up view. */
  readonly urban: readonly GeoRun[];

  /** The towns that are there now, biggest first. */
  readonly towns: readonly Town[];

  /** Everything the coarse map covers, and so how far out the map can zoom. */
  readonly bounds: GeoBox;

  /** Where `fine` has anything to say. */
  readonly detail: GeoBox;

  constructor(init: {
    places: readonly Place[];
    chapters: ReadonlyMap<string, readonly ChapterPlace[]>;
    coarse: BaseMap;
    fine: BaseMap;
    urban: readonly GeoRun[];
    towns: readonly Town[];
    bounds: GeoBox;
    detail: GeoBox;
  }) {
    this.places = init.places;
    this.chapters = init.chapters;
    this.coarse = init.coarse;
    this.fine = init.fine;
    this.urban = init.urban;
    this.towns = init.towns;
    this.bounds = init.bounds;
    this.detail = init.detail;
  }

  static readonly empty = new AtlasData({
    places: [],
    chapters: new Map(),
    coarse: BaseMap.empty,
    fine: BaseMap.empty,
    urban: [],
    towns: [],
    bounds: GeoBox.empty,
    detail: GeoBox.empty,
  });

  get isEmpty(): boolean {
    return this.places.length === 0;
  }

  /** The places named in a chapter, with the verses naming them. */
  inChapter(bookCode: string, chapter: number): readonly ChapterPlace[] {
    return this.chapters.get(`${bookCode.toUpperCase()} ${chapter}`) ?? [];
  }

  /** Every place named anywhere in a book. */
  inBook(bookCode: string): Place[] {
    const code = bookCode.toUpperCase();
    const seen = new Set<Place>();
    for (const [key, named] of this.chapters) {
      if (!key.startsWith(`${code} `)) continue;
      for (const entry of named) {
        seen.add(entry.place);
      }
    }
    return [...seen].sort((a, b) => compareCodeUnits(a.name, b.name));
  }

  static fromJson(json: Record<string, unknown>): AtlasData {
    // Coordinates are stored as whole thousandths of a degree.
    const scale = 1000.0;

    const run = (raw: unknown): GeoRun => {
      const numbers = asList(raw);
      const points = new Float32Array(numbers.length);
      for (let i = 0; i < numbers.length; i++) {
        points[i] = asNum(numbers[i]) / scale;
      }
      return new GeoRun(points);
    };

    const runs = (raw: unknown): GeoRun[] => (raw == null ? [] : asList(raw).map(run));

    const box = (raw: unknown, fallback: GeoBox): GeoBox => {
      const numbers = raw == null ? [] : asList(raw);
      if (numbers.length !== 4) return fallback;
      return new GeoBox(
        asNum(numbers[0]) / scale,
        asNum(numbers[1]) / scale,
        asNum(numbers[2]) / scale,
        asNum(numbers[3]) / scale,
      );
    };

    const split = (raw: unknown): string[] => {
      const text = raw == null ? '' : asString(raw);
      if (text.length === 0) return [];
      return text.split('|');
    };

    const places: Place[] = [];
    for (const raw of json.places == null ? [] : asList(json.places)) {
      const fields = asList(raw);
      places.push(
        new Place({
          name: asString(fields[0]),
          types: split(fields[1]),
          lon: asNum(fields[2]) / scale,
          lat: asNum(fields[3]) / scale,
          confidence: Math.trunc(asNum(fields[4])),
          modern: fields.length > 5 ? (fields[5] == null ? '' : asString(fields[5])) : '',
          otherNames: fields.length > 6 ? split(fields[6]) : [],
          comment: fields.length > 7 ? (fields[7] == null ? '' : asString(fields[7])) : '',
          verseCount: fields.length > 8 ? (fields[8] == null ? 0 : Math.trunc(asNum(fields[8]))) : 0,
        }),
      );
    }

    const chapters = new Map<string, ChapterPlace[]>();
    const rawChapters = json.chapters == null ? {} : asRecord(json.chapters);
    for (const [key, value] of Object.entries(rawChapters)) {
      const named: ChapterPlace[] = [];
      for (const raw of asList(value)) {
        // [place index, verse, verse, …]
        const fields = asList(raw);
        if (fields.length === 0) continue;
        const index = Math.trunc(asNum(fields[0]));
        if (index < 0 || index >= places.length) continue;
        named.push(
          new ChapterPlace({
            place: places[index],
            verses: fields.slice(1).map((verse) => Math.trunc(asNum(verse))),
          }),
        );
      }
      chapters.set(key, named);
    }

    const bounds = box(json.bounds, GeoBox.empty);
    const towns: Town[] = [];
    for (const raw of json.towns == null ? [] : asList(json.towns)) {
      if (Array.isArray(raw) && raw.length >= 4) {
        towns.push(
          new Town({
            name: asString(raw[3]),
            lon: asNum(raw[0]) / scale,
            lat: asNum(raw[1]) / scale,
            rank: Math.trunc(asNum(raw[2])),
          }),
        );
      }
    }
    return new AtlasData({
      places,
      chapters,
      coarse: new BaseMap({
        land: runs(json.land),
        lakes: runs(json.lakes),
        rivers: runs(json.rivers),
      }),
      fine: new BaseMap({
        land: runs(json.fineLand),
        lakes: runs(json.fineLakes),
        rivers: runs(json.fineRivers),
      }),
      urban: runs(json.urban),
      towns,
      bounds,
      detail: box(json.detail, bounds),
    });
  }
}

// These throw on the wrong shape, and the loader turns that into an empty
// atlas rather than a half-read one.

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function asRecord(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) throw new FormatException('the atlas is not shaped as expected');
  return value;
}

function asList(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw new FormatException('the atlas is not shaped as expected');
  return value;
}

function asNum(value: unknown): number {
  if (typeof value !== 'number') throw new FormatException('the atlas is not shaped as expected');
  return value;
}

function asString(value: unknown): string {
  if (typeof value !== 'string') throw new FormatException('the atlas is not shaped as expected');
  return value;
}
