import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/dio_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/usage_provider.dart';
import '../services/rewarded_ad_service.dart';

/// Bottom sheet shown when a free user hits the daily quota wall.
/// Two CTAs:
///   - "Watch ad" — rewarded video, on completion calls
///     POST /quota/grant-reward → +5 requests / +500 chars and the
///     caller can immediately retry the original translation.
///   - "Upgrade" — routes to /upgrade. Provides the unlimited path.
///
/// Returns:
///   - `true`  if user watched an ad AND the reward was credited
///             server-side (caller should retry the original action)
///   - `false` if user dismissed without watching
///   - `null`  if the upgrade route was taken (sheet popped before
///             reward fires; caller can refresh usage on return)
class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key});

  /// Convenience: showModalBottomSheet wrapper preserving the sheet's
  /// own return-value semantics (see class doc).
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PaywallSheet(),
    );
  }

  @override
  ConsumerState<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<PaywallSheet> {
  late final RewardedAdService _adService;
  bool _watchingAd = false;

  @override
  void initState() {
    super.initState();
    _adService = RewardedAdService();
    // Preload as soon as the sheet appears so by the time the user
    // reads the CTAs and taps "Watch ad" the video is already in
    // memory — saves the user from staring at a spinner.
    _adService.preload();
  }

  @override
  void dispose() {
    _adService.dispose();
    super.dispose();
  }

  Future<void> _onWatchAd() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _watchingAd = true);

    final earned = await _adService.showAndAwaitReward();
    if (!mounted) return;

    if (!earned) {
      setState(() => _watchingAd = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.paywallAdNotComplete)),
      );
      return;
    }

    // Credit server-side. If this fails (network, replay rate-limit),
    // pop with `false` so the caller doesn't optimistically retry into
    // another 429.
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/quota/grant-reward');
      // Refresh the usage bar so the home screen reflects the new
      // limit immediately.
      await ref.read(usageProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _watchingAd = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          e.response?.data is Map
              ? (e.response?.data['message']?.toString() ?? l.paywallCreditFailed)
              : l.paywallCreditFailed,
        )),
      );
    }
  }

  void _onUpgrade() {
    Navigator.of(context).pop(null);
    context.push('/upgrade');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.hourglass_bottom, color: Colors.orange, size: 28),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l.paywallTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l.paywallBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Watch-ad CTA (free, immediate)
            FilledButton.icon(
              onPressed: _watchingAd ? null : _onWatchAd,
              icon: _watchingAd
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_circle_outline),
              label: Text(_watchingAd ? l.paywallLoading : l.paywallWatchAdCta),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.paywallWatchAdSub,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Upgrade CTA (unlimited, paid)
            OutlinedButton.icon(
              onPressed: _watchingAd ? null : _onUpgrade,
              icon: const Icon(Icons.workspace_premium),
              label: Text(l.paywallUpgradeCta),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.paywallUpgradeSub,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton(
                onPressed: _watchingAd ? null : () => Navigator.of(context).pop(false),
                child: Text(l.paywallDismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
