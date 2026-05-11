import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../models/translate_models.dart';
import '../providers/translate_provider.dart';

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

class _ResultBottomSheetState extends ConsumerState<ResultBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _sourceExpanded = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Auto-translate on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(translateProvider.notifier).translate(
            text: widget.sourceText,
            targetLang: widget.targetLang,
          );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isProUser {
    final auth = ref.read(authStateProvider).valueOrNull; // from auth_provider
    return auth?.session?.isPro ?? false;
  }

  void _handleTab(int index) {
    const modes = TranslateMode.values;
    final mode = modes[index];
    if (mode.requiresPro && !_isProUser) {
      UpgradeNudgeSheet.show(context, featureName: mode.label);
      return;
    }

    final notifier = ref.read(translateProvider.notifier);
    switch (mode) {
      case TranslateMode.translate:
        notifier.translate(
          text: widget.sourceText,
          targetLang: widget.targetLang,
        );
      case TranslateMode.summarize:
        notifier.summarize(text: widget.sourceText, targetLang: widget.targetLang);
      case TranslateMode.explain:
        notifier.explain(text: widget.sourceText, targetLang: widget.targetLang);
      case TranslateMode.refine:
        notifier.refine(text: widget.sourceText);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final translateState = ref.watch(translateProvider);
    final state = translateState.valueOrNull;
    final result = state?.result;
    final isLoading = state?.isLoading ?? false;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const Center(child: DragHandle()),

            // Source text (collapsible)
            InkWell(
              onTap: () => setState(() => _sourceExpanded = !_sourceExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedCrossFade(
                        firstChild: Text(
                          widget.sourceText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        secondChild: Text(
                          widget.sourceText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        crossFadeState: _sourceExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 200),
                      ),
                    ),
                    Icon(
                      _sourceExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),

            // Tab bar
            TabBar(
              controller: _tabController,
              onTap: _handleTab,
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              labelColor: AppColors.primary,
              unselectedLabelColor:
                  isDark ? AppColors.textSecondary : AppColors.textSecondaryLight,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Translate'),
                Tab(text: 'Summarize'),
                Tab(text: 'Explain'),
                Tab(text: 'Refine'),
              ],
            ),

            // Result area
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
                      const Center(child: CircularProgressIndicator())
                    else if (result != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            result.translation,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 16,
                              height: 1.5,
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
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // Action bar
            if (result != null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
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
                    IconButton(
                      icon: const Icon(Icons.volume_up_outlined, size: 20),
                      onPressed: () {/* TODO: TTS */},
                    ),
                    IconButton(
                      icon: const Icon(Icons.star_outline, size: 20),
                      onPressed: () {/* TODO: Save */},
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
