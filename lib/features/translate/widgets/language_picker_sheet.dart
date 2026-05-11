import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../models/language.dart';

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

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filtered = kSupportedLanguages
        .where((l) => widget.showAuto || l.code != 'auto')
        .toList();
    _searchController.addListener(_onSearch);
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
            child: Text('Select Language', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search languages...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final lang = _filtered[index];
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
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
