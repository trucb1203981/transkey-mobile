import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_theme.dart';
import '../services/tts_service.dart';

class TtsButton extends ConsumerStatefulWidget {
  const TtsButton({
    super.key,
    required this.text,
    this.lang = 'en',
    this.size = 20,
    this.color,
  });

  final String text;
  final String lang;
  final double size;
  final Color? color;

  @override
  ConsumerState<TtsButton> createState() => _TtsButtonState();
}

class _TtsButtonState extends ConsumerState<TtsButton> {
  @override
  Widget build(BuildContext context) {
    final tts = ref.watch(ttsProvider);
    final isActive = tts.isPlaying && tts.currentText == widget.text;

    return GestureDetector(
      onTap: () {
        ref.read(ttsProvider.notifier).speak(widget.text, lang: widget.lang);
      },
      onLongPress: () => _showSpeedPicker(context),
      child: isActive
          ? _WaveAnimation(size: widget.size, color: widget.color)
          : Icon(
              Icons.volume_up_outlined,
              size: widget.size,
              color: widget.color,
            ),
    );
  }

  void _showSpeedPicker(BuildContext context) {
    final currentRate = ref.read(ttsProvider).rate;
    const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Speech speed',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            ...speeds.map(
              (speed) => ListTile(
                title: Text(
                  speed == 1.0 ? '1.0x (Normal)' : '${speed}x',
                ),
                trailing: speed == currentRate
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  ref.read(ttsProvider.notifier).setRate(speed);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _WaveAnimation extends StatefulWidget {
  const _WaveAnimation({required this.size, this.color});
  final double size;
  final Color? color;

  @override
  State<_WaveAnimation> createState() => _WaveAnimationState();
}

class _WaveAnimationState extends State<_WaveAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.primary;
    final barH = widget.size * 0.7;
    final barW = widget.size * 0.15;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final phase = i * 0.33;
                final t = (_controller.value + phase) % 1.0;
                final wave = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
                final scale = 0.3 + 0.7 * wave;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: barW * 0.3),
                  child: Container(
                    width: barW,
                    height: barH * scale,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(barW / 2),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
