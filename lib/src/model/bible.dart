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
  blank,

  /// A parallel-passage reference printed under a heading (`\r`), which some
  /// translations carry.
  reference;

  static BlockStyle fromKey(String key) => switch (key) {
    'q' => BlockStyle.poetry,
    'd' => BlockStyle.descriptiveTitle,
    'h' => BlockStyle.heading,
    'b' => BlockStyle.blank,
    'r' => BlockStyle.reference,
    _ => BlockStyle.paragraph,
  };

  /// Whether blocks of this kind carry Scripture rather than apparatus.
  bool get isVerseText =>
      this == BlockStyle.paragraph || this == BlockStyle.poetry;

  String get key => switch (this) {
    BlockStyle.poetry => 'q',
    BlockStyle.descriptiveTitle => 'd',
    BlockStyle.heading => 'h',
    BlockStyle.blank => 'b',
    BlockStyle.reference => 'r',
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
}

/// A paragraph, poetry line or heading.
class Block {
  const Block({
    required this.style,
    this.indent = 0,
    this.indentFirstLine = true,
    this.segments = const [],
  });

  final BlockStyle style;

  /// Indent level; 1-based for poetry, 0 for flush-left prose.
  final int indent;

  /// Whether the first line is indented, as `\p` is and `\m` is not. Some
  /// translations set every paragraph flush to the margin, and indenting
  /// those would misrepresent the text.
  final bool indentFirstLine;

  final List<VerseSegment> segments;

  bool get isEmpty =>
      segments.isEmpty || segments.every((s) => s.text.trim().isEmpty);
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
  ///
  /// Headings and psalm titles sit between verses and carry the number of
  /// whichever verse precedes them, so they are left out: they are not part
  /// of anyone's verse.
  String verseText(int verse) {
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (!block.style.isVerseText) continue;
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
}

/// What a book is, before any of it has been read.
///
/// A `.bib` file keeps this beside the text so that the whole of navigation
/// — how many chapters a book has, how many verses each of them has — can be
/// answered without unpacking a single word of Scripture.
class ChapterOutline {
  const ChapterOutline({required this.number, required this.verseCount});

  final int number;
  final int verseCount;
}

/// A book of the Bible with its chapters.
///
/// The chapters may not have been read yet. A book out of a `.bib` file
/// carries its outline and a way to fetch the rest, and unpacks itself the
/// first time anything asks for [chapters] — which reading one book does and
/// navigating between them does not.
class Book {
  /// A book whose chapters are already in hand: an import, a parse, a test.
  Book({required this.meta, required List<Chapter> chapters})
    : _chapters = chapters,
      _load = null,
      outline = List.unmodifiable([
        for (final chapter in chapters)
          ChapterOutline(
            number: chapter.number,
            verseCount: chapter.verseCount,
          ),
      ]);

  /// A book still in the file. [load] is called at most once, and only if
  /// something needs the text itself.
  Book.deferred({
    required this.meta,
    required List<ChapterOutline> outline,
    required List<Chapter> Function() load,
  }) : _chapters = null,
       // A private field cannot be a named initializing formal across
       // libraries, and bib_file.dart calls this.
       // ignore: prefer_initializing_formals
       _load = load,
       outline = List.unmodifiable(outline);

  final BookMeta meta;

  /// Every chapter's number and length, always available.
  final List<ChapterOutline> outline;

  List<Chapter>? _chapters;
  final List<Chapter> Function()? _load;

  /// The chapters, unpacking them if that has not happened yet.
  List<Chapter> get chapters => _chapters ??= _load!();

  /// Whether the text is in memory. Nothing in the app needs to know; the
  /// tests do, because "does opening a Bible unpack all of it" is the whole
  /// point of the arrangement.
  bool get isLoaded => _chapters != null;

  String get code => meta.code;
  String get name => meta.name;
  String get abbrev => meta.abbrev;
  BookSection get section => meta.section;

  int get chapterCount => outline.length;

  /// Every chapter number, in order, without unpacking anything.
  Iterable<int> get chapterNumbers => outline.map((c) => c.number);

  /// How many verses the nth chapter has, counting from one — the same
  /// position [chapter] takes, not the printed number. Answered from the
  /// outline, so asking does not unpack the book.
  int verseCountAt(int position) => (position < 1 || position > outline.length)
      ? 0
      : outline[position - 1].verseCount;

  /// Every verse in the book, from the outline.
  int get verseCount =>
      outline.fold(0, (sum, chapter) => sum + chapter.verseCount);

  /// The nth chapter, counting from one — which is a position, not a number.
  /// A book that begins at chapter 3 answers that chapter to `chapter(1)`.
  Chapter? chapter(int number) {
    if (number < 1 || number > outline.length) return null;
    return chapters[number - 1];
  }
}

/// Which way the script of a translation runs.
enum ReadingDirection {
  ltr,
  rtl;

  static ReadingDirection fromKey(String key) =>
      key.toLowerCase() == 'rtl' ? ReadingDirection.rtl : ReadingDirection.ltr;

  String get key => name;
}

/// How a translation numbers its verses.
///
/// Carried because everything anchored to a verse — the cross-references,
/// the original-language layer — is anchored to one scheme, and a file that
/// does not say which it uses can be mis-anchored silently. Anything not
/// listed here round-trips as written rather than being flattened.
class Versification {
  const Versification._();

  /// The numbering of the English Protestant Bible, which the app's own
  /// translations, its cross-references and its Strong's layer all share.
  static const String english = 'eng';

  /// Said by a file that does not know. Nothing may assume it matches.
  static const String unknown = 'unknown';
}

/// Identity and licensing of a translation.
class TranslationInfo {
  const TranslationInfo({
    required this.id,
    required this.name,
    required this.abbreviation,
    required this.license,
    required this.sourceUrl,
    this.language = 'en',
    this.script = '',
    this.direction = ReadingDirection.ltr,
    this.versification = Versification.unknown,
    this.attribution = '',
  });

  final String id;
  final String name;
  final String abbreviation;
  final String license;
  final String sourceUrl;

  /// BCP 47, so `en`, `es-419`, `arb`.
  final String language;

  /// ISO 15924, so `Latn`, `Hebr`, `Arab`. Empty where it is not said.
  final String script;

  /// Which way the text runs. A translation that does not say runs
  /// left-to-right, which is what every translation shipped here does.
  final ReadingDirection direction;

  /// The verse numbering this translation follows; see [Versification].
  final String versification;

  /// Wording the licence obliges the app to show. Empty where there is
  /// none — a public-domain text asks for nothing.
  final String attribution;

  TranslationInfo copyWith({
    String? id,
    String? name,
    String? abbreviation,
    String? license,
    String? sourceUrl,
    String? language,
    String? script,
    ReadingDirection? direction,
    String? versification,
    String? attribution,
  }) => TranslationInfo(
    id: id ?? this.id,
    name: name ?? this.name,
    abbreviation: abbreviation ?? this.abbreviation,
    license: license ?? this.license,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    language: language ?? this.language,
    script: script ?? this.script,
    direction: direction ?? this.direction,
    versification: versification ?? this.versification,
    attribution: attribution ?? this.attribution,
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

  final TranslationInfo translation;
  final List<Book> books;
  final Map<String, int> _indexByCode = {};

  Book? bookByCode(String code) {
    final index = _indexByCode[code.toUpperCase()];
    return index == null ? null : books[index];
  }

  int? indexOfCode(String code) => _indexByCode[code.toUpperCase()];

  /// Every verse in the translation, counted from the books' outlines, so
  /// asking does not unpack any of them.
  int get verseCount => books.fold(0, (total, book) => total + book.verseCount);
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
