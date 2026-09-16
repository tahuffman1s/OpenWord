import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/bible_source.dart';
import '../data/library.dart';

/// First-launch flow: pick a freely licensed translation and download it.
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  BibleSource? _chosen;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final library = scope.library;
    final theme = Theme.of(context);
    final source = _chosen ?? BibleSource.byId(scope.settings.translationId);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedBuilder(
                animation: library,
                builder: (context, _) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Logo(theme: theme),
                      const SizedBox(height: 28),
                      Text(
                        'OpenWord',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A free and open source Bible reader',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (library.isBusy)
                        _Progress(library: library)
                      else ...[
                        _TranslationPicker(
                          selected: source,
                          onChanged: (value) {
                            setState(() => _chosen = value);
                            scope.settings.translationId = value.id;
                          },
                        ),
                        const SizedBox(height: 20),
                        if (library.status == LibraryStatus.failed)
                          _ErrorCard(message: library.errorMessage ?? ''),
                        FilledButton.icon(
                          onPressed: () => library.download(source),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            library.status == LibraryStatus.failed
                                ? 'Try again'
                                : 'Download ${source.info.abbreviation}',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '${source.info.name} • ${source.info.license}\n'
                          'Downloaded once, then read entirely offline.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(34),
        ),
        child: Icon(
          Icons.auto_stories_rounded,
          size: 56,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indeterminate =
        library.status == LibraryStatus.parsing ||
        library.status == LibraryStatus.loading ||
        library.status == LibraryStatus.checking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: indeterminate ? null : library.progress,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          library.message.isEmpty ? 'Working…' : library.message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TranslationPicker extends StatelessWidget {
  const _TranslationPicker({required this.selected, required this.onChanged});

  final BibleSource selected;
  final ValueChanged<BibleSource> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final source in BibleSource.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onChanged(source),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: source.id == selected.id
                      ? theme.colorScheme.secondaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                ),
                child: Row(
                  children: [
                    Icon(
                      source.id == selected.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.info.name,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            '${source.info.abbreviation} • '
                            '${source.info.license}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
