import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/setup_status_provider.dart';
import '../widgets/setup_pieces.dart';
import 'setup_task_screen.dart';
import '../../../shared/widgets/glass/glass_app_bar.dart';

/// The setup home: one row per thing that still has to be turned on, each
/// showing its REAL state and leading to its own short flow.
///
/// This replaces a five-page linear wizard that ran exactly once per install,
/// counted "Skip" as completion, and never checked whether anything worked. A
/// checklist survives being abandoned halfway, which is what actually happens:
/// the user leaves for system settings, gets lost, comes back later. It also
/// disappears on its own once everything is on, so it never becomes a nag.
class SetupHubScreen extends ConsumerStatefulWidget {
  const SetupHubScreen({super.key});

  /// How many times the app has opened this by itself. Used to stop the
  /// automatic prompt after a few launches WITHOUT ever hiding the screen: the
  /// old "seen once, never again" flag meant a single stray tap on Skip removed
  /// the only guidance the user would ever be offered.
  static const _promptCountKey = 'setup_prompt_count';
  static const maxAutoPrompts = 3;

  static Future<int> promptCount() async =>
      (await SharedPreferences.getInstance()).getInt(_promptCountKey) ?? 0;

  static Future<void> notePrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_promptCountKey, (prefs.getInt(_promptCountKey) ?? 0) + 1);
  }

  @override
  ConsumerState<SetupHubScreen> createState() => _SetupHubScreenState();
}

class _SetupHubScreenState extends ConsumerState<SetupHubScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(setupStatusProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final status = ref.watch(setupStatusProvider).value ?? const SetupStatus();

    return Scaffold(
      appBar: GlassAppBar(title: Text(t.setupHubTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              status.allDone ? t.setupHubAllDoneBody : t.setupHubSubtitle,
              style: const TextStyle(fontSize: 16.5, height: 1.45),
            ),
            const SizedBox(height: 22),
            if (status.showButtonTask) ...[
              _taskTile(
                t: t,
                icon: Icons.touch_app_rounded,
                title: t.setupTaskButtonTitle,
                body: t.setupTaskButtonBody,
                step: status.button,
                label: _buttonLabel(t, status.button),
                task: SetupTask.button,
              ),
              const SizedBox(height: 14),
            ],
            _taskTile(
              t: t,
              icon: Icons.keyboard_rounded,
              title: t.setupTaskKeyboardTitle,
              body: t.setupTaskKeyboardBody,
              step: status.keyboard,
              label: _keyboardLabel(t, status.keyboard),
              task: SetupTask.keyboard,
            ),
            const SizedBox(height: 24),
            Text(
              t.setupNoWorries,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buttonLabel(AppLocalizations t, SetupStep step) => switch (step) {
        SetupStep.done => t.setupStateDone,
        SetupStep.partial => t.setupStateButtonPaused,
        _ => t.setupStateOff,
      };

  String _keyboardLabel(AppLocalizations t, SetupStep step) => switch (step) {
        SetupStep.done => t.setupStateDone,
        SetupStep.partial => t.setupStateKeyboardNotUsed,
        SetupStep.unknown => t.setupStateUnknown,
        SetupStep.missing => t.setupStateOff,
      };

  Widget _taskTile({
    required AppLocalizations t,
    required IconData icon,
    required String title,
    required String body,
    required SetupStep step,
    required String label,
    required SetupTask task,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final done = step == SetupStep.done;
    return Material(
      color: dark ? AppColors.surface : AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(
          task == SetupTask.button ? '/setup/button' : '/setup/keyboard',
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: (done ? AppColors.green : AppColors.primary)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon,
                    color: done ? AppColors.green : AppColors.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.35,
                          color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    SetupStepBadge(step: step, label: label),
                  ],
                ),
              ),
              if (!done)
                const Padding(
                  padding: EdgeInsets.only(top: 10, left: 6),
                  child: Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
