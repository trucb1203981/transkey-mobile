import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../l10n/generated/app_localizations.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/plan_status_banner.dart';
import '../../../shared/widgets/quota_bar.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../../history/screens/history_screen.dart';
import '../../glossary/screens/glossary_screen.dart';
import '../../onboarding/screens/accessibility_setup_screen.dart';
import '../../onboarding/screens/keyboard_setup_screen.dart';
import '../../../core/bubble/bubble_manager.dart';
import '../../settings/providers/app_settings_provider.dart';
import '../../settings/screens/settings_screen.dart';
import '../../../core/api/dio_client.dart';
import '../../upgrade/providers/usage_provider.dart';
import '../../upgrade/services/rewarded_ad_service.dart';
import '../../upgrade/widgets/paywall_sheet.dart';
import '../models/translate_models.dart';
import '../providers/features_provider.dart';
import '../providers/language_settings_provider.dart';
import '../providers/translate_provider.dart';
import '../services/tts_service.dart';
import '../widgets/clipboard_chip.dart';
import '../widgets/feature_buttons.dart';
import '../widgets/language_bar.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/name_chip_palette.dart';
import '../widgets/result_card.dart';
import '../widgets/source_field.dart';
import 'home_voice_mixin.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver, HomeVoiceMixin<HomeScreen> {
  @override
  TextEditingController get voiceTextController => _textController;

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

  // Speech-to-text state + toggleSpeechToText() live in [HomeVoiceMixin].

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
    // The observer can still fire while the element is detaching (we saw
    // "No ProviderScope found" here). Bail before any ref.read so a lifecycle
    // event during teardown can't reach a disposed/scope-less element.
    if (!mounted) return;
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
    stopVoiceIfListening();
    super.dispose();
  }

  /// Current admin-config-aware feature flags. UI gates read THIS instead
  /// of hardcoding `isPro` so that an admin toggling /admin/features at
  /// runtime is reflected on the next app open without an app update.
  /// Uses `ref.watch` so when /features resolves (or refreshes) the gates
  /// re-evaluate and lock icons flip live without manual rebuild.
  FeatureFlags get _features => ref.watch(featuresProvider).flags;

  bool _isModeAllowed(TranslateMode mode) {
    final flags = _features;
    switch (mode) {
      case TranslateMode.translate:
        return flags.translate;
      case TranslateMode.reply:
        return flags.replyTranslate;
      case TranslateMode.summarize:
        return flags.summarize;
      case TranslateMode.explain:
        return flags.explain;
      case TranslateMode.refine:
        return flags.refine;
    }
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

  /// Quota wall — opened from the translate listener on 429
  /// quota_exceeded. If the user watches a rewarded ad and the server
  /// credits the reward (sheet returns `true`), retry the same mode
  /// against the still-current text so they don't have to tap again.
  /// Guarded by `_paywallVisible` because the same error can re-fire
  /// during a retry race; a second sheet on top of the first is the
  /// noisiest possible UX.
  bool _paywallVisible = false;
  Future<void> _showPaywall(TranslateMode lastMode) async {
    if (_paywallVisible) return;
    _paywallVisible = true;
    try {
      final earned = await PaywallSheet.show(context);
      if (!mounted) return;
      // Clear the error so the result panel doesn't keep showing the
      // 429 red bar after a successful credit / dismiss.
      ref.read(translateProvider.notifier).clearError();
      if (earned == true && _textController.text.trim().isNotEmpty) {
        _handleAction(lastMode);
      }
    } finally {
      _paywallVisible = false;
    }
  }

  /// Camera entry point. Gated on the server-side `camera` feature flag —
  /// admin can toggle per plan via /admin/features. Free users on a plan
  /// where camera is disabled see the upgrade nudge instead of opening
  /// the screen and hitting a 403 on the first capture.
  void _handleCameraTap() {
    if (!_features.camera) {
      final l = AppLocalizations.of(context)!;
      UpgradeNudgeSheet.show(context, featureName: l.cameraTitle);
      return;
    }
    context.push('/camera');
  }

  void _handleAction(TranslateMode mode) {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (!_isModeAllowed(mode)) {
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
      // Floating camera button + 4 standard tabs around it.
      //
      // Design (Instagram / TikTok / Snapchat pattern):
      //   ┌───────────────────────────────────────┐
      //   │                  ●                    │ ← floating camera
      //   │  Translate │ History │ Glossary │ Set │ ← 4 standard tabs
      //   └───────────────────────────────────────┘
      //
      // The Material 3 NavigationBar can't host a "raised" tab so we
      // overlay a circular Material widget via a Stack that overflows
      // the bottomNavigationBar slot. The FAB-style button sits above
      // the divider between History and Glossary — visually it lands
      // in the center 1/4-1/4 boundary, which thumb-reach studies
      // (Steven Hoober, 2014) put at the natural arc midpoint for a
      // right-hand single-thumb grip.
      bottomNavigationBar: _BottomBarWithCamera(
        currentTab: _currentTab,
        onTabChanged: (i) => setState(() {
          _currentTab = i;
          _visitedTabs.add(i);
        }),
        onCameraTap: _handleCameraTap,
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
            isWatchingAd: _isWatchingProactiveAd,
            // Server-gated: when /features.ads_enabled is OFF (AdMob still
            // in review), pass null so QuotaBar drops the "+Ad" affordance
            // entirely — free users only see the "Upgrade" path until the
            // flag flips on without an app update.
            onWatchAd: !_features.adsEnabled || _isWatchingProactiveAd
                ? null
                : _watchProactiveAd,
          ),
      ],
    );
  }

  bool _isWatchingProactiveAd = false;

  /// Proactive "Watch ad for more quota" — lets a free user top up
  /// BEFORE hitting the daily wall. Necessary because each ad only
  /// grants +200 chars; a single 500-char translation would otherwise
  /// require try → 429 → ad → try → 429 → ad → try cycle. With this
  /// button users can pre-stack 2-3 ads in a row, then translate.
  Future<void> _watchProactiveAd() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _isWatchingProactiveAd = true);
    final adService = RewardedAdService();
    try {
      await adService.preload();
      final earned = await adService.showAndAwaitReward();
      if (!mounted) return;
      if (!earned) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.paywallAdNotComplete)),
        );
        return;
      }
      try {
        final api = ref.read(apiClientProvider);
        await api.dio.post('/quota/grant-reward');
        await ref.read(usageProvider.notifier).refresh();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.quotaRewardGranted)),
        );
      } on DioException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            e.response?.data is Map
                ? (e.response?.data['message']?.toString() ?? l.paywallCreditFailed)
                : l.paywallCreditFailed,
          ),
        ));
      }
    } finally {
      adService.dispose();
      if (mounted) setState(() => _isWatchingProactiveAd = false);
    }
  }

  Widget _buildTranslateTab() {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final translateState = ref.watch(translateProvider);
    final state = translateState.valueOrNull;
    final isLoading = state?.isLoading ?? false;
    final result = state?.result;

    // When a reply finishes, auto-copy and offer to replace the input —
    // mirrors the desktop Cmd+Shift+R flow inside the app.
    ref.listen<AsyncValue<TranslateState>>(translateProvider, (prev, next) {
      final prevResult = prev?.valueOrNull?.result;
      final nextState = next.valueOrNull;
      final nextResult = nextState?.result;
      if (nextResult != null && nextResult != prevResult &&
          nextState?.mode == TranslateMode.reply) {
        _onReplyReady(nextResult.translation, l);
      }

      // Daily-quota wall: free user just hit the 20-req/2000-char cap.
      // Intercept the 429 and show the paywall sheet so they can either
      // watch a rewarded ad (+5 / +500) or upgrade. On a successful ad
      // grant, retry the original translation with the same mode +
      // source text the user had in flight.
      final prevCode = prev?.valueOrNull?.errorCode;
      final nextCode = nextState?.errorCode;
      if (nextCode == ApiErrorCode.quotaExceeded && nextCode != prevCode) {
        _showPaywall(nextState!.mode);
      }
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
            ClipboardChip(
              text: _clipboardSuggestion!,
              onUse: _useClipboardSuggestion,
              onDismiss: _dismissClipboardSuggestion,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Consumer(builder: (_, ref, __) {
            final langs = ref.watch(languageSettingsProvider).valueOrNull;
            final sourceLang = langs?.sourceLang ?? 'auto';
            final targetLang = langs?.targetLang ?? 'en';
            return LanguageBar(
              sourceLang: sourceLang,
              targetLang: targetLang,
              detectedLang: sourceLang == 'auto' ? result?.detectedLang : null,
              isDark: isDark,
              onPickSource: () => _pickSourceLang(sourceLang),
              onPickTarget: () => _pickTargetLang(targetLang),
              onSwap: _swapLanguages,
            );
          }),
          const SizedBox(height: AppSpacing.md),

          Consumer(builder: (_, ref, __) {
            // Voice can't auto-detect language on Android, so when source
            // is "auto" we surface a muted mic + a tooltip that explains
            // the next step instead of letting the user wonder why the
            // button "doesn't work" (tap still works — it opens the picker).
            final src = ref.watch(languageSettingsProvider).valueOrNull?.sourceLang ?? 'auto';
            final ready = src != 'auto';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SourceField(
                  controller: _textController,
                  focusNode: _inputFocus,
                  maxChars: _maxChars,
                  hintText: l.hintEnterText,
                  isListening: isListening,
                  voiceReady: ready,
                  voiceTooltip: isListening
                      ? l.voiceListening
                      : (ready ? l.voiceTooltip : l.voiceNeedsLang),
                  onVoicePressed: toggleSpeechToText,
                  onClear: () {
                    _textController.clear();
                    ref.read(translateProvider.notifier).clearResult();
                  },
                ),
                // Glossary name chips — tap to insert into the input. Speech
                // recognizers reliably mangle foreign names ("Shinzato" →
                // "sinh nhật" on vi-VN); the chips make the recovery one tap
                // instead of retyping the whole name. Empty/no-name glossary
                // → palette returns SizedBox.shrink() so this costs nothing.
                NameChipPalette(
                  controller: _textController,
                  focusNode: _inputFocus,
                ),
              ],
            );
          }),
          const SizedBox(height: AppSpacing.md),

          // Camera moved to bottom NavigationBar (4th tab). Don't pass
          // onCamera so the home FeatureButtons row doesn't render the
          // duplicate camera button — bottom-bar entry is the single
          // discoverable surface for Camera now.
          FeatureButtons(
            isDark: isDark,
            features: _features,
            onAction: _handleAction,
          ),
          const SizedBox(height: AppSpacing.md),

          if (state?.error != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              child: Text(
                // Prefer the localized text derived from errorCode so the
                // banner respects the user's locale; fall back to the raw
                // message field only for codes we don't have a mapping for
                // (effectively only the catch-unknown branch).
                state!.errorCode?.localize(l) ?? state.error ?? l.errorGeneric,
                style: const TextStyle(color: AppColors.red),
              ),
            ),

          if (result != null)
            ResultCard(
              result: result,
              isDark: isDark,
              onCopy: _copyToClipboard,
            ),

          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
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

/// Modern bottom navigation — custom layout instead of Material 3's
/// stock NavigationBar so we can get:
///   • Rounded top corners + soft elevated shadow (lifts the bar
///     visually, signals "this is a surface, not a stripe")
///   • Pill-shaped indicator behind the selected tab (primary tint)
///   • Floating gradient Camera button raised above the bar's center
///     (Instagram / TikTok primary-action pattern)
///   • Smooth 200ms cross-fade between selected / idle tab states
///   • Theme-aware: tints adapt to dark/light mode without hardcoded
///     colors
class _BottomBarWithCamera extends StatelessWidget {
  const _BottomBarWithCamera({
    required this.currentTab,
    required this.onTabChanged,
    required this.onCameraTap,
  });

  final int currentTab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onCameraTap;

  /// Lift = how far the camera button sits above the bar top edge.
  /// Equal to half the FAB size so the bar's top edge passes exactly
  /// through the FAB's vertical midpoint — half the circle floats above
  /// the bar, half sits inside it. Cleaner visual ratio than the earlier
  /// 28 (which left a faint asymmetry).
  static const double _kCameraSize = 60;
  static const double _kCameraLift = _kCameraSize / 2;
  static const double _kBarHeight = 64;
  static const double _kTopRadius = 22;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Background + shadow + border go on the INNER bar (only _kBarHeight
    // tall), NOT the outer wrapper. If they sat on the wrapper, the wrapper's
    // full height (bar + lift) would be painted in surface colour — making
    // the lift region above the bar look like an extension of the bar and
    // the FAB appear "stuck on top of a tall bar" instead of half-floating.
    // Keeping the lift region transparent is what gives the FAB the real
    // half-in / half-out look the user asked for.
    return SafeArea(
      top: false,
      child: SizedBox(
        height: _kBarHeight + _kCameraLift,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Bar surface + tabs — only the bottom _kBarHeight is painted.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _kBarHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(_kTopRadius),
                    topRight: Radius.circular(_kTopRadius),
                  ),
                  // Soft lift shadow + subtle top hairline for definition.
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.45)
                          : Colors.black.withValues(alpha: 0.07),
                      blurRadius: 24,
                      offset: const Offset(0, -4),
                    ),
                  ],
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.08),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                      Expanded(
                        child: _TabButton(
                          label: l.translate,
                          icon: Icons.translate_outlined,
                          selectedIcon: Icons.translate,
                          isSelected: currentTab == 0,
                          onTap: () => onTabChanged(0),
                        ),
                      ),
                      Expanded(
                        child: _TabButton(
                          label: l.history,
                          icon: Icons.history_outlined,
                          selectedIcon: Icons.history,
                          isSelected: currentTab == 1,
                          onTap: () => onTabChanged(1),
                        ),
                      ),
                      // Gap reserved for the floating camera button.
                      // Slightly wider than the FAB so tab pills don't
                      // sit too close to the circle.
                      const SizedBox(width: 72),
                      Expanded(
                        child: _TabButton(
                          label: l.glossary,
                          icon: Icons.menu_book_outlined,
                          selectedIcon: Icons.menu_book,
                          isSelected: currentTab == 2,
                          onTap: () => onTabChanged(2),
                        ),
                      ),
                      Expanded(
                        child: _TabButton(
                          label: l.settings,
                          icon: Icons.settings_outlined,
                          selectedIcon: Icons.settings,
                          isSelected: currentTab == 3,
                          onTap: () => onTabChanged(3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Floating Camera button — centered horizontally, raised
              // by [_kCameraLift] above the bar's top edge.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: _CameraFab(
                    onTap: onCameraTap,
                    tooltip: l.cameraTitle,
                    size: _kCameraSize,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// One tab in the modern bottom bar — animated pill background appears
/// when selected (primary tint @ 12%), icon swaps to filled variant,
/// label gains primary color + slight weight bump. AnimatedContainer
/// gives the 200 ms cross-fade.
class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final mutedColor =
        theme.colorScheme.onSurface.withValues(alpha: 0.62);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      splashColor: primary.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                size: 22,
                color: isSelected ? primary : mutedColor,
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  color: isSelected ? primary : mutedColor,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating camera shortcut. Gradient circle (primary → tertiary) with
/// tinted soft shadow + white camera glyph. Larger than the stock M3
/// FAB (60 vs 56) so it reads as the primary action on the bar.
class _CameraFab extends StatelessWidget {
  const _CameraFab({
    required this.onTap,
    required this.tooltip,
    required this.size,
  });

  final VoidCallback onTap;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    // Tertiary may equal primary in plain ColorScheme — blend toward
    // a slightly cooler shade for a visible gradient even on minimalist
    // themes.
    final gradientEnd = Color.lerp(primary, theme.colorScheme.tertiary, 0.6) ??
        primary;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, gradientEnd],
          ),
          boxShadow: [
            // Big soft tinted shadow — the "glow" that lifts the FAB
            // off the bar. Tint of primary so it never looks dirty
            // grey in dark mode.
            BoxShadow(
              color: primary.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
              spreadRadius: 0,
            ),
            // Sharper inner shadow for crisper outline against the bar.
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            splashColor: Colors.white.withValues(alpha: 0.2),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            child: Icon(
              Icons.camera_alt_rounded,
              color: theme.colorScheme.onPrimary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
