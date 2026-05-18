import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../glossary/providers/glossary_provider.dart';

/// Horizontal row of one-tap "insert this name" chips. Sourced from the
/// user's glossary entries flagged `is_name = true` — exactly the set the
/// bubble's voice picker already shows. Designed to live directly below
/// the source text field on the home screen so when the speech-to-text
/// recognizer mishears a foreign name ("Shinzato" → "sinh nhật"), the
/// user can tap once to drop the correct spelling into the input instead
/// of typing it out.
///
/// Insertion strategy:
///  - If text is selected: replace selection with the name.
///  - Otherwise: insert at the caret (or append, if no caret position).
class NameChipPalette extends ConsumerWidget {
  const NameChipPalette({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final glossary = ref.watch(glossaryProvider);
    final names = glossary.entries
        .where((e) => e.isName && e.source.trim().isNotEmpty)
        .map((e) => e.source.trim())
        .toSet()
        .toList();

    if (names.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                l.glossaryNamesLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: names.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final name = names[i];
                return ActionChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: isDark
                      ? AppColors.surface
                      : AppColors.surfaceLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: isDark ? AppColors.border : AppColors.borderLight,
                    ),
                  ),
                  label: Text(
                    name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () => _insertName(name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _insertName(String name) {
    final value = controller.value;
    final sel = value.selection;
    final text = value.text;

    String newText;
    int newOffset;

    if (sel.isValid && !sel.isCollapsed) {
      // Replace selection — useful when ASR put down a wrong word that the
      // user has now selected and wants to swap.
      newText = text.replaceRange(sel.start, sel.end, name);
      newOffset = sel.start + name.length;
    } else {
      // No selection — insert at caret (with a space if needed so it doesn't
      // jam into adjacent words). If the field is empty, just write the name.
      final pos = sel.isValid ? sel.baseOffset : text.length;
      final before = text.substring(0, pos);
      final after = text.substring(pos);
      final needsLeadingSpace = before.isNotEmpty && !before.endsWith(' ');
      final needsTrailingSpace = after.isNotEmpty && !after.startsWith(' ');
      final insert =
          (needsLeadingSpace ? ' ' : '') + name + (needsTrailingSpace ? ' ' : '');
      newText = before + insert + after;
      newOffset = pos + insert.length - (needsTrailingSpace ? 1 : 0);
    }

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    // Keep the field focused so the caret stays where the user expects.
    if (!focusNode.hasFocus) focusNode.requestFocus();
  }
}
