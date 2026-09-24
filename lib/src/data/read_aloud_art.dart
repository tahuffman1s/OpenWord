import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../model/bible.dart';

/// The colours a chapter's cover is drawn in: the reader's own theme.
@immutable
class ArtColours {
  const ArtColours({
    required this.from,
    required this.to,
    required this.ink,
    required this.accent,
  });

  final Color from;
  final Color to;
  final Color ink;
  final Color accent;

  String get key =>
      [from, to, ink, accent].map((c) => c.toARGB32().toRadixString(16)).join();
}

/// A square cover for a chapter, drawn on the device: the book's name and
/// the chapter's number on the theme's colours. What the lock screen, a
/// car or a watch shows beside what is being read. Nothing is downloaded.
Future<Uint8List> renderChapterArt({
  required String book,
  required String chapter,
  required ArtColours colours,
  double size = 600,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bounds = Rect.fromLTWH(0, 0, size, size);
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(size, size), [
        colours.from,
        colours.to,
      ]),
  );

  final margin = size * 0.09;
  final width = size - margin * 2;
  ui.Paragraph line(
    String text,
    double fontSize,
    Color colour,
    FontWeight weight,
  ) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: 'Literata',
              fontSize: fontSize,
              height: 1.05,
              maxLines: 2,
              ellipsis: '…',
            ),
          )
          ..pushStyle(ui.TextStyle(color: colour, fontWeight: weight))
          ..addText(text);
    return builder.build()..layout(ui.ParagraphConstraints(width: width));
  }

  final number = line(chapter, size * 0.42, colours.accent, FontWeight.w600);
  final name = line(book, size * 0.1, colours.ink, FontWeight.w600);
  final mark = line(
    'OpenWord',
    size * 0.045,
    colours.ink.withValues(alpha: 0.6),
    FontWeight.w400,
  );

  final bottom = size - margin;
  canvas.drawParagraph(mark, Offset(margin, bottom - mark.height));
  final nameTop = bottom - mark.height - size * 0.03 - name.height;
  canvas.drawParagraph(name, Offset(margin, nameTop));
  canvas.drawParagraph(number, Offset(margin, nameTop - number.height));

  final image = await recorder.endRecording().toImage(
    size.round(),
    size.round(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// A chapter's cover as a file, drawn the first time it is wanted and kept
/// in the app's cache after that. The media session wants a file it can
/// hand to the system, not bytes.
///
/// Null on the web, where there are no files to hand over, and wherever it
/// cannot be drawn or written: the lock screen then simply has no picture.
Future<Uri?> chapterArtFile(
  Reference chapter, {
  required ArtColours colours,
}) async {
  if (kIsWeb) return null;
  try {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/read_aloud_art',
    );
    final file = File(
      '${directory.path}/${chapter.bookCode}-${chapter.chapter}-${colours.key}.png',
    );
    if (!file.existsSync()) {
      directory.createSync(recursive: true);
      final bytes = await renderChapterArt(
        book: chapter.bookCode == 'PSA' ? 'Psalm' : chapter.bookName,
        chapter: '${chapter.chapter}',
        colours: colours,
      );
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.uri;
  } on Object catch (error) {
    debugPrint('OpenWord: no cover for ${chapter.label}: $error');
    return null;
  }
}
