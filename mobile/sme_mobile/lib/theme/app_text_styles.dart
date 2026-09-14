import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// The typographic scale for the whole app.
///
/// Plus Jakarta Sans — a rounded geometric sans that keeps the neon theme from
/// reading as clinical. Every style is built through [GoogleFonts] so the
/// weights stay consistent; nothing should construct a bare [TextStyle] with a
/// font size in a screen file.
class AppTextStyles {
  const AppTextStyles._();

  /// One place to swap the family if the brand font ever changes.
  static TextStyle _base(TextStyle style) => GoogleFonts.plusJakartaSans(textStyle: style);

  /// Applies the family to a whole [TextTheme] at once, for [ThemeData].
  static TextTheme textTheme(TextTheme base) =>
      GoogleFonts.plusJakartaSansTextTheme(base).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      );

  /// Screen titles and hero headlines.
  static TextStyle get headline => _base(const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.2,
      ));

  /// The smaller headline, for screens whose title sits above content rather
  /// than in an app bar.
  static TextStyle get headlineSmall => _base(const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.25,
      ));

  /// Card headings and app-bar titles.
  static TextStyle get title => _base(const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ));

  /// List-row titles and other inline emphasis.
  static TextStyle get subtitle => _base(const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ));

  /// Default body copy — 80% white so it settles a step behind headings.
  static TextStyle get body => _base(const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textBody,
        height: 1.45,
      ));

  /// Secondary body copy: list subtitles, helper text under a field.
  static TextStyle get bodyMuted => _base(const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
        height: 1.4,
      ));

  /// Spaced caps — section headers and field labels ("EMAIL", "DETAILS").
  static TextStyle get label => _base(const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textLabel,
        letterSpacing: 2,
      ));

  /// Small print: timestamps, counts, footnotes. Not spaced — [label] is for
  /// anything that should read as a heading.
  static TextStyle get caption => _base(const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      ));

  /// Button text.
  static TextStyle get button => _base(const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        letterSpacing: 0.3,
      ));

  /// Large numerals on dashboard stat cards.
  static TextStyle get stat => _base(const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: AppColors.cyan,
        height: 1.1,
      ));
}
