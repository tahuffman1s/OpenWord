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
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
    );
  }

  /// The colour used for the words of Jesus, tuned per brightness so it stays
  /// readable against a Material You surface.
  static Color redLetter(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFFF8A80)
      : const Color(0xFFB3261E);

  /// Highlight tints for bookmarks, in palette order.
  static List<Color> highlights(ColorScheme scheme) => [
    scheme.primaryContainer,
    scheme.tertiaryContainer,
    scheme.secondaryContainer,
  ];
}
