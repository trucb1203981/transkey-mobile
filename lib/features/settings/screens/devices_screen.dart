import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/devices_provider.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _loadCurrentDeviceId();
  }

  Future<void> _loadCurrentDeviceId() async {
    final id = await ref.read(deviceIdProvider).getFingerprint();
    if (mounted) setState(() => _currentDeviceId = id);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final devicesAsync = ref.watch(devicesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.manageDevices)),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (devices) {
          if (devices.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(l.devicesEmpty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(devicesProvider.notifier).refresh(),
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                  child: Text(
                    l.devicesProLimit,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                ...devices.map((d) => _deviceTile(d, l)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _deviceTile(UserDevice d, AppLocalizations l) {
    final isCurrent = _currentDeviceId == d.deviceId;
    final platformIcon = d.platform == 'mobile'
        ? Icons.phone_iphone
        : Icons.desktop_windows_outlined;
    return ListTile(
      leading: Icon(platformIcon, color: AppColors.primary),
      title: Row(
        children: [
          Flexible(child: Text(d.deviceName ?? d.deviceId)),
          if (isCurrent) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l.deviceCurrentThis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        l.deviceLastUsed(_formatDate(d.lastUsedAt)),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: TextButton(
        onPressed: () => _confirmRemove(d, l),
        style:
            TextButton.styleFrom(foregroundColor: AppColors.red),
        child: Text(l.removeDevice),
      ),
    );
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _confirmRemove(UserDevice d, AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeDevice),
        content: Text(l.removeDeviceConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: Text(l.removeDevice),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final success =
        await ref.read(devicesProvider.notifier).remove(d.deviceId);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.removeDeviceFailed),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }
}
