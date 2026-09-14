import 'package:flutter/material.dart';

/// The single source of truth for colour in the Unify mobile app.
///
/// Deep space-blue canvas lit by cyan and magenta neon, extended from the
/// palette the auth screens established. Nothing outside this file should
/// declare a `Color(0x…)` literal — if a screen needs a new hue, it gets a
/// name here first.
///
/// Translucent whites are written as baked ARGB literals rather than
/// `Colors.white.withValues(...)` so every token stays `const`, which in turn
/// lets the widgets that consume them stay `const`.
class AppColors {
  const AppColors._();

  // ───────────────────────── Background ramp ─────────────────────────
  /// Top of the screen — near-black with a blue cast.
  static const bgTop = Color(0xFF050514);

  /// Mid navy, holds the middle third so the ramp doesn't wash straight out.
  static const bgMid = Color(0xFF0A0E2A);

  /// Bottom of the ramp, the lightest of the three.
  static const bgBottom = Color(0xFF141B4D);

  // ───────────────────────── Neon accents ─────────────────────────
  static const cyan = Color(0xFF00E5FF);
  static const magenta = Color(0xFFFF2D95);

  /// Midpoint of the primary gradient. Pulled toward indigo so cyan → magenta
  /// doesn't pass through a muddy grey.
  static const electricBlue = Color(0xFF4C6FFF);

  /// Background blooms and the "in progress" state.
  static const violet = Color(0xFF7A4DFF);

  // ───────────────────────── Text ─────────────────────────
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0x99FFFFFF); // white 60%
  static const textMuted = Color(0x73FFFFFF); // white 45%

  /// Spaced-caps field and section labels — quieter than body copy because
  /// the letter-spacing already marks them as labels.
  static const textLabel = Color(0x8CFFFFFF); // white 55%

  /// Body copy inside cards, per the 80%-white body rule.
  static const textBody = Color(0xCCFFFFFF); // white 80%

  // ───────────────────────── Surfaces ─────────────────────────
  /// Frosted-glass fill. Paired with [glassBorder] and a backdrop blur.
  static const glassFill = Color(0x0FFFFFFF); // white 6%
  static const glassBorder = Color(0x26FFFFFF); // white 15%

  /// Glass chrome (app bar, bottom nav) sits fainter than a card so content
  /// stays the brightest thing on screen.
  static const chromeFill = Color(0x0AFFFFFF); // white 4%

  /// Text-field fill. Solid rather than translucent so input stays legible
  /// wherever a card happens to sit over a background glow.
  static const inputFill = Color(0xFF1A1F3D);
  static const inputBorder = Color(0x33FFFFFF); // white 20%

  /// Small circular icon wells in list rows, and the social buttons.
  static const iconWell = Color(0xFF1E2235);

  /// Solid dark fill for dialogs, sheets and snackbars — surfaces that need
  /// to read as opaque overlays rather than as more glass.
  static const overlaySurface = Color(0xFF12162E);

  /// 1px rules and dividers.
  static const hairline = Color(0x14FFFFFF); // white 8%

  // ───────────────────────── Icon opacities ─────────────────────────
  static const iconPrimary = Color(0xB3FFFFFF); // white 70%
  static const iconSecondary = Color(0x99FFFFFF); // white 60%
  static const iconDisabled = Color(0x73FFFFFF); // white 45%

  /// Trailing chevrons on list rows.
  static const chevron = Color(0x4DFFFFFF); // white 30%

  /// Large empty-state glyphs.
  static const iconGhost = Color(0x33FFFFFF); // white 20%

  // ───────────────────────── Semantic ─────────────────────────
  /// Desaturated so they sit on near-black without vibrating the way the
  /// light theme's fully saturated versions did.
  static const success = Color(0xFF3DDC97);
  static const warning = Color(0xFFFFC24B);
  static const error = Color(0xFFFF6B6B);

  /// Destructive actions are magenta, not red — the neon accent doubles as
  /// the danger hue so delete buttons stay inside the palette.
  static const danger = magenta;

  // ───────────────────────── Legacy aliases ─────────────────────────
  // Names the screens already reference, re-pointed at dark-theme values so
  // the whole app re-skins from this file alone. Prefer the names above in
  // new code.

  /// Primary interactive hue.
  static const primary = cyan;
  static const primaryDark = electricBlue;

  /// Foreground for anything sitting *on* a [primary] fill. Cyan is bright,
  /// so this is near-black rather than white.
  static const onPrimary = Color(0xFF04121A);

  static const accentHigh = magenta;
  static const accentCyan = cyan;

  /// Dark chrome. On this theme the whole canvas is dark, so it resolves to
  /// the top of the background ramp.
  static const ink = bgTop;

  static const purple = violet;
  static const amber = warning;

  /// Scaffold background. Screens should prefer [AppBackground] over painting
  /// this flat, but it's the correct fallback colour underneath it.
  static const surface = bgTop;

  /// Raised surfaces. Glass rather than a solid card fill.
  static const card = glassFill;
  static const cardMuted = overlaySurface;

  static const border = glassBorder;
  static const borderStrong = inputBorder;

  // ───────────────────────── Gradients ─────────────────────────
  /// Full-screen base ramp. Three stops so the mid navy holds the middle.
  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgTop, bgMid, bgBottom],
    stops: [0.0, 0.45, 1.0],
  );

  /// Primary CTA ramp — cyan through electric blue to magenta.
  static const buttonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [cyan, electricBlue, magenta],
  );

  /// Hero panels. The same ramp on the diagonal, dimmed so white headline
  /// text still clears contrast across it.
  static const heroGradient = LinearGradient(
    colors: [Color(0xFF10214F), Color(0xFF241A57), Color(0xFF3D1B4D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Ramps an identity hue (role, business type) into the dark canvas instead
  /// of starting from it, so the hue stays recognisable at the top-left while
  /// the far corner is dark enough for white text.
  static LinearGradient heroGradientFor(Color accent) => LinearGradient(
        colors: [
          Color.lerp(accent, bgMid, 0.55)!,
          Color.lerp(accent, bgTop, 0.82)!,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// Darkens photo-backed tiles from the top down. Bottom-heavy because the
  /// label sits at the foot of the card, so it has to clear whatever the
  /// artwork happens to be doing down there.
  static const tileScrimGradient = LinearGradient(
    colors: [Color(0x99050514), Color(0xF2050514)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Glow cast beneath a primary button.
  static const buttonGlow = Color(0x4D00E5FF); // cyan 30%

  /// Glow behind a danger accent — the unread badge, destructive icons.
  static const dangerGlow = Color(0x66FF2D95); // magenta 40%
}

/// Shared geometry, so cards, fields and buttons agree on their corner radii
/// instead of every screen re-picking a number.
class AppRadii {
  const AppRadii._();

  /// Cards, glass panels, dialogs.
  static const card = 24.0;

  /// Buttons and text fields.
  static const control = 14.0;

  /// List rows and smaller nested cards.
  static const row = 16.0;

  /// Thumbnails and inline images.
  static const image = 12.0;

  /// The floating bottom-nav pill and modal sheets.
  static const pill = 24.0;
}
