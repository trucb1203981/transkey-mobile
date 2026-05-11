import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/session_store.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/quota_bar.dart';
import '../../translate/models/language.dart';
import '../widgets/plan_badge.dart';

const _kTargetLangKey = 'tk_target_lang';
const _kSourceLangKey = 'tk_source_lang';
const _kHistorySaveKey = 'tk_history_save';
const _kRomanizationKey = 'tk_romanization';
const _kReplySuggestionsKey = 'tk_reply_suggestions';
const _kToneOverrideKey = 'tk_tone_override';
const _kAutoCloseKey = 'tk_auto_close_result';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final session = authState.valueOrNull?.session;
    final plan = session?.plan ?? 'free';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── Account section ──
          if (session != null) _buildAccountSection(theme, isDark, session, plan),

          const SizedBox(height: AppSpacing.md),
          _sectionHeader('Language'),
          _langPickerTile('Target language', _kTargetLangKey, 'en', showAuto: false),
          _langPickerTile('Source language', _kSourceLangKey, 'auto', showAuto: true),
          // UI language (placeholder — i18n not yet implemented)
          ListTile(
            title: const Text('App language'),
            subtitle: const Text('English'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () {
              // TODO: UI language picker
            },
          ),

          const SizedBox(height: AppSpacing.md),
          _sectionHeader('Translation'),
          _switchTile('Save history', _kHistorySaveKey, true),
          _switchTile('Romanization', _kRomanizationKey, false, locked: plan == 'free'),
          _switchTile('Reply suggestions', _kReplySuggestionsKey, false, locked: plan == 'free'),
          _switchTile('Tone override', _kToneOverrideKey, false, locked: plan == 'free'),
          _switchTile('Auto-close result', _kAutoCloseKey, false),

          const SizedBox(height: AppSpacing.md),
          _sectionHeader('Other'),
          if (Platform.isIOS)
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: const Text('Keyboard Setup'),
              subtitle: const Text('Configure TransKey keyboard'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => context.push('/keyboard-setup?skip=false'),
            ),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('Send feedback'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => _showFeedbackSheet(context),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => launchUrl(Uri.parse('https://transkey.app/terms')),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => launchUrl(Uri.parse('https://transkey.app/privacy')),
          ),
          if (_version.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Version'),
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
  ) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: isDark ? AppColors.border : AppColors.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  (session.name ?? session.email).substring(0, 1).toUpperCase(),
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
                  ],
                ),
              ),
            ],
          ),
          if (plan == 'free') ...[
            const SizedBox(height: AppSpacing.md),
            const QuotaBar(used: 5, limit: 20, charsUsed: 400, charsLimit: 2000),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (plan == 'free' || plan == 'trial')
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/upgrade'),
                    child: const Text('Upgrade'),
                  ),
                ),
              if (plan == 'mobile') ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pushNamed(context, '/upgrade'),
                    child: const Text('Upgrade to Pro'),
                  ),
                ),
              ],
              if (plan == 'free' || plan == 'trial') ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                    ),
                    child: const Text('Log out'),
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
                    child: const Text('Log out'),
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

  // ── Helpers ──

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _langPickerTile(
    String title,
    String prefsKey,
    String defaultValue, {
    bool showAuto = false,
  }) {
    return FutureBuilder<String>(
      future: _getPref(prefsKey, defaultValue),
      builder: (context, snapshot) {
        final current = snapshot.data ?? defaultValue;
        final lang = languageByCode(current);
        return ListTile(
          title: Text(title),
          subtitle: Text(lang.nativeName),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () async {
            // Simple dialog for now — reuse LanguagePickerSheet if available
            final picked = await _showLangDialog(context, current, showAuto);
            if (picked != null) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(prefsKey, picked);
              setState(() {});
            }
          },
        );
      },
    );
  }

  Future<String?> _showLangDialog(BuildContext context, String current, bool showAuto) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select language'),
        children: kSupportedLanguages
            .where((l) => showAuto || l.code != 'auto')
            .map((l) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, l.code),
                  child: Row(
                    children: [
                      if (l.code == current)
                        const Icon(Icons.check, size: 18, color: AppColors.primary)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 8),
                      Text(l.nativeName),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _switchTile(String title, String prefsKey, bool defaultValue, {bool locked = false}) {
    return FutureBuilder<bool>(
      future: _getBoolPref(prefsKey, defaultValue),
      builder: (context, snapshot) {
        final value = snapshot.data ?? defaultValue;
        return Opacity(
          opacity: locked ? 0.5 : 1.0,
          child: ListTile(
            title: Row(
              children: [
                Text(title),
                if (locked) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.lock_outline, size: 14, color: AppColors.textSecondary),
                ],
              ],
            ),
            trailing: Switch(
              value: locked ? false : value,
              onChanged: locked
                  ? null
                  : (v) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool(prefsKey, v);
                      setState(() {});
                    },
            ),
          ),
        );
      },
    );
  }

  Future<String> _getPref(String key, String defaultValue) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? defaultValue;
  }

  Future<bool> _getBoolPref(String key, bool defaultValue) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }

  void _showFeedbackSheet(BuildContext context) {
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
              Text('Send feedback', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Tell us what you think...',
                ),
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
                        const SnackBar(content: Text('Thank you for your feedback!')),
                      );
                    }
                  } catch (_) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to send feedback'),
                          backgroundColor: AppColors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Send'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}
