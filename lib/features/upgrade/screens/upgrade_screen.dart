import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final plan = _currentPlan;

    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade TransKey')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose your plan',
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Unlock the full power of TransKey',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Plan cards ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _planCard('FREE', '\$0', null, plan == 'free', isDark,
                  isCurrent: plan == 'free',
                  highlight: false,
                  features: const ['Translate', '20 req/day', '2000 chars/day', 'Glossary'],
                )),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _planCard('📱 MOBILE', '\$3/mo', 'Popular', plan != 'free', isDark,
                  isCurrent: plan == 'mobile',
                  highlight: true,
                  features: const ['All features', 'iOS & Android', 'Unlimited'],
                )),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _planCard('⭐ PRO', '\$6/mo', null, plan == 'pro', isDark,
                  isCurrent: plan == 'pro',
                  highlight: false,
                  isGold: true,
                  features: const ['All features', 'All platforms', 'Desktop + Mobile'],
                )),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Feature comparison ──
            _buildComparisonTable(theme, isDark),
            const SizedBox(height: AppSpacing.xl),

            // ── Action buttons ──
            if (plan == 'free') ...[
              _actionButton(
                label: 'Try free for 7 days',
                onPressed: () => _activateTrial(),
                isSecondary: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      label: '📱 Mobile · \$3/mo',
                      onPressed: () => _checkout('mobile'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _actionButton(
                      label: '💻 Pro · \$6/mo',
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
                      label: '📱 Mobile · \$3/mo',
                      onPressed: () => _checkout('mobile'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _actionButton(
                      label: '💻 Pro · \$6/mo',
                      onPressed: () => _checkout('pro'),
                      isGold: true,
                    ),
                  ),
                ],
              ),
            ] else if (plan == 'mobile') ...[
              _actionButton(
                label: '💻 Upgrade to Pro · \$6/mo',
                onPressed: () => _checkout('pro'),
                isGold: true,
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            Text(
              '📱 Mobile: best value if you only use your phone\n💻 Pro: works on both phone and desktop',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
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
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
          color: isCurrent
              ? accentColor
              : (isDark ? AppColors.border : AppColors.borderLight),
          width: isCurrent ? 2 : 1,
        ),
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
                'Current',
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

  Widget _buildComparisonTable(ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: isDark ? AppColors.border : AppColors.borderLight),
      ),
      child: Column(
        children: [
          _tableHeader(isDark),
          const Divider(height: 1),
          _tableRow('Translate', true, true, true, isDark),
          _tableRow('Summarize', false, true, true, isDark),
          _tableRow('Explain', false, true, true, isDark),
          _tableRow('Refine', false, true, true, isDark),
          _tableRow('Reply translate', false, true, true, isDark),
          _tableRow('Romanization', false, true, true, isDark),
          _tableRow('Glossary', true, true, true, isDark),
          _tableRow('📱 iOS & Android', true, true, true, isDark),
          _tableRow('💻 Desktop', false, false, true, isDark, highlight: true),
        ],
      ),
    );
  }

  Widget _tableHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Feature', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          Expanded(child: Text('Free', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
          Expanded(child: Text('Mobile', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
          Expanded(child: Text('Pro', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
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
              style: ElevatedButton.styleFrom(backgroundColor: color),
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
    return Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600));
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Trial activated! ${data['trialEndsAt'] ?? '7 days remaining'}'),
              backgroundColor: AppColors.green,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to activate trial'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkout(String plan) async {
    setState(() => _isLoading = true);
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
          const SnackBar(content: Text('Failed to open checkout'), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
