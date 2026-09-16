import 'package:flutter/material.dart';

/// Renders the small slice of Markdown the bundled book introductions use:
/// headings (both `## atx` and the underlined kind), paragraphs, bullet and
/// numbered lists, bold, italic and backslash escapes. There are no links,
/// images, tables or HTML in the source, so none are handled — a full
/// Markdown package would be a dependency earning its keep on nothing.
class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown({required this.source, this.baseStyle, super.key});

  final String source;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = baseStyle ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final children = <Widget>[];

    for (final block in _parse(source)) {
      switch (block.kind) {
        case _BlockKind.heading:
          // The style is handed to the spans as well as the widget: the spans
          // carry their own style, which would otherwise win.
          final heading =
              (block.level <= 1
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.titleSmall)
                  ?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ) ??
              body;
          children.add(
            Padding(
              padding: EdgeInsets.only(
                top: children.isEmpty ? 0 : (block.level <= 1 ? 22 : 16),
                bottom: 6,
              ),
              child: Text.rich(_inline(block.text, heading), style: heading),
            ),
          );
        case _BlockKind.paragraph:
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text.rich(_inline(block.text, body), style: body),
            ),
          );
        case _BlockKind.bullet:
        case _BlockKind.numbered:
          children.add(
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      block.kind == _BlockKind.bullet
                          ? '•'
                          : '${block.marker}.',
                      style: body.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(_inline(block.text, body), style: body),
                  ),
                ],
              ),
            ),
          );
        case _BlockKind.rule:
          children.add(
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
          );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// Splits the source into blocks. Runs of text become one paragraph, a line
  /// of `=` or `-` under text turns it into a heading.
  static List<_Block> _parse(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_Block>[];
    final paragraph = <String>[];

    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(_Block(_BlockKind.paragraph, paragraph.join(' ').trim()));
      paragraph.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flush();
        continue;
      }

      // An underline turns the paragraph above it into a heading.
      if (RegExp(r'^=+$').hasMatch(trimmed) && paragraph.isNotEmpty) {
        blocks.add(
          _Block(_BlockKind.heading, paragraph.join(' ').trim(), level: 1),
        );
        paragraph.clear();
        continue;
      }
      if (RegExp(r'^-{2,}$').hasMatch(trimmed)) {
        if (paragraph.isNotEmpty) {
          blocks.add(
            _Block(_BlockKind.heading, paragraph.join(' ').trim(), level: 2),
          );
          paragraph.clear();
        } else {
          blocks.add(const _Block(_BlockKind.rule, ''));
        }
        continue;
      }

      final atx = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (atx != null) {
        flush();
        blocks.add(
          _Block(
            _BlockKind.heading,
            atx.group(2)!.trim(),
            level: atx.group(1)!.length,
          ),
        );
        continue;
      }

      final bullet = RegExp(r'^[*\-+]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        flush();
        blocks.add(_Block(_BlockKind.bullet, bullet.group(1)!.trim()));
        continue;
      }

      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
      if (numbered != null) {
        flush();
        blocks.add(
          _Block(
            _BlockKind.numbered,
            numbered.group(2)!.trim(),
            marker: numbered.group(1),
          ),
        );
        continue;
      }

      paragraph.add(trimmed);
    }
    flush();
    return blocks;
  }

  /// Handles `**bold**`, `*italic*` and backslash escapes.
  static TextSpan _inline(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var bold = false;
    var italic = false;

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: base.copyWith(
            fontWeight: bold ? FontWeight.w700 : null,
            fontStyle: italic ? FontStyle.italic : null,
          ),
        ),
      );
      buffer.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == r'\' && i + 1 < text.length) {
        buffer.write(text[i + 1]);
        i++;
        continue;
      }
      if (char == '*') {
        final double = i + 1 < text.length && text[i + 1] == '*';
        flush();
        if (double) {
          bold = !bold;
          i++;
        } else {
          italic = !italic;
        }
        continue;
      }
      buffer.write(char);
    }
    flush();
    return TextSpan(children: spans);
  }
}

enum _BlockKind { heading, paragraph, bullet, numbered, rule }

class _Block {
  const _Block(this.kind, this.text, {this.level = 1, this.marker});

  final _BlockKind kind;
  final String text;
  final int level;
  final String? marker;
}
