import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../app_version.dart';
import '../data/atlas.dart';
import '../data/bib_export.dart';
import '../data/library.dart';
import '../data/book_intros.dart';
import '../data/cross_references.dart';
import '../data/marks.dart';
import '../data/originals.dart';
import '../data/settings.dart';
import '../data/translations.dart';
import '../data/updates.dart';
import '../model/bib_file.dart';
import '../model/bible.dart';
import 'import_sheet.dart';
import 'update_sheet.dart';

/// Display, reading, translation and backup preferences.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final library = scope.library;
    final reading = scope.reading;
    final updates = scope.updates;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          settings,
          library,
          reading,
          updates,
          if (library.shelf != null) library.shelf!,
        ]),
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
              for (final translation in library.available)
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
                      [
                        '${translation.abbreviation} • ${translation.license}',
                        // Said here as well as at import, so that a reader
                        // who later wonders where the cross-references
                        // went is not left guessing — and, where they have
                        // asked for them regardless, what they asked for.
                        if (!Versification.mayAnchorEnglish(
                          translation.versification,
                        ))
                          settings.anchoredAnyway.contains(translation.id)
                              ? 'Numbers its verses differently. '
                                    'Cross-references and the Hebrew and '
                                    'Greek are offered anyway, at your '
                                    'word: expect some to be out by a '
                                    'verse or two.'
                              : 'Numbers its verses differently, so '
                                    'cross-references and the Hebrew and '
                                    'Greek are not offered for it.',
                      ].join('\n'),
                    ),
                    isThreeLine: !Versification.mayAnchorEnglish(
                      translation.versification,
                    ),
                    secondary: _TranslationMenu(
                      translation: translation,
                      settings: settings,
                      library: library,
                    ),
                  ),
                ),
              if (library.shelf != null)
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('Add a translation'),
                  subtitle: const Text(
                    'Import an EPUB of a Bible, or a .bib file',
                  ),
                  onTap: () => showImportSheet(
                    context,
                    shelf: library.shelf!,
                    library: library,
                    settings: settings,
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.compare_arrows_rounded),
                title: const Text('Compare with'),
                subtitle: Text(
                  settings.compareTranslationId == null
                      ? 'Off'
                      : library.infoFor(settings.compareTranslationId!).name,
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
                    for (final translation in library.available)
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
              if (updates.isSupported) ...[
                const _Header('Updates'),
                SwitchListTile(
                  title: const Text('Check for updates'),
                  subtitle: const Text(
                    'Asks GitHub once a day whether a newer release is out. '
                    'This is the only thing OpenWord uses the network for.',
                  ),
                  value: settings.checkForUpdates,
                  onChanged: (value) => settings.checkForUpdates = value,
                  isThreeLine: true,
                ),
                _UpdateRow(updates: updates),
              ],
              const _Header('About'),
              ListTile(
                leading: const Icon(Icons.auto_stories_rounded),
                title: const Text('OpenWord'),
                // The version is shown under Updates, where it is useful.
                subtitle: const Text(
                  'A free and open source Bible reader. The translations, the '
                  'introductions, the maps, the cross-references and the '
                  'Hebrew and Greek are all bundled, so reading needs no '
                  'connection.',
                ),
                isThreeLine: true,
              ),
              // Everything readable, not only what shipped: a translation
              // the reader imported may carry wording its licence obliges
              // the app to show, and a file that says so is no use if
              // nothing reads it out.
              for (final translation in library.available)
                ListTile(
                  dense: true,
                  title: Text(translation.name),
                  subtitle: Text(
                    translation.attribution.isNotEmpty
                        ? translation.attribution
                        : [
                            translation.license,
                            translation.sourceUrl,
                          ].where((part) => part.isNotEmpty).join(' • '),
                  ),
                  isThreeLine: translation.attribution.isNotEmpty,
                ),
              const ListTile(
                dense: true,
                title: Text('Book introductions'),
                subtitle: Text(BookIntros.attribution),
                isThreeLine: true,
              ),
              const ListTile(
                dense: true,
                title: Text('Maps'),
                subtitle: Text(Atlas.attribution),
                isThreeLine: true,
              ),
              const ListTile(
                dense: true,
                title: Text('Cross-references'),
                subtitle: Text(CrossReferences.attribution),
                isThreeLine: true,
              ),
              const ListTile(
                dense: true,
                title: Text('Hebrew, Greek and Strong\'s'),
                subtitle: Text(Originals.attribution),
                isThreeLine: true,
              ),
              const ListTile(
                dense: true,
                title: Text('Literata, Noto Serif, Noto Serif Hebrew'),
                subtitle: Text('SIL Open Font License 1.1'),
                isThreeLine: true,
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

/// The state of the update check: what is installed, whether anything newer
/// is out, and the button that goes and looks.
class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.updates});

  final UpdateService updates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final release = updates.release;

    final (String subtitle, Widget? trailing) = switch (updates.stage) {
      UpdateStage.checking => (
        'Asking GitHub…',
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      UpdateStage.failed => (updates.error ?? 'The check did not work.', null),
      UpdateStage.upToDate => ('This is the newest release.', null),
      _ when updates.updateAvailable && release != null => (
        '${release.version} is out.',
        FilledButton(
          onPressed: () => showUpdateSheet(context, updates),
          child: const Text('See it'),
        ),
      ),
      _ => ('Last checked ${_when(updates.settings.lastUpdateCheck)}.', null),
    };

    return ListTile(
      title: Text('Version $appVersion'),
      subtitle: Text(subtitle),
      trailing:
          trailing ??
          TextButton(
            onPressed: updates.stage == UpdateStage.checking
                ? null
                : () => updates.check(force: true),
            child: const Text('Check now'),
          ),
      textColor: updates.stage == UpdateStage.failed
          ? theme.colorScheme.error
          : null,
    );
  }

  static String _when(DateTime? at) {
    if (at == null) return 'never';
    final days = DateTime.now().difference(at).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    return '$days days ago';
  }
}

/// What can be done with a translation: keep a copy of the `.bib`, and —
/// where the reader brought it themselves — take it off the shelf again.
///
/// Saving works for the three that ship as well as for an import. A format
/// only one app can write is that app's cache; one any of them can hand to
/// the next is a format, and there is no reason the bundled three should be
/// the ones nobody can get out.
class _TranslationMenu extends StatelessWidget {
  const _TranslationMenu({
    required this.translation,
    required this.settings,
    required this.library,
  });

  final TranslationInfo translation;

  String get id => translation.id;
  String get name => translation.name;
  final Settings settings;
  final LibraryController library;

  bool get _imported => library.isImported(id);

  /// The `.bib` itself, wherever it lives.
  Future<Uint8List?> _bytes() async {
    if (_imported) return library.shelf?.fileBytes(id);
    final data = await library.bundle.load(Translations.assetFor(id));
    return Uint8List.sublistView(data);
  }

  @override
  Widget build(BuildContext context) {
    final shelved = library.shelf?.byId(id);
    return PopupMenuButton<String>(
      tooltip: _imported ? 'Imported translation' : 'Translation',
      icon: Icon(
        _imported ? Icons.inventory_2_outlined : Icons.more_vert_rounded,
      ),
      itemBuilder: (context) => [
        if (_imported)
          PopupMenuItem(
            value: 'about',
            enabled: false,
            child: Text(shelved == null ? 'Imported' : shelved.readableSize),
          ),
        // Only where the app has withheld them, since that is the only
        // case there is anything to overrule.
        if (!Versification.mayAnchorEnglish(translation.versification))
          CheckedPopupMenuItem(
            value: 'anchor',
            checked: settings.anchoredAnyway.contains(id),
            child: const Text('Cross-references and originals anyway'),
          ),
        const PopupMenuItem(value: 'save', child: Text('Save a copy…')),
        const PopupMenuItem(
          value: 'save-with-layers',
          child: Text('Save a copy with the study layers…'),
        ),
        if (_imported)
          const PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
      onSelected: (choice) async {
        final messenger = ScaffoldMessenger.of(context);
        if (choice == 'anchor') {
          final wanted = !settings.anchoredAnyway.contains(id);
          settings.setAnchoredAnyway(id, wanted);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                wanted
                    ? 'Cross-references and the Hebrew and Greek are on for '
                          '$name. Some will be out by a verse or two.'
                    : 'Cross-references and the Hebrew and Greek are off '
                          'for $name again.',
              ),
            ),
          );
          return;
        }
        if (choice == 'save') {
          final bytes = await _bytes();
          if (bytes == null) return;
          final saved = await FilePicker.saveFile(
            dialogTitle: 'Save $name',
            fileName: '$id${BibFile.extension}',
            bytes: bytes,
          );
          if (saved == null) return;
          messenger.showSnackBar(
            SnackBar(content: Text('Saved to ${_where(saved)}')),
          );
          return;
        }
        if (choice == 'save-with-layers') {
          await _saveWithLayers(messenger);
          return;
        }
        if (choice == 'remove') {
          final shelf = library.shelf;
          if (shelf == null) return;
          await shelf.remove(id);
          // Whatever was being read has just gone; fall back to a bundled
          // translation rather than an empty screen.
          if (settings.translationId == id) {
            settings.translationId = Translations.fallback.id;
            await library.load(Translations.fallback.id);
          }
          if (settings.compareTranslationId == id) {
            settings.compareTranslationId = null;
          }
          messenger.showSnackBar(SnackBar(content: Text('Removed $name')));
        }
      },
    );
  }

  /// Saves the `.bib` with the app's cross-references and its Hebrew and
  /// Greek written into it, so the file carries them wherever it goes and
  /// whatever opens it.
  ///
  /// Refused where the translation's numbering was measured as different
  /// and the reader has not overruled that: baking layers into a file they
  /// do not fit would put the mistake beyond reach of anyone who later
  /// reads it.
  Future<void> _saveWithLayers(ScaffoldMessengerState messenger) async {
    void say(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));

    if (!settings.offersVerseKeyedLayers(translation)) {
      say(
        '$name numbers its verses differently, so the bundled layers would '
        'land on the wrong verses. Turn them on for it first if you want '
        'them anyway.',
      );
      return;
    }

    final bytes = await _bytes();
    if (bytes == null) return;

    // A translation that brought layers of its own keeps them: they are
    // keyed to its own numbering, and the bundled ones are no improvement
    // on that.
    List<String> tags;
    try {
      tags = BibFile.tags(bytes);
    } on Object {
      tags = const [];
    }
    final wanted = StudyLayers(
      crossReferences: tags.contains(CrossReferences.chunkTag)
          ? null
          : Uint8List.sublistView(
              await library.bundle.load(CrossReferences.assetPath),
            ),
      originals: tags.contains(Originals.chunkTag)
          ? null
          : Uint8List.sublistView(
              await library.bundle.load(Originals.assetPath),
            ),
    );
    if (wanted.isEmpty) {
      say('$name already carries both of them.');
      return;
    }

    say('Writing the study layers into $name…');
    final AttachedLayers written;
    try {
      written = await compute(attachStudyLayers, (bytes, wanted));
    } on Object catch (error) {
      say('Could not write them in: $error');
      return;
    }

    final saved = await FilePicker.saveFile(
      dialogTitle: 'Save $name with the study layers',
      fileName: '$id-study${BibFile.extension}',
      bytes: written.bytes,
    );
    if (saved == null) return;
    final megabytes = (written.bytes.length / (1024 * 1024)).toStringAsFixed(
      1,
    );
    say(
      'Saved $megabytes MB to ${_where(saved)} — '
      '${written.references} verses of cross-references, '
      '${written.verses} of Hebrew and Greek.',
    );
  }

  /// A file:// URI reads as a path; anything else (the browser's download,
  /// a content:// URI on Android) is better shown as it is.
  static String _where(Uri saved) =>
      saved.isScheme('file') ? saved.toFilePath() : saved.toString();
}
