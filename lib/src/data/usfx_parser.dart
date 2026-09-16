import 'package:xml/xml_events.dart';

import '../model/bible.dart';
import '../model/book_meta.dart';

/// Converts a USFX (Unified Scripture Format XML) document into a [Bible].
///
/// USFX is the XML flavour of USFM published by eBible.org. It keeps the
/// typesetting structure of the translation — paragraph breaks, poetry indent
/// levels, psalm titles, section headings, words of Jesus and footnotes — which
/// is what lets the reader lay verses out the way a printed Bible does instead
/// of as a flat list of numbered lines.
///
/// The parser is event based so that a 6 MB file can be processed without
/// building a full DOM, which matters on phones.
class UsfxParser {
  UsfxParser(this.translation);

  final TranslationInfo translation;

  /// Block-level elements: each one starts a new [Block].
  static const Set<String> _blockTags = {
    'p',
    'q',
    'd',
    'b',
    'cl',
    'ms',
    'mt',
    's',
    'sp',
    'li',
    'pi',
    'mi',
    'm',
    'nb',
    'pc',
    'ph',
    'qa',
    'qm',
    'qr',
    'qc',
    'tr',
    'cd',
    'lh',
    'lf',
    'lim',
    'iex',
    'lit',
    'mte',
    'periph',
  };

  /// Elements whose text is metadata rather than Scripture.
  static const Set<String> _metaTags = {
    'id',
    'ide',
    'toc',
    'toca',
    'h',
    'rem',
    'sts',
    'vp',
    'cp',
    'ca',
    'va',
    'fig',
    'usfm',
    'languageCode',
    'generated',
    'wtp',
    'milestone',
  };

  /// Parts of a footnote that repeat information the reader already has.
  static const Set<String> _noteMetaTags = {'fr', 'xo', 'fv', 'fdc'};

  /// Character styles rendered in italics.
  static const Set<String> _italicTags = {
    'add',
    'it',
    'bk',
    'tl',
    'sls',
    'em',
    'qt',
    'k',
    'ord',
    'pn',
    'addpn',
  };

  final List<Book> _books = [];

  BookMeta? _bookMeta;
  List<Chapter> _chapters = [];

  int _chapterNumber = 0;
  List<Block> _blocks = [];
  List<String> _notes = [];

  bool _blockOpen = false;
  String _blockStyle = 'p';
  int _blockIndent = 0;
  List<VerseSegment> _segments = [];
  final StringBuffer _text = StringBuffer();

  int _verse = 0;
  bool _pendingVerseStart = false;

  int _suppress = 0;
  StringBuffer? _note;
  int _noteSuppress = 0;

  final List<_Frame> _stack = [];

  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _leadingDigits = RegExp(r'\d+');
  static final RegExp _repeatedSpaces = RegExp(' {2,}');

  /// Parses [xml] into a [Bible]. Books that are not part of the canon table
  /// (front matter, glossaries, concordances) are skipped.
  static Bible parse(String xml, TranslationInfo translation) =>
      UsfxParser(translation)._run(xml);

  Bible _run(String xml) {
    for (final event in parseEvents(xml)) {
      switch (event) {
        case XmlStartElementEvent():
          _onStart(event);
        case XmlEndElementEvent():
          _onEnd(event.name);
        case XmlTextEvent():
          _onText(event.value);
        case XmlCDATAEvent():
          _onText(event.value);
        default:
          break;
      }
    }
    _finishBook();
    return Bible(translation: translation, books: _books);
  }

  void _onStart(XmlStartElementEvent event) {
    final name = event.name;
    final frame = _Frame(name);

    if (name == 'book') {
      _finishBook();
      _bookMeta = BookMeta.lookup(_attr(event, 'id') ?? '');
      _chapters = [];
      _chapterNumber = 0;
      if (!event.isSelfClosing) _stack.add(frame);
      return;
    }

    // Everything outside a recognised book is front/back matter.
    if (_bookMeta == null) {
      if (!event.isSelfClosing) _stack.add(frame);
      return;
    }

    switch (name) {
      case 'c':
        _finishChapter();
        _chapterNumber = _intAttr(event, 'id') ?? _chapterNumber + 1;
        _blocks = [];
        _notes = [];
        _verse = 0;
        _pendingVerseStart = false;
      case 'v':
        _flushSegment();
        _verse = _intAttr(event, 'id') ?? _verse + 1;
        _pendingVerseStart = true;
        if (!_blockOpen) _openBlock('p', 0);
      case 've':
        _flushSegment();
      case 'f' || 'x' || 'ef' || 'ex':
        _note = StringBuffer();
        frame.closesNote = true;
      default:
        if (_metaTags.contains(name)) {
          _suppress++;
          frame.suppressed = true;
        } else if (_note != null && _noteMetaTags.contains(name)) {
          _noteSuppress++;
          frame.noteSuppressed = true;
        } else if (_blockTags.contains(name)) {
          final kind = _classify(name, _attr(event, 'sfm'));
          if (kind == null) {
            // Introductions and book titles are not read in the reader.
            _flushBlock();
            _suppress++;
            frame.suppressed = true;
          } else if (kind == 'b') {
            _flushBlock();
            _blocks.add(const Block(style: BlockStyle.blank));
          } else {
            _openBlock(kind, _indentFor(name, _attr(event, 'sfm'), event));
            frame.closesBlock = true;
          }
        } else if (name == 'wj') {
          _write(Markup.wjStart);
          frame.inlineEnd = Markup.wjEnd;
        } else if (name == 'qs') {
          _write(Markup.selahStart);
          frame.inlineEnd = Markup.selahEnd;
        } else if (_italicTags.contains(name)) {
          _write(Markup.addStart);
          frame.inlineEnd = Markup.addEnd;
        } else if (name == 'th' ||
            name == 'thr' ||
            name == 'tc' ||
            name == 'tcr') {
          _write('   ');
        }
    }

    if (event.isSelfClosing) {
      _unwind(frame);
    } else {
      _stack.add(frame);
    }
  }

  void _onEnd(String name) {
    // Find the matching frame; malformed nesting simply unwinds to it.
    var index = _stack.lastIndexWhere((frame) => frame.name == name);
    if (index < 0) return;
    while (_stack.length > index) {
      _unwind(_stack.removeLast());
    }
    if (name == 'book') _finishBook();
  }

  void _unwind(_Frame frame) {
    if (frame.suppressed) _suppress--;
    if (frame.noteSuppressed) _noteSuppress--;
    if (frame.inlineEnd != null) _write(frame.inlineEnd!);
    if (frame.closesNote) _closeNote();
    if (frame.closesBlock) _flushBlock();
  }

  void _onText(String value) {
    if (_bookMeta == null || value.isEmpty) return;
    final text = value.replaceAll(_whitespace, ' ');
    if (text.trim().isEmpty && _text.isEmpty) return;
    if (_note != null) {
      if (_noteSuppress == 0) _note!.write(text);
      return;
    }
    if (_suppress > 0) return;
    if (!_blockOpen) return;
    _text.write(text);
  }

  void _write(String marker) {
    if (_note != null) return;
    if (_suppress > 0 || !_blockOpen) return;
    _text.write(marker);
  }

  void _closeNote() {
    final note = _note;
    _note = null;
    if (note == null) return;
    final body = note.toString().replaceAll(_whitespace, ' ').trim();
    if (body.isEmpty) return;
    _notes.add(body);
    _write('${Markup.noteStart}${_notes.length - 1}${Markup.noteEnd}');
  }

  void _openBlock(String style, int indent) {
    _flushBlock();
    _blockStyle = style;
    _blockIndent = indent;
    _segments = [];
    _text.clear();
    _blockOpen = true;
  }

  void _flushSegment() {
    if (!_blockOpen) return;
    final text = _text.toString().replaceAll(_repeatedSpaces, ' ').trim();
    _text.clear();
    if (text.isEmpty) return;
    _segments.add(
      VerseSegment(verse: _verse, startsVerse: _pendingVerseStart, text: text),
    );
    _pendingVerseStart = false;
  }

  void _flushBlock() {
    if (!_blockOpen) return;
    _flushSegment();
    if (_segments.isNotEmpty) {
      _blocks.add(
        Block(
          style: BlockStyle.fromKey(_blockStyle),
          indent: _blockIndent,
          segments: List.unmodifiable(_segments),
        ),
      );
    }
    _blockOpen = false;
    _segments = [];
    _text.clear();
  }

  void _finishChapter() {
    _flushBlock();
    if (_chapterNumber == 0) return;
    // Trailing blank lines add nothing to the layout.
    while (_blocks.isNotEmpty && _blocks.last.style == BlockStyle.blank) {
      _blocks.removeLast();
    }
    if (_blocks.isEmpty) return;
    _chapters.add(
      Chapter(
        number: _chapterNumber,
        blocks: List.unmodifiable(_blocks),
        notes: List.unmodifiable(_notes),
      ),
    );
    _blocks = [];
    _notes = [];
    _chapterNumber = 0;
  }

  void _finishBook() {
    _finishChapter();
    final meta = _bookMeta;
    _bookMeta = null;
    if (meta == null || _chapters.isEmpty) {
      _chapters = [];
      return;
    }
    _chapters.sort((a, b) => a.number.compareTo(b.number));
    _books.add(Book(meta: meta, chapters: List.unmodifiable(_chapters)));
    _chapters = [];
  }

  /// Maps an element name plus its `sfm` attribute to a [BlockStyle] key, or
  /// null when the block should be dropped (introductions, book titles).
  static String? _classify(String name, String? sfm) {
    final marker = (sfm == null || sfm.isEmpty) ? name : sfm;
    if (marker == 'b') return 'b';
    if (marker == 'd') return 'd';
    if (marker.startsWith('mt') || marker == 'lit' || marker == 'iex') {
      return null;
    }
    // Introduction markers (\ip, \is, \iot, \io1, \imt ...) — but not \it,
    // which is a character style handled elsewhere.
    if (marker.length > 1 && marker.startsWith('i') && marker != 'it') {
      return null;
    }
    if (marker == 'cl' || marker == 'cp') return null;
    // Parallel-passage references are set apart from the heading above them.
    if (marker == 'r' || marker == 'mr' || marker == 'sr') return 'r';
    if (marker.startsWith('ms') ||
        marker.startsWith('s') && marker != 'sp' ||
        marker == 'qa' ||
        marker == 'cd') {
      return 'h';
    }
    if (marker.startsWith('q')) return 'q';
    return 'p';
  }

  static int _indentFor(String name, String? sfm, XmlStartElementEvent event) {
    final level = _intAttr(event, 'level');
    final marker = (sfm == null || sfm.isEmpty) ? name : sfm;
    if (level != null && level > 0) return level;
    final trailing = _leadingDigits.firstMatch(marker);
    if (trailing != null) return int.parse(trailing.group(0)!);
    if (marker.startsWith('q')) return 1;
    if (marker == 'pi' || marker == 'li' || marker == 'mi' || marker == 'lim') {
      return 1;
    }
    return 0;
  }

  static String? _attr(XmlStartElementEvent event, String name) {
    for (final attribute in event.attributes) {
      if (attribute.name == name) return attribute.value;
    }
    return null;
  }

  static int? _intAttr(XmlStartElementEvent event, String name) {
    final raw = _attr(event, name);
    if (raw == null) return null;
    final match = _leadingDigits.firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(0)!);
  }
}

/// Bookkeeping for one open XML element.
class _Frame {
  _Frame(this.name);

  final String name;
  bool suppressed = false;
  bool noteSuppressed = false;
  bool closesBlock = false;
  bool closesNote = false;
  String? inlineEnd;
}
