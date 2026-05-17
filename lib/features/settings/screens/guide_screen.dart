import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

/// User-facing reference for "how do I use each feature".
///
/// The matrix mirrors the canonical feature spec discussed during the
/// refactor: each of Translate/Summary/Refine/Explain/Reply has 3-5
/// input methods, none of which require Accessibility for capturing
/// source text. Reply uniquely benefits from Accessibility on the
/// OUTPUT side (auto-paste back into the focused input field).
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text(t.guideTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        children: [
          _intro(theme, t),
          const SizedBox(height: AppSpacing.md),
          _featureCard(
            theme: theme,
            isDark: isDark,
            icon: Icons.translate,
            title: t.guideFeatureTranslate,
            subtitle: t.guideFeatureTranslateSubtitle,
            inputs: [
              _Input(t.guideInputCopyTitle, t.guideInputCopyDesc),
              _Input(t.guideInputOcrTitle, t.guideInputOcrDesc),
              _Input(t.guideInputRegionTitle, t.guideInputRegionDesc),
              _Input(t.guideInputShareTitle, t.guideInputShareDesc),
              _Input(
                t.guideInputMenuTitle(t.guideFeatureTranslate),
                t.guideInputMenuDesc(t.guideFeatureTranslate),
              ),
            ],
          ),
          _featureCard(
            theme: theme,
            isDark: isDark,
            icon: Icons.short_text,
            title: t.guideFeatureSummary,
            subtitle: t.guideFeatureSummarySubtitle,
            inputs: [
              _Input(t.guideInputCopyTitle, t.guideInputCopyDesc),
              _Input(t.guideInputOcrTitle, t.guideInputOcrDesc),
              _Input(t.guideInputRegionTitle, t.guideInputRegionDesc),
              _Input(t.guideInputShareTitle, t.guideInputShareDesc),
              _Input(
                t.guideInputMenuTitle(t.guideFeatureSummary),
                t.guideInputMenuDesc(t.guideFeatureSummary),
              ),
            ],
          ),
          _featureCard(
            theme: theme,
            isDark: isDark,
            icon: Icons.auto_fix_high,
            title: t.guideFeatureRefine,
            subtitle: t.guideFeatureRefineSubtitle,
            inputs: [
              _Input(t.guideInputCopyTitle, t.guideInputCopyDesc),
              _Input(t.guideInputShareTitle, t.guideInputShareDesc),
              _Input(
                t.guideInputMenuTitle(t.guideFeatureRefine),
                t.guideInputMenuDesc(t.guideFeatureRefine),
              ),
            ],
          ),
          _featureCard(
            theme: theme,
            isDark: isDark,
            icon: Icons.help_outline,
            title: t.guideFeatureExplain,
            subtitle: t.guideFeatureExplainSubtitle,
            inputs: [
              _Input(t.guideInputCopyTitle, t.guideInputCopyDesc),
              _Input(t.guideInputShareTitle, t.guideInputShareDesc),
              _Input(
                t.guideInputMenuTitle(t.guideFeatureExplain),
                t.guideInputMenuDesc(t.guideFeatureExplain),
              ),
            ],
          ),
          _featureCard(
            theme: theme,
            isDark: isDark,
            icon: Icons.reply,
            title: t.guideFeatureReply,
            subtitle: t.guideFeatureReplySubtitle,
            inputs: [
              _Input(t.guideInputCopyTitle, t.guideInputCopyDesc),
              _Input(t.guideInputShareTitle, t.guideInputShareDesc),
              _Input(
                t.guideInputMenuTitle(t.guideFeatureReply),
                t.guideInputMenuDesc(t.guideFeatureReply),
              ),
            ],
            footer: _replyFooter(theme, t),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _intro(ThemeData theme, AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.guideIntroTitle,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(t.guideIntroBody, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _replyFooter(ThemeData theme, AppLocalizations t) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.accessibility_new,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(t.guideReplyA11yTitle,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Text(t.guideReplyA11yBody, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _featureCard({
    required ThemeData theme,
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<_Input> inputs,
    Widget? footer,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            for (final inp in inputs) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2, right: 8),
                    child: Icon(Icons.fiber_manual_record,
                        size: 8, color: AppColors.primary),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(inp.title,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(inp.body, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (footer != null) footer,
          ],
        ),
      ),
    );
  }
}

class _Input {
  final String title;
  final String body;
  const _Input(this.title, this.body);
}
