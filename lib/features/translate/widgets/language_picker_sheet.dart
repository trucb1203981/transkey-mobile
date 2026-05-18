import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/generated/app_localizations.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/drag_handle.dart';
import '../models/language.dart';
import '../providers/features_provider.dart';
import '../providers/language_settings_provider.dart';

/// Which slot the picker is filling. Drives the allowed_* gate so admin's
/// per-field restrictions in /system-config are respected here.
enum LanguagePickerField { target, source, reply }

/// Optional hint banner shown at the top of [LanguagePickerSheet]. Use
/// this when the caller is opening the picker in response to a *condition*
/// the user needs to resolve (e.g. voice input requires a concrete source
/// language) so the explanation is in the picker itself — a snackbar shown
/// alongside the modal would be hidden behind it.
class LanguagePickerHint {
  const LanguagePickerHint({required this.text, this.icon = Icons.info_outline});
  final String text;
  final IconData icon;
}

class LanguagePickerSheet extends ConsumerStatefulWidget {
  const LanguagePickerSheet({
    super.key,
    required this.selectedCode,
    this.showAuto = true,
    this.field = LanguagePickerField.target,
    this.hint,
  });

  final String selectedCode;
  final bool showAuto;
  final LanguagePickerField field;
  /// Optional banner shown above the search box. Used by callers that
  /// opened the picker in response to a condition the user needs to
  /// resolve (e.g. voice-input mic in auto mode); without it the user
  /// has no idea why the picker popped up.
  final LanguagePickerHint? hint;

  static Future<String?> show(
    BuildContext context, {
    required String selectedCode,
    bool showAuto = true,
    LanguagePickerField field = LanguagePickerField.target,
    LanguagePickerHint? hint,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.sheetRadius),
        ),
      ),
      builder: (_) => LanguagePickerSheet(
        selectedCode: selectedCode,
        showAuto: showAuto,
        field: field,
        hint: hint,
      ),
    );
  }

  @override
  ConsumerState<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends ConsumerState<LanguagePickerSheet> {
  late final TextEditingController _searchController;
  List<Language> _recents = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearch);
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final codes = await loadRecentTargetLangs();
    if (!mounted) return;
    setState(() {
      _recents = codes
          .map(languageByCode)
          .where((l) => widget.showAuto || l.code != 'auto')
          .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    setState(() => _query = _searchController.text.toLowerCase());
  }

  List<String> _allowedListFor(FeatureFlags flags) {
    switch (widget.field) {
      case LanguagePickerField.target:
        return flags.allowedTargetLangs;
      case LanguagePickerField.source:
        return flags.allowedSourceLangs;
      case LanguagePickerField.reply:
        return flags.allowedReplyTargetLangs;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // Watch features so the picker re-renders when /features refresh brings
    // a new catalog or new allowed_* gates.
    final flags = ref.watch(featuresProvider).flags;
    final allowed = _allowedListFor(flags);
    final allowedSet = allowed.toSet();
    final filterByAllowed = allowed.isNotEmpty;

    final base = supportedLanguages
        .where((l) => widget.showAuto || l.code != 'auto')
        .where((l) => !filterByAllowed || l.code == 'auto' || allowedSet.contains(l.code))
        .toList();

    final filtered = _query.isEmpty
        ? base
        : base
            .where((l) =>
                l.code.toLowerCase().contains(_query) ||
                l.nativeName.toLowerCase().contains(_query) ||
                (l.name?.toLowerCase().contains(_query) ?? false))
            .toList();

    // Recents must also respect the per-field allowed_* gate; a code the
    // admin removed shouldn't reappear via the user's history.
    final visibleRecents = _recents
        .where((l) => !filterByAllowed || l.code == 'auto' || allowedSet.contains(l.code))
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0,
            ),
            child: Text(
              AppLocalizations.of(context)?.selectLanguage ?? 'Select Language',
              style: theme.textTheme.titleLarge,
            ),
          ),
          if (widget.hint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(widget.hint!.icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.hint!.text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)?.searchLanguages ?? 'Search languages...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Flexible(
            child: CustomScrollView(
              shrinkWrap: true,
              slivers: [
                // For the reply-language picker, surface "From conversation"
                // (code = "") as a pinned synthetic option above the catalog.
                // Reply lang has a special meaning at code="" — pick per-
                // message based on the original — so it's a first-class
                // option, not a normal language.
                if (widget.field == LanguagePickerField.reply && _query.isEmpty)
                  SliverToBoxAdapter(child: _buildFromConversationTile(theme)),
                // Only show recents when the user isn't actively searching —
                // otherwise the search results pull from the full list.
                if (visibleRecents.isNotEmpty && _query.isEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0,
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.recent,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: visibleRecents.length,
                    itemBuilder: (context, index) =>
                        _buildLangTile(visibleRecents[index], theme),
                  ),
                  const SliverToBoxAdapter(child: Divider(height: 1)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0,
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.allLanguages,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
                SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildLangTile(filtered[index], theme),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildLangTile(Language lang, ThemeData theme) {
    final isSelected = lang.code == widget.selectedCode;
    return ListTile(
      selected: isSelected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
      title: Text(lang.nativeName),
      subtitle: lang.name != null
          ? Text(
              lang.name!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          : null,
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () => Navigator.pop(context, lang.code),
    );
  }

  Widget _buildFromConversationTile(ThemeData theme) {
    final isSelected = widget.selectedCode.isEmpty;
    final l = AppLocalizations.of(context)!;
    return ListTile(
      selected: isSelected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
      leading: const Icon(Icons.auto_awesome_outlined, size: 22),
      title: Text(l.replyLanguageFromConversation),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () => Navigator.pop(context, ''),
    );
  }
}
