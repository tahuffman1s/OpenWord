import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/bible.dart';
import '../model/book_meta.dart';
import '../model/text_normal.dart';
import '../model/versification_check.dart';
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
    // The table of contents is in the spine of most EPUBs, and it is not
    // Scripture: read as one it puts a list of every book of the Bible in
    // whatever chapter happened to be open. The manifest says which file
    // it is, so there is nothing to guess at.
    final navigation = _navigationPaths(opf, base);
    final documents = _spineDocuments(
      opf,
      files,
      base,
    ).where((file) => !navigation.contains(_normalisePath(file.name))).toList();
    if (documents.isEmpty) {
      return const ImportResult.failed(
        'That EPUB has no readable chapters in it.',
      );
    }

    final labels = _tocLabels(files, opf, base);
    final builder = _BibleBuilder();
    for (final document in documents) {
      try {
        builder.read(
          XmlDocument.parse(_repair(_text(document))),
          path: document.name,
          tocLabel: labels[_normalisePath(document.name)],
        );
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

    // Which verse numbering this follows decides whether the bundled
    // cross-references and the original-language layer can be pointed at
    // it. They do not fail against a Bible numbered differently; they
    // quietly land on the wrong verse, so this is measured rather than
    // assumed.
    final described = Bible(
      translation: _describe(opf, fileName, builder),
      books: books,
    );
    final match = VersificationCheck.against(described);
    if (match.versification == Versification.other) {
      builder.warn(
        'This Bible numbers its verses differently from the ones bundled '
        'with the app — ${match.differing} of ${match.compared} chapters '
        'are a different length. Cross-references and the Hebrew and Greek '
        'are not offered for it, because they would point at the wrong '
        'verses. Everything else works.',
      );
      for (final example in match.examples) {
        builder.warn(example);
      }
    }

    return ImportResult(
      bible: Bible(
        translation: described.translation.copyWith(
          versification: match.versification,
        ),
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

  /// The EPUB's own navigation documents: the EPUB 3 nav, which the
  /// manifest marks `properties="nav"`, and the EPUB 2 `toc.ncx`.
  static Set<String> _navigationPaths(XmlDocument opf, String base) {
    final paths = <String>{};
    for (final item in opf.findAllElements('item', namespace: '*')) {
      final href = item.getAttribute('href');
      if (href == null) continue;
      final properties = item.getAttribute('properties') ?? '';
      final mediaType = item.getAttribute('media-type') ?? '';
      if (properties.split(RegExp(r'\s+')).contains('nav') ||
          mediaType.contains('x-dtbncx')) {
        paths.add(_resolve(base, href));
      }
    }
    return paths;
  }

  /// What the table of contents calls each document — the EPUB 3 nav, or
  /// the EPUB 2 `toc.ncx`. A Bible whose chapter files carry no book title
  /// of their own is still named here.
  static Map<String, String> _tocLabels(
    Map<String, ArchiveFile> files,
    XmlDocument opf,
    String base,
  ) {
    final labels = <String, String>{};

    void note(String? href, String? label) {
      if (href == null || label == null) return;
      final text = label.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) return;
      labels.putIfAbsent(_resolve(base, href), () => text);
    }

    for (final item in opf.findAllElements('item', namespace: '*')) {
      final href = item.getAttribute('href');
      final properties = item.getAttribute('properties') ?? '';
      final mediaType = item.getAttribute('media-type') ?? '';
      if (href == null) continue;
      final isNav = properties.split(RegExp(r'\s+')).contains('nav');
      final isNcx = mediaType.contains('x-dtbncx');
      if (!isNav && !isNcx) continue;

      final file = files[_resolve(base, href)];
      if (file == null) continue;
      final XmlDocument document;
      try {
        document = XmlDocument.parse(_repair(_text(file)));
      } on Object {
        continue;
      }

      // EPUB 2: navPoint → navLabel/text plus content/@src.
      for (final point in document.findAllElements(
        'navPoint',
        namespace: '*',
      )) {
        note(
          point
              .findElements('content', namespace: '*')
              .firstOrNull
              ?.getAttribute('src'),
          point.findElements('navLabel', namespace: '*').firstOrNull?.innerText,
        );
      }

      // EPUB 3: the nav document is a list of links.
      for (final link in document.findAllElements('a', namespace: '*')) {
        note(link.getAttribute('href'), link.innerText);
      }
    }
    return labels;
  }

  /// A document's text, composed to NFC.
  ///
  /// An EPUB may carry its accents decomposed, or two Hebrew points in
  /// either order. Either looks right on the page and matches nothing a
  /// reader types, so everything is composed once, here, before it is
  /// parsed — which covers the Scripture, the headings the books are named
  /// from and the footnotes alike.
  static String _text(ArchiveFile file) =>
      ScriptureText.normalise(utf8.decode(file.content, allowMalformed: true));

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

  /// Headings wait here until there is Scripture under them.
  ///
  /// A section heading belongs to what follows, and what follows is often
  /// the next chapter — "The Flood Subsides" is printed before Genesis 8:1,
  /// while the reader is still in chapter 7. Holding it until the next verse
  /// opens puts it at the head of the chapter it introduces instead of
  /// stranding it at the foot of the one before.
  /// Each held block with the chapter that was open when it was gathered,
  /// so one that turns out to open a different chapter can be stripped of
  /// the verse number it would otherwise claim from the chapter before.
  final List<({Block block, int chapter})> _pending = [];

  static final RegExp _chapterHeading = RegExp(
    r'^(?:chapter|psalm|chap\.?)?\s*(\d{1,3})\s*$',
    caseSensitive: false,
  );
  static final RegExp _leadingVerse = RegExp(r'^\s*(\d{1,3})[.\s ]+');
  static final RegExp _leadingChapterVerse = RegExp(
    r'^\s*(\d{1,3}):(\d{1,3})[.\s ]+',
  );

  /// Project Gutenberg's Bibles number every verse from the book up:
  /// `41:001:001` is Mark 1:1. Read as chapter and verse it would put the
  /// whole Gospel into a chapter 41 that does not exist.
  static final RegExp _leadingBookChapterVerse = RegExp(
    r'^\s*(\d{1,3}):(\d{1,3}):(\d{1,3})[.\s]+',
  );

  /// The sixty-six books of the Protestant canon in order, which is how
  /// Project Gutenberg numbers them.
  static final List<String> _canonicalOrder = [
    for (final meta in BookMeta.all)
      if (meta.section != BookSection.deuterocanon) meta.code,
  ];
  static final RegExp _digits = RegExp(r'^\s*(\d{1,3})[.:\s ]*$');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _anyNumber = RegExp(r'\d{1,3}');
  static final RegExp _romanHeading = RegExp(
    r'^(?:chapter|psalm|chap\.?)?\s*([ivxlc]+)\s*$',
    caseSensitive: false,
  );

  /// The first number in a string, for a chapter label in a language whose
  /// word for "chapter" this app has never heard of.
  static int? _numberIn(String text) {
    final match = _anyNumber.firstMatch(text);
    return match == null ? null : int.parse(match.group(0)!);
  }

  /// Roman numerals, as far as a chapter number ever reaches.
  static int? _roman(String text) {
    const values = {'i': 1, 'v': 5, 'x': 10, 'l': 50, 'c': 100};
    final letters = text.toLowerCase();
    var total = 0;
    var previous = 0;
    for (var i = letters.length - 1; i >= 0; i--) {
      final value = values[letters[i]];
      if (value == null) return null;
      if (value < previous) {
        total -= value;
      } else {
        total += value;
        previous = value;
      }
    }
    return total >= 1 && total <= EpubImport.maxChapter ? total : null;
  }

  void warn(String message) {
    if (warnings.length < 40) warnings.add(message);
  }

  /// Reads one document of the spine.
  ///
  /// [path] and [tocLabel] are what the EPUB says this file is, and are used
  /// only when nothing inside it names a book: a file called `GEN.xhtml`, or
  /// one the table of contents calls "Genesis", is Genesis even when the
  /// markup never says so.
  void read(XmlDocument document, {String? path, String? tocLabel}) {
    final named = _bookFromName(path) ?? _bookHeading(tocLabel ?? '');
    if (named != null && named.code != _book) {
      _book = named.code;
      _chapter = 0;
      _verse = 0;
      if (named.chapter != null) _startChapter(named.chapter!);
    }

    // Nothing in this document has been numbered yet. A file that numbers
    // nothing at all — a preface, a copyright page, an index, a table of
    // contents — used to have every paragraph read as a continuation of the
    // last verse of the last chapter left open, because the open verse
    // carried across the file boundary. Text ahead of a document's own
    // first verse marker belongs to no verse, and text belonging to no
    // verse is dropped.
    //
    // The open verse itself is kept, because it is the one signal that a
    // chapter has begun in an edition that heads none: a file whose numbers
    // run 1, 2, 3 after a file that ended at 31 has started a new chapter.
    _numberedHere = false;
    _inNavigation = false;

    final body = document.findAllElements('body', namespace: '*').firstOrNull;
    _walk(body ?? document.rootElement, BlockStyle.paragraph, 0);
  }

  /// A book named by a file name: `GEN.xhtml`, `01_Genesis.xhtml`,
  /// `PSA119.xhtml`.
  ({String code, int? chapter})? _bookFromName(String? path) {
    if (path == null) return null;
    var stem = path.split('/').last;
    final dot = stem.lastIndexOf('.');
    if (dot > 0) stem = stem.substring(0, dot);

    stem = stem
        // "GEN01" is a book and a chapter; "1CO" is one book.
        .replaceAllMapped(
          RegExp(r'([A-Za-z])(\d)'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        // A leading file-order number is not part of the name.
        .replaceFirst(RegExp(r'^\s*\d{1,3}\s+'), '')
        .trim();
    if (stem.isEmpty) return null;
    return _bookHeading(stem);
  }

  /// Walks the tree, emitting a block for each block-level element.
  void _walk(XmlNode node, BlockStyle style, int indent) {
    for (final child in node.children) {
      if (child is! XmlElement) continue;
      final name = child.localName.toLowerCase();
      final classes = (child.getAttribute('class') ?? '').toLowerCase();

      if (_skip(child)) continue;

      if (_isHeading(name, classes)) {
        _heading(
          child.innerText,
          name,
          labelsChapter: _isChapterLabel(classes),
          level: _headingLevel(name, classes),
        );
        continue;
      }

      if (_isBlock(name, classes)) {
        // A row of links is navigation, not Scripture.
        if (_isNavigation(child)) {
          _inNavigation = true;
          continue;
        }
        final blockStyle = _styleFor(name, classes, style);
        final level = _poetryLevel(classes);
        // A row holds cells, which are not blocks: the row is read whole
        // however many cells it has, or each name of a genealogy would
        // become a paragraph of its own.
        if (_hasBlockChildren(child) && blockStyle != BlockStyle.tableRow) {
          _walk(
            child,
            blockStyle,
            level ?? indent + (name == 'blockquote' ? 1 : 0),
          );
        } else {
          _paragraph(
            child,
            blockStyle,
            level ??
                (blockStyle == BlockStyle.listItem
                    ? _listDepth
                    : indent + (name == 'blockquote' ? 1 : 0)),
          );
        }
        continue;
      }

      // How deep a list is nested is the level of the items inside it.
      if (name == 'ol' || name == 'ul') {
        _listDepth++;
        _walk(child, style, indent);
        _listDepth--;
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

  static const Set<String> _skippedNames = {
    'script',
    'style',
    'head',
    'nav',
    'figure',
    'img',
    // A footnote proper, kept at the end of the file.
    'aside',
    // The machinery of a pop-up note.
    'input',
  };

  /// Classes whose contents are apparatus rather than Scripture.
  ///
  /// `note` matters as much as `footnote`: haiola writes each footnote
  /// inline as `<span class='note'>…</span>`, so without this the note's
  /// text lands in the middle of the verse it annotates.
  static const Set<String> _skippedClasses = {
    'footnote',
    'note',
    'noteref',
    'notemark',
    'notebackref',
    'ntlbl',
    'popnote',
    'ftxt',
    'crossref',
    'xref',
    'copyright',
    'toc',
  };

  /// Whether a block is a row of links rather than a word of Scripture.
  ///
  /// A book's landing page lists the chapters under it — "1 John 1 · 1 John
  /// 2 · …" — and an edition that puts one in the reading order had that
  /// read as the first verse of the book: a paragraph opening with a number
  /// is one of the ways an edition numbers a verse, so the "1" of "1 John
  /// 1" was taken for verse 1 and the rest of the line for its text.
  ///
  /// Scripture is not made of links and navigation is, which is the whole
  /// test. Measured on how much of the text sits inside a link rather than
  /// on how many links there are, so a verse carrying one or two of them —
  /// a footnote marker, a reference — is not mistaken for a menu. Two links
  /// at least, because a single one is as likely to be a citation as a
  /// list, and a heading is never judged this way: plenty of editions make
  /// a chapter's own heading a link to itself.
  bool _isNavigation(XmlElement element) {
    var links = 0;
    var linked = 0;
    var total = 0;
    // A block that numbers a verse is Scripture whatever else is in it.
    // Some editions hang a link on every verse — to a commentary, to a
    // note — and without this a verse wrapped in one end to end would be
    // read as a menu item and dropped.
    var numbered = false;

    void measure(XmlNode node, {required bool inLink}) {
      if (node is XmlText || node is XmlCDATA) {
        final length = (node.value ?? '').trim().length;
        total += length;
        if (inLink) linked += length;
        return;
      }
      if (node is! XmlElement) return;
      // Apparatus is not counted either way: a verse with three footnote
      // markers in it is still a verse.
      if (_skip(node)) return;
      final classes = classesOf(node);
      if (_isChapterLabel(classes) ||
          _verseNumber(
                node.localName.toLowerCase(),
                classes,
                node.getAttribute('id') ?? '',
                node.innerText,
              ) !=
              null) {
        numbered = true;
        return;
      }
      final isLink =
          node.localName.toLowerCase() == 'a' &&
          (node.getAttribute('href') ?? '').isNotEmpty;
      if (isLink && !inLink) links++;
      for (final child in node.children) {
        measure(child, inLink: inLink || isLink);
      }
    }

    for (final child in element.children) {
      measure(child, inLink: false);
    }
    if (numbered || links < 1 || total == 0) return false;
    final fraction = linked / total;
    // A block that is nothing but a link is navigation however many links
    // it has: an edition's footer puts each of "ESV", "The Old Testament"
    // and "Show Last Hilite" in a paragraph of its own, and one link each
    // is all they are. A verse is never a link end to end.
    if (fraction >= 0.95) return true;
    // Below that it takes more than one, because a single link inside a
    // run of text is as likely to be a citation as a list.
    return links >= 2 && fraction >= 0.6;
  }

  bool _skip(XmlElement element) {
    final name = element.localName.toLowerCase();
    if (_skippedNames.contains(name)) return true;

    final classes = (element.getAttribute('class') ?? '').toLowerCase();
    if (_classWords(classes).any(_skippedClasses.contains)) {
      return true;
    }

    // EPUB 3 says what a thing is in its own attribute, whatever it is
    // classed as.
    final type = (element.getAttribute('type', namespace: '*') ?? '')
        .toLowerCase();
    return type.contains('footnote') ||
        type.contains('noteref') ||
        type.contains('endnote');
  }

  static final RegExp _titleClass = RegExp(r'^(mt|ms)\d?$');

  /// Classes that mark an element as the label opening a chapter. haiola —
  /// which generates the EPUBs on ebible.org, and so most of the freely
  /// available ones — writes every chapter label as `psalmlabel`, Psalms or
  /// not, so this is the difference between reading those Bibles and
  /// refusing them.
  static const Set<String> _chapterClasses = {
    'chapterlabel',
    'psalmlabel',
    'chapternum',
    'chapternumber',
    // USFM's own marker for a chapter label. Not bare "c", which as often
    // as not means centred.
    'cl',
  };

  bool _isChapterLabel(String classes) =>
      _classWords(classes).any(_chapterClasses.contains);

  bool _isHeading(String name, String classes) =>
      const {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}.contains(name) ||
      _isChapterLabel(classes) ||
      _classWords(classes).any(_titleClass.hasMatch);

  bool _isBlock(String name, String classes) =>
      const {'p', 'div', 'blockquote', 'li', 'tr'}.contains(name);

  int _listDepth = 0;
  int _cellsInRow = 0;

  /// Whether a verse marker has been seen in the document being read.
  bool _numberedHere = false;

  /// Whether this document has reached its navigation.
  ///
  /// A footer is not one block. Between the links an edition writes plain
  /// labels — "ESV · The Old Testament" heads the list of the books under
  /// it — which carry no link to give them away and would otherwise be
  /// appended to the last verse of the book, as the links themselves used
  /// to be. Once a document is into its navigation, everything that
  /// follows is navigation until something numbers a verse again.
  bool _inNavigation = false;

  /// What was last placed, which is how a line carrying nothing but an
  /// indent is read: after a line of verse it is another line of verse.
  BlockStyle? _lastStyle;

  /// What a verse is printed as, by the verse it is stored under.
  final Map<String, Map<int, Map<int, String>>> _labels = {};

  /// The labels of the chapter being read.
  final Map<int, String> _verseLabels = {};

  /// Every verse a chapter numbers, so one numbered and left empty can be
  /// told from one that was never there.
  final Map<String, Map<int, Set<int>>> _seen = {};
  final Set<int> _versesSeenHere = {};

  /// A bridged verse as the edition prints it: "1-2", "1,2", "1–3".
  static String? _printedVerse(String text) {
    final match = _bridgedVerses.firstMatch(text.trim());
    return match?.group(0)?.trim();
  }

  /// A cell of a table. Not a block of its own: a row is the block, and
  /// its cells are parted inside it, or a genealogy comes out as one
  /// paragraph per name.
  static bool _isCell(String name) => name == 'td' || name == 'th';

  /// Where the markup sets a block across the column.
  static BlockAlign _alignFor(String classes, String style) {
    final flattened = style.replaceAll(' ', '');
    if (flattened.contains('text-align:center')) return BlockAlign.center;
    if (flattened.contains('text-align:right')) return BlockAlign.end;
    for (final word in _classWords(classes)) {
      if (word == 'center' ||
          word == 'centre' ||
          word == 'centered' ||
          word == 'qc' ||
          word == 'pc') {
        return BlockAlign.center;
      }
      if (word == 'right' ||
          word == 'qr' ||
          word == 'pr' ||
          word == 'colophon') {
        return BlockAlign.end;
      }
    }
    return BlockAlign.start;
  }

  /// What a section heading is called. USFM says `s1`; the editions that
  /// were not generated from USFM spell it out.
  static const Set<String> _headingClasses = {
    's',
    's1',
    's2',
    's3',
    'section',
    'sectionhead',
    'sectionheading',
    'subhead',
    'subheading',
    'heading',
    'head',
  };

  /// How deep a poetry line is indented, where the markup says so: `q2`,
  /// `line2`, `indent-2`. Without it every line of a psalm sits at the same
  /// depth and the couplets stop reading as couplets.
  static final RegExp _levelClass = RegExp(
    r'^(?:q|iq|li|pi|line|indent)-?([1-4])$',
  );

  /// A class that says a line is indented and nothing else: `indent`,
  /// `indent2`, `block-indent`.
  static final RegExp _indentClass = RegExp(r'^(?:block)?indent([1-4])?$');

  static String classesOf(XmlElement element) =>
      (element.getAttribute('class') ?? '').toLowerCase();

  /// The class names in an attribute, with the punctuation publishers vary
  /// on taken out.
  ///
  /// `chapter-num`, `chapternum` and `chapter_num` are one class spelled
  /// three ways, and all three turn up; the sets below used to have to
  /// carry every spelling, and a spelling nobody had thought of — a
  /// hyphenated `psalm-title` — simply did not match.
  static List<String> _classWords(String classes) => classes
      .split(RegExp(r'[\s]+'))
      .map((word) => word.replaceAll(RegExp(r'[-_]'), ''))
      .where((word) => word.isNotEmpty)
      .toList();

  /// How major a heading is, where the markup says. An EPUB spells it
  /// either in the tag — `h1` above `h2` — or in a class, `s1` above `s2`.
  static int _headingLevel(String name, String classes) {
    for (final word in _classWords(classes)) {
      if (word == 'ms' || word == 'ms1' || word == 'majorsection') return 1;
      if (word == 's' || word == 's1') return 2;
      if (word == 's2' || word == 's3' || word == 's4') return 3;
    }
    return switch (name) {
      'h1' || 'h2' => 2,
      'h3' => 2,
      'h4' || 'h5' || 'h6' => 3,
      _ => 0,
    };
  }

  /// Text a publisher sets in small capitals, which in Scripture means the
  /// divine name. Spelled as a class, or in a style attribute.
  static bool _isDivineName(String name, String classes, String style) {
    if (name == 'abbr') return false;
    for (final word in _classWords(classes)) {
      if (word == 'nd' ||
          word == 'divine' ||
          word == 'divinename' ||
          word == 'sc' ||
          word == 'smallcaps') {
        return true;
      }
    }
    return style.replaceAll(' ', '').contains('font-variant:small-caps');
  }

  int? _poetryLevel(String classes) {
    for (final word in _classWords(classes)) {
      final match = _levelClass.firstMatch(word);
      if (match != null) return int.parse(match.group(1)!);
      // An indent with no depth on it is one step in from the line above.
      if (_indentClass.hasMatch(word)) return 2;
    }
    return null;
  }

  BlockStyle _styleFor(String name, String classes, BlockStyle inherited) {
    if (name == 'blockquote') return BlockStyle.poetry;
    final words = _classWords(classes);
    // Before the poetry test below: "qa" begins with a q and is not a
    // line of verse but the letter an acrostic stanza runs on.
    if (words.any((c) => c == 'qa' || c == 'acrostic')) {
      return BlockStyle.acrostic;
    }
    if (words.any((c) => c == 'sp' || c == 'speaker')) {
      return BlockStyle.speaker;
    }
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
    // A line that says nothing about itself but how far it is indented,
    // coming straight after a line of verse, is the next line of the same
    // stanza — which is how the ESV sets the second line of a couplet.
    // Read as prose it took a paragraph's first-line indent and wrapped
    // back to the margin, so a couplet came out looking like a poetry line
    // that had lost its indent. Only after verse: an indented paragraph of
    // prose is a common thing in its own right.
    if (_lastStyle == BlockStyle.poetry && words.any(_indentClass.hasMatch)) {
      return BlockStyle.poetry;
    }
    if (words.any(
      (c) =>
          c == 'd' ||
          c == 'psalmtitle' ||
          c == 'psalmref' ||
          c == 'superscription' ||
          c == 'descriptivetitle',
    )) {
      return BlockStyle.descriptiveTitle;
    }
    if (words.any(_headingClasses.contains)) {
      return BlockStyle.heading;
    }
    if (name == 'li') return BlockStyle.listItem;
    if (name == 'tr') return BlockStyle.tableRow;
    return inherited == BlockStyle.poetry
        ? BlockStyle.poetry
        : BlockStyle.paragraph;
  }

  /// A heading either names a book, numbers a chapter, or belongs to the text
  /// as a section heading.
  void _heading(
    String rawText,
    String tag, {
    bool labelsChapter = false,
    int level = 0,
  }) {
    final text = rawText.replaceAll(_whitespace, ' ').trim();
    if (text.isEmpty) return;

    // An element the markup itself calls a chapter label is one, whatever
    // language it is labelled in: "Chapter 3", "Kapitel 3", "Psalm 23", or
    // bare "3". Only the number has to be found.
    if (labelsChapter) {
      final number = _numberIn(text);
      if (number != null && number <= EpubImport.maxChapter) {
        _startChapter(number);
      }
      return;
    }

    final book = _bookHeading(text);
    if (book != null) {
      // Whatever was waiting belonged to the book that just ended, so it
      // is placed there rather than thrown away: the Song of Songs ends
      // with a speaker's label and nothing follows it to flush it out.
      _flushPending();
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

    // "CHAPTER XXIII", the way older editions number them.
    final roman = _romanHeading.firstMatch(text);
    if (roman != null) {
      final number = _roman(roman.group(1)!);
      if (number != null) {
        _startChapter(number);
        return;
      }
    }

    // Anything else is a heading inside the text, worth keeping as one.
    if (_book != null && tag != 'h1') {
      _hold(
        Block(
          style: BlockStyle.heading,
          level: level,
          segments: [
            VerseSegment(verse: _verse, startsVerse: false, text: text),
          ],
        ),
      );
    }
  }

  void _startChapter(int number) {
    _stashChapter();
    _chapter = number;
    _verse = 0;
    if (_book != null) {
      (_blocks[_book!] ??= {}).putIfAbsent(number, () => []);
      (_notes[_book!] ??= {}).putIfAbsent(number, () => []);
    }
  }

  /// Puts away what was gathered about the chapter just left.
  void _stashChapter() {
    final book = _book;
    if (book == null || _chapter == 0) return;
    if (_verseLabels.isNotEmpty) {
      ((_labels[book] ??= {})[_chapter] ??= {}).addAll(_verseLabels);
    }
    if (_versesSeenHere.isNotEmpty) {
      ((_seen[book] ??= {})[_chapter] ??= <int>{}).addAll(_versesSeenHere);
    }
    _verseLabels.clear();
    _versesSeenHere.clear();
  }

  /// The block styles that stand above a chapter's first verse rather than
  /// belonging to a verse of their own.
  static const Set<BlockStyle> _opensChapter = {
    BlockStyle.heading,
    BlockStyle.descriptiveTitle,
    BlockStyle.acrostic,
    BlockStyle.speaker,
  };

  /// Everything inside one block-level element, cut into verses.
  void _paragraph(XmlElement element, BlockStyle style, int indent) {
    _cellsInRow = 0;
    final align = _alignFor(
      (element.getAttribute('class') ?? '').toLowerCase(),
      (element.getAttribute('style') ?? '').toLowerCase(),
    );
    final segments = <VerseSegment>[];
    final buffer = StringBuffer();
    var startsVerse = false;
    // Until this document numbers something, its text belongs to no verse.
    var verse = _numberedHere ? _verse : 0;
    // Set when a chapter opened partway through this block without saying
    // which verse it opened on, which makes the text that follows verse 1.
    var impliesFirstVerse = false;

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

    /// Opens a chapter partway through a block.
    ///
    /// Anything buffered ahead of it precedes the new chapter's first verse,
    /// so it is a label — the book's name as a running head — and is marked
    /// as belonging to no verse so that it is dropped below. Text that has
    /// already been placed in a verse is left as it is.
    void startChapterHere(int number) {
      if (segments.isEmpty && !startsVerse) verse = 0;
      flush();
      _startChapter(number);
    }

    void openVerse(int number, {String? printed}) {
      impliesFirstVerse = false;
      flush();
      // "1-2" for a bridged verse: the text is stored under the first and
      // printed as the edition prints it.
      if (printed != null && printed != '\$number') {
        _verseLabels[number] = printed;
      }
      // Obadiah, Philemon, 2 and 3 John and Jude have one chapter, and many
      // editions give them no chapter heading at all. A numbered verse under
      // a book heading opens chapter 1 rather than being thrown away.
      if (_chapter == 0 && _book != null) {
        _startChapter(1);
      } else if (number < _verse && _book != null) {
        // The numbering has gone backwards, so a chapter began and nothing
        // said so. This is the one signal that does not depend on knowing
        // how a particular edition marks its chapters.
        _startChapter(_chapter + 1);
      }
      verse = number;
      startsVerse = true;
      _verse = number;
      _numberedHere = true;
      // Scripture again: whatever navigation there was is behind us.
      _inNavigation = false;
      _versesSeenHere.add(number);
    }

    void write(XmlNode node) {
      if (node is XmlText || node is XmlCDATA) {
        var text = node.value ?? '';
        if (impliesFirstVerse && text.trim().isNotEmpty) {
          openVerse(1);
        }
        if (buffer.isEmpty && segments.isEmpty) {
          // "3:16 For God so loved…" and "16 For God so loved…" are both
          // ways of numbering a paragraph that is a verse.
          // Book, chapter and verse, before chapter and verse: "41:001:001"
          // must not be read as chapter 41.
          final numbered = _leadingBookChapterVerse.firstMatch(text);
          if (numbered != null) {
            final book = int.parse(numbered.group(1)!);
            final chapter = int.parse(numbered.group(2)!);
            final number = int.parse(numbered.group(3)!);
            if (book >= 1 &&
                book <= _canonicalOrder.length &&
                chapter >= 1 &&
                chapter <= EpubImport.maxChapter &&
                number >= 1 &&
                number <= EpubImport.maxVerse) {
              final code = _canonicalOrder[book - 1];
              if (code != _book) {
                _book = code;
                _chapter = 0;
                _verse = 0;
              }
              if (chapter != _chapter) startChapterHere(chapter);
              openVerse(number);
              buffer.write(text.substring(numbered.end));
              return;
            }
          }

          final both = _leadingChapterVerse.firstMatch(text);
          if (both != null) {
            final chapter = int.parse(both.group(1)!);
            final number = int.parse(both.group(2)!);
            if (chapter <= EpubImport.maxChapter &&
                number <= EpubImport.maxVerse) {
              if (chapter != _chapter) startChapterHere(chapter);
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

      if (_skip(node)) return;

      // A chapter number printed inside the paragraph rather than above it.
      // The ESV and others open each chapter with
      // `<b class="chapter-num" id="v43001001-1">1:1&nbsp;</b>`, which is the
      // chapter and its first verse in one marker.
      if (_isChapterLabel(classes)) {
        final opened = _chapterAt(node.innerText, id);
        if (opened != null) {
          if (opened.chapter != _chapter) startChapterHere(opened.chapter);
          if (opened.verse != null) {
            openVerse(opened.verse!);
          } else {
            // A printed Bible does not repeat the 1 of a chapter's first
            // verse: the chapter number stands for it. So whatever follows
            // this marker is verse 1, unless a verse marker gets in first.
            impliesFirstVerse = true;
          }
        }
        // Either way the marker is a number, not Scripture.
        return;
      }

      final number = _verseNumber(name, classes, id, node.innerText);
      if (number != null) {
        openVerse(number, printed: _printedVerse(node.innerText));
        return;
      }

      if (name == 'br') {
        buffer.write(' ');
        return;
      }

      // A cell boundary inside a row, so the row can be laid out as one.
      if (_isCell(name)) {
        if (_cellsInRow > 0) buffer.write(Markup.cell);
        _cellsInRow++;
        for (final child in node.children) {
          write(child);
        }
        return;
      }

      // Words quoted from elsewhere in Scripture. Not the same thing as a
      // translator's addition, though both used to be stored as one.
      if (name == 'q' || _classWords(classes).contains('qt')) {
        buffer.write(Markup.quotationStart);
        for (final child in node.children) {
          write(child);
        }
        buffer.write(Markup.quotationEnd);
        return;
      }

      // The divine name, which an edition sets in small capitals — as a
      // class, or in a style attribute. Every printed Bible distinguishes
      // it from "Lord" as a title, and the marker is what lets this one.
      if (_isDivineName(
        name,
        classes,
        (node.getAttribute('style') ?? '').toLowerCase(),
      )) {
        buffer.write(Markup.divineStart);
        for (final child in node.children) {
          write(child);
        }
        buffer.write(Markup.divineEnd);
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

    // A heading, a psalm's superscription, the letter of an acrostic stanza
    // and a speaker's label all stand above a chapter's first verse. In an
    // edition that prints the chapter number inside that verse's own
    // paragraph — the ESV does — they arrive before anything has said the
    // chapter changed, so they are held and placed once it is known which
    // chapter they open. Without this, a psalm's heading and superscription
    // were committed to the end of the psalm before it.
    if (_opensChapter.contains(style)) {
      _hold(
        Block(
          style: style,
          level: style == BlockStyle.heading
              ? _headingLevel(
                  element.localName.toLowerCase(),
                  classesOf(element),
                )
              : 0,
          align: align,
          segments: segments,
        ),
      );
      return;
    }

    // Once a document is into its footer, a block that numbers nothing is
    // part of that footer rather than the end of the book.
    if (_inNavigation && !segments.any((segment) => segment.startsVerse)) {
      return;
    }

    // Text sitting before the chapter's first verse is a label, not
    // Scripture — the book's name repeated as a running head, which the
    // ESV prints inside the opening paragraph. Every word of Scripture
    // belongs to a verse.
    while (segments.isNotEmpty &&
        segments.first.verse == 0 &&
        !segments.first.startsVerse) {
      segments.removeAt(0);
    }
    if (segments.isEmpty) return;

    // Whatever headings were waiting belong above this, in whatever chapter
    // this turned out to be.
    _flushPending();
    _add(
      Block(
        style: style,
        indent: switch (style) {
          BlockStyle.poetry => indent < 1 ? 1 : indent,
          // How deep the list was nested.
          BlockStyle.listItem => indent < 1 ? 1 : indent,
          _ => 0,
        },
        indentFirstLine: style == BlockStyle.paragraph,
        align: align,
        segments: segments,
      ),
    );
  }

  static const Set<String> _verseClasses = {
    'v',
    'vn',
    'verse',
    'versenum',
    'versenumber',
    'vnumber',
  };

  static final RegExp _verseId = RegExp(r'^V\d', caseSensitive: false);
  static final RegExp _bridgedVerses = RegExp(
    r'^\s*(\d{1,3})\s*[-\u2010-\u2015]\s*\d{1,3}[.:\s\u00a0]*$',
  );
  static final RegExp _lastNumber = RegExp(r'(\d{1,3})\D*$');

  static final RegExp _chapterAndVerse = RegExp(
    r'(\d{1,3})\s*[:.]\s*(\d{1,3})',
  );

  /// `v43001001-1` — book, chapter and verse in one id, the scheme Crossway
  /// and several others number their anchors with.
  static final RegExp _packedId = RegExp(r'^v(\d{2})(\d{3})(\d{3})');

  /// What chapter — and, where the marker carries it, what verse — an
  /// element that the markup calls a chapter number opens.
  ({int chapter, int? verse})? _chapterAt(String text, String id) {
    // The id, where it carries the whole reference: `v01002001-1`.
    ({int chapter, int verse})? packed;
    final match = _packedId.firstMatch(id);
    if (match != null) {
      final chapter = int.parse(match.group(2)!);
      final verse = int.parse(match.group(3)!);
      if (chapter >= 1 &&
          chapter <= EpubImport.maxChapter &&
          verse >= 1 &&
          verse <= EpubImport.maxVerse) {
        packed = (chapter: chapter, verse: verse);
      }
    }

    final both = _chapterAndVerse.firstMatch(text);
    if (both != null) {
      final chapter = int.parse(both.group(1)!);
      final verse = int.parse(both.group(2)!);
      if (chapter >= 1 &&
          chapter <= EpubImport.maxChapter &&
          verse >= 1 &&
          verse <= EpubImport.maxVerse) {
        return (chapter: chapter, verse: verse);
      }
    }

    final number = _numberIn(text);
    if (number != null && number >= 1 && number <= EpubImport.maxChapter) {
      // A chapter opening prints its number and not the 1 of its first
      // verse, which the id holds. Without reading it the chapter opened
      // with no verse open and the whole of verse 1 was dropped as a
      // running head.
      return (
        chapter: number,
        verse: packed?.chapter == number ? packed!.verse : null,
      );
    }

    // Nothing printed: the id is all there is to go on.
    if (packed != null) return packed;
    return null;
  }

  /// Whether an element is a verse number rather than part of the text.
  ///
  /// Some editions print the number, others hold it in an `id` and draw it
  /// with a stylesheet — `<a id="V3"/>` with nothing inside. The marker is
  /// still a marker; the number just has to be read from somewhere else.
  int? _verseNumber(String name, String classes, String id, String text) {
    final words = _classWords(classes);
    final marked =
        name == 'sup' ||
        words.any(_verseClasses.contains) ||
        _verseId.hasMatch(id);
    if (!marked) return null;

    // "3" or, where an edition bridges two verses, "3-4".
    final digits = _digits.firstMatch(text) ?? _bridgedVerses.firstMatch(text);
    if (digits != null) {
      final number = int.parse(digits.group(1)!);
      return number >= 1 && number <= EpubImport.maxVerse ? number : null;
    }

    // Nothing printed: take the number the id ends with, which is the verse
    // in every scheme going — "V3", "Gen.1.3", "GEN3_16".
    if (text.trim().isNotEmpty) return null;
    final tail = _lastNumber.firstMatch(id);
    if (tail == null) return null;
    final number = int.parse(tail.group(1)!);
    return number >= 1 && number <= EpubImport.maxVerse ? number : null;
  }

  /// Holds a block that belongs above the next chapter's first verse.
  void _hold(Block block) => _pending.add((block: block, chapter: _chapter));

  void _flushPending() {
    if (_pending.isEmpty) return;
    final held = List.of(_pending);
    _pending.clear();
    for (final entry in held) {
      // A block held across a chapter boundary was gathered while a verse
      // of the chapter before was still open, and must not carry that
      // verse into the chapter it opens: it stands above the first verse
      // and belongs to none.
      _add(
        entry.chapter == _chapter ? entry.block : entry.block.withoutVerses(),
      );
    }
  }

  void _add(Block block) {
    final book = _book;
    if (book == null || _chapter == 0) return;
    ((_blocks[book] ??= {})[_chapter] ??= []).add(block);
    _lastStyle = block.style;
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

  /// Enough text that it cannot really be a single verse.
  static bool _isLong(Chapter chapter) {
    var length = 0;
    for (final block in chapter.blocks) {
      for (final segment in block.segments) {
        length += segment.text.length;
      }
      if (length > 200) return true;
    }
    return false;
  }

  List<Book> finish() {
    // Nothing is coming to flush out what is still being held, and a
    // heading or a speaker's label at the end of the last book is no less
    // part of it for being last.
    _flushPending();
    // The chapter last read has not been put away yet.
    _stashChapter();
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
        // A verse the chapter numbered and never gave text to is left out
        // on purpose, the way the critical texts drop Matthew 17:21.
        final withText = <int>{};
        for (final block in blocks) {
          for (final segment in block.segments) {
            if (segment.text.trim().isNotEmpty) withText.add(segment.verse);
          }
        }
        final seen = _seen[entry.key]?[number] ?? const <int>{};
        final chapter = Chapter(
          // Chapters are read by position, so they have to run 1, 2, 3 with
          // no gaps. Where the source skipped one, the shift is reported
          // rather than left for the reader to notice.
          number: chapters.length + 1,
          blocks: blocks,
          notes: _notes[entry.key]?[number] ?? const [],
          labels: _labels[entry.key]?[number] ?? const {},
          omitted: {
            for (final verse in seen)
              if (!withText.contains(verse)) verse,
          },
        );
        if (chapter.verseCount == 0) {
          warn('${meta.name} $number has no numbered verses; left out.');
          continue;
        }
        if (chapter.number != number) {
          warn(
            '${meta.name} $number follows a chapter that was not found, so '
            'it is numbered ${chapter.number} here.',
          );
        }
        if (chapter.verseCount == 1 && _isLong(chapter)) {
          warn(
            '${meta.name} $number came through as one long verse; its verse '
            'numbers were not recognised.',
          );
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
