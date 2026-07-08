import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/generated/app_localizations.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/bubble/bubble_manager.dart';
import '../../../core/locale/locale_provider.dart';
import '../../../core/tracking/tracking_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/option_picker_sheet.dart';
import '../../../shared/widgets/plan_status_banner.dart';
import '../../translate/models/language.dart';
import '../../translate/providers/language_settings_provider.dart';
import '../../translate/services/tts_service.dart';
import '../../translate/widgets/language_picker_sheet.dart';
import '../providers/app_settings_provider.dart';
import '../widgets/account_section.dart';
import '../widgets/feedback_sheet.dart';

// Picker-visible app UI languages. ARB files exist for 14 locales (en, vi,
// zh, ja, ko, fr, de, es + pt, it, ru, th, id, ar) but we surface only the
// 11 we've spot-checked enough to be confident the translations aren't
// confusing. it / th / id stay disabled in the picker until reviewed —
// their ARB files are kept so the app still localises correctly if a user
// forces those languages via system locale.
const _appLangOptions = [
  ('en', 'English'),
  ('vi', 'Tiếng Việt'),
  ('zh', '中文'),
  ('ja', '日本語'),
  ('ko', '한국어'),
  ('fr', 'Français'),
  ('de', 'Deutsch'),
  ('es', 'Español'),
  ('pt', 'Português'),
  ('ru', 'Русский'),
  ('ar', 'العربية'),
];

// _replyLangOptions used to be a hard-coded 8-language list, which silently
// truncated the picker even when /features advertised ~130 languages. We
// now build the option list at picker-open time from the dynamic catalog
// — see [_SettingsScreenState._replyLangCodes].

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  String _version = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-poll bubble running state on resume. Bubble state is primarily
    // driven by BubbleService's bubbleStateChanged broadcast, but aggressive
    // OEM battery managers (Xiaomi MIUI especially) can force-kill the
    // foreground service before stopBubble() reaches notifyFlutterBubbleState
    // — the broadcast never fires and the toggle stays stale at ON.
    // Re-polling isRunning() native side on resume converges the UI even when
    // the broadcast was lost.
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _refreshBubbleState();
    }
  }

  Future<void> _refreshBubbleState() async {
    final notifier = ref.read(bubbleManagerProvider.notifier);
    final running = await notifier.isRunning();
    if (!mounted) return;
    notifier.syncState(running);
  }

  Future<void> _init() async {
    final info = await PackageInfo.fromPlatform();
    if (Platform.isAndroid) {
      // Defensive re-poll: covers the case where the user enters Settings
      // WITHOUT triggering a lifecycle resume (e.g., navigates directly from
      // another in-app screen after an OEM-killed bubble that never broadcast
      // its state change).
      unawaited(_refreshBubbleState());
    }
    if (mounted) {
      setState(() {
        _version = '${info.version} (${info.buildNumber})';
      });
    }
  }

  String _toneLabel(String value, AppLocalizations t) {
    return switch (value) {
      'business' => t.toneBusiness,
      'casual' => t.toneCasual,
      'formal' => t.toneFormal,
      'polite' => t.tonePolite,
      'technical' => t.toneTechnical,
      'neutral' => t.toneNeutral,
      _ => t.toneAuto,
    };
  }

  String _replyToneLabel(String value, AppLocalizations t) {
    if (value.isEmpty) return t.toneReplySameAsTranslate;
    return _toneLabel(value, t);
  }

  String _replyLangLabel(String code, AppLocalizations t) {
    if (code.isEmpty) return t.replyLanguageFromConversation;
    return languageByCode(code).nativeName;
  }


  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final authState = ref.watch(authStateProvider);
    final session = authState.valueOrNull?.session;
    final plan = session?.plan ?? 'free';
    final appLang = ref.watch(localeProvider).valueOrNull?.languageCode ?? 'en';
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    // Driven by BubbleService's bubbleStateChanged broadcast — covers every
    // path that flips the bubble (keyboard-setup auto-start, drag-to-close,
    // notification "Turn off", system restart) without callers having to
    // remember to poll isRunning() after navigation.
    final bubbleRunning = ref.watch(bubbleManagerProvider);

    // Transparent Scaffold — hosted inside Home's IndexedStack, which already
    // paints the aurora (own aurora here = double backdrop + seam at tab bar).
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // Clear the floating glass tab bar (shared from HomeScreen).
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 100,
              ),
              children: [
                if (session != null) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md, AppSpacing.md, 0,
                    ),
                    child: PlanStatusBanner(),
                  ),
                  AccountSection(session: session, plan: plan),
                  // Guests have no account (and Google-only accounts have no
                  // password), so they can't "change" one. Hide it for the guest
                  // session; the Google-no-password case still needs a backend
                  // `hasPassword` flag to gate properly (tracked separately).
                  if (!session.isAnonymous)
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(session.hasPassword
                          ? t.changePassword
                          : t.setPassword),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () =>
                          context.push('/settings/change-password'),
                    ),
                  if (plan == 'pro')
                    ListTile(
                      leading: const Icon(Icons.devices_outlined),
                      title: Text(t.manageDevices),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => context.push('/settings/devices'),
                    ),
                  if (plan == 'pro' || plan == 'mobile')
                    ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: Text(t.manageSubscription),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () =>
                          context.push('/settings/subscription'),
                    ),
                  // Saved dishes from camera "What is this?" — same plan
                  // gate as camera itself (pro / mobile / trial).
                  if (plan == 'pro' || plan == 'mobile' || plan == 'trial')
                    ListTile(
                      leading: const Icon(Icons.bookmark_outline),
                      title: Text(t.phrasebookTitle),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => context.push('/phrasebook'),
                    ),
                ],

                const SizedBox(height: AppSpacing.md),
                _sectionHeader(t.sectionLanguage),
                _langTile(t.targetLanguage, isTarget: true, showAuto: false),
                _langTile(t.sourceLanguage, isTarget: false, showAuto: true),
                _appLangTile(appLang, t),

                const SizedBox(height: AppSpacing.md),
                _sectionHeader(t.sectionTranslation),
                _switchTile(
                  t.saveHistory,
                  settings.historySave,
                  locked: false,
                  onChanged: (v) =>
                      ref.read(appSettingsProvider.notifier).setHistorySave(v),
                ),
                _switchTile(
                  t.romanization,
                  settings.romanization,
                  locked: plan == 'free',
                  onChanged: (v) => ref
                      .read(appSettingsProvider.notifier)
                      .setRomanization(v),
                ),
                _toneTile(plan, t, settings.toneOverride),
                _autoCloseTile(t, settings.autoCloseSeconds),

                const SizedBox(height: AppSpacing.md),
                _sectionHeader(t.sectionAdvanced),
                _replyLangTile(t, plan, settings.replyLang),
                _replyToneTile(t, plan, settings.replyToneOverride),
                _switchTile(
                  t.replySuggestions,
                  settings.replySuggestions,
                  locked: plan == 'free',
                  onChanged: (v) => ref
                      .read(appSettingsProvider.notifier)
                      .setReplySuggestions(v),
                ),

                const SizedBox(height: AppSpacing.md),
                _sectionHeader(t.sectionSpeech),
                _speechSpeedTile(t),

                const SizedBox(height: AppSpacing.md),
                _sectionHeader(t.sectionOther),
                // Single consolidated entry into the dedicated Keyboard
                // Settings screen, which now groups EVERYTHING keyboard-
                // related in one place: floating bubble + the TransKey system
                // keyboard (IME). The standalone bubble block and the separate
                // IME shortcut that used to sit out here were folded into that
                // screen so there is one obvious destination.
                ListTile(
                  leading: const Icon(Icons.keyboard_outlined),
                  title: Text(t.keyboardSettingsTitle),
                  subtitle: Platform.isAndroid
                      ? Text(
                          bubbleRunning ? t.bubbleActive : t.bubbleInactive,
                          style: TextStyle(
                            fontSize: 12,
                            color: bubbleRunning
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push('/settings/keyboard'),
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(t.guideTitle),
                  subtitle: Text(
                    t.guideSubtitle,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => context.push('/settings/guide'),
                ),
                _helpImproveAppTile(t),
                ListTile(
                  leading: const Icon(Icons.feedback_outlined),
                  title: Text(t.sendFeedback),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => FeedbackSheet.show(context),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(t.termsOfService),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => launchUrl(Uri.parse('https://transkey.app/terms')),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(t.privacyPolicy),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => launchUrl(Uri.parse('https://transkey.app/privacy')),
                ),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text(t.openSourceLicenses),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'TransKey',
                    applicationVersion: _version,
                  ),
                ),
                if (_version.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(t.version),
                    subtitle: Text(_version),
                  ),

                // Guests have no real account to delete (App Store 5.1.1(v));
                // the account card already invites them to sign in instead.
                if (session != null && !session.isAnonymous) ...[
                  const SizedBox(height: AppSpacing.md),
                  const DeleteAccountButton(),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  // ── Tiles ──

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

  Widget _langTile(
    String title, {
    required bool isTarget,
    required bool showAuto,
  }) {
    final langs = ref.watch(languageSettingsProvider).valueOrNull;
    final current = isTarget
        ? (langs?.targetLang ?? 'en')
        : (langs?.sourceLang ?? 'auto');
    final lang = languageByCode(current);
    return ListTile(
      title: Text(title),
      subtitle: Text(lang.nativeName),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () async {
        final picked = await LanguagePickerSheet.show(
          context,
          selectedCode: current,
          showAuto: showAuto,
          field: isTarget ? LanguagePickerField.target : LanguagePickerField.source,
        );
        if (picked != null) {
          final notifier = ref.read(languageSettingsProvider.notifier);
          if (isTarget) {
            await notifier.setTargetLang(picked);
          } else {
            await notifier.setSourceLang(picked);
          }
        }
      },
    );
  }

  Widget _appLangTile(String currentCode, AppLocalizations t) {
    final label = _appLangOptions
        .firstWhere((e) => e.$1 == currentCode,
            orElse: () => ('en', 'English'))
        .$2;
    return ListTile(
      title: Text(t.appLanguage),
      subtitle: Text(label),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showAppLangPicker(currentCode, t),
    );
  }

  Future<void> _showAppLangPicker(String current, AppLocalizations t) async {
    final picked = await OptionPickerSheet.show<String>(
      context,
      title: t.appLanguage,
      selectedValue: current,
      options: [
        for (final opt in _appLangOptions)
          PickerOption(value: opt.$1, label: opt.$2),
      ],
    );
    if (picked != null && mounted) {
      await ref.read(localeProvider.notifier).setLocale(picked);
    }
  }

  Widget _switchTile(
    String title,
    bool value, {
    required bool locked,
    required ValueChanged<bool> onChanged,
  }) {
    return Opacity(
      opacity: locked ? 0.5 : 1.0,
      child: ListTile(
        title: Row(
          children: [
            Flexible(child: Text(title)),
            if (locked) ...[
              const SizedBox(width: 4),
              const Icon(Icons.lock_outline,
                  size: 14, color: AppColors.textSecondary),
            ],
          ],
        ),
        trailing: Switch(
          value: locked ? false : value,
          onChanged: locked ? null : onChanged,
        ),
      ),
    );
  }

  /// "Help improve the app" — opt-out of anonymous usage tracking. Stored
  /// in [TrackingService] (persisted in prefs). Default ON (opt-out=false)
  /// so we get data from the silent majority; users who care will toggle.
  /// Crash reporting is intentionally NOT gated by this toggle — it's
  /// strictly technical, contains no user content, and we need it to keep
  /// the app stable.
  Widget _helpImproveAppTile(AppLocalizations t) {
    final optedOut = ref.watch(trackingOptOutProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.insights_outlined),
      title: Text(t.helpImproveApp),
      subtitle: Text(
        t.helpImproveAppHint,
        style: const TextStyle(fontSize: 12),
      ),
      value: !optedOut,
      onChanged: (enabled) async {
        await ref.read(trackingOptOutProvider.notifier).set(!enabled);
      },
    );
  }

  Widget _toneTile(String plan, AppLocalizations t, String current) {
    final isLocked = plan == 'free';
    return Opacity(
      opacity: isLocked ? 0.5 : 1.0,
      child: ListTile(
        title: Row(
          children: [
            Flexible(child: Text(t.toneOverride)),
            if (isLocked) ...[
              const SizedBox(width: 4),
              const Icon(Icons.lock_outline,
                  size: 14, color: AppColors.textSecondary),
            ],
          ],
        ),
        subtitle: Text(_toneLabel(current, t)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: isLocked
            ? null
            : () => _showTonePicker(current, t, isReply: false),
      ),
    );
  }

  Widget _replyToneTile(AppLocalizations t, String plan, String current) {
    final isLocked = plan == 'free';
    return Opacity(
      opacity: isLocked ? 0.5 : 1.0,
      child: ListTile(
        title: Row(
          children: [
            Flexible(child: Text(t.replyToneOverride)),
            if (isLocked) ...[
              const SizedBox(width: 4),
              const Icon(Icons.lock_outline,
                  size: 14, color: AppColors.textSecondary),
            ],
          ],
        ),
        subtitle: Text(_replyToneLabel(current, t)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: isLocked
            ? null
            : () => _showTonePicker(current, t, isReply: true),
      ),
    );
  }

  Widget _replyLangTile(AppLocalizations t, String plan, String current) {
    final isLocked = plan == 'free';
    return Opacity(
      opacity: isLocked ? 0.5 : 1.0,
      child: ListTile(
        title: Row(
          children: [
            Flexible(child: Text(t.replyLanguage)),
            if (isLocked) ...[
              const SizedBox(width: 4),
              const Icon(Icons.lock_outline,
                  size: 14, color: AppColors.textSecondary),
            ],
          ],
        ),
        subtitle: Text(_replyLangLabel(current, t)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: isLocked ? null : () => _showReplyLangPicker(current, t),
      ),
    );
  }

  Widget _speechSpeedTile(AppLocalizations t) {
    final rate = ref.watch(ttsProvider).rate;
    final label = rate == 1.0 ? '1.0× (${t.speedNormal})' : '$rate×';
    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: Text(t.speedPickerTitle),
      subtitle: Text(label),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showSpeedPicker(rate, t),
    );
  }

  Future<void> _showSpeedPicker(double current, AppLocalizations t) async {
    const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75];
    final picked = await OptionPickerSheet.show<double>(
      context,
      title: t.speedPickerTitle,
      selectedValue: current,
      options: [
        for (final s in speeds)
          PickerOption(
            value: s,
            label: s == 1.0 ? '1.0× (${t.speedNormal})' : '$s×',
          ),
      ],
    );
    if (picked != null && mounted) {
      await ref.read(ttsProvider.notifier).setRate(picked);
    }
  }

  Widget _autoCloseTile(AppLocalizations t, int seconds) {
    return ListTile(
      title: Text(t.autoCloseSeconds),
      subtitle: Text(seconds <= 0 ? t.autoCloseDisabled : '$seconds ${t.autoCloseUnit}'),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showAutoClosePicker(seconds, t),
    );
  }

  // Capture-keepalive + bubble-idle tiles moved to KeyboardSettingsScreen
  // (same impls live there) so all bubble knobs sit on one screen.

  Future<void> _showTonePicker(String current, AppLocalizations t,
      {required bool isReply}) async {
    // Reply tone has an extra "Same as translate" option re-using value = '';
    // translate tone uses '' for Auto. Same code, different label.
    final picked = await OptionPickerSheet.show<String>(
      context,
      title: isReply ? t.replyToneOverride : t.toneOverride,
      selectedValue: current,
      options: [
        for (final opt in toneOptions)
          PickerOption(
            value: opt.$1,
            label: isReply && opt.$1.isEmpty
                ? t.toneReplySameAsTranslate
                : _toneLabel(opt.$1, t),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    final notifier = ref.read(appSettingsProvider.notifier);
    if (isReply) {
      await notifier.setReplyToneOverride(picked);
    } else {
      await notifier.setToneOverride(picked);
    }
  }

  void _showReplyLangPicker(String current, AppLocalizations t) async {
    // Reuse LanguagePickerSheet for consistency with source/target pickers:
    // gives search, recents, the full dynamic catalogue (~130 langs) and the
    // synthetic "From conversation" tile pinned at top via
    // field: LanguagePickerField.reply.
    final code = await LanguagePickerSheet.show(
      context,
      selectedCode: current,
      showAuto: false,
      field: LanguagePickerField.reply,
    );
    if (code == null) return;
    await ref.read(appSettingsProvider.notifier).setReplyLang(code);
  }

  Future<void> _showAutoClosePicker(int current, AppLocalizations t) async {
    const options = [0, 5, 10, 15, 30, 60];
    final picked = await OptionPickerSheet.show<int>(
      context,
      title: t.autoCloseSeconds,
      selectedValue: current,
      options: [
        for (final secs in options)
          PickerOption(
            value: secs,
            label: secs == 0 ? t.autoCloseDisabled : '$secs ${t.autoCloseUnit}',
          ),
      ],
    );
    if (picked != null && mounted) {
      await ref.read(appSettingsProvider.notifier).setAutoCloseSeconds(picked);
    }
  }

}

