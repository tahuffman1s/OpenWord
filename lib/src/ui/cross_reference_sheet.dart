import 'package:flutter/material.dart';

import '../data/cross_references.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';
import '../model/xref_codec.dart';

/// Where else Scripture takes up what this verse says.
///
/// The references are grouped under the phrase that prompted them, the way
/// the Treasury of Scripture Knowledge sets them out, and each one carries
/// the words it points at so the list can be read without leaving it.
Future<Reference?> showCrossReferences(
  BuildContext context, {
  required Reference reference,
  required List<XrefAnchor> anchors,
  required Bible bible,
}) {
  return showModalBottomSheet<Reference>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _CrossReferenceSheet(
        reference: reference,
        anchors: anchors,
        bible: bible,
      ),
    ),
  );
}

class _CrossReferenceSheet extends StatelessWidget {
  const _CrossReferenceSheet({
    required this.reference,
    required this.anchors,
    required this.bible,
  });

  final Reference reference;
  final List<XrefAnchor> anchors;
  final Bible bible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var passages = 0;
    for (final anchor in anchors) {
      passages += anchor.ranges.length;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reference.label, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              passages == 1
                  ? 'One cross-reference'
                  : '$passages cross-references',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (final anchor in anchors) ...[
                    if (anchor.phrase.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
                        child: Text(
                          '“${anchor.phrase}”',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    for (final range in anchor.ranges)
                      _Passage(range: range, bible: bible),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    CrossReferences.attribution,
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

/// One passage: what it is called, and what it says where the translation
/// being read has it.
class _Passage extends StatelessWidget {
  const _Passage({required this.range, required this.bible});

  final XrefRange range;
  final Bible bible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = CrossReferences.bookAt(range.book);
    if (code == null) return const SizedBox.shrink();
    final meta = BookMeta.lookup(code);
    if (meta == null) return const SizedBox.shrink();

    final label =
        '${meta.name} ${range.chapter}:${range.verse}'
        '${range.isRange ? '-${range.endVerse}' : ''}';
    final text = _textOf(code);

    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: theme.textTheme.labelLarge),
        subtitle: text == null
            ? Text(
                'Not in this translation',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
        onTap: () =>
            Navigator.of(context)
                .pop(Reference(code, range.chapter, range.verse)),
      ),
    );
  }

  /// The verses of the passage, joined, from the translation in hand. A
  /// reference into a book this edition does not carry has no text, and says
  /// so rather than going blank.
  String? _textOf(String code) {
    final book = bible.bookByCode(code);
    final chapter = book?.chapter(range.chapter);
    if (chapter == null) return null;
    final parts = <String>[];
    for (var verse = range.verse; verse <= range.endVerse; verse++) {
      final text = chapter.verseText(verse);
      if (text.isNotEmpty) parts.add(text);
    }
    return parts.isEmpty ? null : parts.join(' ');
  }
}
