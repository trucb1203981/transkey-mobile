import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
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
      onLongPress: () => _showOptionsSheet(context),
      child: isActive
          ? _WaveAnimation(size: widget.size, color: widget.color)
          : Icon(
              Icons.volume_up_outlined,
              size: widget.size,
              color: widget.color,
            ),
    );
  }

  void _showOptionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TtsOptionsSheet(lang: widget.lang),
    );
  }
}

class _TtsOptionsSheet extends ConsumerStatefulWidget {
  const _TtsOptionsSheet({required this.lang});

  final String lang;

  @override
  ConsumerState<_TtsOptionsSheet> createState() => _TtsOptionsSheetState();
}

class _TtsOptionsSheetState extends ConsumerState<_TtsOptionsSheet> {
  late Future<List<TtsVoice>> _voicesFuture;

  @override
  void initState() {
    super.initState();
    _voicesFuture = ref.read(ttsProvider.notifier).voicesFor(widget.lang);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tts = ref.watch(ttsProvider);
    final currentRate = tts.rate;
    final currentVoice = tts.voiceByLang[widget.lang];
    const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5];

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Speed picker
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
              child: Text(l.speedPickerTitle,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...speeds.map(
              (speed) => ListTile(
                dense: true,
                title: Text(speed == 1.0 ? '1.0× (${l.speedNormal})' : '$speed×'),
                trailing: speed == currentRate
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  ref.read(ttsProvider.notifier).setRate(speed);
                },
              ),
            ),

            const Divider(height: 1),

            // Voice picker
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
              child: Text(l.voicePickerTitle,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            FutureBuilder<List<TtsVoice>>(
              future: _voicesFuture,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final voices = snap.data ?? const [];
                if (voices.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      l.voiceDefault,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return Column(
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(l.voiceDefault),
                      trailing: currentVoice == null
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () {
                        ref
                            .read(ttsProvider.notifier)
                            .setVoice(widget.lang, '');
                      },
                    ),
                    ...voices.map((v) => ListTile(
                          dense: true,
                          title: Text(v.name),
                          subtitle: Text(v.locale,
                              style: const TextStyle(fontSize: 11)),
                          trailing: v.name == currentVoice
                              ? const Icon(Icons.check,
                                  color: AppColors.primary)
                              : null,
                          onTap: () {
                            ref
                                .read(ttsProvider.notifier)
                                .setVoice(widget.lang, v.name);
                          },
                        )),
                  ],
                );
              },
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
