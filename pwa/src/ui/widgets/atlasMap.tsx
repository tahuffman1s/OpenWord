import type { RefObject } from 'preact';
import { useEffect, useRef } from 'preact/hooks';
import { type AtlasData, type BaseMap, GeoBox, type GeoRun, type Place } from '../../data/atlas';
import { currentScheme, hexOf, rgba } from '../m3';
import './atlasMap.css';

/** A width and a height, in CSS pixels. */
export interface Size {
  readonly width: number;
  readonly height: number;
}

/** A point on the canvas, in CSS pixels. */
export interface Offset {
  readonly x: number;
  readonly y: number;
}

interface Rect {
  left: number;
  top: number;
  width: number;
  height: number;
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(Math.max(value, low), high);
}

/**
 * Where the map is looking: a point on the ground in the middle of the
 * canvas, and how many pixels a degree of latitude takes.
 *
 * Equirectangular, with longitude squeezed by the cosine of the middle
 * latitude. Over the eastern Mediterranean that is indistinguishable from a
 * proper projection and costs two multiplies, which matters when it runs on
 * every frame of a pinch.
 */
export class MapCamera {
  readonly centreLon: number;
  readonly centreLat: number;

  /** Pixels per degree of latitude. */
  readonly scale: number;

  readonly size: Size;

  constructor(init: { centreLon: number; centreLat: number; scale: number; size: Size }) {
    this.centreLon = init.centreLon;
    this.centreLat = init.centreLat;
    this.scale = init.scale;
    this.size = init.size;
  }

  /** Frames a box in a canvas, leaving a little room around it. */
  static fit(box: GeoBox, size: Size, options: { padding?: number } = {}): MapCamera {
    const padding = options.padding ?? 1.12;
    const squeeze = MapCamera.squeezeAt(box.centreLat);
    const width = Math.max(box.width * squeeze, 1e-6);
    const height = Math.max(box.height, 1e-6);
    const scale = Math.min(size.width / width, size.height / height) / padding;
    return new MapCamera({ centreLon: box.centreLon, centreLat: box.centreLat, scale, size });
  }

  get squeeze(): number {
    return MapCamera.squeezeAt(this.centreLat);
  }

  private static squeezeAt(lat: number): number {
    return clamp(Math.abs(Math.cos((lat * Math.PI) / 180)), 0.2, 1.0);
  }

  toOffset(lon: number, lat: number): Offset {
    return {
      x: this.size.width / 2 + (lon - this.centreLon) * this.squeeze * this.scale,
      y: this.size.height / 2 + (this.centreLat - lat) * this.scale,
    };
  }

  /** The ground under a point on the canvas: `[lon, lat]`. */
  toGround(point: Offset): [lon: number, lat: number] {
    return [
      this.centreLon + (point.x - this.size.width / 2) / (this.squeeze * this.scale),
      this.centreLat - (point.y - this.size.height / 2) / this.scale,
    ];
  }

  /** The ground the canvas is showing. */
  get visible(): GeoBox {
    const halfLat = this.size.height / 2 / this.scale;
    const halfLon = this.size.width / 2 / (this.squeeze * this.scale);
    return new GeoBox(this.centreLon - halfLon, this.centreLat - halfLat, this.centreLon + halfLon, this.centreLat + halfLat);
  }

  /** Roughly how many metres a pixel covers, for the scale bar. */
  get metresPerPixel(): number {
    return 111320 / this.scale;
  }

  copyWith(changes: { centreLon?: number; centreLat?: number; scale?: number; size?: Size }): MapCamera {
    return new MapCamera({
      centreLon: changes.centreLon ?? this.centreLon,
      centreLat: changes.centreLat ?? this.centreLat,
      scale: changes.scale ?? this.scale,
      size: changes.size ?? this.size,
    });
  }

  /**
   * Zooms about a point on the canvas, so what is under the fingers stays
   * under the fingers.
   */
  zoomedAt(focus: Offset, factor: number, limits: { min: number; max: number }): MapCamera {
    const wanted = clamp(this.scale * factor, limits.min, limits.max);
    if (wanted === this.scale) return this;
    const [lon, lat] = this.toGround(focus);
    let next = this.copyWith({ scale: wanted });
    // Moving the centre changes the latitude the longitude is squeezed by,
    // so the correction is applied until it settles — three rounds is far
    // more than enough at any zoom this map reaches.
    for (let i = 0; i < 3; i++) {
      const [afterLon, afterLat] = next.toGround(focus);
      next = next.copyWith({
        centreLon: next.centreLon + (lon - afterLon),
        centreLat: next.centreLat + (lat - afterLat),
      });
    }
    return next;
  }

  /**
   * Keeps the middle of the map inside the ground the atlas covers, so it
   * cannot be dragged off into blankness.
   */
  clampedTo(bounds: GeoBox): MapCamera {
    if (bounds.width <= 0 || bounds.height <= 0) return this;
    return this.copyWith({
      centreLon: clamp(this.centreLon, bounds.west, bounds.east),
      centreLat: clamp(this.centreLat, bounds.south, bounds.north),
    });
  }

  /** Whether `other` holds the same values as this. */
  equals(other: MapCamera | null | undefined): boolean {
    return (
      other != null &&
      other.centreLon === this.centreLon &&
      other.centreLat === this.centreLat &&
      other.scale === this.scale &&
      other.size.width === this.size.width &&
      other.size.height === this.size.height
    );
  }
}

/**
 * A rectangle around a group of places, never so small that one place fills
 * the screen with nothing around it.
 */
export function boxAround(places: Iterable<Place>, options: { minimumSpan?: number } = {}): GeoBox {
  const minimumSpan = options.minimumSpan ?? 0.6;
  let west = Number.POSITIVE_INFINITY;
  let east = Number.NEGATIVE_INFINITY;
  let south = Number.POSITIVE_INFINITY;
  let north = Number.NEGATIVE_INFINITY;
  for (const place of places) {
    west = Math.min(west, place.lon);
    east = Math.max(east, place.lon);
    south = Math.min(south, place.lat);
    north = Math.max(north, place.lat);
  }
  if (west > east) return new GeoBox(34, 31, 36, 33);

  const growX = Math.max(0, minimumSpan - (east - west)) / 2;
  const growY = Math.max(0, minimumSpan - (north - south)) / 2;
  return new GeoBox(west - growX, south - growY, east + growX, north + growY);
}

/** What the map can be asked to do from outside. */
export interface AtlasMapHandle {
  readonly camera: MapCamera | null;
  zoomBy(factor: number): void;
  /**
   * Brings a place to the middle of the map without changing the zoom, for
   * when it is chosen from the list rather than tapped on the map.
   */
  centreOn(place: Place): void;
  /** Back to the passage the map was opened for. */
  reset(): void;
}

export interface AtlasMapProps {
  data: AtlasData;
  places: readonly Place[];
  selected?: Place | null;
  onSelected?: (place: Place | null) => void;
  /** Filled in with the map's handle once it is on screen. */
  controller?: RefObject<AtlasMapHandle | null>;
}

/**
 * As far in as the map will go: about half a metre to the pixel. The
 * coastline runs out of detail long before this, but a reader zooming
 * into a city should not be stopped by the app.
 */
export const maxScale = 220000;

/** How long a tap waits to see whether it is the first half of a double tap. */
const doubleTapTimeout = 300;

/** How far apart two taps may land and still be one double tap. */
const doubleTapSlop = 100;

/** How far a pointer may move and still be a tap rather than a drag. */
const touchSlop = 8;

/**
 * The map: coastline, water and the places of a passage, with the panning
 * and zooming anyone expects of a map.
 */
export function AtlasMap({ data, places, selected = null, onSelected, controller }: AtlasMapProps) {
  const host = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);

  // Everything the gestures touch lives in one mutable record: a pinch
  // runs many times a frame and must not wait on a render to see its own
  // result.
  const state = useRef({
    camera: null as MapCamera | null,
    size: { width: 0, height: 0 } as Size,
    data,
    places,
    selected,
    onSelected,
    frame: 0,
    /** The camera when a gesture started, so it is applied to it whole. */
    gestureStart: null as MapCamera | null,
    gestureFocus: null as Offset | null,
    gestureSpan: 0,
    pointers: new Map<number, Offset>(),
    moved: false,
    lastTapAt: 0,
    lastTapPoint: null as Offset | null,
    tapTimer: 0 as ReturnType<typeof setTimeout> | 0,
  });
  const s = state.current;
  // A different passage is a different map; a new selection is not.
  if (s.places !== places) s.camera = null;
  s.data = data;
  s.places = places;
  s.selected = selected;
  s.onSelected = onSelected;

  const api = useRef<{
    draw: () => void;
    schedule: () => void;
    moveTo: (camera: MapCamera) => void;
    minScale: (size: Size) => number;
    handle: AtlasMapHandle;
  } | null>(null);
  if (api.current === null) {
    /** How far out the map will go: the whole of what the atlas covers. */
    const minScale = (size: Size): number => {
      const bounds = s.data.bounds;
      if (bounds.width <= 0 || bounds.height <= 0) return 1;
      return MapCamera.fit(bounds, size, { padding: 1 }).scale;
    };
    const cameraFor = (size: Size): MapCamera => {
      const current = s.camera;
      if (current !== null && current.size.width === size.width && current.size.height === size.height) return current;
      if (current !== null) return current.copyWith({ size });
      return MapCamera.fit(boxAround(s.places), size);
    };
    const draw = () => {
      const element = canvas.current;
      if (element === null || s.size.width <= 0 || s.size.height <= 0) return;
      const ratio = Math.min(globalThis.devicePixelRatio || 1, 3);
      const width = Math.round(s.size.width * ratio);
      const height = Math.round(s.size.height * ratio);
      if (element.width !== width) element.width = width;
      if (element.height !== height) element.height = height;
      const ctx = element.getContext('2d');
      if (ctx === null) return;
      // The camera catching up with a canvas that has just changed size.
      const camera = cameraFor(s.size);
      s.camera = camera;
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      const scheme = currentScheme();
      new AtlasPainter({
        data: s.data,
        places: s.places,
        selected: s.selected,
        camera,
        // A little of the seed colour in the water, so land and sea
        // are told apart at a glance whatever the palette.
        water: hexOf(alphaBlend(scheme.primary, 0.16, scheme.surfaceContainerHighest)),
        land: hexOf(scheme.surface),
        coast: hexOf(scheme.outline),
        river: rgba(scheme.primary, 0.45),
        marker: hexOf(scheme.primary),
        label: hexOf(scheme.onSurface),
        labelFaint: rgba(scheme.onSurface, 0.7),
        labelHalo: hexOf(scheme.surface),
        labelHaloSoft: rgba(scheme.surface, 0.85),
        modern: hexOf(scheme.onSurfaceVariant),
        built: rgba(scheme.onSurface, 0.07),
        fontFamily: getComputedStyle(element).fontFamily || 'sans-serif',
        direction: getComputedStyle(element).direction === 'rtl' ? 'rtl' : 'ltr',
      }).paint(ctx, s.size);
    };
    const schedule = () => {
      if (s.frame !== 0) return;
      s.frame = requestAnimationFrame(() => {
        s.frame = 0;
        draw();
      });
    };
    const moveTo = (camera: MapCamera) => {
      s.camera = camera.clampedTo(s.data.bounds);
      schedule();
    };
    api.current = {
      draw,
      schedule,
      moveTo,
      minScale,
      handle: {
        get camera() {
          return s.camera;
        },
        zoomBy(factor: number) {
          const camera = s.camera;
          if (camera === null) return;
          moveTo(
            camera.zoomedAt({ x: s.size.width / 2, y: s.size.height / 2 }, factor, { min: minScale(s.size), max: maxScale }),
          );
        },
        centreOn(place: Place) {
          const camera = s.camera;
          if (camera === null) return;
          moveTo(camera.copyWith({ centreLon: place.lon, centreLat: place.lat }));
        },
        reset() {
          s.camera = MapCamera.fit(boxAround(s.places), s.size);
          schedule();
        },
      },
    };
  }
  const { draw, schedule, moveTo, minScale, handle } = api.current;
  if (controller) controller.current = handle;

  // The canvas follows the room it is given.
  useEffect(() => {
    const element = host.current;
    if (element === null) return;
    const measure = () => {
      const rect = element.getBoundingClientRect();
      s.size = { width: rect.width, height: rect.height };
      draw();
    };
    measure();
    const observer = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(measure);
    observer?.observe(element);
    // The labels are measured in the page's face, which may still be on
    // its way when the map first draws.
    void document.fonts?.ready.then(schedule);
    return () => {
      observer?.disconnect();
      if (s.frame !== 0) cancelAnimationFrame(s.frame);
      s.frame = 0;
      if (s.tapTimer !== 0) clearTimeout(s.tapTimer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // A new selection, another passage, another palette: drawn again.
  useEffect(() => {
    schedule();
  });

  const pointOf = (event: { clientX: number; clientY: number }): Offset => {
    const rect = canvas.current!.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };

  /** Where the fingers are, taken together, and how far apart. */
  const focal = (): { point: Offset; span: number } => {
    const points = [...s.pointers.values()];
    const x = points.reduce((sum, p) => sum + p.x, 0) / points.length;
    const y = points.reduce((sum, p) => sum + p.y, 0) / points.length;
    const span = points.length < 2 ? 0 : points.reduce((sum, p) => sum + Math.hypot(p.x - x, p.y - y), 0) / points.length;
    return { point: { x, y }, span };
  };

  const startGesture = () => {
    const { point, span } = focal();
    s.gestureStart = s.camera;
    s.gestureFocus = point;
    s.gestureSpan = span;
  };

  const onTap = (position: Offset) => {
    const pick = s.onSelected;
    const camera = s.camera;
    if (pick === undefined || camera === null) return;
    let nearest: Place | null = null;
    let best = 30.0;
    for (const place of s.places) {
      const at = camera.toOffset(place.lon, place.lat);
      const distance = Math.hypot(at.x - position.x, at.y - position.y);
      if (distance < best) {
        best = distance;
        nearest = place;
      }
    }
    pick(nearest);
  };

  const zoomAt = (focus: Offset, factor: number) => {
    const camera = s.camera;
    if (camera === null) return;
    moveTo(camera.zoomedAt(focus, factor, { min: minScale(camera.size), max: maxScale }));
  };

  const onPointerDown = (event: PointerEvent) => {
    if (event.pointerType === 'mouse' && event.button !== 0) return;
    (event.currentTarget as Element).setPointerCapture?.(event.pointerId);
    if (s.pointers.size === 0) s.moved = false;
    s.pointers.set(event.pointerId, pointOf(event));
    // A second finger makes it a pinch, which is never a tap.
    if (s.pointers.size > 1) s.moved = true;
    startGesture();
  };

  const onPointerMove = (event: PointerEvent) => {
    if (!s.pointers.has(event.pointerId)) return;
    s.pointers.set(event.pointerId, pointOf(event));
    const start = s.gestureStart;
    const focus = s.gestureFocus;
    if (start === null || focus === null) return;
    const { point, span } = focal();
    const moved = { x: point.x - focus.x, y: point.y - focus.y };
    if (!s.moved) {
      if (Math.hypot(moved.x, moved.y) < touchSlop) return;
      // Past the slop it is a drag, and the drag starts from here: the
      // map does not lurch by the distance it took to be sure.
      s.moved = true;
      startGesture();
      return;
    }

    // Pinch first, about where the fingers landed, then drag.
    const scale = s.gestureSpan > 0 && span > 0 ? span / s.gestureSpan : 1;
    const zoomed = scale === 1 ? start : start.zoomedAt(focus, scale, { min: minScale(start.size), max: maxScale });
    moveTo(
      zoomed.copyWith({
        centreLon: zoomed.centreLon - moved.x / (zoomed.squeeze * zoomed.scale),
        centreLat: zoomed.centreLat + moved.y / zoomed.scale,
      }),
    );
  };

  const onPointerUp = (event: PointerEvent) => {
    if (!s.pointers.has(event.pointerId)) return;
    const position = pointOf(event);
    s.pointers.delete(event.pointerId);
    if (s.pointers.size > 0) {
      // One finger lifted from a pinch: what is left is a drag, begun
      // from where the map now is.
      startGesture();
      return;
    }
    s.gestureStart = null;
    s.gestureFocus = null;
    if (s.moved || event.type === 'pointercancel') return;

    // A tap counts as a tap once it is clear it was not the first half of
    // a double tap, so it lands after the double-tap window.
    const now = Date.now();
    const last = s.lastTapPoint;
    if (
      s.tapTimer !== 0 &&
      last !== null &&
      now - s.lastTapAt <= doubleTapTimeout &&
      Math.hypot(last.x - position.x, last.y - position.y) <= doubleTapSlop
    ) {
      clearTimeout(s.tapTimer);
      s.tapTimer = 0;
      s.lastTapPoint = null;
      // Where the second tap landed, so the zoom happens under the finger.
      zoomAt(position, 2);
      return;
    }
    s.lastTapAt = now;
    s.lastTapPoint = position;
    s.tapTimer = setTimeout(() => {
      s.tapTimer = 0;
      onTap(position);
    }, doubleTapTimeout);
  };

  const onWheel = (event: WheelEvent) => {
    const camera = s.camera;
    if (camera === null) return;
    event.preventDefault();
    // Lines and pages, where a mouse reports those, as pixels.
    const delta = event.deltaMode === 1 ? event.deltaY * 40 : event.deltaMode === 2 ? event.deltaY * 400 : event.deltaY;
    const factor = Math.exp(-delta / 320);
    moveTo(camera.zoomedAt(pointOf(event), factor, { min: minScale(camera.size), max: maxScale }));
  };

  return (
    <div class="ow-atlas-map" ref={host}>
      <canvas
        ref={canvas}
        class="ow-atlas-map__canvas"
        role="img"
        aria-label="Map of the places this passage names"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        onWheel={onWheel}
      />
    </div>
  );
}

/** `fg` at `alpha` laid over an opaque `bg`, as ARGB. */
function alphaBlend(fg: number, alpha: number, bg: number): number {
  const mix = (shift: number) => {
    const f = (fg >> shift) & 0xff;
    const b = (bg >> shift) & 0xff;
    return Math.round(f * alpha + b * (1 - alpha)) & 0xff;
  };
  return ((0xff << 24) | (mix(16) << 16) | (mix(8) << 8) | mix(0)) >>> 0;
}

function overlaps(a: Rect, b: Rect): boolean {
  return a.left < b.left + b.width && b.left < a.left + a.width && a.top < b.top + b.height && b.top < a.top + a.height;
}

function inflate(rect: Rect, by: number): Rect {
  return { left: rect.left - by, top: rect.top - by, width: rect.width + 2 * by, height: rect.height + 2 * by };
}

type Canvas2D = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;

export interface AtlasPainterInit {
  data: AtlasData;
  places: readonly Place[];
  selected: Place | null;
  camera: MapCamera;
  water: string;
  land: string;
  coast: string;
  river: string;
  marker: string;
  label: string;
  /** `label` at seven tenths, for the scale bar's line. */
  labelFaint: string;
  labelHalo: string;
  /** `labelHalo` at 85%, behind lettering. */
  labelHaloSoft: string;
  modern: string;
  built: string;
  fontFamily: string;
  direction: 'ltr' | 'rtl';
}

export class AtlasPainter {
  /** Below this many degrees across, the fine base map is worth its detail. */
  static readonly detailBelowDegrees = 14;

  /**
   * And below this, the ground people live on now is worth drawing: the
   * built-up areas and the towns, so that a close-up of an ancient site is
   * not a blank page.
   */
  static readonly modernBelowDegrees = 2.2;

  private readonly o: AtlasPainterInit;

  constructor(init: AtlasPainterInit) {
    this.o = init;
  }

  paint(canvas: Canvas2D, size: Size): void {
    const { data, camera } = this.o;
    const visible = camera.visible;
    const base = this.baseFor(visible);

    canvas.direction = this.o.direction;
    canvas.textBaseline = 'alphabetic';
    canvas.textAlign = 'left';
    canvas.lineJoin = 'round';

    canvas.fillStyle = this.o.water;
    canvas.fillRect(0, 0, size.width, size.height);

    // Non-zero winding, not even-odd: clipping the coastline to the map
    // leaves rings that share the map's own edges, and even-odd would read
    // the overlap between two of them as a hole and paint land as sea.
    // Islands and inland seas are wound the other way and still come out as
    // holes.
    this.trace(canvas, base.land, visible, true);
    canvas.fillStyle = this.o.land;
    canvas.fill('nonzero');
    canvas.strokeStyle = this.o.coast;
    canvas.lineWidth = 1;
    canvas.stroke();

    this.trace(canvas, base.lakes, visible, true);
    canvas.fillStyle = this.o.water;
    canvas.fill('nonzero');

    this.trace(canvas, base.rivers, visible, false);
    canvas.strokeStyle = this.o.river;
    canvas.lineWidth = 1.2;
    canvas.stroke();

    if (visible.width <= AtlasPainter.modernBelowDegrees) {
      this.trace(canvas, data.urban, visible, true);
      canvas.fillStyle = this.o.built;
      canvas.fill('nonzero');
      this.paintTowns(canvas, size, visible);
    }

    this.paintPlaces(canvas, size);
    this.paintScale(canvas, size);
  }

  /**
   * The fine map once the view is small enough for it to matter, and only
   * where it has anything — outside that, the coarse one still covers.
   */
  private baseFor(visible: GeoBox): BaseMap {
    const { data } = this.o;
    if (data.fine.isEmpty) return data.coarse;
    if (visible.width > AtlasPainter.detailBelowDegrees) return data.coarse;
    const detail = data.detail;
    const overlapping =
      visible.west <= detail.east && visible.east >= detail.west && visible.south <= detail.north && visible.north >= detail.south;
    return overlapping ? data.fine : data.coarse;
  }

  /** Begins a path of the runs in view, ready to fill or stroke. */
  private trace(canvas: Canvas2D, runs: readonly GeoRun[], visible: GeoBox, close: boolean): void {
    const { camera } = this.o;
    // The projection, unrolled: this runs for every point of the coast.
    const halfWidth = camera.size.width / 2;
    const halfHeight = camera.size.height / 2;
    const kx = camera.squeeze * camera.scale;
    const ky = camera.scale;
    const lon0 = camera.centreLon;
    const lat0 = camera.centreLat;
    canvas.beginPath();
    for (const run of runs) {
      if (!run.intersects(visible.west, visible.south, visible.east, visible.north)) continue;
      const points = run.points;
      if (points.length < 4) continue;
      for (let i = 0; i < points.length; i += 2) {
        const x = halfWidth + (points[i] - lon0) * kx;
        const y = halfHeight + (lat0 - points[i + 1]) * ky;
        if (i === 0) canvas.moveTo(x, y);
        else canvas.lineTo(x, y);
      }
      if (close) canvas.closePath();
    }
  }

  private font(size: number, weight: number): string {
    return `${weight} ${size}px ${this.o.fontFamily}`;
  }

  /** Lays a line of lettering out: how wide and tall it is, and where its baseline sits. */
  private layout(canvas: Canvas2D, text: string, size: number, weight: number): { width: number; height: number; ascent: number; font: string } {
    const font = this.font(size, weight);
    canvas.font = font;
    const metrics = canvas.measureText(text);
    const ascent = metrics.fontBoundingBoxAscent ?? size * 0.93;
    const descent = metrics.fontBoundingBoxDescent ?? size * 0.24;
    return { width: metrics.width, height: ascent + descent, ascent, font };
  }

  private roundRect(canvas: Canvas2D, rect: Rect, radius: number, fill: string): void {
    canvas.beginPath();
    if (typeof canvas.roundRect === 'function') canvas.roundRect(rect.left, rect.top, rect.width, rect.height, radius);
    else canvas.rect(rect.left, rect.top, rect.width, rect.height);
    canvas.fillStyle = fill;
    canvas.fill();
  }

  /**
   * The modern towns, under everything the passage is about. Smaller places
   * appear as the map is zoomed further in, the way an atlas thins its
   * lettering.
   */
  private paintTowns(canvas: Canvas2D, size: Size, visible: GeoBox): void {
    const { data, places, camera, modern } = this.o;
    const limit = visible.width <= 0.35 ? 12 : visible.width <= 1.0 ? 8 : 5;
    const taken: Rect[] = [];
    // A modern town that shares its name with a place of the passage would
    // only be drawn twice over, in two colours.
    const named = new Set(places.map((place) => place.name.toLowerCase()));

    for (const town of data.towns) {
      if (town.rank > limit) continue;
      if (named.has(town.name.toLowerCase())) continue;
      if (!visible.contains(town.lon, town.lat)) continue;
      const at = camera.toOffset(town.lon, town.lat);

      const text = this.layout(canvas, town.name, 10, 400);
      const spot: Rect = { left: at.x + 6, top: at.y - text.height / 2, width: text.width, height: text.height };
      if (spot.left + spot.width > size.width || spot.top < 0 || spot.top + spot.height > size.height) continue;
      const padded = inflate(spot, 2);
      if (taken.some((other) => overlaps(padded, other))) continue;
      taken.push(spot);

      canvas.beginPath();
      canvas.arc(at.x, at.y, 2.5, 0, Math.PI * 2);
      canvas.strokeStyle = modern;
      canvas.lineWidth = 1.2;
      canvas.stroke();
      canvas.font = text.font;
      canvas.fillStyle = modern;
      canvas.fillText(town.name, spot.left, spot.top + text.ascent);
    }
  }

  private paintPlaces(canvas: Canvas2D, size: Size): void {
    const { places, selected, camera, marker, label, labelHalo, labelHaloSoft } = this.o;
    // Markers and labels are drawn at a fixed size however far the map is
    // zoomed in, the way a map's lettering behaves rather than a photograph's.
    const taken: Rect[] = [];
    const markers = new Map<Place, Rect>();
    const drawn = new Map<Place, Offset>();

    const ordered = [...places.filter((place) => place !== selected), ...(selected !== null ? [selected] : [])];

    for (const place of ordered) {
      const at = camera.toOffset(place.lon, place.lat);
      if (at.x < -40 || at.y < -40 || at.x > size.width + 40 || at.y > size.height + 40) continue;
      const isSelected = place === selected;
      const radius = isSelected ? 7.0 : 4.0;
      drawn.set(place, at);
      const reach = isSelected ? radius + 6 : radius + 2;
      markers.set(place, { left: at.x - reach, top: at.y - reach, width: reach * 2, height: reach * 2 });

      canvas.beginPath();
      canvas.arc(at.x, at.y, radius + 2, 0, Math.PI * 2);
      canvas.fillStyle = labelHalo;
      canvas.fill();

      canvas.beginPath();
      canvas.arc(at.x, at.y, radius, 0, Math.PI * 2);
      if (place.isUncertain && !isSelected) {
        canvas.strokeStyle = marker;
        canvas.lineWidth = 2;
        canvas.stroke();
      } else {
        canvas.fillStyle = marker;
        canvas.fill();
      }
      if (isSelected) {
        // A ring around the marker rather than a hole through it: a hollow
        // marker already means the location is disputed.
        canvas.beginPath();
        canvas.arc(at.x, at.y, radius + 4, 0, Math.PI * 2);
        canvas.strokeStyle = marker;
        canvas.lineWidth = 2;
        canvas.stroke();
      }
    }

    for (const [place, at] of drawn) {
      const isSelected = place === selected;
      const radius = isSelected ? 7.0 : 4.0;

      const text = this.layout(canvas, place.name, isSelected ? 13 : 11, isSelected ? 700 : 500);
      const candidates: Offset[] = [
        { x: at.x + radius + 4, y: at.y - text.height / 2 },
        { x: at.x - radius - 4 - text.width, y: at.y - text.height / 2 },
        { x: at.x - text.width / 2, y: at.y + radius + 3 },
        { x: at.x - text.width / 2, y: at.y - radius - 3 - text.height },
      ];
      let spot: Rect | null = null;
      for (const candidate of candidates) {
        const rect: Rect = { left: candidate.x, top: candidate.y, width: text.width, height: text.height };
        if (rect.left < 0 || rect.top < 0 || rect.left + rect.width > size.width || rect.top + rect.height > size.height) {
          continue;
        }
        const padded = inflate(rect, 1);
        if (taken.some((other) => overlaps(padded, other))) continue;
        let onMarker = false;
        for (const [other, box] of markers) {
          if (other !== place && overlaps(box, padded)) {
            onMarker = true;
            break;
          }
        }
        if (onMarker) continue;
        spot = rect;
        break;
      }
      if (spot === null && !isSelected) continue;
      spot ??= { left: candidates[0].x, top: candidates[0].y, width: text.width, height: text.height };
      taken.push(spot);

      this.roundRect(canvas, inflate(spot, 2), 4, labelHaloSoft);
      canvas.font = text.font;
      canvas.fillStyle = label;
      canvas.fillText(place.name, spot.left, spot.top + text.ascent);
    }
  }

  /**
   * A bar in the corner saying how far it is across the map, which is the
   * only way to tell one zoom level from another on empty ground.
   */
  private paintScale(canvas: Canvas2D, size: Size): void {
    const { camera, label, labelFaint, labelHaloSoft } = this.o;
    const metres = camera.metresPerPixel;
    if (!Number.isFinite(metres) || metres <= 0) return;

    // The roundest distance that fits in about a fifth of the width.
    const wanted = (metres * size.width) / 5;
    const steps = [
      1.0, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000, 2000000,
    ];
    let distance = steps[steps.length - 1];
    for (const step of steps) {
      if (step >= wanted) {
        distance = step;
        break;
      }
    }

    const length = distance / metres;
    if (length < 20 || length > size.width - 40) return;
    const y = size.height - 16;

    canvas.beginPath();
    canvas.moveTo(16, y - 5);
    canvas.lineTo(16, y);
    canvas.lineTo(16 + length, y);
    canvas.lineTo(16 + length, y - 5);
    canvas.strokeStyle = labelFaint;
    canvas.lineWidth = 2;
    canvas.lineJoin = 'miter';
    canvas.stroke();
    canvas.lineJoin = 'round';

    const words = distance >= 1000 ? `${Math.round(distance / 1000)} km` : `${Math.round(distance)} m`;
    const text = this.layout(canvas, words, 11, 400);
    const at = { x: 16, y: y - 7 - text.height };
    this.roundRect(canvas, inflate({ left: at.x, top: at.y, width: text.width, height: text.height }, 3), 4, labelHaloSoft);
    canvas.font = text.font;
    canvas.fillStyle = label;
    canvas.fillText(words, at.x, at.y + text.ascent);
  }
}
