import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/bible_source.dart';
import '../data/library.dart';
import '../data/settings.dart';

/// Display, reading and library preferences.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final library = scope.library;

    return Scaffold(
      appBar: AppBar(title: const Text('Display and settings')),
      body: AnimatedBuilder(
        animation: Listenable.merge([settings, library]),
        builder: (context, _) {
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const _Header('Theme'),
              ListTile(
                title: const Text('Appearance'),
                subtitle: const Text('Light, dark or follow the system'),
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
              const _Header('Library'),
              ListTile(
                title: const Text('Translation'),
                subtitle: Text(
                  '${library.source.info.name}\n'
                  '${library.source.info.license}',
                ),
                isThreeLine: true,
              ),
              RadioGroup<String>(
                groupValue: settings.translationId,
                onChanged: (value) {
                  if (library.isBusy ||
                      value == null ||
                      value == settings.translationId) {
                    return;
                  }
                  _switchTranslation(settings, library, value);
                },
                child: Column(
                  children: [
                    for (final source in BibleSource.all)
                      RadioListTile<String>(
                        value: source.id,
                        title: Text(source.info.name),
                        subtitle: Text(source.info.abbreviation),
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete downloaded text'),
                subtitle: const Text(
                  'Frees space; the app will offer to download again',
                ),
                onTap: library.isBusy
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        await library.deleteDownload();
                        navigator.popUntil((route) => route.isFirst);
                      },
              ),
              const _Header('About'),
              ListTile(
                leading: const Icon(Icons.auto_stories_rounded),
                title: const Text('OpenWord'),
                subtitle: Text(
                  'A free and open source Bible reader.\n'
                  'Scripture: ${library.source.info.name} '
                  '(${library.source.info.abbreviation}), '
                  '${library.source.info.license}.\n'
                  '${library.source.info.sourceUrl}',
                ),
                isThreeLine: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Switches translation: remember the choice, then load it from the cache or
/// download it.
Future<void> _switchTranslation(
  Settings settings,
  LibraryController library,
  String id,
) async {
  settings.translationId = id;
  await library.initialize(id);
  if (library.status == LibraryStatus.needsDownload) {
    await library.download(BibleSource.byId(id));
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
