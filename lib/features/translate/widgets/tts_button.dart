import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/toast.dart';
import '../services/tts_service.dart';

class TtsButton extends ConsumerStatefulWidget {
  const TtsButton({
    super.key,
    required this.text,
    this.lang = 'en',
    this.size = 20,
    this.color,
    this.showOptions = true,
  });

  final String text;
  final String lang;
  final double size;
  final Color? color;

  /// When true, render a companion settings icon next to the speak button
  /// so users can change speed/voice without discovering long-press. Set to
  /// false in cramped layouts (e.g. inline history cards).
  final bool showOptions;

  @override
  ConsumerState<TtsButton> createState() => _TtsButtonState();
}

class _TtsButtonState extends ConsumerState<TtsButton> {
  Future<bool>? _availabilityCheck;
  String? _checkedLang;

  Future<bool> _checkAvailability() {
    // Memoize per-language — re-run only when widget.lang changes.
    if (_availabilityCheck == null || _checkedLang != widget.lang) {
      _checkedLang = widget.lang;
      _availabilityCheck =
          ref.read(ttsProvider.notifier).isLanguageAvailable(widget.lang);
    }
    return _availabilityCheck!;
  }

  Future<void> _onTap(BuildContext context) async {
    final available = await _checkAvailability();
    if (!context.mounted) return;
    if (!available) {
      showAppToast(
        context,
        'TTS not available for ${widget.lang}',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    await ref.read(ttsProvider.notifier).speak(widget.text, lang: widget.lang);
  }

  @override
  Widget build(BuildContext context) {
    final tts = ref.watch(ttsProvider);
    final isActive = tts.isPlaying && tts.currentText == widget.text;

    return FutureBuilder<bool>(
      future: _checkAvailability(),
      builder: (context, snap) {
        // While checking, show the button normally — speak() will bail out
        // gracefully if the OS turns out to lack a voice.
        final isAvailable = snap.data ?? true;
        final color = isAvailable
            ? widget.color
            : (widget.color ?? AppColors.primary).withValues(alpha: 0.35);

        final speakBtn = GestureDetector(
          onTap: () => _onTap(context),
          onLongPress: isAvailable ? () => _showOptionsSheet(context) : null,
          child: isActive
              ? _WaveAnimation(size: widget.size, color: widget.color)
              : Icon(
                  Icons.volume_up_outlined,
                  size: widget.size,
                  color: color,
                ),
        );

        if (!widget.showOptions || !isAvailable) return speakBtn;

        // Compact companion button for speed/voice picker — much more
        // discoverable than long-press. Tap opens the same options sheet.
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            speakBtn,
            GestureDetector(
              onTap: () => _showOptionsSheet(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.size * 0.2),
                child: Text(
                  '${_formatRate(tts.rate)}×',
                  style: TextStyle(
                    fontSize: widget.size * 0.55,
                    fontWeight: FontWeight.w600,
                    color: widget.color ?? AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        );
      },
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

/// Format the speech rate to match desktop's labels: "1×", "1.25×", etc.
/// (no trailing zero on whole numbers). Shared between speak button chip and
/// the speed picker sheet so labels stay consistent.
String _formatRate(double r) {
  if (r == r.truncateToDouble()) return r.toInt().toString();
  return r.toString();
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
    // Match desktop's rate options exactly: 0.25, 0.5, 0.75, 1, 1.25, 1.5
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
                title: Text(speed == 1.0
                    ? '1× (${l.speedNormal})'
                    : '${_formatRate(speed)}×'),
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
