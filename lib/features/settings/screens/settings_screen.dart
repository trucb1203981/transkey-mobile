import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/generated/app_localizations.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/session_store.dart';
import '../../../core/bubble/bubble_manager.dart';
import '../../../core/locale/locale_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/plan_status_banner.dart';
import '../../../shared/widgets/quota_bar.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../../translate/models/language.dart';
import '../../translate/providers/language_settings_provider.dart';
import '../../translate/services/tts_service.dart';
import '../../translate/widgets/language_picker_sheet.dart';
import '../../upgrade/providers/usage_provider.dart';
import '../providers/app_settings_provider.dart';
import '../widgets/plan_badge.dart';

const _appLangOptions = [
  ('en', 'English'),
  ('vi', 'Tiếng Việt'),
  ('zh', '中文'),
  ('ja', '日本語'),
  ('ko', '한국어'),
  ('fr', 'Français'),
  ('de', 'Deutsch'),
  ('es', 'Español'),
];

const _replyLangOptions = [
  '', // From conversation
  'en',
  'vi',
  'ja',
  'zh',
  'ko',
  'fr',
  'de',
  'es',
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  String _version = '';
  bool _bubbleRunning = false;
  bool _accessibilityEnabled = false;

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
    // Re-poll accessibility/bubble state when user returns from system settings.
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _refreshAndroidPermissions();
    }
  }

  Future<void> _refreshAndroidPermissions() async {
    final notifier = ref.read(bubbleManagerProvider.notifier);
    final running = await notifier.isRunning();
    final accessibility = await notifier.checkAccessibility();
    if (!mounted) return;
    setState(() {
      _bubbleRunning = running;
      _accessibilityEnabled = accessibility;
    });
  }

  Future<void> _init() async {
    final info = await PackageInfo.fromPlatform();
    if (Platform.isAndroid) {
      final notifier = ref.read(bubbleManagerProvider.notifier);
      _bubbleRunning = await notifier.isRunning();
      _accessibilityEnabled = await notifier.checkAccessibility();
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final session = authState.valueOrNull?.session;
    final plan = session?.plan ?? 'free';
    final appLang = ref.watch(localeProvider).valueOrNull?.languageCode ?? 'en';
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (session != null) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md, AppSpacing.md, 0,
                    ),
                    child: PlanStatusBanner(),
                  ),
                  _buildAccountSection(theme, isDark, session, plan, t),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(t.changePassword),
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
                if (Platform.isAndroid) ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.bubble_chart_outlined),
                    title: Text(t.floatingBubble),
                    subtitle: Text(
                      _bubbleRunning ? t.bubbleActive : t.bubbleInactive,
                      style: TextStyle(
                        fontSize: 12,
                        color: _bubbleRunning
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    value: _bubbleRunning,
                    onChanged: (_) async => _toggleBubble(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.bubble_chart_outlined),
                    title: Text(t.bubbleSetup),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () async {
                      await context.push('/keyboard-setup?skip=false');
                      if (mounted) {
                        final running = await ref
                            .read(bubbleManagerProvider.notifier)
                            .isRunning();
                        setState(() => _bubbleRunning = running);
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.accessibility_new,
                      color: _accessibilityEnabled
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    title: Text(t.accessibilityPasteBack),
                    subtitle: Text(
                      _accessibilityEnabled
                          ? t.accessibilityEnabled
                          : t.accessibilityDisabled,
                      style: TextStyle(
                        fontSize: 12,
                        color: _accessibilityEnabled
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => ref
                        .read(bubbleManagerProvider.notifier)
                        .requestAccessibility(),
                  ),
                ] else ...[
                  ListTile(
                    leading: const Icon(Icons.keyboard_outlined),
                    title: Text(t.keyboardSetup),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => context.push('/keyboard-setup?skip=false'),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.feedback_outlined),
                  title: Text(t.sendFeedback),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _showFeedbackSheet(context, t),
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
                if (_version.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(t.version),
                    subtitle: Text(_version),
                  ),

                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  // ── Account section ──

  Widget _buildAccountSection(
    ThemeData theme,
    bool isDark,
    AuthSession session,
    String plan,
    AppLocalizations t,
  ) {
    final usage = ref.watch(usageProvider).valueOrNull;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border:
            Border.all(color: isDark ? AppColors.border : AppColors.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  _avatarInitial(session),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name ?? 'User',
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    PlanBadge(plan: plan),
                    _buildSubscriptionLine(theme, plan, usage, t),
                  ],
                ),
              ),
            ],
          ),
          if (plan == 'free' && usage != null) ...[
            const SizedBox(height: AppSpacing.md),
            QuotaBar(
              used: usage.requestsUsed,
              limit: usage.requestsLimit,
              charsUsed: usage.charsUsed,
              charsLimit: usage.charsLimit,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (plan == 'free' || plan == 'trial')
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => context.push('/upgrade'),
                    child: Text(t.upgrade),
                  ),
                ),
              if (plan == 'mobile')
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.push('/upgrade'),
                    child: Text(t.upgradeToPro),
                  ),
                ),
              if (plan == 'free' || plan == 'trial') ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                    ),
                    child: Text(t.logOut),
                  ),
                ),
              ],
              if (plan != 'free' && plan != 'trial')
                Expanded(
                  child: OutlinedButton(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                    ),
                    child: Text(t.logOut),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _logout() {
    ref.read(authStateProvider.notifier).logout();
  }

  /// Subline under the plan badge: subscription type + end date (if any).
  /// Lets the user see at a glance whether they're on Mobile or Pro, and
  /// when access actually ends (for cancelled / trial users).
  Widget _buildSubscriptionLine(
    ThemeData theme,
    String plan,
    UsageInfo? usage,
    AppLocalizations t,
  ) {
    String? typeLabel;
    String? endIso;
    if (plan == 'mobile') {
      typeLabel = t.planMobileSubscription;
      endIso = usage?.subEndsAt;
    } else if (plan == 'pro') {
      typeLabel = t.planProSubscription;
      endIso = usage?.subEndsAt;
    } else if (plan == 'trial') {
      typeLabel = t.planTrial;
      endIso = usage?.trialEndsAt;
    }
    if (typeLabel == null && endIso == null) return const SizedBox.shrink();

    final parts = <String>[
      if (typeLabel != null) typeLabel,
      if (endIso != null) t.subscriptionEndsOn(_formatIsoDate(endIso)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        parts.join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          fontSize: 11,
        ),
      ),
    );
  }

  String _formatIsoDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  String _avatarInitial(AuthSession session) {
    final source = (session.name?.trim().isNotEmpty ?? false)
        ? session.name!.trim()
        : session.email.trim();
    if (source.isEmpty) return '?';
    return source.characters.first.toUpperCase();
  }

  Future<void> _toggleBubble() async {
    final bm = ref.read(bubbleManagerProvider.notifier);
    if (_bubbleRunning) {
      await bm.stopBubble();
      if (mounted) setState(() => _bubbleRunning = false);
    } else {
      final hasPermission = await bm.checkPermission();
      if (!hasPermission) {
        if (mounted) {
          context.push('/keyboard-setup?skip=false');
        }
        return;
      }
      final ok = await bm.startBubble();
      if (mounted) setState(() => _bubbleRunning = ok);
    }
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

  void _showAppLangPicker(String current, AppLocalizations t) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.sheetRadius)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: Text(t.appLanguage,
                style: Theme.of(ctx).textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._appLangOptions.map((opt) => ListTile(
                title: Text(opt.$2),
                trailing: opt.$1 == current
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref.read(localeProvider.notifier).setLocale(opt.$1);
                },
              )),
          SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.sm),
        ],
      ),
    );
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

  void _showSpeedPicker(double current, AppLocalizations t) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75];
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.sheetRadius)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: Text(t.speedPickerTitle,
                style: Theme.of(ctx).textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...speeds.map((s) => ListTile(
                title: Text(s == 1.0 ? '1.0× (${t.speedNormal})' : '$s×'),
                trailing: s == current
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref.read(ttsProvider.notifier).setRate(s);
                },
              )),
          SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.sm),
        ],
      ),
    );
  }

  Widget _autoCloseTile(AppLocalizations t, int seconds) {
    return ListTile(
      title: Text(t.autoCloseSeconds),
      subtitle: Text(seconds <= 0 ? t.autoCloseDisabled : '$seconds ${t.autoCloseUnit}'),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () => _showAutoClosePicker(seconds, t),
    );
  }

  void _showTonePicker(String current, AppLocalizations t,
      {required bool isReply}) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.sheetRadius)),
      ),
      builder: (ctx) {
        final title = isReply ? t.replyToneOverride : t.toneOverride;
        // Reply tone has an extra "Same as translate" option (value = '').
        // Translate tone uses '' for Auto.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Text(title,
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...toneOptions.map((opt) {
              final code = opt.$1;
              final label = isReply && code.isEmpty
                  ? t.toneReplySameAsTranslate
                  : _toneLabel(code, t);
              return ListTile(
                title: Text(label),
                trailing: code == current
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  final notifier = ref.read(appSettingsProvider.notifier);
                  if (isReply) {
                    await notifier.setReplyToneOverride(code);
                  } else {
                    await notifier.setToneOverride(code);
                  }
                },
              );
            }),
            SizedBox(
                height: MediaQuery.of(context).padding.bottom + AppSpacing.sm),
          ],
        );
      },
    );
  }

  void _showReplyLangPicker(String current, AppLocalizations t) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.sheetRadius)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: Text(t.replyLanguage,
                style: Theme.of(ctx).textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._replyLangOptions.map((code) => ListTile(
                title: Text(_replyLangLabel(code, t)),
                trailing: code == current
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(appSettingsProvider.notifier)
                      .setReplyLang(code);
                },
              )),
          SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.sm),
        ],
      ),
    );
  }

  void _showAutoClosePicker(int current, AppLocalizations t) {
    const options = [0, 5, 10, 15, 30, 60];
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppSpacing.sheetRadius)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: Text(t.autoCloseSeconds,
                style: Theme.of(ctx).textTheme.titleLarge),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...options.map((secs) => ListTile(
                title: Text(secs == 0
                    ? t.autoCloseDisabled
                    : '$secs ${t.autoCloseUnit}'),
                trailing: secs == current
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(appSettingsProvider.notifier)
                      .setAutoCloseSeconds(secs);
                },
              )),
          SizedBox(height: MediaQuery.of(context).padding.bottom + AppSpacing.sm),
        ],
      ),
    );
  }

  void _showFeedbackSheet(BuildContext context, AppLocalizations t) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.feedbackTitle, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                maxLines: 5,
                decoration: InputDecoration(hintText: t.feedbackHint),
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: () async {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  try {
                    final api = ref.read(apiClientProvider);
                    await api.dio.post('/feedback', data: {
                      'category': 'general',
                      'message': text,
                      'source': 'mobile',
                    });
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t.feedbackThanks)),
                      );
                    }
                  } catch (_) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(t.feedbackFailed),
                          backgroundColor: AppColors.red,
                        ),
                      );
                    }
                  }
                },
                child: Text(t.feedbackSend),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

