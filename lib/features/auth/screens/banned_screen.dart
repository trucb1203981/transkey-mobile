import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

/// Shown instead of the normal Scaffold when the user's plan is "banned".
/// Without this, a banned user could still navigate the UI while every API
/// call silently returned 403 — confusing and looks like a bug. Full-screen
/// notice + clear paths (contact support, log out) is the honest UX.
class BannedScreen extends ConsumerWidget {
  const BannedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.block,
                  size: 64,
                  color: AppColors.red,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l.accountBannedTitle,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: AppColors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l.accountBannedBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppColors.textSecondary
                        : AppColors.textSecondaryLight,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.mail_outline),
                    label: Text(l.accountBannedContact),
                    onPressed: () => launchUrl(
                      Uri.parse('mailto:support@transkey.app?subject=Account%20suspended'),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () =>
                        ref.read(authStateProvider.notifier).logout(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                    ),
                    child: Text(l.accountBannedLogout),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
