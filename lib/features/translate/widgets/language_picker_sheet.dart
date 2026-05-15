import 'package:flutter/material.dart';
import '../../../l10n/generated/app_localizations.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../models/language.dart';
import '../providers/language_settings_provider.dart';

class LanguagePickerSheet extends StatefulWidget {
  const LanguagePickerSheet({
    super.key,
    required this.selectedCode,
    this.showAuto = true,
  });

  final String selectedCode;
  final bool showAuto;

  static Future<String?> show(
    BuildContext context, {
    required String selectedCode,
    bool showAuto = true,
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
      ),
    );
  }

  @override
  State<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<LanguagePickerSheet> {
  late final TextEditingController _searchController;
  late List<Language> _filtered;
  List<Language> _recents = const [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filtered = kSupportedLanguages
        .where((l) => widget.showAuto || l.code != 'auto')
        .toList();
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
    final query = _searchController.text.toLowerCase();
    final source = kSupportedLanguages
        .where((l) => widget.showAuto || l.code != 'auto')
        .toList();
    setState(() {
      _filtered = query.isEmpty
          ? source
          : source
              .where((l) =>
                  l.code.toLowerCase().contains(query) ||
                  l.nativeName.toLowerCase().contains(query) ||
                  (l.name?.toLowerCase().contains(query) ?? false))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

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
                if (_recents.isNotEmpty && _searchController.text.isEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0,
                      ),
                      child: Text(
                        _localeIsVi(context) ? 'Gần đây' : 'Recent',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: _recents.length,
                    itemBuilder: (context, index) =>
                        _buildLangTile(_recents[index], theme),
                  ),
                  const SliverToBoxAdapter(child: Divider(height: 1)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0,
                      ),
                      child: Text(
                        _localeIsVi(context) ? 'Tất cả ngôn ngữ' : 'All languages',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
                SliverList.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) =>
                      _buildLangTile(_filtered[index], theme),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  bool _localeIsVi(BuildContext ctx) =>
      Localizations.localeOf(ctx).languageCode == 'vi';

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
