import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

/// Sends things to the platform's share sheet. A seam, so a test can see
/// what would have been shared without a platform to share it with.
class VerseSharing {
  const VerseSharing._();

  static Future<void> Function(ShareParams params) share = (params) async {
    await SharePlus.instance.share(params);
  };

  /// Saves an image where sharing a file is not possible. Linux has no
  /// share sheet for files, so there the image is saved instead.
  static Future<bool> Function(Uint8List bytes, String fileName) save =
      (bytes, fileName) async {
        final saved = await FilePicker.saveFile(
          dialogTitle: 'Save the image',
          fileName: fileName,
          bytes: bytes,
        );
        return saved != null;
      };

  /// Whether this platform can hand a file to a share sheet.
  static bool get canShareFiles =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.linux;
}

/// How a verse card is coloured.
enum CardStyle {
  paper('Paper'),
  night('Night'),
  colour('Colour'),
  dawn('Dawn');

  const CardStyle(this.label);

  final String label;
}

/// A verse set as a picture: the words, where they are from, and the
/// translation, on a card sized for a phone's share sheet.
///
/// Drawn at a fixed size in logical pixels and captured at three times
/// that, so the image is 1080 × 1350 — the portrait shape social apps show
/// without cropping — whatever size the preview is on screen.
class VerseCard extends StatelessWidget {
  const VerseCard({
    required this.text,
    required this.citation,
    required this.translation,
    required this.style,
    super.key,
  });

  static const Size size = Size(360, 450);
  static const double pixelRatio = 3;

  final String text;
  final String citation;
  final String translation;
  final CardStyle style;

  /// Longer passages are set smaller; past that the words are scaled to
  /// fit rather than cut off.
  static double fontSizeFor(String text) {
    final length = text.length;
    if (length <= 120) return 25;
    if (length <= 240) return 21;
    if (length <= 420) return 17.5;
    if (length <= 650) return 15;
    return 13;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, ink, accent) = switch (style) {
      CardStyle.paper => (
        const BoxDecoration(color: Color(0xFFFBF7EF)),
        const Color(0xFF2A2622),
        const Color(0xFF8A6D3B),
      ),
      CardStyle.night => (
        const BoxDecoration(color: Color(0xFF15181E)),
        const Color(0xFFEDEAE4),
        const Color(0xFFB9C4D6),
      ),
      CardStyle.colour => (
        BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        scheme.onPrimaryContainer,
        scheme.primary,
      ),
      CardStyle.dawn => (
        const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE2C6), Color(0xFFF6B5A4), Color(0xFFB98AB3)],
          ),
        ),
        const Color(0xFF2E1F2B),
        const Color(0xFF5B3452),
      ),
    };
    final body = TextStyle(
      fontFamily: 'Literata',
      fontFamilyFallback: const ['Noto Serif', 'serif'],
      fontSize: fontSizeFor(text),
      height: 1.45,
      color: ink,
    );

    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: background,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '“',
                style: body.copyWith(
                  fontSize: 56,
                  height: 0.8,
                  color: accent.withValues(alpha: 0.55),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: size.width - 64,
                      child: Text(text, style: body),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(width: 36, height: 2, color: accent),
              const SizedBox(height: 10),
              Text(
                citation,
                style: body.copyWith(
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      translation,
                      style: body.copyWith(
                        fontSize: 11.5,
                        height: 1.2,
                        color: ink.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  Text(
                    'OpenWord',
                    style: body.copyWith(
                      fontSize: 10,
                      height: 1.2,
                      letterSpacing: 0.8,
                      color: ink.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the passage as a card, lets the reader pick how it looks, and
/// shares it as an image.
Future<void> showVerseImageSheet(
  BuildContext context, {
  required String text,
  required String citation,
  required String translation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => VerseImageSheet(
      text: text,
      citation: citation,
      translation: translation,
    ),
  );
}

class VerseImageSheet extends StatefulWidget {
  const VerseImageSheet({
    required this.text,
    required this.citation,
    required this.translation,
    super.key,
  });

  final String text;
  final String citation;
  final String translation;

  @override
  State<VerseImageSheet> createState() => _VerseImageSheetState();
}

class _VerseImageSheetState extends State<VerseImageSheet> {
  final GlobalKey _card = GlobalKey();
  CardStyle _style = CardStyle.paper;
  bool _busy = false;

  /// "John_3-16–18.png": a name any file system takes.
  String get _fileName =>
      '${widget.citation.replaceAll(RegExp(r'[:/\\,]+'), '-').replaceAll(' ', '_')}.png';

  /// The card as a PNG, at full resolution.
  Future<Uint8List?> _render() async {
    final boundary =
        _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: VerseCard.pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final bytes = await _render();
      if (bytes == null) return;
      if (VerseSharing.canShareFiles) {
        await VerseSharing.share(
          ShareParams(
            // Named twice: the web reads the file's own name, and the
            // other platforms only the override.
            files: [
              XFile.fromData(bytes, mimeType: 'image/png', name: _fileName),
            ],
            fileNameOverrides: [_fileName],
            subject: widget.citation,
          ),
        );
        navigator.pop();
      } else {
        final saved = await VerseSharing.save(bytes, _fileName);
        navigator.pop();
        if (saved) {
          messenger.showSnackBar(
            SnackBar(content: Text('Saved ${widget.citation} as an image')),
          );
        }
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share the image: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Share ${widget.citation} as an image',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AspectRatio(
                  aspectRatio: VerseCard.size.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FittedBox(
                      child: RepaintBoundary(
                        key: _card,
                        child: VerseCard(
                          text: widget.text,
                          citation: widget.citation,
                          translation: widget.translation,
                          style: _style,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final style in CardStyle.values)
                  ChoiceChip(
                    label: Text(style.label),
                    selected: _style == style,
                    onSelected: (_) => setState(() => _style = style),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _share,
              icon: Icon(
                VerseSharing.canShareFiles
                    ? Icons.ios_share_rounded
                    : Icons.save_alt_rounded,
              ),
              label: Text(
                VerseSharing.canShareFiles ? 'Share image' : 'Save image',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
