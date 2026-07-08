import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_glass.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/glass/glass_card.dart';
import '../../../shared/widgets/selectable_with_actions.dart';
import '../../history/providers/history_provider.dart';
import '../models/language.dart';
import '../models/translate_models.dart';
import '../providers/language_settings_provider.dart';
import '../providers/translate_provider.dart';
import 'scam_banner.dart';
import 'tts_button.dart';

/// Translation result card shown on the home screen below the input.
/// Contains the translated text (tap-to-copy + long-press selection),
/// optional romanization, optional reply suggestions, and an action
/// row (copy / TTS / favorite).
///
/// Watches Riverpod itself so the host doesn't have to plumb
/// languageSettings + translate + history state through the build call.
class ResultCard extends ConsumerWidget {
  const ResultCard({
    super.key,
    required this.result,
    required this.isDark,
    required this.onCopy,
  });

  final TranslateResult result;
  final bool isDark;

  /// Invoked when the user taps anywhere on the result text OR the
  /// explicit copy icon. Host snackbar / haptic is its responsibility.
  final void Function(String text) onCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final p = GlassPalette.forDark(isDark);
    final langs = ref.watch(languageSettingsProvider).valueOrNull;
    final sourceLang = langs?.sourceLang ?? 'auto';
    final targetLang = langs?.targetLang ?? 'en';

    return GlassCard(
      isDark: isDark,
      variant: GlassVariant.tint,
      blur: true,
      accentStrip: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fraud warning above everything else (only when the server flags it).
          if (result.scamRisk != null) ...[
            ScamBanner(scamRisk: result.scamRisk!),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Detected source language (only when auto-detect)
          if (result.detectedLang != null && sourceLang == 'auto') ...[
            Text(
              l.detectedLang(languageByCode(result.detectedLang!).nativeName),
              style: theme.textTheme.bodySmall?.copyWith(
                color: p.accent,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Tap-anywhere-on-result copies. SelectableText still handles
          // long-press selection + the custom "TransKey" context menu.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onCopy(result.translation),
            child: SelectableWithActions(
              result.translation,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                height: 1.5,
                color: p.textPrimary,
              ),
              targetLang: targetLang,
            ),
          ),

          if (result.romanization != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              result.romanization!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: p.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          if (result.suggestions.isNotEmpty)
            _SuggestionList(
              suggestions: result.suggestions,
              isDark: isDark,
              onCopy: onCopy,
            ),

          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ActionIcon(
                icon: Icons.copy_outlined,
                tooltip: l.copy,
                onTap: () => onCopy(result.translation),
              ),
              const SizedBox(width: AppSpacing.sm),
              _GlassCircle(
                isDark: isDark,
                child: TtsButton(
                  text: result.translation,
                  lang: targetLang,
                  size: 20,
                  showOptions: false,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const _SaveIcon(),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.suggestions,
    required this.isDark,
    required this.onCopy,
  });

  final List<SuggestionEntry> suggestions;
  final bool isDark;
  final void Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final p = GlassPalette.forDark(isDark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        Divider(color: p.border),
        const SizedBox(height: AppSpacing.sm),
        Text(l.suggestions, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        // Bilingual chips (matches desktop popup): each card shows the
        // reply in the partner's language on top, the user's language
        // hint below, and tap copies the SOURCE (what the user would
        // actually send back).
        ...suggestions.map((s) {
          final source = s.source.trim();
          final target = s.target.trim();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: InkWell(
              onTap: () => onCopy(source.isNotEmpty ? source : target),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: AppGlass.card(
                  isDark: isDark,
                  radius: 12,
                  shadow: false,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (source.isNotEmpty)
                      Text(
                        source,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (target.isNotEmpty && target != source) ...[
                      const SizedBox(height: 2),
                      Text(
                        target,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: p.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Star icon that toggles the current translation's favorite flag in
/// history. Uses `select` so only this widget rebuilds when the entry's
/// favorite state changes — not on every history search/filter tick.
class _SaveIcon extends ConsumerWidget {
  const _SaveIcon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final historyId = ref.watch(
      translateProvider.select((s) => s.valueOrNull?.lastHistoryId),
    );
    final isFavorite = ref.watch(
      historyProvider.select((s) {
        if (historyId == null) return false;
        for (final e in s.entries) {
          if (e.id == historyId) return e.isFavorite;
        }
        return false;
      }),
    );
    return _ActionIcon(
      icon: isFavorite ? Icons.star : Icons.star_outline,
      tooltip: l.save,
      onTap: historyId == null
          ? null
          : () => ref.read(historyProvider.notifier).toggleFavorite(historyId),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = GlassPalette.forDark(isDark);
    return Tooltip(
      message: tooltip,
      child: _GlassCircle(
        isDark: isDark,
        onTap: onTap,
        child: Icon(icon, size: 20, color: p.textSecondary),
      ),
    );
  }
}

/// A 40px frosted glass disc for a result-card action (copy / TTS / favorite).
/// [onTap] optional so it can wrap a child that handles its own taps (TTS).
class _GlassCircle extends StatelessWidget {
  const _GlassCircle({
    required this.isDark,
    required this.child,
    this.onTap,
  });

  final bool isDark;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.forDark(isDark);
    final circle = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.fillStrong,
        border: Border.all(color: p.border),
      ),
      child: child,
    );
    if (onTap == null) return circle;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: circle,
      ),
    );
  }
}
