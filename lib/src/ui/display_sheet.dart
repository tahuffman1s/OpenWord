import 'package:flutter/material.dart';

import '../data/settings.dart';
import '../data/translations.dart';
import '../model/bible.dart';

/// Quick reading controls, reachable from the reader without leaving the page,
/// plus the picker for reading two translations side by side.
class DisplaySheet extends StatelessWidget {
  const DisplaySheet({
    required this.settings,
    required this.current,
    super.key,
  });

  final Settings settings;

  /// The translation being read, so it is not offered as its own comparison.
  final TranslationInfo current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Display', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                _sizeRow(context, theme),
                _slider(
                  theme,
                  label: 'Line spacing',
                  value: settings.lineHeight,
                  min: 1.2,
                  max: 2.4,
                  divisions: 12,
                  display: settings.lineHeight.toStringAsFixed(1),
                  onChanged: (value) => settings.lineHeight = value,
                ),
                const SizedBox(height: 8),
                SegmentedButton<ReadingFont>(
                  segments: [
                    for (final font in ReadingFont.values)
                      ButtonSegment(value: font, label: Text(font.label)),
                  ],
                  selected: {settings.readingFont},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      settings.readingFont = selection.first,
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.paragraphLayout,
                  title: const Text('Paragraph layout'),
                  onChanged: (value) => settings.paragraphLayout = value,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.showVerseNumbers,
                  title: const Text('Verse numbers'),
                  onChanged: (value) => settings.showVerseNumbers = value,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.redLetter,
                  title: const Text('Words of Jesus in red'),
                  onChanged: (value) => settings.redLetter = value,
                ),
                const Divider(height: 24),
                Text('Compare with', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Shows a second translation verse by verse.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Off'),
                      selected: settings.compareTranslationId == null,
                      onSelected: (_) => settings.compareTranslationId = null,
                    ),
                    for (final translation in Translations.all)
                      if (translation.id != current.id)
                        ChoiceChip(
                          label: Text(translation.abbreviation),
                          selected:
                              settings.compareTranslationId == translation.id,
                          onSelected: (_) =>
                              settings.compareTranslationId = translation.id,
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sizeRow(BuildContext context, ThemeData theme) {
    void nudge(double delta) {
      settings.fontScale = (settings.fontScale + delta).clamp(0.8, 2.0);
    }

    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: settings.fontScale > 0.8 ? () => nudge(-0.1) : null,
          icon: const Text('A', style: TextStyle(fontSize: 13)),
          tooltip: 'Smaller text',
        ),
        Expanded(
          child: Slider(
            value: settings.fontScale.clamp(0.8, 2.0),
            min: 0.8,
            max: 2.0,
            divisions: 12,
            label: '${(settings.fontScale * 100).round()}%',
            onChanged: (value) => settings.fontScale = value,
          ),
        ),
        IconButton.filledTonal(
          onPressed: settings.fontScale < 2.0 ? () => nudge(0.1) : null,
          icon: const Text('A', style: TextStyle(fontSize: 21)),
          tooltip: 'Larger text',
        ),
      ],
    );
  }

  Widget _slider(
    ThemeData theme, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyLarge),
            Text(display, style: theme.textTheme.labelLarge),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
