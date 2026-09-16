import 'book_meta.dart';

/// Sentinel characters used to carry inline character formatting inside verse
/// text. Control characters are used because they never occur in Scripture
/// text, so no escaping is needed when the text is stored or searched.
class Markup {
  Markup._();

  /// Words of Jesus (`\wj ... \wj*`).
  static const String wjStart = '';
  static const String wjEnd = '';

  /// Words supplied by the translators (`\add ... \add*`) — rendered italic.
  static const String addStart = '';
  static const String addEnd = '';

  /// A footnote / cross-reference marker, followed by the note index and
  /// terminated by [noteEnd].
  static const String noteStart = '';
  static const String noteEnd = '';

  /// `Selah` and similar poetry directions (`\qs ... \qs*`).
  static const String selahStart = '';
  static const String selahEnd = '';

  static final RegExp noteMarker = RegExp('$noteStart(\\d+)$noteEnd');

  static final RegExp _controls = RegExp('[-]');

  /// The text with every marker removed — used for search and for copying.
  static String strip(String text) =>
      text.replaceAll(noteMarker, '').replaceAll(_controls, '');
}

/// How a block of text is laid out on the page.
enum BlockStyle {
  /// Prose paragraph; verses flow into each other.
  paragraph,

  /// A line of poetry. [Block.indent] carries the indent level.
  poetry,

  /// A psalm's descriptive title (`\d`).
  descriptiveTitle,

  /// A major section heading such as `BOOK 1` in the Psalms (`\ms`, `\s`).
  heading,

  /// A blank line used to separate stanzas (`\b`).
  blank;

  static BlockStyle fromKey(String key) => switch (key) {
    'q' => BlockStyle.poetry,
    'd' => BlockStyle.descriptiveTitle,
    'h' => BlockStyle.heading,
    'b' => BlockStyle.blank,
    _ => BlockStyle.paragraph,
  };

  String get key => switch (this) {
    BlockStyle.poetry => 'q',
    BlockStyle.descriptiveTitle => 'd',
    BlockStyle.heading => 'h',
    BlockStyle.blank => 'b',
    BlockStyle.paragraph => 'p',
  };
}

/// A run of text inside a [Block] that belongs to a single verse.
class VerseSegment {
  const VerseSegment({
    required this.verse,
    required this.startsVerse,
    required this.text,
  });

  /// The verse this text belongs to, or 0 for text outside any verse.
  final int verse;

  /// Whether the verse number should be printed before this run.
  final bool startsVerse;

  final String text;

  List<Object?> toJson() => [verse, startsVerse ? 1 : 0, text];

  static VerseSegment fromJson(List<Object?> json) => VerseSegment(
    verse: json[0]! as int,
    startsVerse: json[1] == 1,
    text: json[2]! as String,
  );
}

/// A paragraph, poetry line or heading.
class Block {
  const Block({required this.style, this.indent = 0, this.segments = const []});

  final BlockStyle style;

  /// Indent level; 1-based for poetry, 0 for flush-left prose.
  final int indent;

  final List<VerseSegment> segments;

  bool get isEmpty =>
      segments.isEmpty || segments.every((s) => s.text.trim().isEmpty);

  List<Object?> toJson() => [
    style.key,
    indent,
    [for (final segment in segments) segment.toJson()],
  ];

  static Block fromJson(List<Object?> json) => Block(
    style: BlockStyle.fromKey(json[0]! as String),
    indent: json[1]! as int,
    segments: [
      for (final segment in json[2]! as List)
        VerseSegment.fromJson((segment as List).cast<Object?>()),
    ],
  );
}

/// One chapter: an ordered list of blocks plus the chapter's footnotes.
class Chapter {
  Chapter({required this.number, required this.blocks, required this.notes})
    : verseCount = blocks.fold(
        0,
        (max, block) => block.segments.fold(
          max,
          (m, segment) => segment.verse > m ? segment.verse : m,
        ),
      );

  final int number;
  final List<Block> blocks;

  /// Footnote and cross-reference bodies, addressed by the index carried in a
  /// note marker.
  final List<String> notes;

  final int verseCount;

  /// Plain text of a single verse, with inline markers removed.
  String verseText(int verse) {
    final buffer = StringBuffer();
    for (final block in blocks) {
      for (final segment in block.segments) {
        if (segment.verse != verse) continue;
        final text = Markup.strip(segment.text).trim();
        if (text.isEmpty) continue;
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(text);
      }
    }
    return buffer.toString().trim();
  }

  Map<String, Object?> toJson() => {
    'n': number,
    'b': [for (final block in blocks) block.toJson()],
    if (notes.isNotEmpty) 'f': notes,
  };

  static Chapter fromJson(Map<String, Object?> json) => Chapter(
    number: json['n']! as int,
    blocks: [
      for (final block in json['b']! as List)
        Block.fromJson((block as List).cast<Object?>()),
    ],
    notes: ((json['f'] as List?) ?? const []).cast<String>(),
  );
}

/// A book of the Bible with its chapters.
class Book {
  Book({required this.meta, required this.chapters});

  final BookMeta meta;
  final List<Chapter> chapters;

  String get code => meta.code;
  String get name => meta.name;
  String get abbrev => meta.abbrev;
  BookSection get section => meta.section;
  int get chapterCount => chapters.length;

  Chapter? chapter(int number) {
    if (number < 1 || number > chapters.length) return null;
    return chapters[number - 1];
  }

  Map<String, Object?> toJson() => {
    'c': meta.code,
    'ch': [for (final chapter in chapters) chapter.toJson()],
  };

  static Book? fromJson(Map<String, Object?> json) {
    final meta = BookMeta.lookup(json['c']! as String);
    if (meta == null) return null;
    return Book(
      meta: meta,
      chapters: [
        for (final chapter in json['ch']! as List)
          Chapter.fromJson((chapter as Map).cast<String, Object?>()),
      ],
    );
  }
}

/// Identity and licensing of a translation.
class TranslationInfo {
  const TranslationInfo({
    required this.id,
    required this.name,
    required this.abbreviation,
    required this.license,
    required this.sourceUrl,
  });

  final String id;
  final String name;
  final String abbreviation;
  final String license;
  final String sourceUrl;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'abbr': abbreviation,
    'license': license,
    'url': sourceUrl,
  };

  static TranslationInfo fromJson(Map<String, Object?> json) => TranslationInfo(
    id: json['id']! as String,
    name: json['name']! as String,
    abbreviation: json['abbr']! as String,
    license: json['license']! as String,
    sourceUrl: json['url']! as String,
  );
}

/// A fully parsed Bible held in memory.
class Bible {
  Bible({required this.translation, required List<Book> books})
    : books = List.unmodifiable(
        books.toList()..sort(
          (a, b) => (BookMeta.ordinalByCode[a.code] ?? 999).compareTo(
            BookMeta.ordinalByCode[b.code] ?? 999,
          ),
        ),
      ) {
    for (var i = 0; i < this.books.length; i++) {
      _indexByCode[this.books[i].code] = i;
    }
  }

  /// Bumped whenever the on-disk cache layout changes.
  static const int formatVersion = 1;

  final TranslationInfo translation;
  final List<Book> books;
  final Map<String, int> _indexByCode = {};

  Book? bookByCode(String code) {
    final index = _indexByCode[code.toUpperCase()];
    return index == null ? null : books[index];
  }

  int? indexOfCode(String code) => _indexByCode[code.toUpperCase()];

  int get verseCount => books.fold(
    0,
    (total, book) =>
        total +
        book.chapters.fold(0, (sum, chapter) => sum + chapter.verseCount),
  );

  Map<String, Object?> toJson() => {
    'v': formatVersion,
    't': translation.toJson(),
    'books': [for (final book in books) book.toJson()],
  };

  static Bible? fromJson(Map<String, Object?> json) {
    if (json['v'] != formatVersion) return null;
    final books = <Book>[];
    for (final entry in json['books']! as List) {
      final book = Book.fromJson((entry as Map).cast<String, Object?>());
      if (book != null) books.add(book);
    }
    if (books.isEmpty) return null;
    return Bible(
      translation: TranslationInfo.fromJson(
        (json['t']! as Map).cast<String, Object?>(),
      ),
      books: books,
    );
  }
}

/// A place in the Bible: book code plus chapter, and optionally a verse.
class Reference {
  const Reference(this.bookCode, this.chapter, [this.verse]);

  final String bookCode;
  final int chapter;
  final int? verse;

  String get bookName => BookMeta.lookup(bookCode)?.name ?? bookCode;

  String get label =>
      verse == null ? '$bookName $chapter' : '$bookName $chapter:$verse';

  Reference withVerse(int? verse) => Reference(bookCode, chapter, verse);

  String encode() => '$bookCode/$chapter/${verse ?? ''}';

  static Reference? decode(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('/');
    if (parts.length < 2) return null;
    final chapter = int.tryParse(parts[1]);
    if (chapter == null) return null;
    final verse = parts.length > 2 ? int.tryParse(parts[2]) : null;
    return Reference(parts[0], chapter, verse);
  }

  @override
  bool operator ==(Object other) =>
      other is Reference &&
      other.bookCode == bookCode &&
      other.chapter == chapter &&
      other.verse == verse;

  @override
  int get hashCode => Object.hash(bookCode, chapter, verse);

  @override
  String toString() => label;
}
