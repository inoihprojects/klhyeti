import 'package:flutter/material.dart';

/// Design tokens: raw hex values live here and nowhere else.
@immutable
class KlhyetiColors extends ThemeExtension<KlhyetiColors> {
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color line;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color vermilion;
  final Color indigo;

  const KlhyetiColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.vermilion,
    required this.indigo,
  });

  static const KlhyetiColors light = KlhyetiColors(
    bg: Color(0xFFF4F1EA),
    surface: Color(0xFFFBF9F5),
    surfaceAlt: Color(0xFFEDE8DE),
    line: Color(0xFFDCD5C8),
    ink: Color(0xFF23211D),
    ink2: Color(0xFF5A554C),
    ink3: Color(0xFF8C857A),
    vermilion: Color(0xFFA8503F),
    indigo: Color(0xFF3F6A8C),
  );

  static const KlhyetiColors dark = KlhyetiColors(
    bg: Color(0xFF1A1917),
    surface: Color(0xFF211F1D),
    surfaceAlt: Color(0xFF2A2724),
    line: Color(0xFF34302B),
    ink: Color(0xFFEDE8DE),
    ink2: Color(0xFFB3ABA0),
    ink3: Color(0xFF7C766C),
    vermilion: Color(0xFFC9705B),
    indigo: Color(0xFF7FA3C7),
  );

  @override
  KlhyetiColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? line,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? vermilion,
    Color? indigo,
  }) {
    return KlhyetiColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      vermilion: vermilion ?? this.vermilion,
      indigo: indigo ?? this.indigo,
    );
  }

  @override
  KlhyetiColors lerp(ThemeExtension<KlhyetiColors>? other, double t) {
    if (other is! KlhyetiColors) return this;
    return KlhyetiColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      line: Color.lerp(line, other.line, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      vermilion: Color.lerp(vermilion, other.vermilion, t)!,
      indigo: Color.lerp(indigo, other.indigo, t)!,
    );
  }
}

extension KlhyetiThemeX on BuildContext {
  KlhyetiColors get c => Theme.of(this).extension<KlhyetiColors>()!;
}

/// 4dp base unit.
abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class Radii {
  static const double cell = 10;
  static const double sheet = 14;
  static const double fab = 20;
}

abstract final class Motion {
  static const Duration press = Duration(milliseconds: 90);
  static const Duration month = Duration(milliseconds: 160);

  /// Arrows, Today and the year view scrolling the continuous grid.
  static const Duration monthScroll = Duration(milliseconds: 300);

  /// The event sheet's resting height changing with the selected day.
  /// (Dragging and flicking it use a spring instead; see EventSheet.)
  static const Duration sheet = Duration(milliseconds: 180);
  static const Duration view = Duration(milliseconds: 280);
  static const Duration theme = Duration(milliseconds: 200);

  /// Honours the OS "reduce motion" setting: everything becomes instant.
  ///
  /// Depends on that one setting only. MediaQuery.of would make every
  /// caller (each day cell among them) rebuild whenever anything about the
  /// screen changes, which includes every frame of the keyboard sliding.
  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}

/// Digits that don't change width as the numbers change.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

const List<String> monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Indexed by DateTime.weekday - 1 (Monday == 1).
const List<String> weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
