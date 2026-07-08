import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/tracking/tracking_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_glass.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/glass/aurora_scaffold.dart';
import '../checkout_flow.dart';
import '../providers/plans_provider.dart';
import '../providers/usage_provider.dart';
import '../services/purchases_service.dart';

class UpgradeScreen extends ConsumerStatefulWidget {
  const UpgradeScreen({super.key});

  @override
  ConsumerState<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends ConsumerState<UpgradeScreen> {
  bool _isLoading = false;

  String get _currentPlan {
    final auth = ref.read(authStateProvider).valueOrNull;
    return auth?.session?.plan ?? 'free';
  }

  @override
  void initState() {
    super.initState();
    ref.read(trackingServiceProvider).event('upgrade_view', properties: {
      'source':       'screen',
      'current_plan': _currentPlan,
    });
    // The plans catalog (prices, feature flags, highlights) is cached for the
    // whole app session by the non-autoDispose plansProvider, so a price
    // change made on the server AFTER the first fetch wouldn't appear until a
    // full app restart. Re-fetch on every screen open so the cards + CTAs
    // always reflect the current /plans (mirrors desktop swapping
    // features:get -> features:refresh for the same stale-cache reason).
    ref.read(plansProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final plan = _currentPlan;
    final l = AppLocalizations.of(context)!;
    final usage = ref.watch(usageProvider).valueOrNull;
    final plansAsync = ref.watch(plansProvider);
    // Show the 7-day-trial CTA only when (a) the user hasn't used it yet
    // AND (b) the server actually returns a `trial` plan in /plans for
    // this platform. Trial is desktop-only by business rule (anti-abuse:
    // tourists activating 7-day trial then dropping the app), so on
    // mobile the trial plan is filtered out by PlatformGuard → the CTA
    // should hide too. Pure catalog-driven gate; no hardcoded platform
    // check on the client.
    final hasTrialPlan = plansAsync.valueOrNull?.any((p) => p.plan == 'trial') ?? false;
    final canActivateTrial = hasTrialPlan && !(usage?.trialUsed ?? false);
    // First-month half-price discount: badge on the Pro card + appended to
    // the checkout button so the price is honest. The discount is a
    // LemonSqueezy coupon applied only on the web checkout (/auth/checkout);
    // when RevenueCat is ready the purchase goes through Apple/Play IAP, which
    // CANNOT apply that coupon — so showing the badge there would advertise a
    // discount the IAP can't deliver (misleading + an App Store 3.1.1 risk).
    // Only show it when checkout will actually take the LemonSqueezy path.
    final hasDiscount =
        (usage?.firstMonthDiscount ?? false) && !PurchasesService.isReady;

    // Server is the source of truth for prices, feature lists, and limits.
    // Fall back to a sensible default while the request is in flight or if
    // it fails — the user can still see the comparison and proceed to
    // checkout, but with cached values that may be slightly stale.
    final plans = plansAsync.valueOrNull;
    final mobilePlan = planByKey(plans, 'mobile');
    final proPlan = planByKey(plans, 'pro');
    final freePlan = planByKey(plans, 'free');
    final mobilePrice = mobilePlan?.priceMonthly;
    final proPrice = proPlan?.priceMonthly;

    // Prefer the exact store-charged monthly price (localized currency) from
    // RevenueCat over the server's USD reference price, so cards + CTAs match
    // what Apple / Play actually bills. Falls back to the server price when RC
    // isn't ready or the product is missing.
    final storePrices =
        ref.watch(storeMonthlyPricesProvider).valueOrNull ?? const <String, String>{};
    String displayPrice(String planKey, num? serverPrice) {
      final sp = storePrices[planKey];
      return sp != null ? '$sp/mo' : _formatPrice(serverPrice);
    }

    return AuroraScaffold(
      appBar: AppBar(title: Text(l.upgradeScreenTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
              ).createShader(bounds),
              child: Text(
                l.upgradeChooseYourPlan,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.upgradeUnlockFullPower,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Plan cards ──
            // Loading state — render skeleton-equivalent so users on slow
            // networks don't see "no plans" briefly.
            if (plans == null && plansAsync.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _planCard(
                    (freePlan?.displayName ?? l.planFree).toUpperCase(),
                    _formatPrice(freePlan?.priceMonthly),
                    null,
                    plan == 'free',
                    isDark,
                    isCurrent: plan == 'free',
                    highlight: false,
                    features: _featuresFor(freePlan, l, [
                      l.upgradeFreeFeat1,
                      l.upgradeFreeFeat2,
                      l.upgradeFreeFeat3,
                      l.upgradeFreeFeat4,
                    ]),
                  )),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _planCard(
                    '📱 ${(mobilePlan?.displayName ?? l.planMobile).toUpperCase()}',
                    displayPrice('mobile', mobilePrice),
                    l.upgradePopularBadge,
                    plan != 'free',
                    isDark,
                    isCurrent: plan == 'mobile',
                    highlight: true,
                    features: _featuresFor(mobilePlan, l, [
                      l.upgradeMobileFeat1,
                      l.upgradeMobileFeat2,
                      l.upgradeMobileFeat3,
                    ]),
                  )),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _planCard(
                    '⭐ ${(proPlan?.displayName ?? l.planPro).toUpperCase()}',
                    displayPrice('pro', proPrice),
                    hasDiscount ? l.discountFirstMonth : null,
                    plan == 'pro',
                    isDark,
                    isCurrent: plan == 'pro',
                    highlight: false,
                    isGold: true,
                    features: _featuresFor(proPlan, l, [
                      l.upgradeProFeat1,
                      l.upgradeProFeat2,
                      l.upgradeProFeat3,
                    ]),
                  )),
                ],
              ),
            const SizedBox(height: AppSpacing.xl),

            // ── Feature comparison ──
            _buildComparisonTable(theme, isDark, l, plans),
            const SizedBox(height: AppSpacing.xl),

            // ── Action buttons ──
            // Labels include the current price pulled from /plans so the CTA
            // never mismatches the plan card above (e.g. if the team runs a
            // pricing experiment server-side).
            if (plan == 'free') ...[
              if (canActivateTrial) ...[
                _actionButton(
                  label: l.upgradeTryFreeDays,
                  onPressed: () => _activateTrial(),
                  isSecondary: true,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: '📱 ${mobilePlan?.displayName ?? l.planMobile} · ${displayPrice('mobile', mobilePrice)}',
                      onPressed: () => _checkout('mobile'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _actionButton(
                      label: '💻 ${proPlan?.displayName ?? l.planPro} · ${displayPrice('pro', proPrice)}',
                      onPressed: () => _checkout('pro'),
                      isGold: true,
                    ),
                  ),
                ],
              ),
            ] else if (plan == 'trial') ...[
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: '📱 ${mobilePlan?.displayName ?? l.planMobile} · ${displayPrice('mobile', mobilePrice)}',
                      onPressed: () => _checkout('mobile'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _actionButton(
                      label: '💻 ${proPlan?.displayName ?? l.planPro} · ${displayPrice('pro', proPrice)}',
                      onPressed: () => _checkout('pro'),
                      isGold: true,
                    ),
                  ),
                ],
              ),
            ] else if (plan == 'mobile') ...[
              _actionButton(
                label: '💻 ${l.upgradeToPro} · ${displayPrice('pro', proPrice)}',
                onPressed: () => _checkout('pro'),
                isGold: true,
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            Text(
              l.upgradeFooterHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            // Restore button — BOTH the App Store and Google Play require an
            // app with paid subscriptions to offer an explicit "Restore
            // purchases" entry so users returning after a reinstall / device
            // switch can re-link their entitlement without re-paying. Show it
            // on every store-billing surface (iOS + Android via RevenueCat).
            // The web / desktop LemonSqueezy path uses the account itself as
            // the restore mechanism, so it stays hidden there (isReady false).
            if (PurchasesService.isReady) ...[
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: _isLoading ? null : _restorePurchases,
                  child: Text(l.upgradeRestoreButton),
                ),
              ),
              // Auto-renewable subscription disclosure, required AT THE POINT
              // OF PURCHASE by App Store Guideline 3.1.2 (and Google Play):
              // renewal terms + functional links to the Terms of Use (EULA)
              // and Privacy Policy. Omitting this is a common review rejection.
              const SizedBox(height: AppSpacing.md),
              Text(
                l.upgradeSubscriptionTerms,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse('https://transkey.app/terms'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(l.termsOfService),
                  ),
                  const Text('·', style: TextStyle(color: AppColors.textSecondary)),
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse('https://transkey.app/privacy'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(l.privacyPolicy),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  // ── Plan card ──

  Widget _planCard(
    String title,
    String price,
    String? badge,
    bool checkmark,
    bool isDark, {
    bool isCurrent = false,
    bool highlight = false,
    bool isGold = false,
    required List<String> features,
  }) {
    final accentColor = isGold ? AppColors.amber : AppColors.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: AppGlass.card(
        isDark: isDark,
        variant: isGold ? GlassVariant.tint : GlassVariant.normal,
        borderColor: isCurrent ? accentColor : null,
        shadow: false,
      ),
      child: Column(
        children: [
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else
            const SizedBox(height: 18),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isCurrent ? accentColor : null,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            price,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isCurrent ? accentColor : (isDark ? AppColors.textPrimary : AppColors.textPrimaryLight),
            ),
          ),
          if (isCurrent)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                AppLocalizations.of(context)!.upgradeCurrentLabel,
                style: TextStyle(fontSize: 10, color: accentColor, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 8),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.textSecondary : AppColors.textSecondaryLight,
                  ),
                  textAlign: TextAlign.center,
                ),
              )),
        ],
      ),
    );
  }

  // ── Comparison table ──

  Widget _buildComparisonTable(
    ThemeData theme,
    bool isDark,
    AppLocalizations l,
    List<PlanInfo>? plans,
  ) {
    // Pull the features map for each tier — drives the check / X icons.
    // Fall back to hardcoded availability so the table still renders before
    // /plans completes or if the API is down.
    final freeFeat = planByKey(plans, 'free')?.features ?? const {};
    final mobileFeat = planByKey(plans, 'mobile')?.features ?? const {};
    final proFeat = planByKey(plans, 'pro')?.features ?? const {};

    bool has(Map<String, bool> map, String key, bool fallback) =>
        map.containsKey(key) ? (map[key] ?? false) : fallback;

    // Comparison rows: (label, server feature key, fallback availability per
    // tier). The fallback triple kicks in only when /plans hasn't returned
    // a value for that key — once it does, the API wins.
    final rows = [
      (l.translate, 'translate', (true, true, true)),
      (l.summarize, 'summarize', (false, true, true)),
      (l.explain, 'explain', (false, true, true)),
      (l.refine, 'refine', (false, true, true)),
      (l.comparisonReplyTranslate, 'reply', (false, true, true)),
      (l.romanization, 'romanization', (false, true, true)),
      (l.glossary, 'glossary', (true, true, true)),
    ];

    return Container(
      decoration: AppGlass.card(isDark: isDark, shadow: false),
      child: Column(
        children: [
          _tableHeader(isDark, l),
          const Divider(height: 1),
          for (final (label, key, fb) in rows)
            _tableRow(
              label,
              has(freeFeat, key, fb.$1),
              has(mobileFeat, key, fb.$2),
              has(proFeat, key, fb.$3),
              isDark,
            ),
          _tableRow(l.comparisonMobileApps, true, true, true, isDark),
          _tableRow(l.comparisonDesktop, false, false, true, isDark, highlight: true),
        ],
      ),
    );
  }

  Widget _tableHeader(bool isDark, AppLocalizations l) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(l.upgradeFeatureColumn, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          Expanded(child: Text(l.planFree, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
          Expanded(child: Text(l.planMobile, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
          Expanded(child: Text(l.planPro, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _tableRow(String label, bool free, bool mobile, bool pro, bool isDark, {bool highlight = false}) {
    final bg = highlight ? AppColors.primary.withValues(alpha: 0.05) : null;
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
                color: highlight
                    ? AppColors.primary
                    : (isDark ? AppColors.textSecondary : AppColors.textSecondaryLight),
              ),
            ),
          ),
          Expanded(child: _checkIcon(free)),
          Expanded(child: _checkIcon(mobile)),
          Expanded(child: _checkIcon(pro)),
        ],
      ),
    );
  }

  Widget _checkIcon(bool on) {
    return Center(
      child: Icon(
        on ? Icons.check : Icons.close,
        size: 16,
        color: on ? AppColors.green : AppColors.red.withValues(alpha: 0.5),
      ),
    );
  }

  // ── Action button ──

  Widget _actionButton({
    required String label,
    required VoidCallback onPressed,
    bool isSecondary = false,
    bool isGold = false,
  }) {
    final color = isGold ? AppColors.amber : AppColors.primary;
    final isLoadingThis = _isLoading;

    return SizedBox(
      height: 52,
      child: isSecondary
          ? OutlinedButton(
              onPressed: isLoadingThis ? null : onPressed,
              child: _buttonChild(label, color, isLoadingThis),
            )
          : ElevatedButton(
              onPressed: isLoadingThis ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                // Tighten the default horizontal padding so the
                // name + price label has more room before FittedBox
                // has to scale it down on the narrow half-width CTAs.
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: _buttonChild(label, Colors.white, isLoadingThis),
            ),
    );
  }

  Widget _buttonChild(String label, Color color, bool loading) {
    if (loading) {
      return const SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    // Keep the name + price on a SINGLE line: the half-width "Mobile · $x"
    // / "Pro · $x" CTAs are too narrow for the full label, and a plain Text
    // wraps it into an ugly 2-line break. FittedBox scales the text down to
    // fit instead, never up, so full-width buttons keep their normal size.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── Actions ──

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.upgradeTrialActivated(info)),
              backgroundColor: AppColors.green,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.upgradeTrialActivateFailed), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkout(String plan) async {
    setState(() => _isLoading = true);
    try {
      await startPlanCheckout(context, ref, plan);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      await restorePlanPurchases(context, ref);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Render a monthly price label, e.g. `$3/mo`. Prices come from /plans;
  /// when the API hasn't resolved yet OR the plan is missing from the
  /// response, return `…` as a loading placeholder instead of a stale
  /// hardcoded fallback (previously $3 mobile / $6 pro silently lied if
  /// the team raised prices server-side).
  String _formatPrice(num? price) {
    if (price == null) return '…';
    if (price == 0) return '\$0';
    // Trim trailing zeros — `3.0` → `3`, `3.50` → `3.5`.
    final str = price % 1 == 0 ? price.toInt().toString() : price.toString();
    return '\$$str/mo';
  }

  /// Pick highlights to show on a plan card. Prefer the server's curated
  /// `highlights` array; fall back to the i18n defaults so the UI never
  /// renders an empty card before /plans resolves.
  List<String> _featuresFor(
    PlanInfo? plan,
    AppLocalizations l,
    List<String> fallback,
  ) {
    final hl = plan?.highlights;
    if (hl != null && hl.isNotEmpty) return hl;
    return fallback;
  }
}
