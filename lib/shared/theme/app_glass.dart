import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// ============================================================================
/// Liquid Glass design tokens.
///
/// The redesign layers frosted, translucent glass surfaces over an immersive
/// indigo -> purple aurora backdrop, while preserving the app's signature brand
/// gradient exactly as it ships. Values are lifted verbatim from the TransKey
/// Design System (tokens/colors.css + glass.css).
///
/// The brand gradient is the one fixed point: never recolour or re-angle it.
/// Everything else (fills, borders, aurora, text-on-glass) is theme-aware via
/// [GlassPalette] so the immersive look works in both dark (default) and a
/// pale-violet light wash.
/// ============================================================================
class AppGlass {
  const AppGlass._();

  // ---- Brand gradient (unchanged — indigo #6366F1 -> purple #A855F7) --------
  static const Color gradStart = Color(0xFF6366F1);
  static const Color gradEnd = Color(0xFFA855F7);
  static const Color gradViolet = Color(0xFF7C3AED);

  /// 135deg diagonal — buttons, FAB, active chips, logo tile.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradStart, gradEnd],
  );

  /// 90deg horizontal — wordmark clip, result-card accent strip, progress.
  static const LinearGradient brandH = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [gradStart, gradEnd],
  );

  // ---- Blur strength (sigma). Only used where content scrolls behind glass
  //      (the fixed tab bar) — over the static aurora, blur is invisible and a
  //      wasted GPU pass, so most surfaces use fill+specular instead. ---------
  static const double blurSm = 8;
  static const double blur = 16;
  static const double blurLg = 28;

  // ---- Radii (AppSpacing parity) --------------------------------------------
  static const double rSm = 8;
  static const double rBtn = 12;
  static const double rCard = 16;
  static const double rSheet = 24;
  static const double rPill = 999;

  /// The frosted-glass backdrop filter: blur + saturation boost, mirroring the
  /// design system's `backdrop-filter: blur(20px) saturate(160%)`. The
  /// saturation is what makes the violet aurora POP through the glass — plain
  /// blur alone looks flat. Use inside a ClipRRect'd [BackdropFilter].
  static ui.ImageFilter frost([double sigma = blur]) {
    // Luminance-preserving saturation matrix for s = 1.6.
    const s = 1.6;
    const lr = 0.2126, lg = 0.7152, lb = 0.0722, inv = 1 - s;
    const m = <double>[
      lr * inv + s, lg * inv, lb * inv, 0, 0,
      lr * inv, lg * inv + s, lb * inv, 0, 0,
      lr * inv, lg * inv, lb * inv + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
    return ui.ImageFilter.compose(
      outer: const ColorFilter.matrix(m),
      inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
  }

  /// Brand glow cast under any gradient element — what makes primary actions
  /// feel lit. Indigo @ ~42% (dark) / ~30% (light).
  static List<BoxShadow> brandGlow({bool strong = false}) => [
        BoxShadow(
          color: gradStart.withValues(alpha: strong ? 0.50 : 0.42),
          blurRadius: strong ? 30 : 22,
          offset: const Offset(0, 8),
        ),
      ];

  /// The standard glass-card decoration: a top-lit translucent fill (fakes the
  /// specular highlight), a 1px light edge, and a soft drop shadow that lifts
  /// the card off the aurora.
  ///
  /// [variant] selects the fill strength / brand tint. When [accent] the caller
  /// is responsible for clipping + painting the 3px gradient strip (see
  /// [GlassCard]); this only returns the base decoration.
  static BoxDecoration card({
    required bool isDark,
    GlassVariant variant = GlassVariant.normal,
    double radius = rCard,
    bool border = true,
    bool shadow = true,
    Color? borderColor,
  }) {
    final p = GlassPalette.forDark(isDark);
    final Gradient fill;
    switch (variant) {
      case GlassVariant.tint:
        // Brand-tinted glass for hero / primary panels.
        fill = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            gradStart.withValues(alpha: isDark ? 0.22 : 0.16),
            gradEnd.withValues(alpha: isDark ? 0.16 : 0.12),
          ],
        );
      case GlassVariant.strong:
        fill = _topLit(p.fillStrong, isDark);
      case GlassVariant.faint:
        fill = _topLit(p.fillFaint, isDark);
      case GlassVariant.normal:
        fill = _topLit(p.fill, isDark);
    }
    return BoxDecoration(
      gradient: fill,
      borderRadius: BorderRadius.circular(radius),
      border: border
          ? Border.all(
              color: borderColor ??
                  (variant == GlassVariant.tint ? p.borderStrong : p.border),
            )
          : null,
      boxShadow: shadow
          ? [
              BoxShadow(
                color: p.shadow,
                blurRadius: isDark ? 24 : 20,
                offset: const Offset(0, 10),
              ),
            ]
          : null,
    );
  }

  /// A vertical fill gradient that is a touch brighter at the top than the base
  /// fill, approximating the inset specular top-edge highlight of real glass.
  static LinearGradient _topLit(Color base, bool isDark) {
    final top = Color.alphaBlend(
      Colors.white.withValues(alpha: isDark ? 0.10 : 0.30),
      base,
    );
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, base],
      stops: const [0.0, 0.55],
    );
  }
}

/// Which glass fill / tint a surface uses.
enum GlassVariant { normal, tint, strong, faint }

/// Theme-resolved colour bundle for the Liquid Glass surfaces. Two const
/// instances ([dark] / [light]); pick with [of] (context) or [forDark] (bool).
class GlassPalette {
  const GlassPalette({
    required this.auroraBase,
    required this.auroraTop,
    required this.auroraBottom,
    required this.glowIndigo,
    required this.glowPurple,
    required this.glowViolet,
    required this.fill,
    required this.fillStrong,
    required this.fillFaint,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentStrong,
    required this.shadow,
  });

  /// Near-black base the aurora sits on (dark) / pale violet wash (light).
  final Color auroraBase;
  final Color auroraTop;
  final Color auroraBottom;
  final Color glowIndigo;
  final Color glowPurple;
  final Color glowViolet;

  final Color fill;
  final Color fillStrong;
  final Color fillFaint;
  final Color border;
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentStrong;

  final Color shadow;

  static GlassPalette of(BuildContext context) =>
      forDark(Theme.of(context).brightness == Brightness.dark);

  static GlassPalette forDark(bool isDark) => isDark ? dark : light;

  static const GlassPalette dark = GlassPalette(
    auroraBase: Color(0xFF0A0A12),
    auroraTop: Color(0xFF0C0A1A),
    auroraBottom: Color(0xFF08080F),
    glowIndigo: Color(0xFF6366F1),
    glowPurple: Color(0xFFA855F7),
    glowViolet: Color(0xFF7C3AED),
    fill: Color(0x12FFFFFF), // white @ 7%
    fillStrong: Color(0x1FFFFFFF), // white @ 12%
    fillFaint: Color(0x0BFFFFFF), // white @ 4.5%
    border: Color(0x29FFFFFF), // white @ 16%
    borderStrong: Color(0x47FFFFFF), // white @ 28%
    textPrimary: Color(0xFFF3F2FF),
    textSecondary: Color(0xFFB6B4CE),
    textTertiary: Color(0xFF807E9C),
    accent: Color(0xFFA99BFF),
    accentStrong: Color(0xFFC4B6FF),
    shadow: Color(0x66080618), // rgba(8,6,24,0.40)
  );

  static const GlassPalette light = GlassPalette(
    auroraBase: Color(0xFFEEF0FB),
    auroraTop: Color(0xFFF3F2FD),
    auroraBottom: Color(0xFFECEAFB),
    glowIndigo: Color(0xFF6366F1),
    glowPurple: Color(0xFFA855F7),
    glowViolet: Color(0xFF7C3AED),
    fill: Color(0x8CFFFFFF), // white @ 55%
    fillStrong: Color(0xB8FFFFFF), // white @ 72%
    fillFaint: Color(0x66FFFFFF), // white @ 40%
    border: Color(0xD9FFFFFF), // white @ 85%
    borderStrong: Color(0xF2FFFFFF), // white @ 95%
    textPrimary: Color(0xFF1A1A2E),
    textSecondary: Color(0xFF4F4D6B),
    textTertiary: Color(0xFF7C7A96),
    accent: Color(0xFF6C63FF),
    accentStrong: Color(0xFF5A52E0),
    shadow: Color(0x294C4682), // rgba(76,70,130,0.16)
  );

  /// Alpha the aurora glows are painted at (dimmer in light mode).
  double get glowOpacity => this == dark ? 1.0 : 0.55;
}
