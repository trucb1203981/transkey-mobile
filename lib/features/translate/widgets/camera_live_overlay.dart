import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/camera/camera_service.dart';

/// Draws colored rectangles over the live camera preview to indicate
/// detected text quality: green (good), orange (fair), red (poor).
///
/// When [onBlockTap] is provided, each rect becomes tappable — the
/// camera screen wires this to the "What is this?" flow so users can
/// ask about any visible line without committing to a full capture.
class CameraLiveOverlay extends StatelessWidget {
  const CameraLiveOverlay({
    super.key,
    required this.blocks,
    required this.imageSize,
    this.onBlockTap,
  });

  final List<OcrBlock> blocks;
  final ui.Size imageSize;
  final ValueChanged<OcrBlock>? onBlockTap;

  Color _borderColor(TextQuality quality) => switch (quality) {
    TextQuality.good => Colors.green,
    TextQuality.fair => Colors.orange,
    TextQuality.poor => Colors.red,
  };

  Color _fillColor(TextQuality quality) => switch (quality) {
    TextQuality.good => Colors.green.withValues(alpha: 0.1),
    TextQuality.fair => Colors.orange.withValues(alpha: 0.15),
    TextQuality.poor => Colors.red.withValues(alpha: 0.2),
  };

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final imageAspect = imageSize.width / imageSize.height;
        final viewAspect = viewSize.width / viewSize.height;
        double fitW, fitH, offsetX, offsetY;
        if (imageAspect > viewAspect) {
          fitW = viewSize.width;
          fitH = viewSize.width / imageAspect;
          offsetX = 0;
          offsetY = (viewSize.height - fitH) / 2;
        } else {
          fitH = viewSize.height;
          fitW = viewSize.height * imageAspect;
          offsetX = (viewSize.width - fitW) / 2;
          offsetY = 0;
        }
        final scaleX = fitW / imageSize.width;
        final scaleY = fitH / imageSize.height;

        return Stack(
          children: [
            for (final block in blocks)
              _QualityRect(
                rect: Rect.fromLTRB(
                  block.boundingBox.left * scaleX + offsetX,
                  block.boundingBox.top * scaleY + offsetY,
                  block.boundingBox.right * scaleX + offsetX,
                  block.boundingBox.bottom * scaleY + offsetY,
                ),
                quality: block.quality,
                borderColor: _borderColor(block.quality),
                fillColor: _fillColor(block.quality),
                onTap: onBlockTap == null ? null : () => onBlockTap!(block),
              ),
          ],
        );
      },
    );
  }
}

class _QualityRect extends StatelessWidget {
  const _QualityRect({
    required this.rect,
    required this.quality,
    required this.borderColor,
    required this.fillColor,
    this.onTap,
  });

  final Rect rect;
  final TextQuality quality;
  final Color borderColor;
  final Color fillColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Minimum hit target — ML Kit sometimes returns very thin boxes (1
    // line at 12 px tall) which are basically untappable on real fingers.
    // Inflate the visual rect by hit-padding for the tap handler only.
    const double hitPad = 8;
    final tapRect = Rect.fromLTRB(
      rect.left - hitPad,
      rect.top - hitPad,
      rect.right + hitPad,
      rect.bottom + hitPad,
    );
    final visual = Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 2),
        color: fillColor,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    if (onTap == null) {
      return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: visual,
      );
    }
    return Positioned(
      left: tapRect.left,
      top: tapRect.top,
      width: tapRect.width,
      height: tapRect.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(hitPad),
          child: visual,
        ),
      ),
    );
  }
}
