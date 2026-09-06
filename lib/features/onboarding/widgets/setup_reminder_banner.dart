import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/setup_status_provider.dart';

/// Quiet home-screen reminder that TransKey is not finished being set up.
///
/// Rendered from live status only, never from a "dismissed" flag: the point is
/// that it disappears by itself the moment the user actually turns things on,
/// and stays reachable until then. It is deliberately not a dialog, not a
/// SnackBar, and not dismissible - a user who is not set up has no working
/// button and no working keyboard, and hiding that from them helps nobody.
class SetupReminderBanner extends ConsumerWidget {
  const SetupReminderBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(setupStatusProvider).value;
    if (status == null || !status.hasWorkLeft) return const SizedBox.shrink();

    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/setup'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.settings_suggest_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.setupBannerTitle,
                    style: const TextStyle(fontSize: 14.5, height: 1.3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  t.setupBannerAction,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
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
