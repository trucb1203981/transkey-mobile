import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

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
import '../../../shared/theme/app_glass.dart';
import '../../../shared/widgets/glass/aurora_background.dart';
import '../../../shared/widgets/glass/glass_app_bar.dart';
import '../../../shared/widgets/plan_status_banner.dart';
import '../../../shared/widgets/quota_bar.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../../history/screens/history_screen.dart';
import '../../glossary/screens/glossary_screen.dart';
import '../../onboarding/providers/setup_status_provider.dart';
import '../../onboarding/screens/setup_hub_screen.dart';
import '../../onboarding/widgets/setup_reminder_banner.dart';
import '../../../core/bubble/bubble_manager.dart';
import '../../settings/providers/app_settings_provider.dart';
import '../../settings/screens/settings_screen.dart';
import '../../../core/api/dio_client.dart';
import '../../upgrade/providers/usage_provider.dart';
import '../../upgrade/screens/quota_exhausted_screen.dart';
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
  // iOS-only: "clipboard has text" chip shown WITHOUT reading the pasteboard
  // (UIPasteboard.hasStrings raises no paste banner). The actual read — and
  // the one-time iOS paste confirmation — happens on tap.
  bool _clipboardChipIOS = false;
  bool _clipboardChipDismissed = false;
  // The iOS paste confirmation briefly backgrounds the app; the resume that
  // follows re-peeks and would resurrect the chip right after a successful
  // paste. Suppress peeks for a short window around a paste action.
  DateTime? _lastIOSPasteAt;
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
    // *behind* the setup screen. Order matters:
    // 1. Decide whether to push setup; if pushed, don't focus.
    // 2. Restore last source text (skips focus when text is restored).
    // 3. Peek clipboard for the suggestion chip.
    // 4. If safe, focus the input so the user can start typing immediately.
    //
    // The prompt is driven by the REAL platform state, not by a "seen it" flag:
    // the old gate marked itself done when the user tapped Skip, so one stray
    // tap on the very first screen removed the only guidance they would ever be
    // offered. Now it stops after a few launches, and the home banner keeps the
    // door open for as long as something is actually still off.
    final status = await ref.read(setupStatusProvider.future);
    final prompts = await SetupHubScreen.promptCount();
    if (!mounted) return;
    if (status.hasWorkLeft && prompts < SetupHubScreen.maxAutoPrompts) {
      await SetupHubScreen.notePrompted();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push('/setup');
      });
      // Don't focus - the setup screen will be on top.
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
    if (state == AppLifecycleState.paused) {
      // Reset the quota-wall "already dismissed this foreground" flag so
      // it re-appears on the next resume / cold start while the user is
      // still exhausted.
      QuotaExhaustedScreen.onAppPaused();
    }
    if (state == AppLifecycleState.resumed) {
      ref.read(languageSettingsProvider.notifier).reload();
      ref.read(appSettingsProvider.notifier).reload();
      ref.read(ttsProvider.notifier).reload();
      ref.read(usageProvider.notifier).refreshIfStale();
      ref.read(authStateProvider.notifier).refreshUser();
      // After usage refresh resolves, _maybeShowQuotaWall is invoked
      // from the build-time ref.listen on usageProvider (see
      // _buildTranslateTab) so we don't need an explicit call here.
      // Pick up admin changes to the language catalog (enable/disable/rename)
      // without forcing a full app restart.
      ref.read(featuresProvider.notifier).refreshIfNeeded();
      // Re-peek on EVERY resume: on iOS this is banner-free now (hasStrings
      // only; the read happens on chip tap), and coming back from another
      // app is exactly when a fresh copy is most likely. Reset the dismiss
      // so a chip the user hid in a previous session can reappear.
      _clipboardChipDismissed = false;
      _peekClipboard();
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
    try {
      if (Platform.isIOS) {
        // hasStrings = UIPasteboard.hasStrings: answers "is there text?"
        // WITHOUT reading, so no iOS "Allow Paste" banner. The read (and its
        // one-time confirmation) happens only when the user taps the chip.
        final justPasted = _lastIOSPasteAt != null &&
            DateTime.now().difference(_lastIOSPasteAt!).inSeconds < 5;
        final has = await Clipboard.hasStrings();
        if (!mounted) return;
        setState(() =>
            _clipboardChipIOS = has && !_clipboardChipDismissed && !justPasted);
        return;
      }
      // Android: no paste banner, read freely and preview the text.
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
    if (Platform.isIOS && _clipboardSuggestion == null) {
      _pasteAndTranslateIOS();
      return;
    }
    final text = _clipboardSuggestion;
    if (text == null) return;
    _textController.text = text;
    setState(() {
      _clipboardSuggestion = null;
    });
    _handleAction(TranslateMode.translate);
  }

  /// iOS chip tap: read the pasteboard NOW (the system paste confirmation
  /// appears tied to this explicit user intent), fill and translate in one go.
  Future<void> _pasteAndTranslateIOS() async {
    _lastIOSPasteAt = DateTime.now();
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (!mounted) return;
      _lastIOSPasteAt = DateTime.now();
      setState(() => _clipboardChipIOS = false);
      if (text == null || text.isEmpty || text.length > _maxChars) return;
      _textController.text = text;
      _handleAction(TranslateMode.translate);
    } catch (_) {
      if (mounted) setState(() => _clipboardChipIOS = false);
    }
  }

  void _dismissClipboardSuggestion() {
    setState(() {
      _dismissedClipboard = _clipboardSuggestion;
      _clipboardSuggestion = null;
      _clipboardChipDismissed = true;
      _clipboardChipIOS = false;
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
    // Fail OPEN until /features has resolved (fetchedAt != null). Before the
    // first response every paid flag holds its pessimistic default (off), so
    // gating on that wrongly nudged a paid user to upgrade during the load /
    // failure window - the "pro account but upgrade popup" bug (also seen on
    // Refine). The server's 403 is the real gate for a genuine free user.
    final featState = ref.watch(featuresProvider);
    if (featState.fetchedAt == null) return true;
    final flags = featState.flags;
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
    // Only block when we KNOW the plan lacks camera, i.e. /features has
    // actually loaded (fetchedAt != null). The default before the first
    // response is camera=false; gating on that wrongly nudged a paid user
    // who tapped during the load window - the "camera opens sometimes,
    // sometimes not" bug. When the flag state is unknown, open optimistically
    // and let the capture path's server guard (403) be the real gate.
    final featState = ref.read(featuresProvider);
    if (featState.fetchedAt != null && !featState.flags.camera) {
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

  /// Surface the full-screen quota-exhausted wall if the latest usage
  /// snapshot says a FREE user has hit either daily cap. The wall is
  /// strictly free-plan-only: trial / mobile / pro plans have higher or
  /// unlimited caps where "exhausted" doesn't apply, so we explicitly
  /// gate on the session-derived plan (the JWT source of truth) AND
  /// re-check inside [QuotaExhaustedScreen.shouldShow] for defence in
  /// depth. The screen itself enforces "don't re-pop after dismiss until
  /// app backgrounds" so this method can be invoked freely from any
  /// listener / lifecycle hook.
  void _maybeShowQuotaWall(UsageInfo? usage, String usagePlan) {
    if (!mounted) return;
    final sessionPlan =
        ref.read(authStateProvider).valueOrNull?.session?.plan ?? 'free';
    if (sessionPlan != 'free' || usagePlan != 'free') return;
    if (!QuotaExhaustedScreen.shouldShow(plan: sessionPlan, usage: usage)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) QuotaExhaustedScreen.show(context);
    });
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

  /// Reply or refine just finished — directly replace the input text with
  /// the result and offer undo. Mirrors the keyboard's Trau chuốt chip
  /// and desktop Cmd+Shift+R flow where the result replaces the input.
  void _onAutoReplace(String result, AppLocalizations l) {
    if (result.isEmpty) return;
    final originalSource = _textController.text;
    _textController.text = result;
    // Clear the ResultCard so only the replaced input is visible.
    ref.read(translateProvider.notifier).clearResult();
    Clipboard.setData(ClipboardData(text: result));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.copied),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _textController.text = originalSource;
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      // Aurora is the base layer behind everything; the tab bar's own glass
      // floats over this same near-black base.
      backgroundColor: GlassPalette.forDark(isDark).auroraBase,
      // Let the body (and its aurora) draw BEHIND the floating glass tab bar
      // on every tab, so the aurora stays continuous — otherwise the
      // transparent lift region above the bar reads as a flat black band. The
      // tab screens (History/Glossary/Settings) are aurora Scaffolds too and
      // pad their scroll content to clear the bar.
      extendBody: true,
      body: AuroraBackground(
        isDark: isDark,
        // No bottom inset: tab content scrolls on behind the floating glass
        // capsule (each tab pads its scroll view by 100 to clear it), so the
        // bottom padding is removed rather than left to SafeArea.
        child: SafeArea(
          bottom: false,
          // [context] is above the SafeArea, so its top inset is removed too
          // or the tab app bars would add the status bar height a second time.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
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
        ),
      ),
      // Floating glass tab capsule + Camera disc (see _BottomBarWithCamera).
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

  Widget _buildTranslateTabWithQuota() => _buildTranslateTab();

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
                ? (e.response?.data['message']?.toString() ??
                    l.paywallCreditFailed)
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

    // When a reply or refine finishes, auto-replace the input text and
    // offer undo — mirrors the desktop Cmd+Shift+R flow.
    ref.listen<AsyncValue<TranslateState>>(translateProvider, (prev, next) {
      final prevResult = prev?.valueOrNull?.result;
      final nextState = next.valueOrNull;
      final nextResult = nextState?.result;
      if (nextResult != null &&
          nextResult != prevResult &&
          (nextState?.mode == TranslateMode.reply ||
              nextState?.mode == TranslateMode.refine)) {
        _onAutoReplace(nextResult.translation, l);
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
      final sessionPlan =
          ref.read(authStateProvider).valueOrNull?.session?.plan;
      if (sessionPlan != null && sessionPlan != usagePlan) {
        ref.read(authStateProvider.notifier).refreshUser();
      }
      // Quota-exhausted full-screen wall. Each fresh usage snapshot — at
      // cold start, on lifecycle resume (refreshIfStale), and after every
      // translate — funnels through here. The screen has its own gating
      // (foreground-dismiss flag + isShowing) so we can call freely.
      _maybeShowQuotaWall(next.valueOrNull, usagePlan);
    });

    return SingleChildScrollView(
      // Extra bottom padding clears the floating glass tab bar (bar height +
      // camera FAB lift) now that the body draws behind it (extendBody).
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HomeHeader(tagline: l.homeTagline, isDark: isDark),
          // Trial countdown / subscription-expired banner — shown above
          // everything so the user can't miss it. The banner widget
          // returns SizedBox.shrink() with no margin when nothing is to
          // be shown, so no awkward spacing on the common case.
          const PlanStatusBanner(),
          // Persistent, non-modal door back into setup. The automatic prompt
          // stops after a few launches; this stays for as long as something is
          // genuinely still off, and removes itself the moment both are on.
          const SetupReminderBanner(),
          if (_clipboardSuggestion != null || _clipboardChipIOS) ...[
            ClipboardChip(
              // iOS can't preview without triggering the paste banner —
              // show a generic call-to-action instead of the text.
              text: _clipboardSuggestion ??
                  AppLocalizations.of(context)!.pasteTranslate,
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
            final src =
                ref.watch(languageSettingsProvider).valueOrNull?.sourceLang ??
                    'auto';
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
                  // Source-side TTS: use the pinned lang, or the server's
                  // detected lang once a translation came back (auto mode).
                  // The server returns the literal string 'auto' when its
                  // script heuristic can't tell (all Latin-script langs) -
                  // not a speakable code, so treat it as unknown.
                  ttsLang: ready
                      ? src
                      : (result?.detectedLang != 'auto'
                          ? result?.detectedLang
                          : null),
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
            activeMode: state?.result != null ? state?.mode : null,
            onAction: _handleAction,
          ),
          const SizedBox(height: AppSpacing.md),
          Consumer(builder: (_, ref, __) {
            final usage = ref.watch(usageProvider).valueOrNull;
            final plan =
                ref.watch(authStateProvider).valueOrNull?.session?.plan ??
                    'free';
            if (plan != 'free' || usage == null) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: QuotaBar(
                used: usage.requestsUsed,
                limit: usage.requestsLimit,
                charsUsed: usage.charsUsed,
                charsLimit: usage.charsLimit,
                isWatchingAd: _isWatchingProactiveAd,
                onWatchAd: !_features.adsEnabled || _isWatchingProactiveAd
                    ? null
                    : _watchProactiveAd,
              ),
            );
          }),

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

class _HomeHeader extends ConsumerStatefulWidget {
  const _HomeHeader({required this.tagline, required this.isDark});

  final String tagline;
  final bool isDark;

  @override
  ConsumerState<_HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends ConsumerState<_HomeHeader>
    with WidgetsBindingObserver {
  // Same channel + handlers the Settings screen uses for the IME shortcut.
  static const _imeChannel = MethodChannel('transkey/ime');
  bool _imeEnabled = false;
  bool _imeSelected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshIme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have switched the active keyboard, or granted the button
    // permission, while we were backgrounded. Re-poll BOTH: re-reading only the
    // keyboard is why a user who had just granted the permission came back to
    // an unchanged grey button and assumed nothing had happened.
    if (state != AppLifecycleState.resumed) return;
    _refreshIme();
    ref.read(setupStatusProvider.notifier).refresh();
  }

  Future<void> _refreshIme() async {
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
      // Older Android / channel not ready - button still opens settings.
    }
  }

  /// Android forbids an app from programmatically setting/clearing the default
  /// keyboard, so the best we can do is route the user to the right system UI:
  /// not-enabled -> IME settings to switch it on; enabled -> the system picker
  /// (pick TransKey to turn on, pick another keyboard to turn off).
  Future<void> _onKeyboardTap() async {
    if (!Platform.isAndroid) return;
    try {
      if (!_imeEnabled) {
        await _imeChannel.invokeMethod('openImeSettings');
      } else {
        await _imeChannel.invokeMethod('showImePicker');
      }
    } catch (_) {
      // ignore - nothing actionable
    }
    // The picker resolves after this returns; re-poll a moment later so the
    // toggle reflects the user's choice without waiting for a full resume.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) _refreshIme();
  }

  Future<void> _onBubbleTap(bool running) async {
    final mgr = ref.read(bubbleManagerProvider.notifier);
    if (running) {
      await mgr.stopBubble();
      return;
    }
    final has = await mgr.checkPermission();
    if (!has) {
      // Send the user through the guided flow instead of straight into system
      // settings. The old path fired a SnackBar right as the system screen
      // covered the app, so the one explanation on offer was painted behind it
      // and had timed out before the user came back.
      if (mounted) context.push('/setup/button');
      return;
    }
    await mgr.startBubble(source: 'home_header');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final bubbleRunning = ref.watch(bubbleManagerProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                  ).createShader(bounds),
                  child: Text(
                    'TransKey',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Colors.white,
                    ),
                  ),
                ),
                Text(
                  widget.tagline,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: GlassPalette.forDark(widget.isDark).textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Quick toggles (Android only): set TransKey as the active keyboard,
          // and turn the floating bubble on/off - both gradient when active.
          // Grouped in one glass capsule like the app bar actions.
          if (Platform.isAndroid)
            GlassCapsule(
              children: [
                _GradientIconButton(
                  icon: Icons.keyboard_rounded,
                  active: _imeSelected,
                  tooltip: l.imeKeyboardTitle,
                  onTap: _onKeyboardTap,
                ),
                const SizedBox(width: 2),
                _GradientIconButton(
                  icon: Icons.bubble_chart_rounded,
                  active: bubbleRunning,
                  tooltip: bubbleRunning ? l.bubbleActive : l.bubbleInactive,
                  onTap: () => _onBubbleTap(bubbleRunning),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Round icon button inside the home-header glass capsule: lit with the brand
/// gradient when [active], bare on the capsule glass when off. Used for the
/// quick toggles (keyboard / bubble).
class _GradientIconButton extends StatelessWidget {
  const _GradientIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = GlassPalette.forDark(isDark);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active ? AppGlass.brand : null,
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? Colors.white : p.textSecondary,
            ),
          ),
        ),
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

/// Floating Liquid Glass navigation, the iOS 26 tab bar shape (as in Slack):
///   • a frosted capsule inset from the screen edges, so content scrolls
///     visibly behind and around it
///   • the selected tab sits in its own lighter glass pill inside the capsule
///   • the Camera primary action is a separate gradient disc beside the
///     capsule, the slot iOS gives a tab bar's accessory button
class _BottomBarWithCamera extends StatelessWidget {
  const _BottomBarWithCamera({
    required this.currentTab,
    required this.onTabChanged,
    required this.onCameraTap,
  });

  final int currentTab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onCameraTap;

  static const double _kBarHeight = 64;
  static const double _kSideInset = 16;
  static const double _kCameraGap = 10;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final p = GlassPalette.of(context);
    // Float into the home-indicator zone like the system bar does, but keep
    // a gap above the screen edge on devices without one.
    final bottom =
        math.max(MediaQuery.viewPaddingOf(context).bottom - 12, 12.0);
    final tabs = [
      (l.translate, Icons.translate_outlined, Icons.translate),
      (l.history, Icons.history_outlined, Icons.history),
      (l.glossary, Icons.menu_book_outlined, Icons.menu_book),
      (l.settings, Icons.settings_outlined, Icons.settings),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(_kSideInset, 0, _kSideInset, bottom),
      child: SizedBox(
        height: _kBarHeight,
        child: Row(
          children: [
            Expanded(
              // The shadow lives outside the clip so it can lift the capsule;
              // the blur and glass fill live inside the rounded clip. This is
              // the app's one real BackdropFilter (weak-device budget).
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppGlass.rPill),
                  boxShadow: [
                    BoxShadow(
                      color: p.shadow,
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppGlass.rPill),
                  child: BackdropFilter(
                    filter: AppGlass.frost(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // Top-lit: a brighter upper edge reads as curved glass.
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.alphaBlend(p.fillFaint, p.fillStrong),
                            p.fill,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(AppGlass.rPill),
                        border: Border.all(color: p.border, width: 0.8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Row(
                          children: [
                            for (var i = 0; i < tabs.length; i++)
                              Expanded(
                                child: _TabButton(
                                  label: tabs[i].$1,
                                  icon: tabs[i].$2,
                                  selectedIcon: tabs[i].$3,
                                  isSelected: currentTab == i,
                                  onTap: () => onTabChanged(i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: _kCameraGap),
            _CameraFab(
              onTap: onCameraTap,
              tooltip: l.cameraTitle,
              size: _kBarHeight,
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab in the glass capsule: the selected tab gets its own lighter glass
/// pill (200 ms cross-fade), a filled icon and the accent tint. Text on glass
/// uses the palette's accentStrong / textSecondary, never the raw brand
/// indigo, which is unreadable on violet glass.
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
    final p = GlassPalette.of(context);
    final color = isSelected ? p.accentStrong : p.textSecondary;
    // Dark: a lighter glass pill. Light: the capsule is already near-white,
    // so a white pill vanishes; tint it with the accent instead.
    final pillFill = p == GlassPalette.light
        ? p.accent.withValues(alpha: 0.14)
        : p.fillStrong;
    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        splashColor: p.fill,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: ShapeDecoration(
            color: isSelected ? pillFill : Colors.transparent,
            shape: StadiumBorder(
              side: BorderSide(
                color: isSelected ? p.border : Colors.transparent,
                width: 0.6,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isSelected ? selectedIcon : icon, size: 22, color: color),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  color: color,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Camera shortcut beside the tab capsule. Gradient circle (primary →
/// tertiary) with a glass rim, tinted soft shadow and a white camera glyph,
/// as tall as the capsule so the two read as one bar.
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
    final gradientEnd =
        Color.lerp(primary, theme.colorScheme.tertiary, 0.6) ?? primary;
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
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 0.8,
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
