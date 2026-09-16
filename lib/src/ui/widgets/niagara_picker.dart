import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How the idle (non-scrubbing) list is laid out.
enum PickerLayout {
  /// One row per entry — used for book names.
  list,

  /// Compact chips — used for chapter and verse numbers.
  grid,
}

/// One selectable entry inside a [PickerGroup].
@immutable
class PickerEntry<T> {
  const PickerEntry({
    required this.label,
    required this.value,
    this.subtitle,
    this.selected = false,
    this.marked = false,
  });

  final String label;
  final String? subtitle;
  final T value;

  /// Drawn as the current choice (the book or chapter being read).
  final bool selected;

  /// Drawn with a dot — used for chapters that contain a bookmark.
  final bool marked;
}

/// A rail slot: a letter, a number range or a section name, plus the entries
/// that live under it.
@immutable
class PickerGroup<T> {
  const PickerGroup({required this.key, required this.entries});

  /// Short rail label, e.g. `J`, `70`, `NT`.
  final String key;

  final List<PickerEntry<T>> entries;

  bool get isEmpty => entries.isEmpty;
}

/// An index rail in the spirit of Niagara Launcher's alphabet scrubber.
///
/// The rail lives on the trailing edge; the text always sits to its left. While
/// a finger is on the rail the nearest labels swell and slide toward the touch
/// point with a smooth falloff, and the entries under the focused label fan in
/// next to it. Sliding left off the rail hovers an entry, and lifting picks it;
/// lifting on the rail leaves the group pinned so it can be tapped instead.
class NiagaraPicker<T> extends StatefulWidget {
  const NiagaraPicker({
    required this.groups,
    required this.onSelected,
    this.layout = PickerLayout.list,
    this.emptyLabel = 'Nothing here yet',
    this.railWidth = 52,
    super.key,
  });

  final List<PickerGroup<T>> groups;
  final ValueChanged<T> onSelected;
  final PickerLayout layout;
  final String emptyLabel;
  final double railWidth;

  @override
  State<NiagaraPicker<T>> createState() => _NiagaraPickerState<T>();
}

class _NiagaraPickerState<T> extends State<NiagaraPicker<T>>
    with TickerProviderStateMixin {
  /// How far up and down the rail a touch pulls neighbouring labels, as a
  /// multiple of one slot's height.
  static const double _reachInSlots = 3.4;
  static const double _maxGrowth = 1.35;
  static const double _maxSlide = 30;

  late final AnimationController _engage = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final AnimationController _fanIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );

  double? _touchY;
  int? _activeGroup;
  int? _hoverEntry;
  bool _pinned = false;

  _RailGeometry _geometry = const _RailGeometry.empty();

  @override
  void dispose() {
    _engage.dispose();
    _fanIn.dispose();
    super.dispose();
  }

  List<PickerGroup<T>> get _groups => widget.groups;

  void _engageAt(double y) {
    final index = _geometry.indexAt(y);
    final changed = index != _activeGroup;
    setState(() {
      _touchY = y;
      _pinned = true;
      if (changed) {
        _activeGroup = index;
        _hoverEntry = null;
        _fanIn.forward(from: 0);
      }
    });
    if (changed) HapticFeedback.selectionClick();
    _engage.forward();
  }

  void _hoverAt(double dy) {
    final group = _activeGroup;
    if (group == null) return;
    final index = _geometry.entryIndexAt(
      dy,
      activeIndex: group,
      entryCount: _groups[group].entries.length,
    );
    if (index == _hoverEntry) return;
    setState(() => _hoverEntry = index);
    if (index != null) HapticFeedback.selectionClick();
  }

  /// Lifting a finger picks the hovered entry, or — when the touch never left
  /// the rail — leaves the group fanned out so it can be tapped instead.
  void _release() {
    final group = _activeGroup;
    final hovered = _hoverEntry;
    if (group != null && hovered != null) {
      final entries = _groups[group].entries;
      setState(() => _hoverEntry = null);
      if (hovered < entries.length) {
        widget.onSelected(entries[hovered].value);
        return;
      }
    }
    setState(() {
      _hoverEntry = null;
      // Keep the chosen letter emphasised while its group stays open.
      if (group != null) _touchY = _geometry.centerOf(group);
    });
  }

  void _dismiss() {
    _engage.reverse();
    setState(() {
      _pinned = false;
      _activeGroup = null;
      _touchY = null;
      _hoverEntry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_groups.every((group) => group.isEmpty)) {
      return Center(
        child: Text(
          widget.emptyLabel,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _geometry = _RailGeometry(
          height: constraints.maxHeight,
          count: _groups.length,
          contentWidth: constraints.maxWidth - widget.railWidth,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _pinned ? _dismiss : null,
              ),
            ),
            Positioned.fill(
              right: widget.railWidth,
              child: _buildContent(context),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: widget.railWidth,
              child: _buildRail(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return AnimatedBuilder(
      animation: _engage,
      builder: (context, _) {
        final engaged = Curves.easeOut.transform(_engage.value);
        return Stack(
          children: [
            // The browsable list stays underneath, fading back while the rail
            // is in use.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: engaged > 0.6,
                child: Opacity(
                  opacity: 1 - engaged * 0.85,
                  child: _IdleContent<T>(
                    groups: _groups,
                    layout: widget.layout,
                    onSelected: widget.onSelected,
                  ),
                ),
              ),
            ),
            if (_activeGroup != null && engaged > 0.01)
              // Inset so the pills never sit under a label that has slid in
              // from the rail.
              Positioned.fill(
                right: _maxSlide + 4,
                child: _buildFan(context, engaged),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFan(BuildContext context, double engaged) {
    final theme = Theme.of(context);
    final group = _groups[_activeGroup!];
    final entries = group.entries;
    if (entries.isEmpty) {
      return Align(
        alignment: Alignment.centerRight,
        child: Opacity(
          opacity: engaged,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              'No books under ${group.key}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    final layout = _geometry.fanLayout(
      activeIndex: _activeGroup!,
      count: entries.length,
    );

    return AnimatedBuilder(
      animation: _fanIn,
      builder: (context, _) {
        final children = <Widget>[];
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final start = math.min(0.55, i * 0.055);
          final stagger = CurvedAnimation(
            parent: _fanIn,
            curve: Interval(
              start,
              math.min(1, start + 0.45),
              curve: Curves.easeOutCubic,
            ),
          ).value;
          children.add(
            Positioned(
              right: 0,
              left: 0,
              top: layout.top + i * layout.itemHeight,
              height: layout.itemHeight,
              child: Opacity(
                opacity: engaged * stagger,
                child: Transform.translate(
                  offset: Offset(28 * (1 - stagger), 0),
                  child: _FanEntry(
                    entry: entry,
                    hovered: _hoverEntry == i,
                    height: layout.itemHeight,
                    onTap: () => widget.onSelected(entry.value),
                  ),
                ),
              ),
            ),
          );
        }
        return Stack(children: children);
      },
    );
  }

  Widget _buildRail(BuildContext context) {
    final theme = Theme.of(context);
    // A raw [Listener] engages the rail the instant a finger lands, which a
    // tap recogniser cannot do while it is still competing in the arena. The
    // [GestureDetector] is kept so the rail wins vertical drags against an
    // enclosing sheet or page view.
    return Listener(
      onPointerDown: (event) => _engageAt(event.localPosition.dy),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (_) => _release(),
        // Pan rather than a vertical drag: a finger that slides straight left
        // onto a fanned entry never travels far enough vertically for a
        // vertical-drag recogniser to claim the gesture.
        onPanUpdate: (details) {
          final position = details.localPosition;
          if (position.dx < -8) {
            _hoverAt(position.dy);
          } else {
            if (_hoverEntry != null) setState(() => _hoverEntry = null);
            _engageAt(position.dy);
          }
        },
        onPanEnd: (_) => _release(),
        child: AnimatedBuilder(
          animation: _engage,
          builder: (context, _) {
            final engaged = Curves.easeOut.transform(_engage.value);
            final touch = _touchY;
            final slot = _geometry.slotHeight;
            final reach = math.max(slot * _reachInSlots, 56.0);

            return Stack(
              children: [
                for (var i = 0; i < _groups.length; i++)
                  _railLabel(theme, i, slot, reach, touch, engaged),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _railLabel(
    ThemeData theme,
    int index,
    double slot,
    double reach,
    double? touch,
    double engaged,
  ) {
    final center = _geometry.centerOf(index);
    final group = _groups[index];
    final distance = touch == null ? reach : (touch - center).abs();
    final pull = (1 - distance / reach).clamp(0.0, 1.0);
    final falloff = Curves.easeOutCubic.transform(pull) * engaged;
    final isActive = _activeGroup == index && engaged > 0.05;

    final baseColor = group.isEmpty
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35)
        : theme.colorScheme.onSurfaceVariant;
    final color = Color.lerp(baseColor, theme.colorScheme.primary, falloff)!;

    return Positioned(
      top: center - slot / 2,
      right: 0,
      width: widget.railWidth,
      height: slot,
      child: Transform.translate(
        offset: Offset(-_maxSlide * falloff, 0),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Transform.scale(
              scale: 1 + _maxGrowth * falloff,
              alignment: Alignment.centerRight,
              child: Text(
                group.key,
                textAlign: TextAlign.right,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rail slot arithmetic, shared by the labels and the fan-out.
@immutable
class _RailGeometry {
  const _RailGeometry({
    required this.height,
    required this.count,
    required this.contentWidth,
  });

  const _RailGeometry.empty() : height = 0, count = 1, contentWidth = 0;

  final double height;
  final int count;
  final double contentWidth;

  static const double _minSlot = 14;
  static const double _maxSlot = 30;

  double get slotHeight {
    if (count == 0) return _maxSlot;
    return (height / count).clamp(_minSlot, _maxSlot);
  }

  double get railHeight => slotHeight * count;

  /// The rail is centred vertically when it does not fill the whole side.
  double get railTop => math.max(0, (height - railHeight) / 2);

  double centerOf(int index) => railTop + slotHeight * (index + 0.5);

  int indexAt(double y) {
    final raw = ((y - railTop) / slotHeight).floor();
    return raw.clamp(0, count - 1);
  }

  _FanLayout fanLayout({required int activeIndex, required int count}) {
    final itemHeight = (height / math.max(count, 1)).clamp(30.0, 52.0);
    final total = itemHeight * count;
    var top = centerOf(activeIndex) - total / 2;
    top = top.clamp(0.0, math.max(0.0, height - total));
    return _FanLayout(top: top, itemHeight: itemHeight);
  }

  /// Which fanned entry sits at [dy], or null when the touch is past the ends
  /// of the fan.
  int? entryIndexAt(
    double dy, {
    required int activeIndex,
    required int entryCount,
  }) {
    if (entryCount == 0) return null;
    final layout = fanLayout(activeIndex: activeIndex, count: entryCount);
    final index = ((dy - layout.top) / layout.itemHeight).floor();
    if (index < 0 || index >= entryCount) return null;
    return index;
  }
}

@immutable
class _FanLayout {
  const _FanLayout({required this.top, required this.itemHeight});

  final double top;
  final double itemHeight;
}

/// A single fanned-out entry.
class _FanEntry extends StatelessWidget {
  const _FanEntry({
    required this.entry,
    required this.hovered,
    required this.height,
    required this.onTap,
  });

  final PickerEntry<Object?> entry;
  final bool hovered;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emphasised = hovered || entry.selected;
    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        height: height - 4,
        padding: EdgeInsets.symmetric(horizontal: hovered ? 18 : 14),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: hovered
              ? theme.colorScheme.primary
              : entry.selected
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.9,
                ),
          borderRadius: BorderRadius.circular(height),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(height),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.marked)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.bookmark,
                      size: 14,
                      color: hovered
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.primary,
                    ),
                  ),
                Text(
                  entry.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: hovered
                        ? theme.colorScheme.onPrimary
                        : entry.selected
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurface,
                    fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The plain, always-scrollable view of every entry, shown when the rail is
/// idle so the picker works without gestures too.
class _IdleContent<T> extends StatelessWidget {
  const _IdleContent({
    required this.groups,
    required this.layout,
    required this.onSelected,
  });

  final List<PickerGroup<T>> groups;
  final PickerLayout layout;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    for (final group in groups) {
      if (group.isEmpty) continue;
      children.add(
        Padding(
          padding: EdgeInsets.only(
            left: 20,
            top: children.isEmpty ? 4 : 18,
            bottom: 6,
          ),
          child: Text(
            group.key,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      switch (layout) {
        case PickerLayout.list:
          for (final entry in group.entries) {
            children.add(
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(entry.label),
                subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
                selected: entry.selected,
                trailing: entry.marked
                    ? Icon(
                        Icons.bookmark,
                        size: 16,
                        color: theme.colorScheme.primary,
                      )
                    : null,
                onTap: () => onSelected(entry.value),
              ),
            );
          }
        case PickerLayout.grid:
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in group.entries)
                    _NumberChip(
                      entry: entry,
                      onTap: () => onSelected(entry.value),
                    ),
                ],
              ),
            ),
          );
      }
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }
}

/// A chapter or verse number in the idle grid.
class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.entry, required this.onTap});

  final PickerEntry<Object?> entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 54,
      height: 48,
      child: Material(
        color: entry.selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Stack(
            children: [
              Center(
                child: Text(
                  entry.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: entry.selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (entry.marked)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.bookmark,
                    size: 11,
                    color: entry.selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
