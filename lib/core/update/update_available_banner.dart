import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../tracking/tracking_provider.dart';
import 'app_update_provider.dart';

/// Home-screen notice that the store has a newer build. Tap opens the store
/// page; the close button hides it until an even newer build ships.
class UpdateAvailableBanner extends ConsumerWidget {
  const UpdateAvailableBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(appUpdateProvider).value;
    if (update == null) return const SizedBox.shrink();

    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openStore(ref, update),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.system_update_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t.updateBannerTitle,
                    style: const TextStyle(fontSize: 14.5, height: 1.3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  t.updateBannerAction,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => dismissStoreUpdate(ref, update),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openStore(WidgetRef ref, StoreUpdate update) async {
    ref.read(trackingServiceProvider).event('app_update_click',
        properties: {'platform': Platform.operatingSystem, 'to': update.id});
    try {
      // Opens the store app; a browser if the store app is missing.
      await launchUrl(update.storeUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[AppUpdate] open store failed: $e');
    }
  }
}
