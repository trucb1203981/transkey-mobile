import 'package:flutter/material.dart';

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
        IconButton(
          onPressed: swapEnabled ? onSwap : null,
          icon: Icon(
            Icons.swap_horiz,
            color: swapEnabled
                ? AppColors.primary
                : AppColors.textSecondary,
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
    return Material(
      color: isDark ? AppColors.surface : const Color(0xFFF0EDE8),
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
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
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.primary.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
