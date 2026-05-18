import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../../../shared/widgets/selectable_with_actions.dart';
import '../../../shared/widgets/toast.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../../settings/providers/app_settings_provider.dart';
import '../models/language.dart';
import '../models/translate_models.dart';
import '../providers/translate_provider.dart';
import 'language_picker_sheet.dart';
import 'tts_button.dart';

/// Bottom sheet for translate triggered from Share Extension.
/// Shows source text (collapsible) + tab bar for modes + result area.
class ResultBottomSheet extends ConsumerStatefulWidget {
  const ResultBottomSheet({
    super.key,
    required this.sourceText,
    required this.targetLang,
  });

  final String sourceText;
  final String targetLang;

  @override
  ConsumerState<ResultBottomSheet> createState() => _ResultBottomSheetState();
}

// Explicit tab → mode mapping. Order must match _tabs below.
const _tabModes = <TranslateMode>[
  TranslateMode.translate,
  TranslateMode.summarize,
  TranslateMode.explain,
  TranslateMode.refine,
];

class _ResultBottomSheetState extends ConsumerState<ResultBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _sourceExpanded = false;
  String? _overrideTargetLang;
  Timer? _autoCloseTimer;
  bool _userInteracted = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabModes.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(translateProvider.notifier).translate(
            text: widget.sourceText,
            targetLang: _currentTargetLang,
          );
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  String get _currentTargetLang =>
      _overrideTargetLang ?? widget.targetLang;

  bool get _isProUser =>
      ref.read(authStateProvider).valueOrNull?.session?.isPro ?? false;

  TranslateMode get _currentMode => _tabModes[_tabController.index];

  void _scheduleAutoClose(int seconds) {
    _autoCloseTimer?.cancel();
    if (seconds <= 0 || _userInteracted) return;
    _autoCloseTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _cancelAutoClose() {
    _userInteracted = true;
    _autoCloseTimer?.cancel();
  }

  void _handleTab(int index) {
    _cancelAutoClose();
    final mode = _tabModes[index];
    if (mode.requiresPro && !_isProUser) {
      // Revert tab visually since Pro gate blocks the switch.
      _tabController.animateTo(0);
      UpgradeNudgeSheet.show(context, featureName: mode.label);
      return;
    }

    final notifier = ref.read(translateProvider.notifier);
    final target = _currentTargetLang;
    switch (mode) {
      case TranslateMode.translate:
        notifier.translate(text: widget.sourceText, targetLang: target);
      case TranslateMode.reply:
        notifier.translate(
            text: widget.sourceText, targetLang: target, isReply: true);
      case TranslateMode.summarize:
        notifier.summarize(text: widget.sourceText, targetLang: target);
      case TranslateMode.explain:
        notifier.explain(text: widget.sourceText, targetLang: target);
      case TranslateMode.refine:
        notifier.refine(text: widget.sourceText);
    }
  }

  Future<void> _pickTargetLang() async {
    _cancelAutoClose();
    final code = await LanguagePickerSheet.show(
      context,
      selectedCode: _currentTargetLang,
      showAuto: false,
      field: LanguagePickerField.target,
    );
    if (code != null && code != _currentTargetLang) {
      setState(() => _overrideTargetLang = code);
      _handleTab(_tabController.index);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    final l = AppLocalizations.of(context)!;
    // Toast appears on the root overlay so it stays visible above this
    // modal sheet (a SnackBar would render behind it on the parent Scaffold).
    showAppToast(context, l.copied);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final translateState = ref.watch(translateProvider);
    final state = translateState.valueOrNull;
    final result = state?.result;
    final isLoading = state?.isLoading ?? false;
    final mode = _currentMode;
    final showLangChip = mode != TranslateMode.refine;

    // Re-arm auto-close whenever a new result arrives.
    ref.listen<AsyncValue<TranslateState>>(translateProvider, (prev, next) {
      final newRes = next.valueOrNull?.result;
      if (newRes != null && prev?.valueOrNull?.result != newRes) {
        final secs = ref.read(appSettingsProvider).valueOrNull?.autoCloseSeconds ?? 0;
        _scheduleAutoClose(secs);
      }
    });

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanDown: (_) => _cancelAutoClose(),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              const Center(child: DragHandle()),

              if (showLangChip) _buildLangRow(l),

              _buildSourceText(theme),

              TabBar(
                controller: _tabController,
                onTap: _handleTab,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                labelColor: AppColors.primary,
                unselectedLabelColor: isDark
                    ? AppColors.textSecondary
                    : AppColors.textSecondaryLight,
                indicatorColor: AppColors.primary,
                tabs: [
                  Tab(text: l.tabTranslate),
                  Tab(text: l.tabSummarize),
                  Tab(text: l.tabExplain),
                  Tab(text: l.tabRefine),
                ],
              ),

              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state?.error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Text(
                            state!.error!,
                            style: const TextStyle(color: AppColors.red),
                          ),
                        ),
                      if (isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (result != null)
                        _buildResultBody(theme, result),
                    ],
                  ),
                ),
              ),

              if (result != null) _buildActionBar(isDark, result),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLangRow(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          const Icon(Icons.translate_outlined,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            l.popupTo,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: GestureDetector(
              onTap: _pickTargetLang,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        languageByCode(_currentTargetLang).nativeName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_drop_down,
                        size: 16, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceText(ThemeData theme) {
    return InkWell(
      onTap: () => setState(() => _sourceExpanded = !_sourceExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.sourceText,
                maxLines: _sourceExpanded ? null : 2,
                overflow: _sourceExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Icon(
              _sourceExpanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultBody(ThemeData theme, TranslateResult result) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableWithActions(
          result.translation,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.5,
          ),
          targetLang: _currentTargetLang,
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
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: result.suggestions
                .map((s) => ActionChip(
                      label: Text(s.target),
                      onPressed: () => _copyToClipboard(s.target),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildActionBar(bool isDark, TranslateResult result) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.border : AppColors.borderLight,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: () => _copyToClipboard(result.translation),
          ),
          TtsButton(
              text: result.translation,
              lang: _currentTargetLang,
              size: 20),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
