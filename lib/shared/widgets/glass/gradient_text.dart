import 'package:flutter/material.dart';

import '../../theme/app_glass.dart';

/// Text painted with the brand gradient (the "TransKey" wordmark treatment).
/// Uses a ShaderMask so the glyphs are clipped to the indigo -> purple gradient.
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient = AppGlass.brandH,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final Gradient gradient;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        textAlign: textAlign,
        // Colour is replaced by the shader; white keeps full opacity coverage.
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}
