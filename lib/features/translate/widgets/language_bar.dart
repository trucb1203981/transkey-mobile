import 'package:flutter/material.dart';

import '../../../shared/theme/app_glass.dart';
import '../../../shared/theme/app_theme.dart';
import '../models/language.dart';

/// Source ↔ target language picker bar shown above the translate input
/// field. Two pill chips with a swap button between; tapping a chip
/// calls back so the host can present a language picker bottom-sheet.
///
/// When `detectedLang` is non-null the source chip shows the detected
/// language name plus an "Auto" subtitle — same visual contract as the
/// pre-extraction `_buildLanguageBar` in HomeScreen.
class LanguageBar extends StatelessWidget {
  const LanguageBar({
    super.key,
    required this.sourceLang,
    required this.targetLang,
    required this.detectedLang,
    required this.isDark,
    required this.onPickSource,
    required this.onPickTarget,
    required this.onSwap,
  });

  final String sourceLang;
  final String targetLang;

  /// Code from a successful translation when source is "auto"; null
  /// otherwise. Drives the "Auto" subtitle + detected-name label.
  final String? detectedLang;
  final bool isDark;
  final VoidCallback onPickSource;
  final VoidCallback onPickTarget;

  /// Disabled (greyed-out swap icon) when source is "auto" — there's no
  /// concrete language to swap into the target slot.
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = detectedLang != null
        ? languageByCode(detectedLang!).nativeName
        : languageByCode(sourceLang).nativeName;
    final targetLabel = languageByCode(targetLang).nativeName;
    final swapEnabled = sourceLang != 'auto';

    return Row(
      children: [
        Expanded(
          child: _LangChip(
            label: sourceLabel,
            subtitle: detectedLang != null ? 'Auto' : null,
            isDark: isDark,
            onTap: onPickSource,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: _SwapButton(
            enabled: swapEnabled,
            isDark: isDark,
            onTap: swapEnabled ? onSwap : null,
          ),
        ),
        Expanded(
          child: _LangChip(
            label: targetLabel,
            isDark: isDark,
            onTap: onPickTarget,
          ),
        ),
      ],
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.isDark,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.forDark(isDark);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: AppGlass.card(
            isDark: isDark,
            radius: AppSpacing.buttonRadius,
            shadow: false,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 20, color: p.textSecondary),
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 10,
                    color: p.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular swap button between the two language pills — the brand gradient
/// (lit, with a glow) when a concrete source language can be swapped, a muted
/// glass disc when the source is "Auto" (nothing to swap into the target slot).
class _SwapButton extends StatelessWidget {
  const _SwapButton({
    required this.enabled,
    required this.isDark,
    required this.onTap,
  });

  final bool enabled;
  final bool isDark;
  final VoidCallback? onTap;

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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: enabled ? AppGlass.brand : null,
            color: enabled ? null : p.fill,
            border: enabled ? null : Border.all(color: p.border),
            boxShadow: enabled ? AppGlass.brandGlow() : null,
          ),
          child: Icon(
            Icons.swap_horiz,
            size: 20,
            color: enabled ? Colors.white : p.textTertiary,
          ),
        ),
      ),
    );
  }
}
