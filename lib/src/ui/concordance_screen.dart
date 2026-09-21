import 'package:flutter/material.dart';

import '../data/originals.dart';
import '../model/bible.dart';
import '../model/book_meta.dart';
import '../model/strongs_codec.dart';
import 'scripture_type.dart';

/// Every verse one Strong's number occurs in.
///
/// The list is of the original word's occurrences, so it holds whatever
/// translation is being read: the verses are the same verses. Where the
/// translation in hand does not carry a book, the reference still stands
/// and says so.
Future<Reference?> showConcordance(
  BuildContext context, {
  required StrongsNumber number,
  required Originals originals,
  required Bible bible,
}) {
  return Navigator.of(context).push<Reference>(
    MaterialPageRoute(
      builder: (_) =>
          ConcordanceScreen(number: number, originals: originals, bible: bible),
    ),
  );
}

class ConcordanceScreen extends StatefulWidget {
  const ConcordanceScreen({
    required this.number,
    required this.originals,
    required this.bible,
    super.key,
  });

  final StrongsNumber number;
  final Originals originals;
  final Bible bible;

  @override
  State<ConcordanceScreen> createState() => _ConcordanceScreenState();
}

class _ConcordanceScreenState extends State<ConcordanceScreen> {
  late final List<Reference> _all = widget.originals.occurrences(widget.number);
  String? _book;

  List<Reference> get _shown => _book == null
      ? _all
      : _all.where((reference) => reference.bookCode == _book).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.originals.entryFor(widget.number);
    final shown = _shown;

    // Which books it turns up in, in canonical order, for the filter.
    final books = <String>[];
    for (final reference in _all) {
      if (books.isEmpty || books.last != reference.bookCode) {
        if (!books.contains(reference.bookCode)) books.add(reference.bookCode);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.number.label),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(78),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry != null)
                  Text(
                    '${entry.lemma}   ${entry.transliteration}',
                    style: scriptureStyle(
                      theme.textTheme.titleMedium?.copyWith(height: 1.7),
                      hebrew: widget.number.isHebrew,
                    ),
                  ),
                Text(
                  '${_all.length} verses in ${books.length} '
                  '${books.length == 1 ? 'book' : 'books'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: const Text('All'),
                          selected: _book == null,
                          onSelected: (_) => setState(() => _book = null),
                        ),
                      ),
                      for (final code in books)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(BookMeta.lookup(code)?.abbrev ?? code),
                            selected: _book == code,
                            onSelected: (selected) =>
                                setState(() => _book = selected ? code : null),
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
      body: ListView.builder(
        itemCount: shown.length,
        itemBuilder: (context, index) {
          final reference = shown[index];
          final text = _textOf(reference);
          return ListTile(
            dense: true,
            title: Text(reference.label, style: theme.textTheme.labelLarge),
            subtitle: Text(
              text ?? 'Not in this translation',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: text == null ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
            onTap: text == null
                ? null
                : () => Navigator.of(context).pop(reference),
          );
        },
      ),
    );
  }

  String? _textOf(Reference reference) {
    final verse = reference.verse;
    if (verse == null) return null;
    final chapter = widget.bible
        .bookByCode(reference.bookCode)
        ?.chapter(reference.chapter);
    final text = chapter?.verseText(verse);
    return (text == null || text.isEmpty) ? null : text;
  }
}
