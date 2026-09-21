import 'package:flutter/material.dart';

import '../data/originals.dart';
import '../model/strongs_codec.dart';
import 'scripture_type.dart';

/// What Strong's says about one word, and the way to everywhere else it is
/// used.
///
/// Returns the number if the reader asked to see its occurrences.
Future<StrongsNumber?> showStrongsEntry(
  BuildContext context, {
  required StrongsNumber number,
  required Originals originals,
  String morphology = '',
  String? surface,
}) {
  return showModalBottomSheet<StrongsNumber>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _StrongsSheet(
        number: number,
        originals: originals,
        morphology: morphology,
        surface: surface,
      ),
    ),
  );
}

class _StrongsSheet extends StatelessWidget {
  const _StrongsSheet({
    required this.number,
    required this.originals,
    required this.morphology,
    required this.surface,
  });

  final StrongsNumber number;
  final Originals originals;
  final String morphology;

  /// The word as it stands in the verse, which is often inflected away from
  /// the headword.
  final String? surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = originals.entryFor(number);
    final occurrences = originals.occurrenceCount(number);
    final rtl = number.isHebrew;

    if (entry == null) {
      return _Padded(
        child: Text(
          '${number.label} is not in the dictionary.',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    return _Padded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Text(
                    entry.lemma.isEmpty ? (surface ?? '') : entry.lemma,
                    // Right-to-left inside the word, but still at the head of
                    // the column: the transliteration sits directly under it,
                    // and the two read as one heading rather than drifting to
                    // opposite margins.
                    textAlign: TextAlign.left,
                    style: scriptureStyle(
                      theme.textTheme.headlineMedium?.copyWith(height: 1.8),
                      hebrew: rtl,
                    ),
                  ),
                ),
              ),
              Chip(
                label: Text(number.label),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (entry.transliteration.isNotEmpty ||
              entry.pronunciation.isNotEmpty)
            Text(
              [
                entry.transliteration,
                if (entry.pronunciation.isNotEmpty) '(${entry.pronunciation})',
              ].where((part) => part.isNotEmpty).join('  '),
              style: scriptureStyle(
                theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                hebrew: false,
              ),
            ),
          if (morphology.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              morphology,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                if (entry.definition.trim().isNotEmpty)
                  _Section(title: 'Definition', body: entry.definition.trim()),
                if (entry.derivation.trim().isNotEmpty)
                  _Section(title: 'Derivation', body: entry.derivation.trim()),
                if (entry.kjvUsage.trim().isNotEmpty)
                  _Section(
                    title: 'How the King James renders it',
                    body: entry.kjvUsage.trim(),
                  ),
                const SizedBox(height: 8),
                if (occurrences > 0)
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).pop(number),
                    icon: const Icon(Icons.manage_search_rounded),
                    label: Text(
                      occurrences == 1
                          ? 'Used in one verse'
                          : 'Used in $occurrences verses',
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  Originals.attribution,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            style: scriptureStyle(theme.textTheme.bodyMedium, hebrew: false),
          ),
        ],
      ),
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: child,
    ),
  );
}
