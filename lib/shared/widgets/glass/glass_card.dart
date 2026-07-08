import 'package:flutter/material.dart';

import '../../theme/app_glass.dart';

/// A frosted Liquid Glass panel: translucent top-lit fill, 1px light edge, soft
/// drop shadow, optional brand tint, and an optional 3px gradient accent strip
/// across the top (result cards).
///
/// Blur is OFF by default: over the static aurora a backdrop blur is invisible
/// but costs a full GPU pass, so only enable [blur] for a surface that has real
/// content scrolling behind it (e.g. a fixed tab bar).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.isDark = true,
    this.variant = GlassVariant.normal,
    this.padding = const EdgeInsets.all(AppGlass.rCard),
    this.radius = AppGlass.rCard,
    this.accentStrip = false,
    this.blur = false,
    this.blurSigma = AppGlass.blur,
    this.border = true,
    this.shadow = true,
    this.borderColor,
    this.onTap,
    this.margin,
  });

  final Widget child;
  final bool isDark;
  final GlassVariant variant;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Paints the 3px indigo -> purple strip across the very top (result cards).
  final bool accentStrip;

  /// Real backdrop blur — reserve for surfaces with content moving behind them.
  final bool blur;
  final double blurSigma;
  final bool border;
  final bool shadow;

  /// Overrides the default hairline colour (e.g. quota warning state).
  final Color? borderColor;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final decoration = AppGlass.card(
      isDark: isDark,
      variant: variant,
      radius: radius,
      border: border,
      shadow: shadow,
      borderColor: borderColor,
    );
    final br = BorderRadius.circular(radius);

    Widget content = Padding(padding: padding, child: child);

    if (accentStrip) {
      content = Stack(
        children: [
          content,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              decoration: const BoxDecoration(gradient: AppGlass.brandH),
            ),
          ),
        ],
      );
    }

    // Ink + tap feedback sit above the fill but below the child.
    Widget card = DecoratedBox(
      decoration: decoration,
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: br,
                child: content,
              ),
            ),
    );

    // Clip so the accent strip / ink / blur respect the rounded corners.
    card = ClipRRect(borderRadius: br, child: card);

    if (blur) {
      card = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          // blur + saturate(160%) — the saturation lifts the violet aurora
          // through the glass, which is what reads as "frosted" (a plain
          // blur over the smooth backdrop looks flat).
          filter: AppGlass.frost(blurSigma),
          child: card,
        ),
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: card);
    }
    return card;
  }
}
