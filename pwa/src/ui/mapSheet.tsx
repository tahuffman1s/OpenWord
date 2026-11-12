import { useRef, useState } from 'preact/hooks';
import { Atlas, type AtlasData, type ChapterPlace, type Place } from '../data/atlas';
import { Chip, Icon, IconButton, SheetHandle, showSheet, useOverlay } from './m3';
import { AtlasMap, type AtlasMapHandle } from './widgets/atlasMap';
import './sheets.css';
import './mapSheet.css';

/**
 * Shows the places a passage names, on a map of the world it names them in.
 *
 * `onVerse` is called with a verse number when the reader taps one of a
 * place's references; the sheet closes itself first.
 */
export function showMapSheet(options: {
  data: AtlasData;
  title: string;
  places: readonly ChapterPlace[];
  onVerse?: (verse: number) => void;
}): void {
  if (options.places.length === 0) return;
  void showSheet(<MapSheet {...options} />, { class: 'ow-sheet--h90', name: 'map' });
}

function MapSheet({
  data,
  title,
  places,
  onVerse,
}: {
  data: AtlasData;
  title: string;
  places: readonly ChapterPlace[];
  onVerse?: (verse: number) => void;
}) {
  const overlay = useOverlay();
  const map = useRef<AtlasMapHandle | null>(null);
  // Made once: a different list is a different map to the map.
  const points = useRef<Place[] | null>(null);
  points.current ??= places.map((named) => named.place);
  const [selected, setSelected] = useState<ChapterPlace | null>(null);

  const select = (place: Place | null) => {
    setSelected(place === null ? null : (places.find((named) => named.place === place) ?? null));
  };

  return (
    <>
      <SheetHandle />
      <div class="ow-sheet-fill ow-map-sheet">
        <div class="m3-title-large">{title}</div>
        <div class="m3-body-medium m3-on-surface-variant" style="margin-top:2px">
          {places.length === 1 ? 'One place named here' : `${places.length} places named here`}
        </div>
        <div class="ow-map-sheet__map">
          <AtlasMap data={data} places={points.current} selected={selected?.place ?? null} onSelected={select} controller={map} />
          <div class="ow-map-sheet__controls">
            <IconButton icon="add" label="Zoom in" size="small" iconSize={20} onClick={() => map.current?.zoomBy(1.8)} />
            <IconButton icon="remove" label="Zoom out" size="small" iconSize={20} onClick={() => map.current?.zoomBy(1 / 1.8)} />
            <IconButton
              icon="filter_center_focus"
              label="Back to the passage"
              size="small"
              iconSize={20}
              onClick={() => map.current?.reset()}
            />
          </div>
        </div>
        {/* The chips scroll sideways rather than wrapping: a wrapped row
            of long names used to be cut off by the edge of the sheet. */}
        <div class="ow-map-sheet__chips">
          {places.map((named) => (
            <Chip
              variant="choice"
              label={named.place.name}
              selected={named.place === selected?.place}
              onClick={() => {
                const chosen = named.place !== selected?.place;
                select(chosen ? named.place : null);
                // Chosen from the list, it may be anywhere; bring it
                // to the middle rather than leaving the reader to
                // hunt for it.
                if (chosen) map.current?.centreOn(named.place);
              }}
            />
          ))}
        </div>
        <div class="ow-map-sheet__details">
          {selected === null ? (
            <Hint />
          ) : (
            <Details
              named={selected}
              onVerse={(verse) => {
                overlay.close();
                onVerse?.(verse);
              }}
            />
          )}
        </div>
      </div>
    </>
  );
}

function Hint() {
  return (
    <div>
      <div class="ow-sheet-note">
        Drag to move, pinch or scroll to zoom, double-tap to zoom in. Tap a marker or a name for what is known about it and where
        the chapter names it. A hollow marker is a location scholars are not agreed on.
      </div>
      <div class="ow-sheet-note" style="margin-top:8px">
        {Atlas.attribution}
      </div>
    </div>
  );
}

function iconFor(type: string): string {
  switch (type) {
    case 'settlement':
      return 'location_city';
    case 'region':
    case 'people group':
      return 'crop_free';
    case 'mountain':
    case 'mountain range':
    case 'hill':
      return 'terrain';
    case 'river':
    case 'spring':
    case 'body of water':
      return 'water';
    case 'island':
      return 'landscape';
    case 'campsite':
      return 'cabin';
    case 'gate':
      return 'door_front';
    default:
      return 'place';
  }
}

function summary(place: Place): string {
  const kinds = place.types.join(', ');
  const lat = Math.abs(place.lat).toFixed(3);
  const lon = Math.abs(place.lon).toFixed(3);
  const where = `${lat}°${place.lat >= 0 ? 'N' : 'S'} ${lon}°${place.lon >= 0 ? 'E' : 'W'}`;
  return `${kinds} • ${where}${place.isUncertain ? ' • location uncertain' : ''}`;
}

/** What the open data knows about the place, and where this chapter names it. */
function Details({ named, onVerse }: { named: ChapterPlace; onVerse: (verse: number) => void }) {
  const place = named.place;
  return (
    <div>
      <div class="ow-map-sheet__place">
        <Icon name={iconFor(place.type)} size={18} class="m3-primary" />
        <div style="flex:1;min-width:0">
          <div class="m3-title-small">{place.name}</div>
          <div class="ow-sheet-note">{summary(place)}</div>
        </div>
      </div>
      {place.comment.length > 0 && (
        <div class="m3-body-medium" style="margin-top:8px">
          {place.comment}
        </div>
      )}
      {place.modern.length > 0 && (
        <div style="margin-top:6px">
          <Line label="Identified with" value={place.isUncertain ? `${place.modern} — disputed` : place.modern} />
        </div>
      )}
      {place.otherNames.length > 0 && <Line label="Also called" value={place.otherNames.join(', ')} />}
      <Line
        label="Named in"
        value={place.verseCount === 1 ? 'one verse of the Bible' : `${place.verseCount} verses of the Bible`}
      />
      <div class="ow-map-sheet__label">Named here at</div>
      <div class="ow-map-sheet__verses">
        {named.verses.map((verse) => (
          <Chip variant="assist" class="ow-chip--compact" label={`verse ${verse}`} onClick={() => onVerse(verse)} />
        ))}
      </div>
      <div class="ow-sheet-note" style="margin-top:10px">
        {Atlas.attribution}
      </div>
    </div>
  );
}

function Line({ label, value }: { label: string; value: string }) {
  return (
    <div class="ow-sheet-note" style="padding-top:4px">
      {label}: <span style="color:var(--md-sys-color-on-surface)">{value}</span>
    </div>
  );
}
