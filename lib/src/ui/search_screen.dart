import 'dart:async';

import 'package:flutter/material.dart';

import '../model/bible.dart';
import '../model/book_meta.dart';

/// Where a search looks.
enum SearchScope {
  all('Whole Bible'),
  oldTestament('Old Testament'),
  newTestament('New Testament'),
  currentBook('This book');

  const SearchScope(this.label);

  final String label;
}

/// One hit from a full-text scan.
@immutable
class SearchHit {
  const SearchHit({
    required this.reference,
    required this.text,
    required this.matchStart,
    required this.matchEnd,
  });

  final Reference reference;
  final String text;
  final int matchStart;
  final int matchEnd;
}

/// Plain text search over the translation in memory.
///
/// No index is built: the Bible is already loaded and a scan of roughly 4 MB
/// of text finishes in a fraction of a second, which keeps the bundled format
/// simple and means search works offline like everything else.
List<SearchHit> searchBible(
  Bible bible,
  String query, {
  SearchScope scope = SearchScope.all,
  String? currentBookCode,
  bool wholeWord = false,
  int limit = 400,
}) {
  final needle = query.trim();
  if (needle.length < 2) return const [];

  final pattern = wholeWord
      ? RegExp(
          '(?<![\\p{L}\\p{N}])${RegExp.escape(needle)}(?![\\p{L}\\p{N}])',
          caseSensitive: false,
          unicode: true,
        )
      : RegExp(RegExp.escape(needle), caseSensitive: false);

  final hits = <SearchHit>[];
  for (final book in bible.books) {
    if (!_inScope(book, scope, currentBookCode)) continue;
    for (final chapter in book.chapters) {
      for (var verse = 1; verse <= chapter.verseCount; verse++) {
        final text = chapter.verseText(verse);
        if (text.isEmpty) continue;
        final match = pattern.firstMatch(text);
        if (match == null) continue;
        hits.add(
          SearchHit(
            reference: Reference(book.code, chapter.number, verse),
            text: text,
            matchStart: match.start,
            matchEnd: match.end,
          ),
        );
        if (hits.length >= limit) return hits;
      }
    }
  }
  return hits;
}

bool _inScope(Book book, SearchScope scope, String? currentBookCode) =>
    switch (scope) {
      SearchScope.all => true,
      SearchScope.oldTestament => book.section == BookSection.oldTestament,
      SearchScope.newTestament => book.section == BookSection.newTestament,
      SearchScope.currentBook => book.code == currentBookCode,
    };

class SearchScreen extends StatefulWidget {
  const SearchScreen({required this.bible, this.from, super.key});

  final Bible bible;

  /// Where the reader was, so "this book" has something to scope to.
  final Reference? from;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  List<SearchHit> _hits = const [];
  bool _searching = false;
  String _query = '';
  SearchScope _scope = SearchScope.all;
  bool _wholeWord = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    setState(() => _searching = _controller.text.trim().length >= 2);
    _debounce = Timer(const Duration(milliseconds: 260), _run);
  }

  void _run() {
    if (!mounted) return;
    setState(() {
      _query = _controller.text.trim();
      _hits = searchBible(
        widget.bible,
        _query,
        scope: _scope,
        currentBookCode: widget.from?.bookCode,
        wholeWord: _wholeWord,
      );
      _searching = false;
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
          onChanged: (_) => _schedule(),
          onSubmitted: (_) => _run(),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _controller.clear();
                _schedule();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _filters(theme),
          const Divider(height: 1),
          Expanded(child: _results(theme)),
        ],
      ),
    );
  }

  Widget _filters(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final scope in SearchScope.values)
            if (scope != SearchScope.currentBook || widget.from != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    scope == SearchScope.currentBook && widget.from != null
                        ? widget.from!.bookName
                        : scope.label,
                  ),
                  selected: _scope == scope,
                  onSelected: (_) {
                    setState(() => _scope = scope);
                    _run();
                  },
                ),
              ),
          const SizedBox(width: 4),
          FilterChip(
            label: const Text('Whole word'),
            selected: _wholeWord,
            onSelected: (value) {
              setState(() => _wholeWord = value);
              _run();
            },
          ),
        ],
      ),
    );
  }

  Widget _results(ThemeData theme) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _query.length < 2
                ? 'Type at least two letters'
                : 'Nothing found for “$_query”'
                      '${_scope == SearchScope.all ? '' : ' in ${_scope.label.toLowerCase()}'}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Group by book, keeping canonical order.
    final grouped = <String, List<SearchHit>>{};
    for (final hit in _hits) {
      (grouped[hit.reference.bookCode] ??= []).add(hit);
    }

    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          '${_hits.length}${_hits.length >= 400 ? '+' : ''} '
          '${_hits.length == 1 ? 'verse' : 'verses'} in '
          '${grouped.length} ${grouped.length == 1 ? 'book' : 'books'}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];

    for (final entry in grouped.entries) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  BookMeta.lookup(entry.key)?.name ?? entry.key,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${entry.value.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
      for (final hit in entry.value) {
        rows.add(
          // As in the navigator: the row owns its highlight, so it does not
          // linger over the list when the row scrolls away under a press.
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              dense: true,
              title: Text(
                '${hit.reference.chapter}:${hit.reference.verse}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              subtitle: _Snippet(hit: hit),
              onTap: () => Navigator.of(context).pop(hit.reference),
            ),
          ),
        );
      }
    }

    return ListView(children: rows);
  }
}

/// Shows the match in context with the query emphasised.
class _Snippet extends StatelessWidget {
  const _Snippet({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = hit.matchStart > 48 ? hit.matchStart - 42 : 0;
    final prefix =
        (start > 0 ? '…' : '') + hit.text.substring(start, hit.matchStart);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: hit.text.substring(hit.matchStart, hit.matchEnd),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          ),
          TextSpan(text: hit.text.substring(hit.matchEnd)),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
