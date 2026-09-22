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

/// Styles that say a block is part of the text whatever it repeats.
const Set<BlockStyle> _neverFurniture = {
  BlockStyle.heading,
  BlockStyle.descriptiveTitle,
  BlockStyle.acrostic,
  BlockStyle.speaker,
  BlockStyle.reference,
};

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
      for (final line in _candidatesIn(chapter)) {
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
    final chapters = <Chapter>[];
    for (final chapter in book.chapters) {
      final drop = _furnitureIn(chapter, furniture);
      chapters.add(
        drop.isEmpty
            ? chapter
            : Chapter(
                number: chapter.number,
                blocks: [
                  for (var i = 0; i < chapter.blocks.length; i++)
                    if (!drop.contains(i)) chapter.blocks[i],
                ],
                notes: chapter.notes,
                labels: chapter.labels,
                omitted: chapter.omitted,
                label: chapter.label,
              ),
      );
    }
    swept.add(Book(meta: book.meta, chapters: chapters));
  }

  final removed = furniture.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return BoilerplateSweep(books: swept, removed: removed);
}

/// The lines of a chapter that could be furniture: those lying outside
/// its Scripture altogether, before the first verse of it or after the
/// last.
///
/// Position matters as much as repetition. The Gospels quote the Psalms
/// and each other, so a line can repeat across books and be Scripture in
/// every one of them — "The stone that the builders rejected" stands in
/// five. What it does not do is stand outside the verses: a quotation is
/// in the middle of a chapter, and an edition's furniture is at its edges.
/// Without this the rule took that verse out of all five books.
/// Which blocks of a chapter are furniture, by position.
Set<int> _furnitureIn(Chapter chapter, Set<String> furniture) {
  final out = <int>{};
  for (final at in _candidatePositions(chapter)) {
    final line = _lineOf(chapter.blocks[at]);
    if (line != null && furniture.contains(line)) out.add(at);
  }
  return out;
}

Iterable<String> _candidatesIn(Chapter chapter) sync* {
  for (final at in _candidatePositions(chapter)) {
    final line = _lineOf(chapter.blocks[at]);
    if (line != null) yield line;
  }
}

/// The positions a chapter's furniture could be in.
Iterable<int> _candidatePositions(Chapter chapter) sync* {
  var first = -1;
  var last = -1;
  for (var i = 0; i < chapter.blocks.length; i++) {
    if (chapter.blocks[i].segments.any((segment) => segment.startsVerse)) {
      if (first < 0) first = i;
      last = i;
    }
  }
  // A chapter with no numbered verse at all is not Scripture to begin
  // with, and is left to the rules that decide that.
  if (first < 0) return;
  for (var i = 0; i < chapter.blocks.length; i++) {
    if (i > first && i < last) continue;
    yield i;
  }
}

/// A block's text, where the block belongs to no verse — and null where it
/// belongs to one, which puts it beyond this rule's reach entirely.
///
/// A blank is not a line: an edition that spaces its furniture out would
/// otherwise have every stanza break in the Bible counted together.
String? _lineOf(Block block) {
  if (block.style == BlockStyle.blank) return null;
  // A section heading is never furniture, however often it repeats. The
  // Gospels tell the same events and an edition heads them the same way:
  // "Jesus Foretells His Death" stands over Matthew, Mark and Luke alike,
  // and sweeping it would take a heading out of three Gospels at once.
  // This rule cost the ESV fifty-eight of them before the test caught it.
  if (_neverFurniture.contains(block.style)) return null;
  if (block.segments.any((segment) => segment.startsVerse)) return null;
  final text = block.segments
      .map((segment) => Markup.strip(segment.text))
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? null : text;
}
