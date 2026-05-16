import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

class UpgradeNudgeSheet extends ConsumerStatefulWidget {
  const UpgradeNudgeSheet({
    super.key,
    required this.featureName,
  });

  final String featureName;

  static void show(BuildContext context, {required String featureName}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.sheetRadius),
        ),
      ),
      builder: (_) => UpgradeNudgeSheet(featureName: featureName),
    );
  }

  @override
  ConsumerState<UpgradeNudgeSheet> createState() => _UpgradeNudgeSheetState();
}

class _UpgradeNudgeSheetState extends ConsumerState<UpgradeNudgeSheet> {
  bool _isLoading = false;

  String get _currentPlan {
    final auth = ref.read(authStateProvider).valueOrNull;
    return auth?.session?.plan ?? 'free';
  }

  Future<void> _activateTrial() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.post('/trial/activate');
      final data = response.data as Map<String, dynamic>;

      if (data['ok'] == true) {
        final auth = ref.read(authStateProvider).valueOrNull;
        if (auth?.session != null) {
          await ref.read(authStateProvider.notifier).updateSession(
                auth!.session!.copyWith(plan: data['plan'] as String? ?? 'trial'),
              );
        }
        if (mounted) {
          final info = data['trialEndsAt']?.toString() ?? '7 days';
          final l = AppLocalizations.of(context)!;
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.upgradeTrialActivated(info)),
              backgroundColor: AppColors.green,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.upgradeTrialActivateFailed),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkout(String plan) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get('/auth/checkout', queryParameters: {'plan': plan});
      final url = response.data['url'] as String?;
      if (url != null) {
        await launchUrl(Uri.parse(url));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.upgradeCheckoutFailed),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final plan = _currentPlan;
    final l = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          const SizedBox(height: AppSpacing.lg),
          const Icon(Icons.lock_outline, size: 40, color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          Text(
            l.nudgeUnlock(widget.featureName),
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            plan == 'mobile' ? l.nudgeMobileCopy : l.nudgeChoosePlan,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Plan buttons — conditional on current plan
          if (plan == 'mobile') ...[
            _planButton(
              icon: Icons.devices,
              title: l.nudgeUpgradeToPro,
              price: l.nudgePriceProMonthly,
              subtitle: l.nudgeUpgradeToProSubtitle,
              color: AppColors.amber,
              onTap: () => _checkout('pro'),
            ),
          ] else ...[
            _planButton(
              icon: Icons.phone_android,
              title: l.nudgeMobileTitle,
              price: l.nudgePriceMobile,
              subtitle: l.upgradeMobileSubtitle,
              color: AppColors.primary,
              onTap: () => _checkout('mobile'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _planButton(
              icon: Icons.devices,
              title: l.nudgeProTitle,
              price: l.nudgePriceProMonthly,
              subtitle: l.upgradeProSubtitle,
              color: AppColors.amber,
              onTap: () => _checkout('pro'),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _isLoading ? null : _activateTrial,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : Text(l.upgradeTryFreeDays),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l.nudgeMaybeLater,
              style: TextStyle(
                color: isDark ? AppColors.textSecondary : AppColors.textSecondaryLight,
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.sm),
        ],
      ),
    );
  }

  Widget _planButton({
    required IconData icon,
    required String title,
    required String price,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.surface : AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 16),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                price,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DragHandle extends StatelessWidget {
  const DragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.border : AppColors.borderLight,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
