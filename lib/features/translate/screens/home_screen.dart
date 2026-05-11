import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/quota_bar.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../../history/screens/history_screen.dart';
import '../../glossary/screens/glossary_screen.dart';
import '../../onboarding/screens/keyboard_setup_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../models/language.dart';
import '../models/translate_models.dart';
import '../providers/translate_provider.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/tts_button.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTab = 0;
  final _textController = TextEditingController();
  String _sourceLang = 'auto';
  String _targetLang = 'en';

  static const _maxChars = 5000;

  @override
  void initState() {
    super.initState();
    _checkKeyboardSetup();
  }

  Future<void> _checkKeyboardSetup() async {
    if (!Platform.isIOS) return;
    final done = await KeyboardSetupScreen.hasCompleted();
    if (!done && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.push('/keyboard-setup');
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _isProUser {
    final auth = ref.read(authStateProvider).valueOrNull;
    return auth?.session?.isPro ?? false;
  }

  void _swapLanguages() {
    if (_sourceLang == 'auto') return;
    setState(() {
      final tmp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = tmp;
    });
  }

  Future<void> _pickSourceLang() async {
    final code = await LanguagePickerSheet.show(
      context,
      selectedCode: _sourceLang,
      showAuto: true,
    );
    if (code != null) setState(() => _sourceLang = code);
  }

  Future<void> _pickTargetLang() async {
    final code = await LanguagePickerSheet.show(
      context,
      selectedCode: _targetLang,
      showAuto: false,
    );
    if (code != null) setState(() => _targetLang = code);
  }

  void _handleAction(TranslateMode mode) {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (mode.requiresPro && !_isProUser) {
      UpgradeNudgeSheet.show(context, featureName: mode.label);
      return;
    }

    final notifier = ref.read(translateProvider.notifier);
    switch (mode) {
      case TranslateMode.translate:
        notifier.translate(
          text: text,
          targetLang: _targetLang,
          sourceLang: _sourceLang,
        );
      case TranslateMode.summarize:
        notifier.summarize(text: text, targetLang: _targetLang);
      case TranslateMode.explain:
        notifier.explain(text: text, targetLang: _targetLang);
      case TranslateMode.refine:
        notifier.refine(text: text);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _currentTab,
                children: [
                  _buildTranslateTabWithQuota(),
                  const HistoryScreen(),
                  const GlossaryScreen(),
                  const SettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTranslateTabWithQuota() {
    return Column(
      children: [
        Expanded(child: _buildTranslateTab()),
        const QuotaBar(used: 5, limit: 20, charsUsed: 400, charsLimit: 2000),
      ],
    );
  }

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: _currentTab,
      onDestinationSelected: (i) => setState(() => _currentTab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.translate), label: 'Translate'),
        NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        NavigationDestination(icon: Icon(Icons.menu_book), label: 'Glossary'),
        NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
      ],
    );
  }

  Widget _buildTranslateTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final translateState = ref.watch(translateProvider);
    final state = translateState.valueOrNull;
    final isLoading = state?.isLoading ?? false;
    final result = state?.result;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Language bar
          _buildLanguageBar(theme, isDark),
          const SizedBox(height: AppSpacing.md),

          // Source text field
          _buildSourceField(theme, isDark),
          const SizedBox(height: AppSpacing.md),

          // Feature buttons
          _buildFeatureButtons(isDark),
          const SizedBox(height: AppSpacing.md),

          // Error
          if (state?.error != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              child: Text(
                state!.error!,
                style: const TextStyle(color: AppColors.red),
              ),
            ),

          // Result card
          if (result != null) _buildResultCard(theme, isDark, result),

          // Loading
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildLanguageBar(ThemeData theme, bool isDark) {
    final sourceLabel = languageByCode(_sourceLang);
    final targetLabel = languageByCode(_targetLang);

    return Row(
      children: [
        Expanded(
          child: _langChip(
            sourceLabel.nativeName,
            onTap: _pickSourceLang,
            isDark: isDark,
          ),
        ),
        IconButton(
          onPressed: _sourceLang == 'auto' ? null : _swapLanguages,
          icon: Icon(
            Icons.swap_horiz,
            color: _sourceLang == 'auto'
                ? AppColors.textSecondary
                : AppColors.primary,
          ),
        ),
        Expanded(
          child: _langChip(
            targetLabel.nativeName,
            onTap: _pickTargetLang,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _langChip(String label, {required VoidCallback onTap, required bool isDark}) {
    return Material(
      color: isDark ? AppColors.surface : const Color(0xFFF0EDE8),
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceField(ThemeData theme, bool isDark) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        TextFormField(
          controller: _textController,
          maxLines: 6,
          maxLength: _maxChars,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Enter text to translate...',
            counterStyle: TextStyle(fontSize: 11),
          ),
        ),
        if (_textController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                _textController.clear();
                ref.read(translateProvider.notifier).clearResult();
                setState(() {});
              },
            ),
          ),
      ],
    );
  }

  Widget _buildFeatureButtons(bool isDark) {
    return Row(
      children: [
        _featureBtn(
          icon: Icons.translate,
          label: 'Translate',
          onTap: () => _handleAction(TranslateMode.translate),
          isDark: isDark,
          isPrimary: true,
        ),
        const SizedBox(width: AppSpacing.sm),
        _featureBtn(
          icon: Icons.summarize_outlined,
          label: 'Summarize',
          locked: !_isProUser,
          onTap: () => _handleAction(TranslateMode.summarize),
          isDark: isDark,
        ),
        const SizedBox(width: AppSpacing.sm),
        _featureBtn(
          icon: Icons.lightbulb_outline,
          label: 'Explain',
          locked: !_isProUser,
          onTap: () => _handleAction(TranslateMode.explain),
          isDark: isDark,
        ),
        const SizedBox(width: AppSpacing.sm),
        _featureBtn(
          icon: Icons.auto_fix_high,
          label: 'Refine',
          locked: !_isProUser,
          onTap: () => _handleAction(TranslateMode.refine),
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _featureBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool isPrimary = false,
    bool locked = false,
  }) {
    return Expanded(
      child: Material(
        color: isPrimary
            ? AppColors.primary
            : (isDark ? AppColors.surface : AppColors.surfaceLight),
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(AppSpacing.buttonRadius),
              border: isPrimary
                  ? null
                  : Border.all(
                      color: isDark ? AppColors.border : AppColors.borderLight,
                    ),
            ),
            child: Column(
              children: [
                Icon(
                  locked ? Icons.lock_outline : icon,
                  size: 20,
                  color: isPrimary
                      ? Colors.white
                      : (isDark ? AppColors.textSecondary : AppColors.textSecondaryLight),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isPrimary
                        ? Colors.white
                        : (isDark ? AppColors.textSecondary : AppColors.textSecondaryLight),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(
    ThemeData theme,
    bool isDark,
    TranslateResult result,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Translation text
          SelectableText(
            result.translation,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 16,
              height: 1.5,
            ),
          ),

          // Romanization
          if (result.romanization != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              result.romanization!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          // Suggestions
          if (result.suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Suggestions',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: result.suggestions.map((s) {
                return ActionChip(
                  label: Text(s.target),
                  onPressed: () => _copyToClipboard(s.target),
                );
              }).toList(),
            ),
          ],

          // Action buttons
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _actionIcon(Icons.copy_outlined, 'Copy', () {
                _copyToClipboard(result.translation);
              }),
              const SizedBox(width: AppSpacing.sm),
              TtsButton(text: result.translation, lang: _targetLang),
              const SizedBox(width: AppSpacing.sm),
              _actionIcon(Icons.star_outline, 'Save', () {
                // TODO: Save to history
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }
}
