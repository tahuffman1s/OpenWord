import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/marks.dart';
import '../data/settings.dart';
import '../data/translations.dart';

/// Display, reading, translation and backup preferences.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final library = scope.library;
    final reading = scope.reading;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: Listenable.merge([settings, library, reading]),
        builder: (context, _) {
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const _Header('Theme'),
              const ListTile(
                title: Text('Appearance'),
                subtitle: Text('Light, dark or follow the system'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_rounded),
                    ),
                  ],
                  selected: {settings.themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      settings.themeMode = selection.first,
                ),
              ),
              SwitchListTile(
                value: settings.useDynamicColor,
                title: const Text('Material You colours'),
                subtitle: const Text(
                  'Use the wallpaper palette where the system provides one',
                ),
                onChanged: (value) => settings.useDynamicColor = value,
              ),
              if (!settings.useDynamicColor)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final color in Settings.seedChoices)
                        InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => settings.seedColor = color,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    settings.seedColor.toARGB32() ==
                                        color.toARGB32()
                                    ? theme.colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const _Header('Reading'),
              ListTile(
                title: const Text('Typeface'),
                trailing: SegmentedButton<ReadingFont>(
                  segments: [
                    for (final font in ReadingFont.values)
                      ButtonSegment(value: font, label: Text(font.label)),
                  ],
                  selected: {settings.readingFont},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      settings.readingFont = selection.first,
                ),
              ),
              _SliderTile(
                title: 'Text size',
                value: settings.fontScale,
                min: 0.8,
                max: 2.0,
                divisions: 12,
                label: '${(settings.fontScale * 100).round()}%',
                onChanged: (value) => settings.fontScale = value,
              ),
              _SliderTile(
                title: 'Line spacing',
                value: settings.lineHeight,
                min: 1.2,
                max: 2.4,
                divisions: 12,
                label: settings.lineHeight.toStringAsFixed(1),
                onChanged: (value) => settings.lineHeight = value,
              ),
              SwitchListTile(
                value: settings.paragraphLayout,
                title: const Text('Paragraph layout'),
                subtitle: const Text(
                  'Verses flow together as in a printed Bible',
                ),
                onChanged: (value) => settings.paragraphLayout = value,
              ),
              SwitchListTile(
                value: settings.showVerseNumbers,
                title: const Text('Verse numbers'),
                onChanged: (value) => settings.showVerseNumbers = value,
              ),
              SwitchListTile(
                value: settings.redLetter,
                title: const Text('Words of Jesus in red'),
                onChanged: (value) => settings.redLetter = value,
              ),
              SwitchListTile(
                value: settings.showFootnotes,
                title: const Text('Footnote markers'),
                subtitle: const Text('Translator notes and cross references'),
                onChanged: (value) => settings.showFootnotes = value,
              ),
              SwitchListTile(
                value: settings.showDeuterocanon,
                title: const Text('Deuterocanonical books'),
                subtitle: const Text(
                  'Include Tobit through 4 Maccabees where the edition has '
                  'them',
                ),
                onChanged: (value) => settings.showDeuterocanon = value,
              ),
              const _Header('Translation'),
              for (final translation in Translations.all)
                RadioGroup<String>(
                  groupValue: settings.translationId,
                  onChanged: (value) {
                    if (value == null || value == settings.translationId) {
                      return;
                    }
                    settings.translationId = value;
                    library.load(value);
                  },
                  child: RadioListTile<String>(
                    value: translation.id,
                    title: Text(translation.name),
                    subtitle: Text(
                      '${translation.abbreviation} • ${translation.license}',
                    ),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.compare_arrows_rounded),
                title: const Text('Compare with'),
                subtitle: Text(
                  settings.compareTranslationId == null
                      ? 'Off'
                      : Translations.byId(settings.compareTranslationId!).name,
                ),
                trailing: settings.compareTranslationId == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Stop comparing',
                        onPressed: () => settings.compareTranslationId = null,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final translation in Translations.all)
                      if (translation.id != settings.translationId)
                        ChoiceChip(
                          label: Text(translation.abbreviation),
                          selected:
                              settings.compareTranslationId == translation.id,
                          onSelected: (selected) =>
                              settings.compareTranslationId = selected
                              ? translation.id
                              : null,
                        ),
                  ],
                ),
              ),
              const _Header('Bookmarks, highlights and notes'),
              ListTile(
                leading: const Icon(Icons.copy_all_rounded),
                title: const Text('Copy a backup'),
                subtitle: Text(
                  '${reading.all.length} '
                  '${reading.all.length == 1 ? 'entry' : 'entries'} as JSON on '
                  'the clipboard',
                ),
                onTap: reading.all.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: reading.export()),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Backup copied to the clipboard'),
                          ),
                        );
                      },
              ),
              ListTile(
                leading: const Icon(Icons.paste_rounded),
                title: const Text('Restore from the clipboard'),
                subtitle: const Text(
                  'Merges a backup in; nothing already here is lost',
                ),
                onTap: () => _restore(context, reading),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Remove everything',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: reading.all.isEmpty
                    ? null
                    : () => _confirmClear(context, reading),
              ),
              const _Header('About'),
              ListTile(
                leading: const Icon(Icons.auto_stories_rounded),
                title: const Text('OpenWord'),
                subtitle: const Text(
                  'A free and open source Bible reader. Every translation is '
                  'bundled with the app, so nothing here needs a network '
                  'connection.',
                ),
                isThreeLine: true,
              ),
              for (final translation in Translations.all)
                ListTile(
                  dense: true,
                  title: Text(translation.name),
                  subtitle: Text(
                    '${translation.license} • ${translation.sourceUrl}',
                  ),
                ),
              const ListTile(
                dense: true,
                title: Text('Literata'),
                subtitle: Text('SIL Open Font License 1.1'),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _restore(
    BuildContext context,
    ReadingStore reading,
  ) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final text = data?.text;
    final messenger = ScaffoldMessenger.of(context);
    if (text == null || text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The clipboard is empty')),
      );
      return;
    }
    final result = reading.import(text);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? 'Restored ${result.added} new and updated ${result.updated}'
              : 'That does not look like an OpenWord backup',
        ),
      ),
    );
  }

  static Future<void> _confirmClear(
    BuildContext context,
    ReadingStore reading,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove everything?'),
        content: const Text(
          'Bookmarks, highlights and notes will all be deleted. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) reading.clearAll();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
