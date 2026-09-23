import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import '../data/settings.dart';

/// Builds the app's light and dark themes.
///
/// When the platform exposes a Material You palette (Android 12+, and any
/// desktop that reports one) it is used directly; otherwise the user's chosen
/// seed colour is harmonised into a Material 3 scheme so every platform gets
/// the same look.
class AppTheme {
  const AppTheme._();

  static ThemeData build({
    required ColorScheme? dynamicScheme,
    required Settings settings,
    required Brightness brightness,
  }) {
    final scheme = (settings.useDynamicColor && dynamicScheme != null)
        ? dynamicScheme.harmonized()
        : ColorScheme.fromSeed(
            seedColor: settings.seedColor,
            brightness: brightness,
          );

    final base = ThemeData(
      colorScheme: scheme,
      brightness: scheme.brightness,
      useMaterial3: true,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 3,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: scheme.onSecondaryContainer,
        selectedTileColor: scheme.secondaryContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      // In the reader's own colours. Material's default is the inverse
      // surface — near black on a light theme, near white on a dark one —
      // which reads as something that does not belong to the app.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.secondaryContainer,
        contentTextStyle: TextStyle(
          color: scheme.onSecondaryContainer,
          fontSize: 14,
        ),
        actionTextColor: scheme.primary,
        closeIconColor: scheme.onSecondaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// The colour used for the words of Jesus, tuned per brightness so it stays
  /// readable against a Material You surface.
  static Color redLetter(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFFF8A80)
      : const Color(0xFFB3261E);

  /// Names of the highlight colours, in palette order.
  static const List<String> highlightNames = [
    'Yellow',
    'Green',
    'Blue',
    'Pink',
    'Purple',
  ];

  static const List<Color> _highlightHues = [
    Color(0xFFFFD54F),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFFF48FB1),
    Color(0xFFB39DDB),
  ];

  /// Highlight tints, translucent so the text stays readable and the page
  /// colour still shows through in either theme.
  static List<Color> highlights(ColorScheme scheme) {
    final alpha = scheme.brightness == Brightness.dark ? 0.32 : 0.55;
    return [for (final hue in _highlightHues) hue.withValues(alpha: alpha)];
  }

  /// A solid version for swatches and chips.
  static Color highlightSwatch(int index) =>
      _highlightHues[index % _highlightHues.length];
}
