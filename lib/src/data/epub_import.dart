import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/bible.dart';
import '../model/book_meta.dart';
import 'reference_search.dart';

/// What came of reading an EPUB: a Bible, or the reason there is not one,
/// and whatever the conversion had to guess at along the way.
class ImportResult {
  const ImportResult({this.bible, this.failure, this.warnings = const []});

  const ImportResult.failed(String reason) : this(failure: reason);

  final Bible? bible;

  /// Null when it worked; otherwise why it did not, in words a reader can do
  /// something with.
  final String? failure;

  /// Books that were found but had nothing in them, chapters that came out
  /// empty, and so on. Worth showing: a Bible that is missing Obadiah should
  /// say so rather than look complete.
  final List<String> warnings;

  bool get ok => bible != null;
}

/// Turns a Bible in EPUB form into the app's own model.
///
/// There is no standard for how a Bible is marked up in an EPUB, so this
/// reads the three shapes that cover nearly all of them:
///
///  - numbered elements: `<sup>3</sup>`, `<span class="verse">3</span>`, or
///    an `id` like `V3` — the usual output of Bible publishing tools;
///  - a number at the head of a paragraph, where each paragraph is a verse;
///  - `3:16` at the head of a paragraph, the shape Project Gutenberg's texts
///    take, which carries the chapter as well.
///
/// Books and chapters are recognised by their headings. Anything that cannot
/// be placed is left out and reported rather than guessed at: a Bible with
/// invented verse numbers would be worse than no Bible at all.
class EpubImport {
  const EpubImport._();

  /// Verse numbers above this are not verse numbers.
  static const int maxVerse = 176;

  /// Nor are chapter numbers above this.
  static const int maxChapter = 150;

  static ImportResult convert(Uint8List bytes, {String fileName = 'import'}) {
    // An EPUB is a zip, and a zip starts 'PK'. Without this the decoder makes
    // an empty archive of anything at all and the failure reads as a broken
    // EPUB rather than as the text file it is.
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b) {
      return const ImportResult.failed('That file is not an EPUB.');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (error) {
      return ImportResult.failed('That file is not an EPUB ($error).');
    }

    final files = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isFile) files[_normalisePath(file.name)] = file;
    }

    final opfPath = _findOpf(files);
    if (opfPath == null) {
      return const ImportResult.failed(
        'That EPUB has no package file, so there is no telling what is in it.',
      );
    }

    final XmlDocument opf;
    try {
      opf = XmlDocument.parse(_text(files[opfPath]!));
    } on Object catch (error) {
      return ImportResult.failed('The EPUB package file is broken ($error).');
    }

    final base = _directoryOf(opfPath);
    final documents = _spineDocuments(opf, files, base);
    if (documents.isEmpty) {
      return const ImportResult.failed(
        'That EPUB has no readable chapters in it.',
      );
    }

    final builder = _BibleBuilder();
    for (final document in documents) {
      try {
        builder.read(XmlDocument.parse(_repair(_text(document))));
      } on Object catch (error) {
        builder.warn('Skipped ${document.name}: $error');
      }
    }

    final books = builder.finish();
    if (books.isEmpty) {
      return ImportResult(
        failure:
            'No books of the Bible could be found in that EPUB. The headings '
            'have to name the books — "Genesis", "1 Corinthians" — and the '
            'verses have to be numbered.',
        warnings: builder.warnings,
      );
    }

    return ImportResult(
      bible: Bible(
        translation: _describe(opf, fileName, builder),
        books: books,
      ),
      warnings: builder.warnings,
    );
  }

  /// What to call the translation this EPUB holds.
  static TranslationInfo _describe(
    XmlDocument opf,
    String fileName,
    _BibleBuilder builder,
  ) {
    String metadata(String name) {
      for (final element in opf.findAllElements(name, namespace: '*')) {
        final text = element.innerText.trim();
        if (text.isNotEmpty) return text;
      }
      return '';
    }

    final title = metadata('title');
    final name = title.isEmpty ? _stem(fileName) : title;
    final rights = metadata('rights');
    final publisher = metadata('publisher');

    return TranslationInfo(
      id: _identifier(name, metadata('identifier')),
      name: name,
      abbreviation: _abbreviate(name),
      license: rights.isEmpty
          ? 'Imported — licence not stated in the file'
          : rights,
      sourceUrl: publisher.isEmpty ? fileName : '$publisher · $fileName',
    );
  }

  /// A stable id for the translation, so that re-importing the same EPUB
  /// replaces it rather than making a second copy.
  static String _identifier(String name, String identifier) {
    final seed = identifier.isEmpty ? name : identifier;
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(seed)) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-+|-+\$'), '');
    final short = slug.length > 24 ? slug.substring(0, 24) : slug;
    return 'import-${short.isEmpty ? 'bible' : short}-'
        '${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// Initials, which is what most translations use: "World English Bible"
  /// becomes WEB.
  static String _abbreviate(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .where((word) => !_smallWords.contains(word.toLowerCase()))
        .toList();
    if (words.isEmpty) return 'BIB';
    final letters = words.map((word) => word[0].toUpperCase()).take(4).join();
    return letters.length < 2
        ? words.first.substring(0, words.first.length.clamp(0, 3)).toUpperCase()
        : letters;
  }

  static const Set<String> _smallWords = {
    'the',
    'a',
    'an',
    'of',
    'in',
    'and',
    'holy',
  };

  static String _stem(String fileName) {
    final base = fileName.split('/').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  static String _normalisePath(String path) {
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    return parts.join('/');
  }

  static String _directoryOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  static String _resolve(String base, String href) {
    final target = Uri.decodeFull(href.split('#').first);
    return _normalisePath(base.isEmpty ? target : '$base/$target');
  }

  static String? _findOpf(Map<String, ArchiveFile> files) {
    final container = files['META-INF/container.xml'];
    if (container != null) {
      try {
        final document = XmlDocument.parse(_text(container));
        for (final rootfile in document.findAllElements(
          'rootfile',
          namespace: '*',
        )) {
          final path = rootfile.getAttribute('full-path');
          if (path != null && files.containsKey(_normalisePath(path))) {
            return _normalisePath(path);
          }
        }
      } on Object {
        // Fall through to looking for it.
      }
    }
    for (final path in files.keys) {
      if (path.toLowerCase().endsWith('.opf')) return path;
    }
    return null;
  }

  /// The reading order: the spine, resolved through the manifest.
  static List<ArchiveFile> _spineDocuments(
    XmlDocument opf,
    Map<String, ArchiveFile> files,
    String base,
  ) {
    final hrefById = <String, String>{};
    for (final item in opf.findAllElements('item', namespace: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) hrefById[id] = href;
    }

    final documents = <ArchiveFile>[];
    for (final ref in opf.findAllElements('itemref', namespace: '*')) {
      final id = ref.getAttribute('idref');
      final href = id == null ? null : hrefById[id];
      if (href == null) continue;
      final file = files[_resolve(base, href)];
      if (file != null) documents.add(file);
    }

    if (documents.isEmpty) {
      // No usable spine: fall back to every XHTML file, in name order, which
      // is how most of them are laid out anyway.
      final paths =
          files.keys
              .where(
                (path) =>
                    path.endsWith('.xhtml') ||
                    path.endsWith('.html') ||
                    path.endsWith('.htm'),
              )
              .toList()
            ..sort();
      for (final path in paths) {
        documents.add(files[path]!);
      }
    }
    return documents;
  }

  static String _text(ArchiveFile file) =>
      utf8.decode(file.content, allowMalformed: true);

  /// XHTML is XML, but plenty of EPUBs carry HTML's named entities, which an
  /// XML parser has no table for. The five XML entities are left alone.
  static String _repair(String xhtml) {
    final withoutDoctype = xhtml.replaceAll(
      RegExp('<!DOCTYPE[^>]*>', caseSensitive: false),
      '',
    );
    return withoutDoctype.replaceAllMapped(RegExp('&([a-zA-Z][a-zA-Z0-9]+);'), (
      match,
    ) {
      final name = match.group(1)!;
      if (const {'amp', 'lt', 'gt', 'quot', 'apos'}.contains(name)) {
        return match.group(0)!;
      }
      return _entities[name] ?? ' ';
    });
  }

  static const Map<String, String> _entities = {
    'nbsp': ' ',
    'ensp': ' ',
    'emsp': ' ',
    'thinsp': ' ',
    'mdash': '—',
    'ndash': '–',
    'hellip': '…',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'sect': '§',
    'para': '¶',
    'middot': '·',
    'deg': '°',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'dagger': '†',
    'Dagger': '‡',
    'bull': '•',
    'prime': '′',
    'Prime': '″',
    'laquo': '«',
    'raquo': '»',
    'eacute': 'é',
    'egrave': 'è',
    'agrave': 'à',
    'ccedil': 'ç',
    'uuml': 'ü',
    'ouml': 'ö',
    'auml': 'ä',
  };
}

/// Builds books out of a stream of XHTML documents.
class _BibleBuilder {
  final List<String> warnings = [];

  final Map<String, Map<int, List<Block>>> _blocks = {};
  final Map<String, Map<int, List<String>>> _notes = {};

  String? _book;
  int _chapter = 0;
  int _verse = 0;

  static final RegExp _chapterHeading = RegExp(
    r'^(?:chapter|psalm|chap\.?)?\s*(\d{1,3})\s*$',
    caseSensitive: false,
  );
  static final RegExp _leadingVerse = RegExp(r'^\s*(\d{1,3})[.\s ]+');
  static final RegExp _leadingChapterVerse = RegExp(
    r'^\s*(\d{1,3}):(\d{1,3})[.\s ]+',
  );
  static final RegExp _digits = RegExp(r'^\s*(\d{1,3})[.:\s ]*$');
  static final RegExp _whitespace = RegExp(r'\s+');

  void warn(String message) {
    if (warnings.length < 40) warnings.add(message);
  }

  void read(XmlDocument document) {
    final body = document.findAllElements('body', namespace: '*').firstOrNull;
    _walk(body ?? document.rootElement, BlockStyle.paragraph, 0);
  }

  /// Walks the tree, emitting a block for each block-level element.
  void _walk(XmlNode node, BlockStyle style, int indent) {
    for (final child in node.children) {
      if (child is! XmlElement) continue;
      final name = child.localName.toLowerCase();
      final classes = (child.getAttribute('class') ?? '').toLowerCase();

      if (_isSkippable(name, classes)) continue;

      if (_isHeading(name, classes)) {
        _heading(child.innerText, name);
        continue;
      }

      if (_isBlock(name, classes)) {
        final blockStyle = _styleFor(name, classes, style);
        if (_hasBlockChildren(child)) {
          _walk(child, blockStyle, indent + (name == 'blockquote' ? 1 : 0));
        } else {
          _paragraph(child, blockStyle, indent);
        }
        continue;
      }

      _walk(child, style, indent);
    }
  }

  bool _hasBlockChildren(XmlElement element) => element.children.any(
    (child) =>
        child is XmlElement &&
        const {
          'p',
          'div',
          'blockquote',
          'ul',
          'ol',
          'li',
          'table',
          'h1',
          'h2',
          'h3',
          'h4',
          'h5',
          'h6',
        }.contains(child.localName.toLowerCase()),
  );

  bool _isSkippable(String name, String classes) =>
      const {
        'script',
        'style',
        'head',
        'nav',
        'figure',
        'img',
      }.contains(name) ||
      classes.contains('footnote') ||
      classes.contains('copyright') ||
      classes.contains('toc');

  bool _isHeading(String name, String classes) =>
      const {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(name) ||
      classes.contains('chapterlabel') ||
      classes.split(RegExp(r'\s+')).any((c) => c == 'mt' || c == 'ms');

  bool _isBlock(String name, String classes) =>
      const {'p', 'div', 'blockquote', 'li', 'td'}.contains(name);

  BlockStyle _styleFor(String name, String classes, BlockStyle inherited) {
    if (name == 'blockquote') return BlockStyle.poetry;
    final words = classes.split(RegExp(r'\s+'));
    if (words.any(
      (c) =>
          c.startsWith('q') ||
          c == 'poetry' ||
          c == 'line' ||
          c == 'poem' ||
          c == 'iq',
    )) {
      return BlockStyle.poetry;
    }
    if (words.any((c) => c == 'd' || c == 'psalmtitle')) {
      return BlockStyle.descriptiveTitle;
    }
    if (words.any((c) => c == 's' || c == 's1' || c == 'section')) {
      return BlockStyle.heading;
    }
    return inherited == BlockStyle.poetry
        ? BlockStyle.poetry
        : name == 'li'
        ? BlockStyle.poetry
        : BlockStyle.paragraph;
  }

  /// A heading either names a book, numbers a chapter, or belongs to the text
  /// as a section heading.
  void _heading(String rawText, String tag) {
    final text = rawText.replaceAll(_whitespace, ' ').trim();
    if (text.isEmpty) return;

    final book = _bookHeading(text);
    if (book != null) {
      _book = book.code;
      _chapter = 0;
      _verse = 0;
      // "John 3" names the book and opens the chapter in one line.
      if (book.chapter != null) _startChapter(book.chapter!);
      return;
    }

    final chapter = _chapterHeading.firstMatch(text);
    if (chapter != null) {
      final number = int.parse(chapter.group(1)!);
      if (number >= 1 && number <= EpubImport.maxChapter) {
        _startChapter(number);
        return;
      }
    }

    // Anything else is a heading inside the text, worth keeping as one.
    if (_book != null && _chapter > 0 && tag != 'h1') {
      _add(
        Block(
          style: BlockStyle.heading,
          segments: [
            VerseSegment(verse: _verse, startsVerse: false, text: text),
          ],
        ),
      );
    }
  }

  void _startChapter(int number) {
    _chapter = number;
    _verse = 0;
    if (_book != null) {
      (_blocks[_book!] ??= {}).putIfAbsent(number, () => []);
      (_notes[_book!] ??= {}).putIfAbsent(number, () => []);
    }
  }

  /// Everything inside one block-level element, cut into verses.
  void _paragraph(XmlElement element, BlockStyle style, int indent) {
    final segments = <VerseSegment>[];
    final buffer = StringBuffer();
    var startsVerse = false;
    var verse = _verse;

    void flush() {
      final text = buffer.toString().replaceAll(_whitespace, ' ');
      if (text.trim().isEmpty && !startsVerse) {
        buffer.clear();
        return;
      }
      segments.add(
        VerseSegment(verse: verse, startsVerse: startsVerse, text: text),
      );
      buffer.clear();
      startsVerse = false;
    }

    void openVerse(int number) {
      flush();
      verse = number;
      startsVerse = true;
      _verse = number;
    }

    void write(XmlNode node) {
      if (node is XmlText || node is XmlCDATA) {
        var text = node.value ?? '';
        if (buffer.isEmpty && segments.isEmpty) {
          // "3:16 For God so loved…" and "16 For God so loved…" are both
          // ways of numbering a paragraph that is a verse.
          final both = _leadingChapterVerse.firstMatch(text);
          if (both != null) {
            final chapter = int.parse(both.group(1)!);
            final number = int.parse(both.group(2)!);
            if (chapter <= EpubImport.maxChapter &&
                number <= EpubImport.maxVerse) {
              if (chapter != _chapter) _startChapter(chapter);
              openVerse(number);
              text = text.substring(both.end);
            }
          } else {
            final single = _leadingVerse.firstMatch(text);
            if (single != null) {
              final number = int.parse(single.group(1)!);
              // Only where it carries on from the verse before: a paragraph
              // opening "20 years later" is not verse 20.
              if (number <= EpubImport.maxVerse &&
                  (number == _verse + 1 || (number == 1 && _verse == 0))) {
                openVerse(number);
                text = text.substring(single.end);
              }
            }
          }
        }
        buffer.write(text);
        return;
      }
      if (node is! XmlElement) return;

      final name = node.localName.toLowerCase();
      final classes = (node.getAttribute('class') ?? '').toLowerCase();
      final id = node.getAttribute('id') ?? '';

      if (_isSkippable(name, classes)) return;

      final number = _verseNumber(name, classes, id, node.innerText);
      if (number != null) {
        openVerse(number);
        return;
      }

      if (name == 'br') {
        buffer.write(' ');
        return;
      }

      if (name == 'i' || name == 'em') {
        buffer.write(Markup.addStart);
        for (final child in node.children) {
          write(child);
        }
        buffer.write(Markup.addEnd);
        return;
      }

      for (final child in node.children) {
        write(child);
      }
    }

    for (final child in element.children) {
      write(child);
    }
    flush();

    if (segments.isEmpty) return;
    if (_book == null) return;
    if (_chapter == 0) {
      // Text before any chapter heading: a preface, not Scripture.
      return;
    }
    if (style == BlockStyle.heading) {
      _add(Block(style: BlockStyle.heading, segments: segments));
      return;
    }

    _add(
      Block(
        style: style,
        indent: style == BlockStyle.poetry ? (indent < 1 ? 1 : indent) : 0,
        indentFirstLine: style == BlockStyle.paragraph,
        segments: segments,
      ),
    );
  }

  /// Whether an element is a verse number rather than part of the text.
  int? _verseNumber(String name, String classes, String id, String text) {
    final digits = _digits.firstMatch(text);
    if (digits == null) return null;
    final number = int.parse(digits.group(1)!);
    if (number < 1 || number > EpubImport.maxVerse) return null;

    final words = classes.split(RegExp(r'\s+'));
    final looksLikeVerse =
        name == 'sup' ||
        words.any(
          (c) =>
              c == 'v' ||
              c == 'vn' ||
              c == 'verse' ||
              c == 'versenum' ||
              c == 'verse-num' ||
              c == 'versenumber' ||
              c == 'vnumber',
        ) ||
        RegExp(r'^V\d', caseSensitive: false).hasMatch(id);
    return looksLikeVerse ? number : null;
  }

  void _add(Block block) {
    final book = _book;
    if (book == null || _chapter == 0) return;
    ((_blocks[book] ??= {})[_chapter] ??= []).add(block);
  }

  /// Reads a heading as the name of a book, and the chapter number where it
  /// carries one ("John 3"). Headings name books in every style going — "The
  /// Gospel According to John", "THE REVELATION OF ST. JOHN THE DIVINE", "The
  /// First Epistle of Paul the Apostle to the Corinthians" — so the words
  /// that carry no information are dropped and what is left is looked up.
  ({String code, int? chapter})? _bookHeading(String text) {
    if (text.length > 60) return null;

    var words = text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return null;

    // A number at the end is the chapter, not part of the name.
    int? chapter;
    if (words.length > 1) {
      final last = int.tryParse(words.last);
      if (last != null && last >= 1 && last <= EpubImport.maxChapter) {
        chapter = last;
        words = words.sublist(0, words.length - 1);
      }
    }

    String? numeral;
    final ordered = <String>[];
    for (final word in words) {
      final number =
          _numerals[word] ?? (int.tryParse(word) != null ? word : null);
      if (number != null && numeral == null && ordered.isEmpty) {
        numeral = number;
        continue;
      }
      if (_noiseWords.contains(word)) continue;
      ordered.add(word);
    }
    if (ordered.isEmpty) return null;

    final prefix = numeral ?? '';
    for (final candidate in [ordered.join(), ...ordered]) {
      final code = _lookup('$prefix$candidate') ?? _lookup(candidate);
      if (code != null) return (code: code, chapter: chapter);
    }
    return null;
  }

  static const Map<String, String> _numerals = {
    'first': '1',
    'second': '2',
    'third': '3',
    'i': '1',
    'ii': '2',
    'iii': '3',
  };

  /// Words that decorate a book's name without naming it.
  static const Set<String> _noiseWords = {
    'the',
    'of',
    'to',
    'book',
    'books',
    'gospel',
    'according',
    'epistle',
    'epistles',
    'letter',
    'general',
    'st',
    'saint',
    'apostle',
    'paul',
    'holy',
    'divine',
    'prophet',
    'chapter',
  };

  String? _lookup(String key) {
    final needle = ReferenceSearch.normalise(key);
    if (needle.isEmpty) return null;
    for (final meta in BookMeta.all) {
      if (ReferenceSearch.normalise(meta.name) == needle ||
          ReferenceSearch.normalise(meta.abbrev) == needle ||
          meta.code.toLowerCase() == needle) {
        return meta.code;
      }
    }
    return ReferenceSearch.aliases[needle];
  }

  List<Book> finish() {
    final books = <Book>[];
    for (final entry in _blocks.entries) {
      final meta = BookMeta.lookup(entry.key);
      if (meta == null) continue;

      final numbers = entry.value.keys.toList()..sort();
      final chapters = <Chapter>[];
      for (final number in numbers) {
        final blocks = entry.value[number]!
            .where((block) => !block.isEmpty)
            .toList();
        if (blocks.isEmpty) continue;
        final chapter = Chapter(
          number: chapters.length + 1,
          blocks: blocks,
          notes: _notes[entry.key]?[number] ?? const [],
        );
        if (chapter.verseCount == 0) {
          warn('${meta.name} $number has no numbered verses; left out.');
          continue;
        }
        chapters.add(chapter);
      }

      if (chapters.isEmpty) {
        warn('${meta.name} was found but held no verses; left out.');
        continue;
      }
      books.add(Book(meta: meta, chapters: chapters));
    }
    return books;
  }
}
