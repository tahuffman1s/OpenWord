import 'package:flutter/material.dart';

import '../data/atlas.dart';
import 'widgets/atlas_map.dart';

/// Shows the places a passage names, on a map of the world it names them in.
///
/// [onVerse] is called with a verse number when the reader taps one of a
/// place's references; the sheet closes itself first.
void showMapSheet(
  BuildContext context, {
  required AtlasData data,
  required String title,
  required List<ChapterPlace> places,
  ValueChanged<int>? onVerse,
}) {
  if (places.isEmpty) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _MapSheet(
        data: data,
        title: title,
        places: places,
        onVerse: onVerse,
      ),
    ),
  );
}

class _MapSheet extends StatefulWidget {
  const _MapSheet({
    required this.data,
    required this.title,
    required this.places,
    this.onVerse,
  });

  final AtlasData data;
  final String title;
  final List<ChapterPlace> places;
  final ValueChanged<int>? onVerse;

  @override
  State<_MapSheet> createState() => _MapSheetState();
}

class _MapSheetState extends State<_MapSheet> {
  final GlobalKey<AtlasMapState> _map = GlobalKey<AtlasMapState>();

  late final List<Place> _points = [
    for (final named in widget.places) named.place,
  ];

  ChapterPlace? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
              flex: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AtlasMap(
                        key: _map,
                        data: widget.data,
                        places: _points,
                        selected: selected?.place,
                        onSelected: _select,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: _Controls(
                        onZoomIn: () => _map.currentState?.zoomBy(1.8),
                        onZoomOut: () => _map.currentState?.zoomBy(1 / 1.8),
                        onReset: () => _map.currentState?.reset(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // The chips scroll sideways rather than wrapping: a wrapped row
            // of long names used to be cut off by the edge of the sheet.
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.places.length,
                separatorBuilder: (context, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final named = widget.places[index];
                  return Center(
                    child: ChoiceChip(
                      label: Text(named.place.name),
                      selected: named.place == selected?.place,
                      onSelected: (chosen) {
                        _select(chosen ? named.place : null);
                        // Chosen from the list, it may be anywhere; bring it
                        // to the middle rather than leaving the reader to
                        // hunt for it.
                        if (chosen) _map.currentState?.centreOn(named.place);
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: selected == null
                  ? _Hint(theme: theme)
                  : _Details(
                      named: selected,
                      onVerse: (verse) {
                        Navigator.of(context).pop();
                        widget.onVerse?.call(verse);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _select(Place? place) {
    setState(() {
      _selected = place == null
          ? null
          : widget.places.firstWhere((named) => named.place == place);
    });
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Button(icon: Icons.add_rounded, tooltip: 'Zoom in', onTap: onZoomIn),
          _Button(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom out',
            onTap: onZoomOut,
          ),
          _Button(
            icon: Icons.filter_center_focus_rounded,
            tooltip: 'Back to the passage',
            onTap: onReset,
          ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Drag to move, pinch or scroll to zoom, double-tap to zoom in. '
            'Tap a marker or a name for what is known about it and where the '
            'chapter names it. A hollow marker is a location scholars are not '
            'agreed on.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Atlas.attribution,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the open data knows about the place, and where this chapter names it.
class _Details extends StatelessWidget {
  const _Details({required this.named, required this.onVerse});

  final ChapterPlace named;
  final ValueChanged<int> onVerse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = named.place;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      _summary(place),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (place.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(place.comment, style: theme.textTheme.bodyMedium),
          ],
          if (place.modern.isNotEmpty) ...[
            const SizedBox(height: 6),
            _Line(
              label: 'Identified with',
              value: place.isUncertain
                  ? '${place.modern} — disputed'
                  : place.modern,
            ),
          ],
          if (place.otherNames.isNotEmpty)
            _Line(label: 'Also called', value: place.otherNames.join(', ')),
          _Line(
            label: 'Named in',
            value: place.verseCount == 1
                ? 'one verse of the Bible'
                : '${place.verseCount} verses of the Bible',
          ),
          const SizedBox(height: 10),
          Text(
            'Named here at',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final verse in named.verses)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text('verse $verse'),
                  onPressed: () => onVerse(verse),
                ),
            ],
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
    );
  }

  String _summary(Place place) {
    final kinds = place.types.join(', ');
    final lat = place.lat.abs().toStringAsFixed(3);
    final lon = place.lon.abs().toStringAsFixed(3);
    final where =
        '$lat°${place.lat >= 0 ? 'N' : 'S'} '
        '$lon°${place.lon >= 0 ? 'E' : 'W'}';
    return '$kinds • $where${place.isUncertain ? ' • location uncertain' : ''}';
  }

  IconData get _icon => switch (named.place.type) {
    'settlement' => Icons.location_city_rounded,
    'region' || 'people group' => Icons.crop_free_rounded,
    'mountain' || 'mountain range' || 'hill' => Icons.terrain_rounded,
    'river' || 'spring' || 'body of water' => Icons.water_rounded,
    'island' => Icons.landscape_rounded,
    'campsite' => Icons.cabin_rounded,
    'gate' => Icons.door_front_door_rounded,
    _ => Icons.place_rounded,
  };
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
