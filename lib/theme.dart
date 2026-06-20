import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Faithful rekordbox palette: pure-black content surfaces, dark-gray
/// toolbars/headers, a flat medium-blue accent, and a plain neutral sans.
abstract class Rb {
  static const bg = Color(0xFF0A0A0A); // content / track list (near black)
  static const panel = Color(0xFF141414); // device panels
  static const panelHigh = Color(0xFF1C1C1C); // toolbars
  static const header = Color(0xFF262626); // column-header bar
  static const rowHover = Color(0xFF1B1B1B);
  static const selected = Color(0xFF21527F); // blue selected row
  static const border = Color(0xFF2B2B2B);
  static const borderSoft = Color(0xFF181818);

  static const accent = Color(0xFF2D7AD4); // rekordbox flat blue (buttons/active)
  static const accentBorder = Color(0xFF2E6FB5);
  static const green = Color(0xFF3FB46B);
  static const amber = Color(0xFFE0912F);
  static const red = Color(0xFFD8474C);

  static const text = Color(0xFFE6E6E6);
  static const textDim = Color(0xFF9A9A9A);
  static const textFaint = Color(0xFF6A6A6A);

  /// Neutral UI sans — what rekordbox-style browsers actually use.
  static TextStyle ui(
          {double size = 12.5,
          FontWeight weight = FontWeight.w400,
          Color color = text,
          double spacing = 0}) =>
      GoogleFonts.notoSans(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: spacing);

  /// Same face, tabular figures — for numeric / technical readouts.
  static TextStyle mono(
          {double size = 12.5,
          FontWeight weight = FontWeight.w400,
          Color color = textDim}) =>
      GoogleFonts.notoSans(
          fontSize: size,
          fontWeight: weight,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()]);

  /// Small uppercase tag / button label — modest spacing, not airy.
  static TextStyle label(Color color, {double size = 11}) =>
      GoogleFonts.notoSans(
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.4);
}

ThemeData rekordboxTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Rb.bg,
    colorScheme: const ColorScheme.dark(
      surface: Rb.panel,
      primary: Rb.accent,
      onPrimary: Colors.white,
      secondary: Rb.accent,
      error: Rb.red,
      onSurface: Rb.text,
    ),
    textTheme: GoogleFonts.notoSansTextTheme(base.textTheme)
        .apply(bodyColor: Rb.text, displayColor: Rb.text),
    dividerColor: Rb.border,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Rb.panelHigh,
      contentTextStyle: Rb.ui(color: Rb.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: const BorderSide(color: Rb.border)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Rb.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: Rb.label(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Rb.text,
        backgroundColor: Rb.panelHigh,
        side: const BorderSide(color: Rb.border),
        textStyle: Rb.label(Rb.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    ),
  );
}
