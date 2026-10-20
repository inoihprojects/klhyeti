import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the app theme from the tokens in [KlhyetiColors].
///
/// Deliberately plain: no elevation tints, no ripples, no filled tonal
/// surfaces. Structure comes from spacing and hairlines.
ThemeData buildKlhyetiTheme(Brightness brightness) {
  final KlhyetiColors c =
      brightness == Brightness.dark ? KlhyetiColors.dark : KlhyetiColors.light;

  final ColorScheme scheme = ColorScheme(
    brightness: brightness,
    primary: c.ink,
    onPrimary: c.bg,
    secondary: c.vermilion,
    onSecondary: c.bg,
    error: c.vermilion,
    onError: c.bg,
    surface: c.surface,
    onSurface: c.ink,
  );

  final TextTheme text = Typography.material2021(
    platform: TargetPlatform.android,
  ).black.apply(bodyColor: c.ink, displayColor: c.ink);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[c],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: c.surfaceAlt.withValues(alpha: 0.6),
    textTheme: text,
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    iconTheme: IconThemeData(color: c.ink2, size: 22),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.bg, fontSize: 14),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sheet),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.bg : c.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? c.ink : c.surfaceAlt,
      ),
      // No outline once on: a line-coloured outline around the ink track
      // drew a bracket-like edge on Windows.
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : c.line,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.ink,
        foregroundColor: c.bg,
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.cell),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.cell),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.ink,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: 14,
      ),
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: c.line),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.cell),
        ),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: c.line),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.cell),
        ),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: c.ink, width: 2),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.cell),
        ),
      ),
      hintStyle: TextStyle(color: c.ink3),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.ink,
      foregroundColor: c.bg,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.fab),
      ),
    ),
  );
}
