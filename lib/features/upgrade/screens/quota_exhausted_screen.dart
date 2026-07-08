import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/tracking/tracking_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_glass.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/glass/aurora_scaffold.dart';
import '../../translate/providers/features_provider.dart';
import '../providers/usage_provider.dart';
import '../services/rewarded_ad_service.dart';

/// Full-screen quota-exhausted wall. Shown on every app open / resume
/// while a free user remains at the daily cap — they can't actually USE
/// the app in that state, so re-surfacing the "watch ad / upgrade" CTAs
/// is helping, not nagging. A short in-process cooldown ([_minRedisplay])
/// keeps a quick dismiss → activity resume from re-popping the wall
/// instantly; full cold starts ignore the cooldown.
///
/// Distinct from [PaywallSheet] which is the REACTIVE bottom sheet shown
/// the moment a translation hits 429. This screen is PROACTIVE — it
/// surfaces before the user even tries to translate.
class QuotaExhaustedScreen extends ConsumerStatefulWidget {
  const QuotaExhaustedScreen({super.key});

  /// Dismissed-in-current-foreground flag. Reset by [onAppPaused] when
  /// the app goes to background, so the wall RE-APPEARS on the next
  /// resume / cold start while quota stays exhausted. Once the user
  /// either watches an ad (server credits the reward → usage refresh
  /// → no longer exhausted) or upgrades, the exhausted check itself
  /// returns false and the flag is irrelevant.
  static bool _dismissedThisForeground = false;

  /// True while the wall is on screen. Stops bootstrap + lifecycle-resume
  /// from racing to push two instances when they fire back-to-back.
  static bool _isShowing = false;

  /// Called by [HomeScreen.didChangeAppLifecycleState] on
  /// [AppLifecycleState.paused] — i.e. the app went to background. Clears
  /// the dismissal flag so the next foreground will re-show the wall if
  /// quota is still exhausted.
  static void onAppPaused() {
    _dismissedThisForeground = false;
  }

  /// Decides whether to surface the wall right now. Pure sync check —
  /// caller passes the latest plan + usage snapshot.
  static bool shouldShow({
    required String plan,
    required UsageInfo? usage,
  }) {
    if (_isShowing) return false;
    if (_dismissedThisForeground) return false;
    if (plan != 'free' || usage == null) return false;
    final requestsExhausted = usage.requestsLimit > 0 &&
        usage.requestsUsed >= usage.requestsLimit;
    final charsExhausted = usage.charsLimit > 0 &&
        usage.charsUsed >= usage.charsLimit;
    return requestsExhausted || charsExhausted;
  }

  /// Push the wall as a full-screen modal route. Returns:
  ///   - `true`  if the user watched an ad and the reward was credited
  ///   - `false` if the user dismissed without watching
  ///   - `null`  if the user tapped Upgrade (wall popped before route push)
  static Future<bool?> show(BuildContext context) async {
    if (_isShowing) return false;
    _isShowing = true;
    final result = await Navigator.of(context).push<bool?>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const QuotaExhaustedScreen(),
    ));
    _isShowing = false;
    // Only the explicit-dismiss path should suppress re-showing — when
    // the user actually watched an ad (result == true) usage is now
    // fresh, shouldShow() returns false on its own, so we still set the
    // flag without harm.
    _dismissedThisForeground = true;
    return result;
  }

  @override
  ConsumerState<QuotaExhaustedScreen> createState() =>
      _QuotaExhaustedScreenState();
}

class _QuotaExhaustedScreenState extends ConsumerState<QuotaExhaustedScreen> {
  RewardedAdService? _adService;
  bool _watchingAd = false;
  bool _converted = false;

  @override
  void initState() {
    super.initState();
    final adsEnabled = ref.read(featuresProvider).flags.adsEnabled;
    if (adsEnabled) {
      _adService = RewardedAdService();
      _adService!.preload();
    }
    ref.read(trackingServiceProvider).event('quota_wall_view');
  }

  @override
  void dispose() {
    _adService?.dispose();
    if (!_converted) {
      ref.read(trackingServiceProvider).event('quota_wall_dismiss');
    }
    super.dispose();
  }

  Future<void> _onWatchAd() async {
    final adService = _adService;
    if (adService == null) return;
    final l = AppLocalizations.of(context)!;
    setState(() => _watchingAd = true);
    ref.read(trackingServiceProvider).event('quota_wall_watch_ad_start');

    final earned = await adService.showAndAwaitReward();
    if (!mounted) return;

    if (!earned) {
      setState(() => _watchingAd = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.paywallAdNotComplete)),
      );
      return;
    }

    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/quota/grant-reward');
      await ref.read(usageProvider.notifier).refresh();
      if (!mounted) return;
      _converted = true;
      ref.read(trackingServiceProvider).event('quota_wall_watch_ad_complete',
          properties: {'success': true});
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
    ref.read(trackingServiceProvider).event('quota_wall_upgrade_click');
    _converted = true;
    Navigator.of(context).pop(null);
    context.push('/upgrade');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final usage = ref.watch(usageProvider).valueOrNull;

    return AuroraScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    Center(
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF6366F1).withValues(alpha: 0.15),
                              const Color(0xFFA855F7).withValues(alpha: 0.15),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: ShaderMask(
                          shaderCallback: (b) => const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                          ).createShader(b),
                          child: const Icon(
                            Icons.hourglass_bottom_rounded,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                      ).createShader(b),
                      child: Text(
                        l.quotaWallTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l.quotaWallBody,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (usage != null)
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: AppGlass.card(
                          isDark: isDark,
                          variant: GlassVariant.tint,
                          shadow: false,
                        ),
                        child: Column(
                          children: [
                            _UsageRow(
                              icon: Icons.translate,
                              label: l.usageRequests(
                                  usage.requestsUsed, usage.requestsLimit),
                            ),
                            const SizedBox(height: 8),
                            _UsageRow(
                              icon: Icons.text_fields,
                              label: l.usageCharacters(
                                  usage.charsUsed, usage.charsLimit),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                children: [
                  if (_adService != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1)
                                .withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        height: 56,
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _watchingAd ? null : _onWatchAd,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: _watchingAd
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_circle_outline,
                                  size: 24),
                          label: Text(
                            _watchingAd
                                ? l.paywallLoading
                                : l.quotaWallWatchAdCta,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _onUpgrade,
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: Text(l.quotaWallUpgradeCta),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFF6366F1),
                          width: 1.5,
                        ),
                        foregroundColor: const Color(0xFF6366F1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      l.quotaWallCloseCta,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textSecondary
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.red,
            ),
          ),
        ),
      ],
    );
  }
}
