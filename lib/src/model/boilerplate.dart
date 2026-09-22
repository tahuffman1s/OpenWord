import 'bible.dart';

/// What came of taking an edition's furniture out of its Scripture.
class BoilerplateSweep {
  const BoilerplateSweep({required this.books, required this.removed});

  final List<Book> books;

  /// The lines that were taken out, each once, longest first. Worth
  /// showing: a reader told what was dropped can say whether it should
  /// have been.
  final List<String> removed;

  bool get isEmpty => removed.isEmpty;
}

/// How many separate books a line must turn up in before it is furniture.
///
/// Two would not be enough. A pair of books can share a line honestly —
/// the same doxology, the same closing — and three is the point at which
/// coincidence stops being the likely explanation.
const int boilerplateBooks = 3;

/// Takes an edition's furniture out of a Bible: the navigation, the
/// running headers and the footers it prints around every book.
///
/// Every rule that reads the markup can be defeated by an edition that
/// marks its furniture up some other way — as links, as plain paragraphs,
/// as a table, as whatever the publisher's template happened to emit. This
/// one does not read the markup at all. It reads the text, and asks a
/// question about the book as a whole that no single paragraph can answer:
/// does this line belong to no verse, and does it turn up word for word in
/// three or more separate books?
///
/// Nothing in Scripture answers yes. Text that belongs to a verse is never
/// considered, so a doxology or an "Amen." inside a verse is safe. What
/// repeats outside a verse repeats inside one book — a psalm's
/// superscription is in Psalms and nowhere else, and one book is not three.
/// What repeats across books is what the edition printed around the text
/// rather than in it.
BoilerplateSweep stripBoilerplate(List<Book> books) {
  // Which books each candidate line appears in.
  final seenIn = <String, Set<String>>{};
  for (final book in books) {
    for (final chapter in book.chapters) {
      for (final block in chapter.blocks) {
        final line = _lineOf(block);
        if (line == null) continue;
        (seenIn[line] ??= <String>{}).add(book.code);
      }
    }
  }

  final furniture = {
    for (final entry in seenIn.entries)
      if (entry.value.length >= boilerplateBooks) entry.key,
  };
  if (furniture.isEmpty) {
    return BoilerplateSweep(books: books, removed: const []);
  }

  final swept = <Book>[];
  for (final book in books) {
    swept.add(
      Book(
        meta: book.meta,
        chapters: [
          for (final chapter in book.chapters)
            Chapter(
              number: chapter.number,
              blocks: [
                for (final block in chapter.blocks)
                  if (!furniture.contains(_lineOf(block) ?? '')) block,
              ],
              notes: chapter.notes,
              labels: chapter.labels,
              omitted: chapter.omitted,
              label: chapter.label,
            ),
        ],
      ),
    );
  }

  final removed = furniture.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return BoilerplateSweep(books: swept, removed: removed);
}

/// A block's text, where the block belongs to no verse — and null where it
/// belongs to one, which puts it beyond this rule's reach entirely.
///
/// A blank is not a line: an edition that spaces its furniture out would
/// otherwise have every stanza break in the Bible counted together.
String? _lineOf(Block block) {
  if (block.style == BlockStyle.blank) return null;
  if (block.segments.any((segment) => segment.startsVerse)) return null;
  final text = block.segments
      .map((segment) => Markup.strip(segment.text))
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? null : text;
}
