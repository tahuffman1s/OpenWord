import 'package:flutter/material.dart';

import '../data/updates.dart';
import 'widgets/simple_markdown.dart';

/// What is in the new version, and the one button that gets it.
void showUpdateSheet(BuildContext context, UpdateService updates) {
  if (updates.release == null) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _UpdateSheet(updates: updates),
    ),
  );
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.updates});

  final UpdateService updates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: updates,
      builder: (context, _) {
        final release = updates.release;
        if (release == null) return const SizedBox.shrink();
        final asset = updates.asset;

        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(release.name, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'You have ${updates.currentVersion}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SimpleMarkdown(
                    source: _readable(release.notes),
                    baseStyle: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: _Actions(updates: updates, asset: asset),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The release notes end with the installation boilerplate the workflow
  /// appends, which is of no use to someone already holding the app.
  static String _readable(String notes) {
    final cut = notes.indexOf('\n---\n');
    final body = cut > 0 ? notes.substring(0, cut) : notes;
    return body.trim().isEmpty ? 'No notes for this release.' : body.trim();
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.updates, required this.asset});

  final UpdateService updates;
  final ReleaseAsset? asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = asset;

    switch (updates.stage) {
      case UpdateStage.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: updates.progress),
            const SizedBox(height: 8),
            Text(
              updates.progress == null
                  ? 'Downloading…'
                  : 'Downloading — ${(updates.progress! * 100).round()}%',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );

      case UpdateStage.readyToInstall:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: updates.install,
              icon: const Icon(Icons.install_mobile_rounded),
              label: const Text('Install'),
            ),
            const SizedBox(height: 8),
            Text(
              'Android will ask you to confirm. If it refuses, allow OpenWord '
              'to install unknown apps and try again.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

      case UpdateStage.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              updates.error ?? 'That did not work.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: updates.openReleasePage,
              child: const Text('Open the release page'),
            ),
          ],
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (updates.canInstall && file != null)
              FilledButton.icon(
                onPressed: updates.download,
                icon: const Icon(Icons.download_rounded),
                label: Text('Download ${file.readableSize}'),
              )
            else
              FilledButton.icon(
                onPressed: updates.openReleasePage,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open the release page'),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                updates.skipThisVersion();
                Navigator.of(context).pop();
              },
              child: const Text('Skip this version'),
            ),
          ],
        );
    }
  }
}
