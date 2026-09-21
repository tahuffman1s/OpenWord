import 'package:flutter/material.dart';

/// The face bundled for what the reading face does not cover: the Hebrew
/// block, points and cantillation marks included, and the thirteen modifier
/// letters Strong's transliterates with — ʻayin, ʼaleph, the superscript
/// vowels, the dotted t.
const String scriptureSerif = 'ScriptureSerif';

/// Dresses a style for text that may hold Hebrew or a transliteration.
///
/// A line of Strong's is rarely one alphabet: a headword in Hebrew sits
/// beside how it is said in Latin, and the transliteration itself reaches
/// for marks no reading face carries. Naming both faces, in the order that
/// suits the text at hand, is what keeps such a line whole instead of
/// half of it coming out as empty boxes.
TextStyle? scriptureStyle(TextStyle? style, {required bool hebrew}) {
  if (style == null) return null;
  if (!hebrew) {
    return style.copyWith(fontFamilyFallback: const [scriptureSerif]);
  }
  final reading = style.fontFamily;
  return style.copyWith(
    fontFamily: scriptureSerif,
    fontFamilyFallback: reading == null ? null : [reading],
  );
}
