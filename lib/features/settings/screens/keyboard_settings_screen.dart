import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bubble/bubble_manager.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/option_picker_sheet.dart';
import '../providers/app_settings_provider.dart';

// Phase 1+2 MVP for the TransKey system IME. The Android side has a
// service registered in AndroidManifest + xml/transkey_ime.xml; this
// channel exposes the 4 operations the settings tile needs.
const _imeChannel = MethodChannel('transkey/ime');

/// Dedicated screen for the TransKey bubble/keyboard configuration. Split
/// out of the main Settings so users can find every bubble-affecting knob
/// in one place instead of scanning the long Settings list. Mirrors the
/// state plumbing (bubble running state via [bubbleManagerProvider],
/// accessibility status re-polled on resume) the main Settings screen
/// owns, so toggles here stay in sync with the global Settings view.
class KeyboardSettingsScreen extends ConsumerStatefulWidget {
  const KeyboardSettingsScreen({super.key});

  @override
  ConsumerState<KeyboardSettingsScreen> createState() =>
      _KeyboardSettingsScreenState();
}

class _KeyboardSettingsScreenState
    extends ConsumerState<KeyboardSettingsScreen>
    with WidgetsBindingObserver {
  bool _accessibilityEnabled = false;
  bool _imeEnabled = false;
  bool _imeSelected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAccessibility();
    _refreshImeStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAccessibility();
      _refreshImeStatus();
    }
  }

  Future<void> _refreshAccessibility() async {
    final notifier = ref.read(bubbleManagerProvider.notifier);
    final granted = await notifier.checkAccessibility();
    if (mounted) setState(() => _accessibilityEnabled = granted);
  }

  Future<void> _refreshImeStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final enabled = await _imeChannel.invokeMethod<bool>('isEnabled');
      final selected = await _imeChannel.invokeMethod<bool>('isSelected');
      if (!mounted) return;
      setState(() {
        _imeEnabled = enabled ?? false;
        _imeSelected = selected ?? false;
      });
    } catch (_) {
      // Older Android / channel error - leave the toggle in its default
      // disabled state; the tile still works as an "open settings" link.
    }
  }

  Future<void> _onImeTileTap() async {
    if (!_imeEnabled) {
      await _imeChannel.invokeMethod('openImeSettings');
    } else {
      // Enabled but not the default - showing the picker lets the user
      // pick TransKey for the current session without leaving the app.
      await _imeChannel.invokeMethod('showImePicker');
    }
    if (mounted) _refreshImeStatus();
  }

  Future<void> _toggleBubble(bool currentlyRunning) async {
    final manager = ref.read(bubbleManagerProvider.notifier);
    if (currentlyRunning) {
      await manager.stopBubble();
      return;
    }
    final hasPermission = await manager.checkPermission();
    if (!hasPermission) {
      if (!mounted) return;
      context.push('/keyboard-setup?skip=false');
      return;
    }
    await manager.startBubble();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final bubbleRunning = ref.watch(bubbleManagerProvider);
    final settings =
        ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.keyboardSettingsTitle),
      ),
      body: ListView(
        children: [
          _sectionHeader(t.keyboardSettingsSectionStatus),
          if (Platform.isAndroid) ...[
            SwitchListTile(
              secondary: const Icon(Icons.bubble_chart_outlined),
              title: Text(t.floatingBubble),
              subtitle: Text(
                bubbleRunning ? t.bubbleActive : t.bubbleInactive,
                style: TextStyle(
                  fontSize: 12,
                  color: bubbleRunning
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ),
              value: bubbleRunning,
              onChanged: (_) async => _toggleBubble(bubbleRunning),
            ),
            ListTile(
              leading: Icon(
                Icons.security_outlined,
                color: _accessibilityEnabled
                    ? AppColors.primary
                    : Colors.orange,
              ),
              title: Text(t.appPermissions),
              subtitle: Text(
                _accessibilityEnabled
                    ? t.permissionsAllSet
                    : t.permissionsNeedSetup,
                style: TextStyle(
                  fontSize: 12,
                  color: _accessibilityEnabled
                      ? AppColors.primary
                      : Colors.orange,
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () async {
                await context.push('/accessibility-setup');
                if (mounted) _refreshAccessibility();
              },
            ),
            ListTile(
              leading: const Icon(Icons.bubble_chart_outlined),
              title: Text(t.bubbleSetup),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => context.push('/keyboard-setup?skip=false'),
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(t.keyboardSetup),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => context.push('/keyboard-setup?skip=false'),
            ),
          ],
          if (Platform.isAndroid) ...[
            const SizedBox(height: AppSpacing.md),
            _sectionHeader(t.imeSectionTitle),
            ListTile(
              leading: Icon(
                Icons.keyboard_alt_outlined,
                color: _imeSelected
                    ? AppColors.primary
                    : (_imeEnabled ? null : Colors.orange),
              ),
              title: Text(t.imeKeyboardTitle),
              subtitle: Text(
                _imeSelected
                    ? t.imeStatusActive
                    : _imeEnabled
                        ? t.imeStatusEnabledNotSelected
                        : t.imeStatusNotEnabled,
                style: TextStyle(
                  fontSize: 12,
                  color: _imeSelected
                      ? AppColors.primary
                      : (_imeEnabled
                          ? AppColors.textSecondary
                          : Colors.orange),
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: _onImeTileTap,
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionHeader(t.keyboardSettingsSectionBehavior),
            _captureKeepaliveTile(t, settings.captureKeepaliveSeconds),
            _bubbleIdleTile(t, settings.bubbleIdleMinutes),
          ],
        ],
      ),
    );
  }

  // ── Tiles & helpers (mirror the SettingsScreen impls so the two
  // screens stay visually consistent and toggling on one is reflected
  // on the other through the same providers) ──

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _captureKeepaliveTile(AppLocalizations t, int seconds) {
    return ListTile(
      leading: const Icon(Icons.screenshot_monitor_outlined),
      title: Text(t.captureKeepaliveTitle),
      subtitle: Text(
        seconds == 0
            ? t.captureKeepaliveOff
            : '${_keepaliveLabel(seconds, t)} · ${t.captureKeepaliveHint}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showCaptureKeepalivePicker(seconds, t),
    );
  }

  String _keepaliveLabel(int seconds, AppLocalizations t) {
    if (seconds == 0) return t.captureKeepaliveOff;
    if (seconds % 60 == 0) {
      final mins = seconds ~/ 60;
      return t.captureKeepaliveMinutes(mins);
    }
    return '$seconds ${t.autoCloseUnit}';
  }

  Future<void> _showCaptureKeepalivePicker(
      int current, AppLocalizations t) async {
    String hintFor(int secs) => secs == 0
        ? t.captureKeepaliveOffHint
        : (secs == captureKeepaliveDefault
            ? t.captureKeepaliveDefaultHint
            : (secs > captureKeepaliveDefault
                ? t.captureKeepaliveLongHint
                : t.captureKeepaliveShortHint));
    final picked = await OptionPickerSheet.show<int>(
      context,
      title: t.captureKeepaliveTitle,
      explanation: t.captureKeepaliveExplain,
      selectedValue: current,
      options: [
        for (final secs in captureKeepaliveOptions)
          PickerOption(
            value: secs,
            label: _keepaliveLabel(secs, t),
            subtitle: hintFor(secs),
          ),
      ],
    );
    if (picked != null && mounted) {
      await ref
          .read(appSettingsProvider.notifier)
          .setCaptureKeepaliveSeconds(picked);
    }
  }

  Widget _bubbleIdleTile(AppLocalizations t, int minutes) {
    return ListTile(
      leading: const Icon(Icons.timer_outlined),
      title: Text(t.bubbleIdleTitle),
      subtitle: Text(
        minutes == 0 ? t.bubbleIdleOff : t.bubbleIdleMinutes(minutes),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showBubbleIdlePicker(minutes, t),
    );
  }

  Future<void> _showBubbleIdlePicker(int current, AppLocalizations t) async {
    final picked = await OptionPickerSheet.show<int>(
      context,
      title: t.bubbleIdleTitle,
      explanation: t.bubbleIdleExplain,
      selectedValue: current,
      options: [
        for (final mins in bubbleIdleOptions)
          PickerOption(
            value: mins,
            label: mins == 0 ? t.bubbleIdleOff : t.bubbleIdleMinutes(mins),
          ),
      ],
    );
    if (picked != null && mounted) {
      await ref
          .read(appSettingsProvider.notifier)
          .setBubbleIdleMinutes(picked);
    }
  }
}
