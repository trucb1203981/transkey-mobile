import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/generated/app_localizations.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../models/language.dart';
import '../providers/features_provider.dart';
import '../providers/language_settings_provider.dart';

/// Which slot the picker is filling. Drives the allowed_* gate so admin's
/// per-field restrictions in /system-config are respected here.
enum LanguagePickerField { target, source, reply }

class LanguagePickerSheet extends ConsumerStatefulWidget {
  const LanguagePickerSheet({
    super.key,
    required this.selectedCode,
    this.showAuto = true,
    this.field = LanguagePickerField.target,
  });

  final String selectedCode;
  final bool showAuto;
  final LanguagePickerField field;

  static Future<String?> show(
    BuildContext context, {
    required String selectedCode,
    bool showAuto = true,
    LanguagePickerField field = LanguagePickerField.target,
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
}
