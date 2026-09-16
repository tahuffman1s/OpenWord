import 'dart:async';

import 'package:flutter/material.dart';

import '../model/bible.dart';
import '../model/book_meta.dart';

/// One hit from a full-text scan.
@immutable
class SearchHit {
  const SearchHit({required this.reference, required this.text});

  final Reference reference;
  final String text;
}

/// Plain substring search over the whole downloaded text.
///
/// No index is built: the Bible is already in memory and a scan of roughly
/// 4 MB of text finishes well inside a frame budget on any device this app
/// targets, which keeps the on-disk format simple.
List<SearchHit> searchBible(Bible bible, String query, {int limit = 300}) {
  final needle = query.trim().toLowerCase();
  if (needle.length < 2) return const [];
  final hits = <SearchHit>[];
  for (final book in bible.books) {
    for (final chapter in book.chapters) {
      for (var verse = 1; verse <= chapter.verseCount; verse++) {
        final text = chapter.verseText(verse);
        if (!text.toLowerCase().contains(needle)) continue;
        hits.add(
          SearchHit(
            reference: Reference(book.code, chapter.number, verse),
            text: text,
          ),
        );
        if (hits.length >= limit) return hits;
      }
    }
  }
  return hits;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({required this.bible, super.key});

  final Bible bible;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _searching = value.trim().length >= 2);
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _hits = searchBible(widget.bible, value);
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search the text',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _hits.isEmpty
          ? Center(
              child: Text(
                _query.length < 2
                    ? 'Type at least two letters'
                    : 'No results for “$_query”',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_hits.length} '
                      '${_hits.length == 1 ? "result" : "results"}'
                      '${_hits.length >= 300 ? " (showing the first 300)" : ""}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _hits.length,
                    itemBuilder: (context, index) {
                      final hit = _hits[index];
                      return ListTile(
                        title: Text(
                          hit.reference.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        subtitle: _Snippet(text: hit.text, query: _query),
                        onTap: () => Navigator.of(context).pop(hit.reference),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// Shows the match in context with the query emphasised.
class _Snippet extends StatelessWidget {
  const _Snippet({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lower = text.toLowerCase();
    final needle = query.toLowerCase();
    final at = lower.indexOf(needle);
    if (at < 0 || needle.isEmpty) return Text(text, maxLines: 3);
    final start = at > 48 ? at - 42 : 0;
    final prefix = (start > 0 ? '…' : '') + text.substring(start, at);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: text.substring(at, at + needle.length),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          TextSpan(text: text.substring(at + needle.length)),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Used by the bookmarks screen to show a book's name without the Bible.
String bookNameFor(String code) => BookMeta.lookup(code)?.name ?? code;
