import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../translate/providers/features_provider.dart';

class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final flags = ref.watch(featuresProvider).flags;

    final paidLabel = t.guideInputPaidBadge;
    final hasLens = flags.lens;

    // Each entry carries its availability directly from production flags.
    // When admin flips a flag in /admin/features, the guide re-renders on
    // the next app open — no code change needed.
    final allFeatures = <_FeatureDef>[
      _FeatureDef(
        icon: Icons.translate,
        title: t.guideFeatureTranslate,
        subtitle: t.guideFeatureTranslateSubtitle,
        available: true,
        inputs: [
          _Input(t.guideInputCopyTitle, t.guideInputCopyDesc),
          _Input(t.guideInputShareTitle, t.guideInputShareDesc),
          _Input(
            t.guideInputMenuTitle(t.guideFeatureTranslate),
            t.guideInputMenuDesc(t.guideFeatureTranslate),
          ),
          _Input(t.guideInputVoiceTitle, t.guideInputVoiceDesc),
          _Input(t.guideInputOcrTitle, t.guideInputOcrDesc,
              isPaid: !hasLens, paidLabel: !hasLens ? paidLabel : null),
          _Input(t.guideInputRegionTitle, t.guideInputRegionDesc,
              isPaid: !hasLens, paidLabel: !hasLens ? paidLabel : null),
        ],
      ),
      _FeatureDef(
        icon: Icons.book_outlined,
        title: t.guideFeatureGlossary,
        subtitle: t.guideFeatureGlossarySubtitle,
        available: flags.glossary,
        inputs: [
          _Input(t.guideInputGlossaryTitle, t.guideInputGlossaryDesc),
        ],
      ),
      _FeatureDef(
        icon: Icons.camera_alt_outlined,
        title: t.guideFeatureCamera,
        subtitle: t.guideFeatureCameraSubtitle,
        available: flags.camera,
        inputs: [
          _Input(t.guideInputCameraTitle, t.guideInputCameraDesc),
        ],
      ),
      _FeatureDef(
        icon: Icons.summarize,
        title: t.guideFeatureSummary,
        subtitle: t.guideFeatureSummarySubtitle,
        available: flags.summarize,
        inputs: [
          _Input(t.guideInputCopyTitle, t.guideInputCopyDesc),
          _Input(t.guideInputShareTitle, t.guideInputShareDesc),
          _Input(
            t.guideInputMenuTitle(t.guideFeatureSummary),
            t.guideInputMenuDesc(t.guideFeatureSummary),
          ),
          _Input(t.guideInputOcrTitle, t.guideInputOcrDesc,
              isPaid: !hasLens, paidLabel: !hasLens ? paidLabel : null),
          _Input(t.guideInputRegionTitle, t.guideInputRegionDesc,
              isPaid: !hasLens, paidLabel: !hasLens ? paidLabel : null),
        ],
      ),
      _FeatureDef(
        icon: Icons.lightbulb,
        title: t.guideFeatureExplain,
        subtitle: t.guideFeatureExplainSubtitle,
        available: flags.explain,
        inputs: [
          _Input(t.guideInputCopyTitle, t.guideInputCopyDesc),
          _Input(t.guideInputShareTitle, t.guideInputShareDesc),
          _Input(
            t.guideInputMenuTitle(t.guideFeatureExplain),
            t.guideInputMenuDesc(t.guideFeatureExplain),
          ),
        ],
      ),
      _FeatureDef(
        icon: Icons.auto_fix_high,
        title: t.guideFeatureRefine,
        subtitle: t.guideFeatureRefineSubtitle,
        available: flags.refine,
        inputs: [
          _Input(t.guideInputCopyTitle, t.guideInputCopyDesc),
          _Input(t.guideInputShareTitle, t.guideInputShareDesc),
          _Input(
            t.guideInputMenuTitle(t.guideFeatureRefine),
            t.guideInputMenuDesc(t.guideFeatureRefine),
          ),
        ],
      ),
      _FeatureDef(
        icon: Icons.reply,
        title: t.guideFeatureReply,
        subtitle: t.guideFeatureReplySubtitle,
        available: flags.replyTranslate,
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
    ];

    final freeFeatures = allFeatures.where((f) => f.available).toList();
    final lockedFeatures = allFeatures.where((f) => !f.available).toList();

    return Scaffold(
      appBar: AppBar(title: Text(t.guideTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        children: [
          _planCard(theme, t, freeFeatures, lockedFeatures),
          const SizedBox(height: AppSpacing.lg),

          _sectionLabel(t.guideSectionFree, isFree: true, theme: theme),
          const SizedBox(height: AppSpacing.sm),
          for (final f in freeFeatures)
            _featureCard(
              theme: theme,
              isDark: isDark,
              icon: f.icon,
              title: f.title,
              subtitle: f.subtitle,
              isPaid: false,
              badgeLabel: t.guideFreeBadge,
              inputs: f.inputs,
              footer: f.footer,
            ),

          if (lockedFeatures.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _sectionLabel(t.guideSectionPaid, isFree: false, theme: theme),
            const SizedBox(height: AppSpacing.sm),
            for (final f in lockedFeatures)
              _featureCard(
                theme: theme,
                isDark: isDark,
                icon: f.icon,
                title: f.title,
                subtitle: f.subtitle,
                isPaid: true,
                badgeLabel: t.guidePaidBadge,
                inputs: f.inputs,
                footer: f.footer,
              ),
          ],

          const SizedBox(height: AppSpacing.md),
          _screenshotTip(theme, t),

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  // Tip: how to take a system screenshot without the floating bubble in it.
  // The bubble is an overlay so it lands in the user's screenshots and can't
  // be excluded automatically — this explains the manual "hide for a few
  // seconds" action. Plain steps + benefit only (no internals).
  Widget _screenshotTip(ThemeData theme, AppLocalizations t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.photo_camera_outlined,
                size: 20, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.guideScreenshotTipTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.guideScreenshotTipBody,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(
    ThemeData theme,
    AppLocalizations t,
    List<_FeatureDef> freeFeatures,
    List<_FeatureDef> lockedFeatures,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.guidePlanCompareTitle,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _planColumn(
                    label: t.guidePlanFreeLabel,
                    items: freeFeatures.map((f) => f.title).toList(),
                    isFree: true,
                    theme: theme,
                  ),
                ),
                if (lockedFeatures.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _planColumn(
                      label: t.guidePlanPaidLabel,
                      items: lockedFeatures.map((f) => f.title).toList(),
                      isFree: false,
                      theme: theme,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _planColumn({
    required String label,
    required List<String> items,
    required bool isFree,
    required ThemeData theme,
  }) {
    final color = isFree ? Colors.green : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFree ? Icons.check_circle_outline : Icons.star_outline,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: Icon(Icons.fiber_manual_record,
                        size: 5, color: color.withValues(alpha: 0.7)),
                  ),
                  Expanded(
                    child: Text(item, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(
    String label, {
    required bool isFree,
    required ThemeData theme,
  }) {
    final color = isFree ? Colors.green : AppColors.primary;
    return Row(
      children: [
        Icon(
          isFree ? Icons.check_circle_outline : Icons.star_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: color.withValues(alpha: 0.35))),
      ],
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
    required bool isPaid,
    required String badgeLabel,
    required List<_Input> inputs,
    Widget? footer,
  }) {
    final badgeColor = isPaid ? AppColors.primary : Colors.green;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: badgeColor, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: badgeColor.withValues(alpha: 0.5), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPaid
                            ? Icons.star_outline
                            : Icons.check_circle_outline,
                        size: 11,
                        color: badgeColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            for (final inp in inputs) ...[
              _inputRow(inp, theme, isPaid),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (footer != null) footer,
          ],
        ),
      ),
    );
  }

  Widget _inputRow(_Input inp, ThemeData theme, bool featureIsPaid) {
    final dimmed = inp.isPaid && !featureIsPaid;
    final textColor = dimmed ? AppColors.textSecondary : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3, right: 8),
          child: Icon(
            Icons.fiber_manual_record,
            size: 8,
            color: dimmed
                ? AppColors.textSecondary.withValues(alpha: 0.4)
                : AppColors.primary,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      inp.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (dimmed && inp.paidLabel != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_outline,
                              size: 10, color: AppColors.primary),
                          const SizedBox(width: 2),
                          Text(
                            inp.paidLabel!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                inp.body,
                style: theme.textTheme.bodySmall?.copyWith(color: textColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureDef {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool available;
  final List<_Input> inputs;
  final Widget? footer;

  const _FeatureDef({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.available,
    required this.inputs,
    this.footer,
  });
}

class _Input {
  final String title;
  final String body;
  final bool isPaid;
  final String? paidLabel;

  const _Input(this.title, this.body,
      {this.isPaid = false, this.paidLabel});
}
