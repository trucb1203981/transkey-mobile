import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/bubble/bubble_manager.dart';

/// One-screen permission walkthrough surfaced after login (or via the
/// home-screen banner) so users don't have to figure out the
/// Display-over-other-apps + Accessibility + Android-13-restricted-settings
/// triple by themselves.
///
/// Each row knows how to (a) check its own status via MethodChannel, (b)
/// route the user to the exact Settings screen that grants it, and (c)
/// re-poll when the app resumes so green ticks appear without manual
/// refresh. "Skip" persists a flag so we don't nag every cold start —
/// the home-screen banner is the long-term reminder for the un-skipped
/// case.
class AccessibilitySetupScreen extends ConsumerStatefulWidget {
  const AccessibilitySetupScreen({super.key});

  static const _skipKey = 'tk_accessibility_setup_skipped';

  static Future<bool> wasSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_skipKey) ?? false;
  }

  static Future<void> markSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skipKey, true);
  }

  static Future<void> clearSkip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_skipKey);
  }

  @override
  ConsumerState<AccessibilitySetupScreen> createState() =>
      _AccessibilitySetupScreenState();
}

class _AccessibilitySetupScreenState
    extends ConsumerState<AccessibilitySetupScreen>
    with WidgetsBindingObserver {
  bool _hasOverlay = false;
  bool _hasAccessibility = false;
  // Best-effort: Android 13+ only. On older Android we treat it as
  // implicitly satisfied so the row hides itself.
  bool _restrictedUnlocked = true;
  bool _androidThirteenPlus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectAndroidVersion();
    _refreshStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User went to Settings, came back — re-poll so the row that they
    // just unlocked turns green without them having to leave / re-enter
    // the screen.
    if (state == AppLifecycleState.resumed) _refreshStatuses();
  }

  Future<void> _detectAndroidVersion() async {
    if (!Platform.isAndroid) return;
    try {
      // Cheapest way to get API level without pulling in another package:
      // ask the bubble channel for it. The native side gates A13+ logic
      // on Build.VERSION.SDK_INT >= TIRAMISU (33) anyway, so an absent
      // method here can safely default to "not A13+".
      final apiLevel = await const MethodChannel('transkey/bubble')
          .invokeMethod<int>('androidSdkInt');
      if (mounted && apiLevel != null) {
        setState(() {
          _androidThirteenPlus = apiLevel >= 33;
          // On A13+ we don't have a reliable cross-OEM API to check
          // restricted-settings state, so leave the row visible but
          // optional: completion is judged solely by whether
          // Accessibility actually turned on (it can't, if restricted
          // is still locked).
          _restrictedUnlocked = !_androidThirteenPlus;
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshStatuses() async {
    if (!Platform.isAndroid) return;
    final manager = ref.read(bubbleManagerProvider.notifier);
    final overlay = await manager.checkPermission();
    final a11y = await manager.checkAccessibility();
    if (!mounted) return;
    setState(() {
      _hasOverlay = overlay;
      _hasAccessibility = a11y;
      // If Accessibility is on, the restricted-settings gate must have
      // been cleared (or didn't apply). Mark it done so the row stops
      // pulsing.
      if (a11y) _restrictedUnlocked = true;
    });
  }

  bool get _allDone =>
      _hasOverlay && _hasAccessibility && _restrictedUnlocked;

  Future<void> _skip() async {
    await AccessibilitySetupScreen.markSkipped();
    if (mounted) context.pop();
  }

  Future<void> _done() async {
    // No skip flag — user actually finished. If they re-enter the screen
    // later (e.g. accidentally disabled a permission) we want to show it
    // again without the "skipped" stigma.
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Set up TransKey',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Grant a few permissions so TransKey can translate anywhere — without copy/paste.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _PermissionCard(
                      step: 1,
                      icon: Icons.layers_outlined,
                      title: 'Floating bubble',
                      body:
                          'Show TransKey over other apps. Required for the bubble to appear.',
                      done: _hasOverlay,
                      actionLabel: _hasOverlay ? 'Enabled' : 'Enable',
                      onAction: _hasOverlay
                          ? null
                          : () async {
                              await ref
                                  .read(bubbleManagerProvider.notifier)
                                  .requestPermission();
                            },
                    ),
                    if (_androidThirteenPlus) ...[
                      const SizedBox(height: 12),
                      _PermissionCard(
                        step: 2,
                        icon: Icons.lock_open_outlined,
                        title: 'Allow restricted settings',
                        body:
                            'Android 13+ blocks sideloaded apps from Accessibility by default. Tap ⋮ at the top-right → "Allow restricted settings".',
                        done: _hasAccessibility,
                        actionLabel:
                            _hasAccessibility ? 'Done' : 'Open app details',
                        onAction: _hasAccessibility
                            ? null
                            : () async {
                                await ref
                                    .read(bubbleManagerProvider.notifier)
                                    .openAppDetails();
                              },
                      ),
                    ],
                    const SizedBox(height: 12),
                    _PermissionCard(
                      step: _androidThirteenPlus ? 3 : 2,
                      icon: Icons.accessibility_new_outlined,
                      title: 'Accessibility',
                      body:
                          'Lets TransKey read highlighted text without you copying it first. Find TransKey in the list → toggle ON → Allow.',
                      done: _hasAccessibility,
                      actionLabel: _hasAccessibility ? 'Enabled' : 'Enable',
                      onAction: _hasAccessibility
                          ? null
                          : () async {
                              await ref
                                  .read(bubbleManagerProvider.notifier)
                                  .requestAccessibility();
                            },
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Don\'t want to grant Accessibility? You can skip — but you\'ll have to Copy text before tapping the bubble each time.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _skip,
                      child: const Text('Skip for now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _allDone ? _done : _refreshStatuses,
                      child: Text(_allDone ? 'Done' : 'I\'ve finished — check'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final int step;
  final IconData icon;
  final String title;
  final String body;
  final bool done;
  final String actionLabel;
  final VoidCallback? onAction;

  const _PermissionCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.body,
    required this.done,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done
              ? Colors.green.withValues(alpha: 0.6)
              : cs.outlineVariant,
          width: done ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: done
                  ? Colors.green.withValues(alpha: 0.12)
                  : cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              done ? Icons.check : icon,
              color: done ? Colors.green : cs.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Step $step',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.55),
                            letterSpacing: 0.6,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(actionLabel,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
