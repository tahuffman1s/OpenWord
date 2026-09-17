import 'package:flutter/material.dart';

import '../data/atlas.dart';
import 'widgets/atlas_map.dart';

/// Shows the places a passage names, on a map of the world it names them in.
void showMapSheet(
  BuildContext context, {
  required AtlasData data,
  required String title,
  required List<Place> places,
}) {
  if (places.isEmpty) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.88,
      child: _MapSheet(data: data, title: title, places: places),
    ),
  );
}

class _MapSheet extends StatefulWidget {
  const _MapSheet({
    required this.data,
    required this.title,
    required this.places,
  });

  final AtlasData data;
  final String title;
  final List<Place> places;

  @override
  State<_MapSheet> createState() => _MapSheetState();
}

class _MapSheetState extends State<_MapSheet> {
  Place? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              widget.places.length == 1
                  ? 'One place named here'
                  : '${widget.places.length} places named here',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: InteractiveViewer(
                  maxScale: 8,
                  child: AtlasMap(
                    data: widget.data,
                    places: widget.places,
                    selected: selected,
                    onSelected: (place) => setState(() => _selected = place),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (selected != null)
              _Selected(place: selected)
            else
              Text(
                'Pinch to zoom; tap a marker, or a name below, to pick it '
                'out. A hollow marker is a location scholars are not agreed '
                'on.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final place in widget.places)
                      ChoiceChip(
                        label: Text(place.name),
                        selected: place == selected,
                        onSelected: (chosen) =>
                            setState(() => _selected = chosen ? place : null),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              Atlas.attribution,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What is known about the place the reader has picked.
class _Selected extends StatelessWidget {
  const _Selected({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(place.name, style: theme.textTheme.titleSmall),
              Text(
                '${place.type} • ${_coordinates(place)}'
                '${place.isUncertain ? ' • location uncertain' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData get _icon => switch (place.type) {
    'settlement' => Icons.location_city_rounded,
    'region' => Icons.crop_free_rounded,
    'mountain' || 'mountain range' || 'hill' => Icons.terrain_rounded,
    'river' || 'spring' || 'body of water' => Icons.water_rounded,
    'island' => Icons.landscape_rounded,
    _ => Icons.place_rounded,
  };

  static String _coordinates(Place place) {
    final lat = place.lat.abs().toStringAsFixed(2);
    final lon = place.lon.abs().toStringAsFixed(2);
    return '$lat°${place.lat >= 0 ? 'N' : 'S'} '
        '$lon°${place.lon >= 0 ? 'E' : 'W'}';
  }
}
