import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// The one form Scripture text is stored in.
///
/// Unicode can spell the same word more than one way. "é" is either one
/// codepoint or an "e" with a combining acute after it; Hebrew with two
/// points on a letter can carry them in either order. The forms look
/// identical on screen and are canonically equivalent — and are different
/// bytes, so a search for one will not find the other, and a reader typing
/// what they see on the page gets nothing back.
///
/// So text is composed to NFC as it comes in, and a query is composed the
/// same way before it is used. The text the app ships is already NFC — not
/// one of its 53,251 segments carries a combining mark — but an EPUB from
/// anywhere makes no such promise.
class ScriptureText {
  const ScriptureText._();

  /// Any combining mark. Where a string has none there is nothing for
  /// normalisation to do, which is the common case and worth the check:
  /// composing a whole Bible costs real time, and skipping it costs a scan.
  static final RegExp _combining = RegExp(r'\p{M}', unicode: true);

  /// [text] in NFC.
  static String normalise(String text) =>
      _combining.hasMatch(text) ? unorm.nfc(text) : text;

  /// Whether [text] is already in NFC, for a build-time check.
  static bool isNormalised(String text) =>
      !_combining.hasMatch(text) || unorm.nfc(text) == text;
}
