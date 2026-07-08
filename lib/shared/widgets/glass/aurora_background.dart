import 'package:flutter/material.dart';

import '../../theme/app_glass.dart';

/// The immersive aurora backdrop every glass surface floats over: a near-black
/// (dark) / pale-violet (light) base with three soft radial indigo/purple/violet
/// glows layered over a vertical wash. Full-bleed — place it as the bottom layer
/// of a screen (behind SafeArea) so the glow reaches under the status bar and
/// tab bar.
///
/// Pure paint (gradients only, no blur) so it costs nothing on weak devices.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({
    super.key,
    required this.child,
    this.isDark = true,
  });

  final Widget child;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.forDark(isDark);
    final o = p.glowOpacity;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.auroraTop, p.auroraBase, p.auroraBottom],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Broad, soft glows that overlap in the middle so the violet
          // ambiance fills the whole screen (matches the design's large
          // 110-120% radial ellipses), not just a bright cap at the top.
          _glow(p.glowIndigo, o * (isDark ? 0.42 : 0.26),
              const Alignment(-0.6, -0.85), 1.6),
          _glow(p.glowPurple, o * (isDark ? 0.38 : 0.22),
              const Alignment(0.95, -0.8), 1.5),
          _glow(p.glowViolet, o * (isDark ? 0.36 : 0.20),
              const Alignment(0.65, 1.05), 1.7),
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  Widget _glow(Color color, double opacity, Alignment center, double radius) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: center,
            radius: radius,
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0)
            ],
            stops: const [0.0, 0.72],
          ),
        ),
      ),
    );
  }
}
