import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../../l10n/generated/app_localizations.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/plan_status_banner.dart';
import '../../../shared/widgets/quota_bar.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../../history/providers/history_provider.dart';
import '../../history/screens/history_screen.dart';
import '../../glossary/screens/glossary_screen.dart';
import '../../onboarding/screens/accessibility_setup_screen.dart';
import '../../onboarding/screens/keyboard_setup_screen.dart';
import '../../../core/bubble/bubble_manager.dart';
import '../../settings/providers/app_settings_provider.dart';
import '../../settings/screens/settings_screen.dart';
import '../../upgrade/providers/usage_provider.dart';
import '../models/language.dart';
import '../models/translate_models.dart';
import '../providers/features_provider.dart';
import '../providers/language_settings_provider.dart';
import '../providers/translate_provider.dart';
import '../services/tts_service.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/tts_button.dart';
import '../../../shared/widgets/selectable_with_actions.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _currentTab = 0;
  // Track which tabs have been opened so IndexedStack can keep them in the
  // tree (preserving state), but the heavy History / Glossary / Settings
  // pages don't build at first frame.
  final Set<int> _visitedTabs = {0};
  final _textController = TextEditingController();
  final _inputFocus = FocusNode();

  String? _clipboardSuggestion;
  String? _dismissedClipboard;
  // True while we're populating _textController from saved storage — the
  // controller listener would otherwise schedule a redundant write of the
  // value we just read.
  bool _isRestoring = false;

  static const _maxChars = 5000;
  static const _kSourceTextKey = 'tk_last_source_text';

  // Speech-to-text state. _speech is lazy-inited on first mic tap so the
  // SpeechRecognizer plugin doesn't get attached unless the user actually
  // wants voice input (avoids unnecessary IPC + a permission prompt at
  // app start).
  stt.SpeechToText? _speech;
  bool _isListening = false;
  // Text already in the field BEFORE we started listening — appended to
  // recognised words so users can dictate additions instead of dictating
  // a wholesale replacement of what they typed.
  String _speechPrefix = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _textController.addListener(_persistSourceText);
    // Fetch /features so the language picker shows the full live catalog
    // (134 langs) instead of the embedded 16-lang fallback. Fire-and-forget;
    // if it fails the fallback list keeps the picker usable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(featuresProvider.notifier).refreshIfNeeded();
    });
  }

  Future<void> _bootstrap() async {
    // Sequence cold-start side effects so we don't pop the keyboard up
    // *behind* the keyboard-setup screen. Order matters:
    // 1. Decide whether to push keyboard-setup; if pushed, don't focus.
    // 2. Restore last source text (skips focus when text is restored).
    // 3. Peek clipboard for the suggestion chip.
    // 4. If safe, focus the input so the user can start typing immediately.
    final keyboardDone = await KeyboardSetupScreen.hasCompleted();
    if (!mounted) return;
    if (!keyboardDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push('/keyboard-setup');
      });
      // Don't focus — the keyboard-setup screen will be on top.
      await _restoreSourceText();
      await _peekClipboard();
      return;
    }
    await _restoreSourceText();
    await _peekClipboard();
    if (!mounted) return;
    if (_textController.text.isEmpty && _currentTab == 0) {
      _inputFocus.requestFocus();
    }
    // After the first frame settles, push the Accessibility setup screen
    // if the user hasn't already finished it AND hasn't tapped Skip
    // before. This is the single-shot onboarding the bubble depends on
    // for the "highlight → tap → translate" flow that users expect from
    // Google-Translate-style overlay apps. Done last so it doesn't fight
    // the keyboard-setup route on a true first-launch chain.
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final seen = await AccessibilitySetupScreen.wasSeen();
        if (seen) return;
        final a11y = await ref
            .read(bubbleManagerProvider.notifier)
            .checkAccessibility();
        if (a11y || !mounted) return;
        context.push('/accessibility-setup');
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reload settings when app comes to foreground — the floating bubble (or
    // Share Extension) may have changed language/tone/reply-lang in
    // SharedPreferences while we were backgrounded. Without these reloads the
    // in-app settings UI would show stale values until next cold start.
    if (state == AppLifecycleState.resumed) {
      ref.read(languageSettingsProvider.notifier).reload();
      ref.read(appSettingsProvider.notifier).reload();
      ref.read(ttsProvider.notifier).reload();
      ref.read(usageProvider.notifier).refreshIfStale();
      ref.read(authStateProvider.notifier).refreshUser();
      // Pick up admin changes to the language catalog (enable/disable/rename)
      // without forcing a full app restart.
      ref.read(featuresProvider.notifier).refreshIfNeeded();
      // Skip the clipboard peek on iOS resume — every Clipboard.getData call
      // raises a "TransKey pasted from..." privacy banner on iOS 14+. We pay
      // that cost once at cold start; on resume the user can long-press the
      // input to paste manually. Android has no such banner, so peek freely.
      if (!Platform.isIOS) {
        _peekClipboard();
      }
    }
  }

  Future<void> _restoreSourceText() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kSourceTextKey);
    if (saved == null || saved.isEmpty) return;
    if (!mounted || _textController.text.isNotEmpty) return;
    _isRestoring = true;
    _textController.text = saved;
    _isRestoring = false;
  }

  Timer? _persistDebounce;
  void _persistSourceText() {
    if (_isRestoring) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 500), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSourceTextKey, _textController.text);
    });
  }

  Future<void> _peekClipboard() async {
    // Read clipboard *without* requesting focus (no popup spam). On iOS,
    // accessing pasteboard surfaces a system banner — that's the OS, not us.
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty || text.length > _maxChars) {
        return;
      }
      // Don't suggest if it's already in the input or the user dismissed it.
      if (text == _textController.text.trim() || text == _dismissedClipboard) {
        return;
      }
      if (mounted) setState(() => _clipboardSuggestion = text);
    } catch (_) {
      // Clipboard permission denied or empty — silently skip.
    }
  }

  void _useClipboardSuggestion() {
    final text = _clipboardSuggestion;
    if (text == null) return;
    _textController.text = text;
    setState(() {
      _clipboardSuggestion = null;
    });
    _handleAction(TranslateMode.translate);
  }

  void _dismissClipboardSuggestion() {
    setState(() {
      _dismissedClipboard = _clipboardSuggestion;
      _clipboardSuggestion = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistDebounce?.cancel();
    _textController.removeListener(_persistSourceText);
    _textController.dispose();
    _inputFocus.dispose();
    // Stop any in-flight recognition so the mic doesn't keep listening
    // after the user navigates away.
    if (_isListening) _speech?.stop();
    super.dispose();
  }

  bool get _isProUser {
    final auth = ref.read(authStateProvider).valueOrNull;
    return auth?.session?.isPro ?? false;
  }

  void _swapLanguages() {
    ref.read(languageSettingsProvider.notifier).swap();
  }

  Future<void> _pickSourceLang(String currentSource) async {
    final code = await LanguagePickerSheet.show(
      context,
      selectedCode: currentSource,
      showAuto: true,
      field: LanguagePickerField.source,
    );
    if (code != null) {
      await ref.read(languageSettingsProvider.notifier).setSourceLang(code);
      // Clear detected lang when manually changing source
      ref.read(translateProvider.notifier).clearResult();
    }
  }

  Future<void> _pickTargetLang(String currentTarget) async {
    final code = await LanguagePickerSheet.show(
      context,
      selectedCode: currentTarget,
      showAuto: false,
      field: LanguagePickerField.target,
    );
    if (code == null || code == currentTarget) return;
    await ref.read(languageSettingsProvider.notifier).setTargetLang(code);
    // If there's already a result, the user clearly wants the *same* text
    // re-translated to the new language — skip the extra tap on "Translate".
    final translateState = ref.read(translateProvider).valueOrNull;
    if (translateState?.result != null &&
        _textController.text.trim().isNotEmpty) {
      _handleAction(translateState?.mode ?? TranslateMode.translate);
    }
  }

  void _handleAction(TranslateMode mode) {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (mode.requiresPro && !_isProUser) {
      UpgradeNudgeSheet.show(context, featureName: mode.label);
      return;
    }

    final langs = ref.read(languageSettingsProvider).valueOrNull;
    final sourceLang = langs?.sourceLang ?? 'auto';
    final targetLang = langs?.targetLang ?? 'en';

    final notifier = ref.read(translateProvider.notifier);
    switch (mode) {
      case TranslateMode.translate:
        notifier.translate(
          text: text,
          targetLang: targetLang,
          sourceLang: sourceLang,
        );
      case TranslateMode.reply:
        notifier.translate(
          text: text,
          targetLang: targetLang,
          sourceLang: sourceLang,
          isReply: true,
        );
      case TranslateMode.summarize:
        notifier.summarize(text: text, targetLang: targetLang);
      case TranslateMode.explain:
        notifier.explain(text: text, targetLang: targetLang);
      case TranslateMode.refine:
        notifier.refine(text: text);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    final l = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.copied),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Reply just finished — copy to clipboard and surface a "Use as input"
  /// shortcut so the user can swap the reply back into the source field
  /// (mirrors desktop Cmd+Shift+R, where the reply replaces the input).
  void _onReplyReady(String reply, AppLocalizations l) {
    if (reply.isEmpty) return;
    Clipboard.setData(ClipboardData(text: reply));
    final originalSource = _textController.text;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.copied),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: l.tabReply,
          onPressed: () {
            _textController.text = reply;
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text(l.copied),
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => _textController.text = originalSource,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentTab,
          children: [
            // The translate tab is always built — it's the cold-start surface.
            _buildTranslateTabWithQuota(),
            // History / Glossary / Settings are lazily built on first visit so
            // cold-start doesn't pay for SharedPreferences reads + provider
            // builds + ListView layout of pages the user may never open.
            _LazyTab(
              isVisited: _visitedTabs.contains(1),
              builder: () => const HistoryScreen(),
            ),
            _LazyTab(
              isVisited: _visitedTabs.contains(2),
              builder: () => const GlossaryScreen(),
            ),
            _LazyTab(
              isVisited: _visitedTabs.contains(3),
              builder: () => const SettingsScreen(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() {
          _currentTab = i;
          _visitedTabs.add(i);
        }),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.translate), label: l.translate),
          NavigationDestination(
              icon: const Icon(Icons.history), label: l.history),
          NavigationDestination(
              icon: const Icon(Icons.menu_book), label: l.glossary),
          NavigationDestination(
              icon: const Icon(Icons.settings), label: l.settings),
        ],
      ),
    );
  }

  Widget _buildTranslateTabWithQuota() {
    final usage = ref.watch(usageProvider).valueOrNull;
    final plan = ref.watch(authStateProvider).valueOrNull?.session?.plan ?? 'free';
    return Column(
      children: [
        Expanded(child: _buildTranslateTab()),
        if (plan == 'free' && usage != null)
          QuotaBar(
            used: usage.requestsUsed,
            limit: usage.requestsLimit,
            charsUsed: usage.charsUsed,
            charsLimit: usage.charsLimit,
          ),
      ],
    );
  }

  Widget _buildTranslateTab() {
    final l = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final translateState = ref.watch(translateProvider);
    final state = translateState.valueOrNull;
    final isLoading = state?.isLoading ?? false;
    final result = state?.result;
    final theme = Theme.of(context);

    // When a reply finishes, auto-copy and offer to replace the input —
    // mirrors the desktop Cmd+Shift+R flow inside the app.
    ref.listen<AsyncValue<TranslateState>>(translateProvider, (prev, next) {
      final prevResult = prev?.valueOrNull?.result;
      final nextState = next.valueOrNull;
      final nextResult = nextState?.result;
      if (nextResult == null || nextResult == prevResult) return;
      if (nextState?.mode != TranslateMode.reply) return;
      _onReplyReady(nextResult.translation, l);
    });

    // Mid-session plan downgrade detection: usage refresh runs after every
    // translate, so when the server-side plan field diverges from what's in
    // the local session (trial expired, sub cancelled past ends_at, etc.),
    // pull a fresh /auth/me so the UI flips to free immediately instead of
    // waiting for the next cold start.
    ref.listen<AsyncValue<UsageInfo?>>(usageProvider, (prev, next) {
      final usagePlan = next.valueOrNull?.plan;
      if (usagePlan == null) return;
      final sessionPlan = ref.read(authStateProvider).valueOrNull?.session?.plan;
      if (sessionPlan != null && sessionPlan != usagePlan) {
        ref.read(authStateProvider.notifier).refreshUser();
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trial countdown / subscription-expired banner — shown above
          // everything so the user can't miss it. The banner widget
          // returns SizedBox.shrink() with no margin when nothing is to
          // be shown, so no awkward spacing on the common case.
          const PlanStatusBanner(),
          if (_clipboardSuggestion != null) ...[
            _buildClipboardChip(theme, isDark, _clipboardSuggestion!),
            const SizedBox(height: AppSpacing.sm),
          ],
          _buildLanguageBar(theme, isDark, result),
          const SizedBox(height: AppSpacing.md),

          _buildSourceField(theme, isDark, l),
          const SizedBox(height: AppSpacing.md),

          _buildFeatureButtons(isDark, l),
          const SizedBox(height: AppSpacing.md),

          if (state?.error != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              child: Text(state!.error!,
                  style: const TextStyle(color: AppColors.red)),
            ),

          if (result != null) _buildResultCard(theme, isDark, result, l),

          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildLanguageBar(ThemeData theme, bool isDark, TranslateResult? result) {
    final langs = ref.watch(languageSettingsProvider).valueOrNull;
    final sourceLang = langs?.sourceLang ?? 'auto';
    final targetLang = langs?.targetLang ?? 'en';
    // When source is auto and we have a detection, show detected name in chip
    final detectedCode = (sourceLang == 'auto') ? result?.detectedLang : null;
    final sourceLabel = detectedCode != null
        ? languageByCode(detectedCode).nativeName
        : languageByCode(sourceLang).nativeName;
    final targetLabel = languageByCode(targetLang).nativeName;

    return Row(
      children: [
        Expanded(
          child: _langChip(
            sourceLabel,
            subtitle: detectedCode != null ? 'Auto' : null,
            onTap: () => _pickSourceLang(sourceLang),
            isDark: isDark,
          ),
        ),
        IconButton(
          onPressed: sourceLang == 'auto' ? null : _swapLanguages,
          icon: Icon(
            Icons.swap_horiz,
            color: sourceLang == 'auto'
                ? AppColors.textSecondary
                : AppColors.primary,
          ),
        ),
        Expanded(
          child: _langChip(
            targetLabel,
            onTap: () => _pickTargetLang(targetLang),
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _langChip(String label,
      {String? subtitle,
      required VoidCallback onTap,
      required bool isDark}) {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.primary.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceField(ThemeData theme, bool isDark, AppLocalizations l) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        TextFormField(
          controller: _textController,
          focusNode: _inputFocus,
          maxLines: 6,
          maxLength: _maxChars,
          // No onChanged here — the clear button below subscribes to the
          // controller directly via ListenableBuilder, so the surrounding
          // widget tree no longer rebuilds on every keystroke.
          decoration: InputDecoration(
            hintText: l.hintEnterText,
            counterStyle: const TextStyle(fontSize: 11),
          ),
        ),
        // Top-right action cluster: mic always visible, clear shown only
        // when there's text to clear.
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: _isListening ? l.voiceListening : l.voiceTooltip,
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  size: 22,
                  color: _isListening ? Colors.red : null,
                ),
                onPressed: _toggleSpeechToText,
              ),
              ListenableBuilder(
                listenable: _textController,
                builder: (context, _) {
                  if (_textController.text.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _textController.clear();
                      ref.read(translateProvider.notifier).clearResult();
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Toggle voice-to-text. First tap: ask for mic permission (if not
  /// granted), start listening with the currently-selected source
  /// language as the recognition locale, and stream partial results
  /// into the text field. Second tap: stop early. Auto-stops on ~3 s
  /// of silence (the SpeechRecognizer plugin's default).
  Future<void> _toggleSpeechToText() async {
    final l = AppLocalizations.of(context)!;
    if (_isListening) {
      await _speech?.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    // Android SpeechRecognizer needs a concrete locale — it CAN'T
    // auto-detect across languages. If the picker is "Auto", ask the
    // user to pick a real source first, then open the source picker.
    final langs = ref.read(languageSettingsProvider).valueOrNull;
    final sourceLang = langs?.sourceLang ?? 'auto';
    if (sourceLang == 'auto') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.voicePickSourceLang)),
      );
      await _pickSourceLang(sourceLang);
      return;
    }
    final perm = await Permission.microphone.request();
    if (!perm.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.voicePermDenied)),
        );
      }
      return;
    }
    final speech = _speech ??= stt.SpeechToText();
    final available = await speech.initialize(
      onError: (e) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.voiceUnsupported)),
        );
      }
      return;
    }
    // Recognition locale was already validated above (auto is rejected).
    final localeId = _bcp47ForLang(sourceLang);

    _speechPrefix = _textController.text;
    if (mounted) setState(() => _isListening = true);
    await speech.listen(
      localeId: localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      onResult: (result) {
        final joined = _speechPrefix.isEmpty
            ? result.recognizedWords
            : '$_speechPrefix ${result.recognizedWords}';
        _textController.value = TextEditingValue(
          text: joined,
          selection: TextSelection.collapsed(offset: joined.length),
        );
      },
    );
  }

  /// Map our 2-letter source-language code to the BCP-47 locale ID the
  /// platform SpeechRecognizer expects. Returns null for "auto" so the
  /// plugin uses the device-default locale.
  String? _bcp47ForLang(String code) {
    if (code == 'auto') return null;
    return _localeMap[code] ?? code;
  }

  static const _localeMap = {
    'en': 'en_US',
    'vi': 'vi_VN',
    'zh': 'zh_CN',
    'ja': 'ja_JP',
    'ko': 'ko_KR',
    'fr': 'fr_FR',
    'de': 'de_DE',
    'es': 'es_ES',
  };

  Widget _buildClipboardChip(ThemeData theme, bool isDark, String text) {
    final preview = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        onTap: _useClipboardSuggestion,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.content_paste,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close, size: 16),
                color: AppColors.primary,
                onPressed: _dismissClipboardSuggestion,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureButtons(bool isDark, AppLocalizations l) {
    return Row(
      children: [
        _featureBtn(
          icon: Icons.translate,
          label: l.translate,
          onTap: () => _handleAction(TranslateMode.translate),
          isDark: isDark,
          isPrimary: true,
        ),
        const SizedBox(width: AppSpacing.sm),
        _featureBtn(
          icon: Icons.reply_outlined,
          label: l.reply,
          onTap: () => _handleAction(TranslateMode.reply),
          isDark: isDark,
        ),
        const SizedBox(width: AppSpacing.sm),
        _featureBtn(
          icon: Icons.summarize_outlined,
          label: l.summarize,
          locked: !_isProUser,
          onTap: () => _handleAction(TranslateMode.summarize),
          isDark: isDark,
        ),
        const SizedBox(width: AppSpacing.sm),
        _featureBtn(
          icon: Icons.lightbulb_outline,
          label: l.explain,
          locked: !_isProUser,
          onTap: () => _handleAction(TranslateMode.explain),
          isDark: isDark,
        ),
        const SizedBox(width: AppSpacing.sm),
        _featureBtn(
          icon: Icons.auto_fix_high,
          label: l.refine,
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
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              border: isPrimary
                  ? null
                  : Border.all(
                      color:
                          isDark ? AppColors.border : AppColors.borderLight),
            ),
            child: Column(
              children: [
                Icon(
                  locked ? Icons.lock_outline : icon,
                  size: 18,
                  color: isPrimary
                      ? Colors.white
                      : (isDark
                          ? AppColors.textSecondary
                          : AppColors.textSecondaryLight),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isPrimary
                        ? Colors.white
                        : (isDark
                            ? AppColors.textSecondary
                            : AppColors.textSecondaryLight),
                  ),
                  overflow: TextOverflow.ellipsis,
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
    AppLocalizations l,
  ) {
    final langs = ref.watch(languageSettingsProvider).valueOrNull;
    final sourceLang = langs?.sourceLang ?? 'auto';
    final targetLang = langs?.targetLang ?? 'en';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
            color: isDark ? AppColors.border : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Detected source language (only when auto-detect)
          if (result.detectedLang != null && sourceLang == 'auto') ...[
            Text(
              l.detectedLang(languageByCode(result.detectedLang!).nativeName),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.primary.withValues(alpha: 0.75),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Tap-anywhere-on-result copies. SelectableText still handles
          // long-press selection + the custom "TransKey" context menu.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _copyToClipboard(result.translation),
            child: SelectableWithActions(
              result.translation,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                height: 1.5,
              ),
              targetLang: targetLang,
            ),
          ),

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

          if (result.suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Text(l.suggestions, style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            // Bilingual chips (matches desktop popup): each card shows the
            // reply in the partner's language on top, the user's language
            // hint below, and tap copies the SOURCE (what the user would
            // actually send back).
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: result.suggestions.map((s) {
                final source = s.source.trim();
                final target = s.target.trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: InkWell(
                    onTap: () => _copyToClipboard(
                      source.isNotEmpty ? source : target,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? AppColors.border
                              : AppColors.borderLight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (source.isNotEmpty)
                            Text(
                              source,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (target.isNotEmpty && target != source) ...[
                            const SizedBox(height: 2),
                            Text(
                              target,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _actionIcon(Icons.copy_outlined, l.copy, () {
                _copyToClipboard(result.translation);
              }),
              const SizedBox(width: AppSpacing.sm),
              TtsButton(text: result.translation, lang: targetLang),
              const SizedBox(width: AppSpacing.sm),
              _buildSaveIcon(l),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaveIcon(AppLocalizations l) {
    final historyId = ref.watch(
      translateProvider.select((s) => s.valueOrNull?.lastHistoryId),
    );
    // Subscribe only to *this* entry's favorite flag. Without select, every
    // new translation / search query / filter change rebuilds the icon even
    // though the displayed state hasn't changed. With select Riverpod
    // short-circuits when the resolved bool is identical to the previous one.
    final isFavorite = ref.watch(
      historyProvider.select((s) {
        if (historyId == null) return false;
        for (final e in s.entries) {
          if (e.id == historyId) return e.isFavorite;
        }
        return false;
      }),
    );
    return _actionIcon(
      isFavorite ? Icons.star : Icons.star_outline,
      l.save,
      historyId == null
          ? null
          : () => ref.read(historyProvider.notifier).toggleFavorite(historyId),
    );
  }

  Widget _actionIcon(IconData icon, String tooltip, VoidCallback? onTap) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }
}

/// Holds a slot in IndexedStack but defers building its child until the tab
/// has been visited at least once. Saves cold-start time when the user opens
/// the app, types, and leaves without ever touching History / Glossary /
/// Settings — those subtrees never instantiate their providers or widgets.
class _LazyTab extends StatelessWidget {
  const _LazyTab({required this.isVisited, required this.builder});

  final bool isVisited;
  final Widget Function() builder;

  @override
  Widget build(BuildContext context) {
    if (!isVisited) return const SizedBox.shrink();
    return builder();
  }
}
