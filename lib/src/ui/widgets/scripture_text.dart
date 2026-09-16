import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/reference_search.dart';
import '../../data/settings.dart';
import '../../model/bible.dart';
import '../theme.dart';

/// Resolved text styles for one chapter of Scripture.
@immutable
class ScriptureStyle {
  const ScriptureStyle({
    required this.body,
    required this.verseNumber,
    required this.heading,
    required this.title,
    required this.reference,
    required this.wjColor,
    required this.noteColor,
    required this.redLetter,
    required this.showFootnotes,
    required this.showVerseNumbers,
    required this.paragraphLayout,
  });

  factory ScriptureStyle.of(BuildContext context, Settings settings) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = settings.fontScale;
    final family = settings.readingFont.family;

    final body = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: family,
      // Hebrew and Greek appear in a handful of footnotes; let the platform
      // supply those glyphs where the bundled subset has none.
      fontFamilyFallback: const ['Noto Serif', 'serif'],
      fontSize: 17.5 * scale,
      height: settings.lineHeight,
      color: scheme.onSurface,
    );

    return ScriptureStyle(
      body: body,
      verseNumber: body.copyWith(
        fontSize: body.fontSize! * 0.62,
        height: 1,
        fontFeatures: const [],
        fontWeight: FontWeight.w700,
        color: scheme.primary,
      ),
      heading: body.copyWith(
        fontSize: body.fontSize! * 0.92,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: scheme.primary,
      ),
      title: body.copyWith(
        fontSize: body.fontSize! * 0.9,
        fontStyle: FontStyle.italic,
        color: scheme.onSurfaceVariant,
      ),
      reference: body.copyWith(
        fontSize: body.fontSize! * 0.8,
        fontStyle: FontStyle.italic,
        color: scheme.onSurfaceVariant,
      ),
      wjColor: AppTheme.redLetter(scheme),
      noteColor: scheme.tertiary,
      redLetter: settings.redLetter,
      showFootnotes: settings.showFootnotes,
      showVerseNumbers: settings.showVerseNumbers,
      paragraphLayout: settings.paragraphLayout,
    );
  }

  final TextStyle body;
  final TextStyle verseNumber;
  final TextStyle heading;
  final TextStyle title;
  final TextStyle reference;
  final Color wjColor;
  final Color noteColor;
  final bool redLetter;
  final bool showFootnotes;
  final bool showVerseNumbers;
  final bool paragraphLayout;

  double get blankHeight => (body.fontSize ?? 17) * 0.7;
}

/// Lays out a single [Block] — a prose paragraph, a poetry line, a heading or
/// a stanza break — with verse numbers set as superscripts.
class ScriptureBlock extends StatefulWidget {
  const ScriptureBlock({
    required this.block,
    required this.style,
    required this.onVerseTap,
    required this.onNoteTap,
    required this.highlights,
    required this.flagged,
    required this.isFirst,
    this.matcher,
    this.onReferenceTap,
    super.key,
  });

  final Block block;
  final ScriptureStyle style;

  /// Called when any part of a verse is tapped.
  final ValueChanged<int> onVerseTap;

  /// Called with the chapter-level note index behind a footnote marker.
  final ValueChanged<int> onNoteTap;

  /// Background tints for highlighted verses.
  final Map<int, Color> highlights;

  /// Verses carrying a bookmark or a note, flagged in the margin.
  final Set<int> flagged;

  /// True for the first paragraph of a chapter or section: a paragraph that
  /// opens a passage is set flush, as a printed Bible does.
  final bool isFirst;

  /// Finds citations in parallel-passage lines so they can be tapped.
  final ReferenceMatcher? matcher;

  final ValueChanged<Reference>? onReferenceTap;

  @override
  State<ScriptureBlock> createState() => _ScriptureBlockState();
}

class _ScriptureBlockState extends State<ScriptureBlock> {
  final Map<int, TapGestureRecognizer> _recognizers = {};

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizerFor(int verse) =>
      _recognizers.putIfAbsent(verse, () {
        return TapGestureRecognizer()..onTap = () => widget.onVerseTap(verse);
      });

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final block = widget.block;

    switch (block.style) {
      case BlockStyle.blank:
        return SizedBox(height: style.blankHeight);
      case BlockStyle.heading:
        return Padding(
          padding: EdgeInsets.only(top: style.blankHeight * 1.6, bottom: 6),
          child: Text(_plain(block), style: style.heading),
        );
      case BlockStyle.descriptiveTitle:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(_plain(block), style: style.title),
        );
      case BlockStyle.reference:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: LinkedText(
            text: _plain(block),
            style: style.reference,
            matcher: widget.matcher,
            onTap: widget.onReferenceTap,
          ),
        );
      case BlockStyle.poetry:
        return _poetryLine();
      case BlockStyle.paragraph:
        return Padding(
          padding: EdgeInsets.only(
            left: block.indent.clamp(0, 4) * 16.0,
            bottom: 10,
          ),
          child: _richText(
            indentFirstLine:
                style.paragraphLayout &&
                block.indentFirstLine &&
                !widget.isFirst,
          ),
        );
    }
  }

  static String _plain(Block block) =>
      block.segments.map((s) => Markup.strip(s.text)).join(' ').trim();

  /// A line of verse. The verse number hangs in the margin so that a line too
  /// long for the screen wraps back to the line's own indent, the way a
  /// printed Bible sets poetry.
  Widget _poetryLine() {
    final style = widget.style;
    final block = widget.block;
    final first = block.segments.first;
    final hanging =
        first.startsVerse && first.verse > 0 && style.showVerseNumbers;
    final fontSize = style.body.fontSize ?? 17;
    final gutter = hanging ? fontSize * 1.5 : 0.0;

    return Padding(
      padding: EdgeInsets.only(
        left: 8.0 + (block.indent.clamp(1, 4) - 1) * 18.0,
        bottom: 2,
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(left: gutter),
            child: _richText(indentFirstLine: false, skipFirstNumber: hanging),
          ),
          if (hanging)
            Positioned(
              left: 0,
              // Sit on the first line, allowing for its half-leading.
              top: fontSize * ((style.body.height ?? 1.4) - 1) / 2,
              child: GestureDetector(
                onTap: () => widget.onVerseTap(first.verse),
                child: Text('${first.verse}', style: style.verseNumber),
              ),
            ),
        ],
      ),
    );
  }

  Widget _richText({
    required bool indentFirstLine,
    bool skipFirstNumber = false,
  }) {
    final style = widget.style;
    final spans = <InlineSpan>[];
    if (indentFirstLine) {
      spans.add(
        WidgetSpan(child: SizedBox(width: (style.body.fontSize ?? 17) * 1.1)),
      );
    }

    for (var i = 0; i < widget.block.segments.length; i++) {
      if (i > 0) {
        // Paragraph layout flows verses together; the alternative puts each
        // verse on its own line.
        spans.add(TextSpan(text: style.paragraphLayout ? ' ' : '\n'));
      }
      spans.addAll(
        _segmentSpans(
          widget.block.segments[i],
          includeNumber: !(i == 0 && skipFirstNumber),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style.body,
      textWidthBasis: TextWidthBasis.parent,
    );
  }

  List<InlineSpan> _segmentSpans(
    VerseSegment segment, {
    bool includeNumber = true,
  }) {
    final style = widget.style;
    final spans = <InlineSpan>[];
    final highlight = widget.highlights[segment.verse];
    final recognizer = segment.verse > 0 ? _recognizerFor(segment.verse) : null;

    if (segment.startsVerse && widget.flagged.contains(segment.verse)) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: Padding(
            padding: const EdgeInsets.only(right: 1),
            child: Icon(
              Icons.bookmark_rounded,
              size: (style.body.fontSize ?? 17) * 0.5,
              color: style.verseNumber.color,
            ),
          ),
        ),
      );
    }

    if (includeNumber &&
        segment.startsVerse &&
        segment.verse > 0 &&
        style.showVerseNumbers) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: GestureDetector(
            onTap: () => widget.onVerseTap(segment.verse),
            child: Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Text('${segment.verse}', style: style.verseNumber),
            ),
          ),
        ),
      );
    }

    var inWords = false;
    var inAdded = false;
    var inSelah = false;
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        TextSpan(
          text: buffer.toString(),
          recognizer: recognizer,
          style: style.body.copyWith(
            color: inWords && style.redLetter ? style.wjColor : null,
            fontStyle: inAdded || inSelah ? FontStyle.italic : FontStyle.normal,
            backgroundColor: highlight,
          ),
        ),
      );
      buffer.clear();
    }

    final text = segment.text;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      switch (char) {
        case Markup.wjStart:
          flush();
          inWords = true;
        case Markup.wjEnd:
          flush();
          inWords = false;
        case Markup.addStart:
          flush();
          inAdded = true;
        case Markup.addEnd:
          flush();
          inAdded = false;
        case Markup.selahStart:
          flush();
          inSelah = true;
        case Markup.selahEnd:
          flush();
          inSelah = false;
        case Markup.noteStart:
          flush();
          final end = text.indexOf(Markup.noteEnd, i + 1);
          if (end < 0) break;
          final index = int.tryParse(text.substring(i + 1, end));
          i = end;
          if (index != null && style.showFootnotes) {
            spans.add(_noteSpan(index));
          }
        default:
          buffer.write(char);
      }
    }
    flush();
    return spans;
  }

  InlineSpan _noteSpan(int index) {
    final style = widget.style;
    return WidgetSpan(
      alignment: PlaceholderAlignment.top,
      child: GestureDetector(
        onTap: () => widget.onNoteTap(index),
        child: Padding(
          padding: const EdgeInsets.only(right: 1),
          child: Icon(
            Icons.circle,
            size: (style.body.fontSize ?? 17) * 0.3,
            color: style.noteColor,
          ),
        ),
      ),
    );
  }
}

/// Prose with any Scripture citations in it turned into links.
///
/// Used for parallel-passage lines and footnotes, where a translation cites
/// other passages in plain text.
class LinkedText extends StatefulWidget {
  const LinkedText({
    required this.text,
    required this.style,
    this.matcher,
    this.onTap,
    super.key,
  });

  final String text;
  final TextStyle style;
  final ReferenceMatcher? matcher;
  final ValueChanged<Reference>? onTap;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final matcher = widget.matcher;
    final onTap = widget.onTap;
    _disposeRecognizers();

    if (matcher == null || onTap == null) {
      return Text(widget.text, style: widget.style);
    }
    final matches = matcher.findAll(widget.text);
    if (matches.isEmpty) return Text(widget.text, style: widget.style);

    final linkStyle = widget.style.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary
          .withValues(alpha: 0.4),
    );

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => onTap(match.reference);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: widget.text.substring(match.start, match.end),
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
