import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bubble/bubble_manager.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/setup_status_provider.dart';
import '../widgets/setup_pieces.dart';
import '../widgets/system_screen_mock.dart';
import '../../../shared/widgets/glass/glass_app_bar.dart';

/// The two things a user has to switch on outside the app.
enum SetupTask { button, keyboard }

/// One task, one screen, three phases: show what is coming, send the user to
/// the system screen, then say plainly whether it worked.
///
/// The screen deliberately STAYS mounted while the user is away in system
/// settings, so a back press lands them on the instructions they were following
/// rather than on a fresh prompt. Everything after that is driven by the real
/// platform state read in [setupStatusProvider], never by assuming the user
/// did what we asked: the old wizard congratulated people who had done nothing.
class SetupTaskScreen extends ConsumerStatefulWidget {
  const SetupTaskScreen({super.key, required this.task});

  final SetupTask task;

  @override
  ConsumerState<SetupTaskScreen> createState() => _SetupTaskScreenState();
}

class _SetupTaskScreenState extends ConsumerState<SetupTaskScreen>
    with WidgetsBindingObserver {
  static const _bubbleChannel = MethodChannel('transkey/bubble');
  static const _imeChannel = MethodChannel('transkey/ime');
  static const _appGroupChannel = MethodChannel('transkey/appgroup');

  /// True once the user has been sent to system settings at least once, which
  /// is what turns "not done" from a neutral starting state into a retry.
  bool _returned = false;
  bool _pickerUnavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Permission already granted but the button is not showing: the user asked
    // for the button, so just turn it on rather than walking them through a
    // settings trip they have already made.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The grant can land a moment after the activity comes back on some ROMs,
    // so re-read once immediately and once shortly after.
    _recheck();
    Future.delayed(const Duration(milliseconds: 700), _recheck);
  }

  Future<void> _recheck() async {
    if (!mounted) return;
    await ref.read(setupStatusProvider.notifier).refresh();
    if (!mounted) return;
    // Granting the permission does not start the button; do that for the user
    // rather than making them find a second toggle.
    final status = ref.read(setupStatusProvider).value;
    if (widget.task == SetupTask.button && status?.button == SetupStep.partial) {
      await ref.read(bubbleManagerProvider.notifier).startBubble(source: 'setup');
      if (mounted) await ref.read(setupStatusProvider.notifier).refresh();
    }
  }

  /// Whether the platform lets us confirm this task at all.
  bool get _canVerify =>
      Platform.isAndroid || widget.task == SetupTask.button;

  SetupStep _stepOf(SetupStatus? status) => switch (widget.task) {
        SetupTask.button => status?.button ?? SetupStep.missing,
        SetupTask.keyboard => status?.keyboard ?? SetupStep.missing,
      };

  Future<void> _openSystemScreen() async {
    setState(() => _returned = true);
    try {
      if (widget.task == SetupTask.button) {
        await _bubbleChannel.invokeMethod('requestPermission');
      } else if (Platform.isAndroid) {
        await _imeChannel.invokeMethod('openImeSettings');
      } else {
        await _appGroupChannel.invokeMethod('openKeyboardSettings');
      }
    } on PlatformException {
      // A ROM with no such screen. The native side already fell back to the
      // app-info page where it could; nothing useful to add here.
    } on MissingPluginException {
      // Channel not attached (pre-warmed engine). Retry is one tap away.
    }
  }

  /// Second half of the keyboard task: raise the system keyboard chooser over
  /// our own screen, so switching costs no second trip into settings.
  Future<void> _pickKeyboard() async {
    bool shown = false;
    try {
      shown = await _imeChannel.invokeMethod<bool>('showImePicker') ?? false;
    } on PlatformException {
      shown = false;
    } on MissingPluginException {
      shown = false;
    }
    if (!shown && mounted) setState(() => _pickerUnavailable = true);
    // The picker resolves before the user chooses, so the answer comes from the
    // resume re-check, not from here.
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final status = ref.watch(setupStatusProvider).value;
    final step = _stepOf(status);
    final isButton = widget.task == SetupTask.button;

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(isButton ? t.setupTaskButtonTitle : t.setupTaskKeyboardTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            if (step == SetupStep.done)
              _successBody(t)
            else if (widget.task == SetupTask.keyboard && step == SetupStep.partial)
              ..._pickBody(t)
            else ...[
              // No "it did not work" on the iOS keyboard: the platform gives us
              // no way to know, and telling someone they failed when we cannot
              // see is worse than saying nothing.
              if (_returned && _canVerify) _retryBody(t),
              ..._previewBody(t),
            ],
          ],
        ),
      ),
    );
  }

  // ---- phase 1: what you are about to see -------------------------------

  List<Widget> _previewBody(AppLocalizations t) {
    final isButton = widget.task == SetupTask.button;
    if (!isButton && Platform.isIOS) return _iosKeyboardBody(t);
    return [
      Text(
        isButton ? t.setupButtonWhy : t.setupKeyboardWhy,
        style: const TextStyle(fontSize: 17, height: 1.45),
      ),
      const SizedBox(height: 20),
      SystemScreenMock(
        screenTitle: isButton ? t.setupMockAppsTitle : t.setupMockKeyboardsTitle,
        rows: isButton ? _appListRows() : _keyboardListRows(),
        footnote: isButton ? t.setupButtonListHint : t.setupKeyboardListHint,
      ),
      const SizedBox(height: 22),
      if (isButton) ...[
        NumberedStep(number: 1, text: t.setupButtonStep1),
        NumberedStep(number: 2, text: t.setupButtonStep2),
        NumberedStep(number: 3, text: t.setupButtonStep3),
      ] else ...[
        NumberedStep(number: 1, text: t.setupKeyboardStep1),
        NumberedStep(number: 2, text: t.setupKeyboardStep2),
        const SizedBox(height: 4),
        SetupNoteCard(text: t.setupKeyboardWarning),
      ],
      const SizedBox(height: 24),
      _primaryButton(t.setupOpenSystemSettings, _openSystemScreen),
      const SizedBox(height: 10),
      _reassurance(t),
    ];
  }

  /// The apps list the Android permission screen shows. Neighbours are real,
  /// boring app names so the picture reads as the alphabetical list it is.
  ///
  /// Both target labels are literals, NOT localized strings: they must match
  /// what the system screen actually prints, and the system prints the app's
  /// own launcher label and `ime_service_label`, which are the same in every
  /// language. Showing a translated name here would send the user hunting for
  /// a row that does not exist.
  List<MockRow> _appListRows() => const [
        MockRow('Camera', icon: Icons.photo_camera_outlined, trailing: MockTrailing.chevron),
        MockRow('Chrome', icon: Icons.public, trailing: MockTrailing.chevron),
        MockRow.target('TransKey', trailing: MockTrailing.toggleOff),
        MockRow('YouTube', icon: Icons.play_circle_outline, trailing: MockTrailing.chevron),
      ];

  List<MockRow> _keyboardListRows() => const [
        MockRow('Gboard', icon: Icons.keyboard_alt_outlined, trailing: MockTrailing.toggleOn),
        MockRow.target('TransKey Keyboard', trailing: MockTrailing.toggleOff),
      ];

  // ---- iOS: no status API, so no promises -------------------------------

  List<Widget> _iosKeyboardBody(AppLocalizations t) => [
        Text(t.setupKeyboardWhy, style: const TextStyle(fontSize: 17, height: 1.45)),
        const SizedBox(height: 20),
        NumberedStep(number: 1, text: t.setupIosStep1),
        NumberedStep(number: 2, text: t.setupIosStep2),
        NumberedStep(number: 3, text: t.setupIosStep3),
        NumberedStep(number: 4, text: t.setupIosStep4),
        const SizedBox(height: 8),
        SetupNoteCard(text: t.setupIosFullAccessNote, icon: Icons.lock_outline),
        const SizedBox(height: 24),
        _primaryButton(t.setupOpenSystemSettings, _openSystemScreen),
        const SizedBox(height: 10),
        _reassurance(t),
      ];

  // ---- phase 2: back, and it did not take -------------------------------

  Widget _retryBody(AppLocalizations t) {
    // Name the likely blocker instead of repeating the same instruction: the
    // failure is nearly always the same one per task.
    final text = widget.task == SetupTask.keyboard && Platform.isAndroid
        ? t.setupNotYetKeyboardBody
        : t.setupNotYetButtonBody;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.setupNotYetTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(fontSize: 16, height: 1.45)),
        ],
      ),
    );
  }

  // ---- keyboard half two: choose TransKey -------------------------------

  List<Widget> _pickBody(AppLocalizations t) => [
        _bigIcon(Icons.check_circle_rounded, AppColors.green),
        const SizedBox(height: 16),
        Text(
          t.setupKeyboardPickTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          t.setupKeyboardPickBody,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.45),
        ),
        const SizedBox(height: 24),
        _primaryButton(t.setupKeyboardPickAction, _pickKeyboard),
        if (_pickerUnavailable) ...[
          const SizedBox(height: 14),
          SetupNoteCard(text: t.setupKeyboardPickFallback, icon: Icons.info_outline),
        ],
      ];

  // ---- phase 3: done ----------------------------------------------------

  Widget _successBody(AppLocalizations t) => Column(
        children: [
          const SizedBox(height: 12),
          _bigIcon(Icons.check_circle_rounded, AppColors.green),
          const SizedBox(height: 18),
          Text(
            t.setupDoneTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            widget.task == SetupTask.button
                ? t.setupDoneButtonBody
                : t.setupDoneKeyboardBody,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.45),
          ),
          const SizedBox(height: 26),
          _primaryButton(t.setupDoneAction, () {
            if (context.canPop()) context.pop();
          }),
        ],
      );

  // ---- shared bits ------------------------------------------------------

  Widget _bigIcon(IconData icon, Color color) => Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 56, color: color),
        ),
      );

  Widget _primaryButton(String label, VoidCallback onTap) => SizedBox(
        height: 56,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
      );

  /// Nobody should feel they broke something by not finishing.
  Widget _reassurance(AppLocalizations t) => Text(
        t.setupNoWorries,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
      );
}
