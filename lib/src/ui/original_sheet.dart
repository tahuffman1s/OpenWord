import 'package:flutter/material.dart';

import '../data/originals.dart';
import '../model/bible.dart';
import '../model/strongs_codec.dart';
import 'scripture_type.dart';
import 'strongs_sheet.dart';

/// The Hebrew or Greek behind a verse.
///
/// The English is at the top and the original below it. Tapping an English
/// word lights up the word it most likely came from — Strong's says which
/// English words the King James used for each number, and that is enough to
/// tie most of a verse together. Where it cannot tell, it says so instead of
/// guessing.
///
/// Answers with a Strong's number if the reader asked to see its
/// concordance.
Future<StrongsNumber?> showOriginal(
  BuildContext context, {
  required Reference reference,
  required String english,
  required List<OriginalWord> words,
  required Originals originals,
}) {
  return showModalBottomSheet<StrongsNumber>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _OriginalSheet(
        reference: reference,
        english: english,
        words: words,
        originals: originals,
      ),
    ),
  );
}

class _OriginalSheet extends StatefulWidget {
  const _OriginalSheet({
    required this.reference,
    required this.english,
    required this.words,
    required this.originals,
  });

  final Reference reference;
  final String english;
  final List<OriginalWord> words;
  final Originals originals;

  @override
  State<_OriginalSheet> createState() => _OriginalSheetState();
}

class _OriginalSheetState extends State<_OriginalSheet> {
  /// Which original words are lit, and which English word lit them.
  Set<int> _highlighted = const {};
  String? _tappedEnglish;
  bool _noMatch = false;

  bool get _isHebrew =>
      widget.words.any((word) => word.strongs?.isHebrew ?? false);

  /// How the word is said, from its dictionary entry. Worth the lookup:
  /// without it the original is a shape rather than a word.
  String _transliterationOf(OriginalWord word) {
    final number = word.strongs;
    if (number == null) return '';
    return widget.originals.entryFor(number)?.transliteration ?? '';
  }

  void _tapEnglish(String word) {
    final matches = widget.originals.matchesFor(widget.words, word);
    setState(() {
      if (_tappedEnglish == word) {
        _tappedEnglish = null;
        _highlighted = const {};
        _noMatch = false;
        return;
      }
      _tappedEnglish = word;
      _highlighted = matches.toSet();
      _noMatch = matches.isEmpty;
    });
  }

  Future<void> _openWord(int index) async {
    final word = widget.words[index];
    final number = word.strongs;
    if (number == null) return;
    setState(() {
      _highlighted = {index};
      _tappedEnglish = null;
      _noMatch = false;
    });
    final wanted = await showStrongsEntry(
      context,
      number: number,
      originals: widget.originals,
      morphology: word.morphology,
      surface: word.text,
    );
    if (wanted != null && mounted) Navigator.of(context).pop(wanted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tagged = widget.words.where((w) => w.strongs != null).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.reference.label,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Text(
                  _isHebrew ? 'Hebrew' : 'Greek',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            Text(
              '$tagged words',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _EnglishLine(
                    text: widget.english,
                    selected: _tappedEnglish,
                    onTap: _tapEnglish,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _noMatch
                        ? 'No word of the original is clearly behind '
                              '“$_tappedEnglish”.'
                        : _tappedEnglish != null
                        ? 'Lit below: what “$_tappedEnglish” most likely '
                              'came from.'
                        : 'Tap an English word above, or an original word '
                              'below.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _noMatch
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Directionality(
                    textDirection: _isHebrew
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < widget.words.length; i++)
                          _WordCard(
                            word: widget.words[i],
                            highlighted: _highlighted.contains(i),
                            rtl: _isHebrew,
                            transliteration: _transliterationOf(
                              widget.words[i],
                            ),
                            onTap: () => _openWord(i),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
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
      ),
    );
  }
}

/// The English of the verse, one tappable word at a time.
class _EnglishLine extends StatelessWidget {
  const _EnglishLine({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = text.split(RegExp(r'(\s+)'));

    return Wrap(
      spacing: 0,
      children: [
        for (final token in tokens)
          if (token.trim().isEmpty)
            const Text(' ')
          else
            _EnglishWord(
              token: token,
              selected: _bare(token) == selected,
              onTap: () => onTap(_bare(token)),
              style: theme.textTheme.bodyLarge,
            ),
      ],
    );
  }

  static String _bare(String token) =>
      token.replaceAll(RegExp(r"[^A-Za-z'\-]"), '').toLowerCase();
}

class _EnglishWord extends StatelessWidget {
  const _EnglishWord({
    required this.token,
    required this.selected,
    required this.onTap,
    required this.style,
  });

  final String token;
  final bool selected;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: selected
            ? BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Text(
          '$token ',
          style: selected
              ? style?.copyWith(color: theme.colorScheme.onPrimaryContainer)
              : style,
        ),
      ),
    );
  }
}

/// One word of the original: the word, how it is said, and its number.
class _WordCard extends StatelessWidget {
  const _WordCard({
    required this.word,
    required this.highlighted,
    required this.rtl,
    required this.transliteration,
    required this.onTap,
  });

  final OriginalWord word;
  final bool highlighted;
  final bool rtl;
  final String transliteration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = word.strongs;
    final background = highlighted
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = highlighted
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: number == null ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word.text,
                style: scriptureStyle(
                  theme.textTheme.titleLarge?.copyWith(
                    color: foreground,
                    height: 1.9,
                  ),
                  hebrew: rtl,
                ),
              ),
              if (transliteration.isNotEmpty)
                Text(
                  transliteration,
                  textDirection: TextDirection.ltr,
                  style: scriptureStyle(
                    theme.textTheme.bodySmall?.copyWith(color: foreground),
                    hebrew: false,
                  ),
                ),
              if (number != null)
                Text(
                  number.label,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: highlighted
                        ? theme.colorScheme.onPrimaryContainer
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
