import 'package:flutter/material.dart';

import '../../../shared/theme/app_glass.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/glass/glass_card.dart';

/// Source-text input field with a top-right action cluster (voice mic +
/// clear button). The clear button subscribes to the controller via
/// `ListenableBuilder` so the surrounding tree doesn't rebuild on every
/// keystroke — only the icon's visibility flips.
///
/// Voice STT logic lives in the host screen (mic permission, picker
/// fallback when source is Auto, speech_to_text plugin lifecycle) — too
/// much cross-state to push into a leaf widget. Host supplies the
/// `isListening` flag + `onVoicePressed` callback.
class SourceField extends StatelessWidget {
  const SourceField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.maxChars,
    required this.hintText,
    required this.isListening,
    required this.voiceReady,
    required this.voiceTooltip,
    required this.onVoicePressed,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxChars;
  final String hintText;

  /// Drives the mic icon (filled red while recording) + tooltip text.
  final bool isListening;

  /// `false` when voice can't actually start (e.g., source-lang = auto).
  /// Mic stays interactive — tap opens the source picker — but renders
  /// muted to signal "not ready" so users don't think the button is dead.
  final bool voiceReady;

  /// Resolved text for the tooltip — host swaps between voiceTooltip /
  /// voiceListening / voiceNeedsLang per its current state.
  final String voiceTooltip;
  final VoidCallback onVoicePressed;

  /// Invoked when the user taps the clear-X. Host typically clears the
  /// controller AND nukes the result panel so the next translate doesn't
  /// flash stale output.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = GlassPalette.forDark(isDark);
    return GlassCard(
      isDark: isDark,
      blur: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              TextFormField(
                controller: controller,
                focusNode: focusNode,
                minLines: 3,
                maxLines: 6,
                maxLength: maxChars,
                // Hide the built-in counter; we render our own next to the
                // mic in the bottom action row (matches the design).
                buildCounter: (_,
                        {required int currentLength,
                        required bool isFocused,
                        int? maxLength}) =>
                    null,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 16,
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  // Strip the themed filled/underline chrome — the glass card
                  // IS the surface now.
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.only(right: 40),
                  hintStyle: TextStyle(color: p.textTertiary),
                ),
              ),
              // Clear (X) — top-right frosted disc, only when there's text.
              Positioned(
                top: 0,
                right: 0,
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    if (controller.text.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return _ClearButton(isDark: isDark, onTap: onClear);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Bottom action row: char counter + mic, right-aligned (matches the
          // design's layout).
          Row(
            children: [
              const Spacer(),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Text(
                  '${controller.text.length}/$maxChars',
                  style: TextStyle(fontSize: 11, color: p.textTertiary),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Opacity(
                opacity: voiceReady || isListening ? 1.0 : 0.45,
                child: _MicButton(
                  isDark: isDark,
                  listening: isListening,
                  tooltip: voiceTooltip,
                  onPressed: onVoicePressed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small frosted glass disc holding the clear-X, top-right of the input.
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.forDark(isDark);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.fillStrong,
            border: Border.all(color: p.border),
          ),
          child: Icon(Icons.close, size: 18, color: p.textSecondary),
        ),
      ),
    );
  }
}

/// Round mic button — fills with the brand gradient (white glyph + glow) while
/// recording, otherwise a frosted glass disc with an accent-tinted mic.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.isDark,
    required this.listening,
    required this.tooltip,
    required this.onPressed,
  });

  final bool isDark;
  final bool listening;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.forDark(isDark);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: listening ? AppGlass.brand : null,
              color: listening ? null : p.fillStrong,
              border: listening ? null : Border.all(color: p.border),
              boxShadow: listening ? AppGlass.brandGlow() : null,
            ),
            child: Icon(
              listening ? Icons.mic : Icons.mic_none,
              size: 20,
              color: listening ? Colors.white : p.accent,
            ),
          ),
        ),
      ),
    );
  }
}
