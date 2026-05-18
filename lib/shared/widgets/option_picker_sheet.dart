import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'drag_handle.dart';

/// One option in an [OptionPickerSheet]. `value` is the choice that gets
/// returned, `label` is what the user sees. `subtitle` is an optional
/// per-option hint shown under the label (used by the capture-keepalive
/// picker to explain trade-offs).
class PickerOption<T> {
  const PickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.leading,
  });
  final T value;
  final String label;
  final String? subtitle;
  final Widget? leading;
}

/// Generic single-select bottom-sheet picker. Centralises the boilerplate
/// that 5 different settings pickers had open-coded — `showModalBottomSheet`
/// + drag handle + title + optional explanation + scrollable option list +
/// selection check mark + SafeArea bottom padding.
///
/// The list is rendered in a `Flexible(ListView)` with
/// `isScrollControlled: true` so it scales from 3 options (auto-close) to
/// 14+ options (app language) without overflowing.
///
/// Usage:
/// ```dart
/// final choice = await OptionPickerSheet.show<int>(
///   context,
///   title: t.autoCloseSeconds,
///   options: [
///     PickerOption(value: 0, label: t.autoCloseDisabled),
///     for (final s in [5, 10, 15, 30, 60])
///       PickerOption(value: s, label: '$s ${t.autoCloseUnit}'),
///   ],
///   selectedValue: current,
/// );
/// if (choice != null) await notifier.setAutoCloseSeconds(choice);
/// ```
class OptionPickerSheet<T> extends StatelessWidget {
  const OptionPickerSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selectedValue,
    this.explanation,
  });

  final String title;
  final List<PickerOption<T>> options;
  final T selectedValue;
  /// Optional paragraph shown below the title, before the option list.
  /// Used by pickers whose options are themselves trade-offs (e.g. the
  /// capture-keepalive window — longer window = less re-consent prompts
  /// but more casting time).
  final String? explanation;

  /// Convenience launcher — opens the picker as a modal bottom sheet and
  /// returns the selected value, or null if the user dismissed without
  /// picking.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required List<PickerOption<T>> options,
    required T selectedValue,
    String? explanation,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      // Lets the sheet grow taller than the default half-screen cap so
      // long option lists (e.g. 14-language picker) don't overflow on
      // short or split-screen devices.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.sheetRadius),
        ),
      ),
      builder: (_) => OptionPickerSheet<T>(
        title: title,
        options: options,
        selectedValue: selectedValue,
        explanation: explanation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              explanation != null ? AppSpacing.xs : 0,
            ),
            child: Text(title, style: theme.textTheme.titleLarge),
          ),
          if (explanation != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                explanation!,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: options.map((opt) {
                final isSelected = opt.value == selectedValue;
                return ListTile(
                  leading: opt.leading,
                  title: Text(opt.label),
                  subtitle: opt.subtitle != null
                      ? Text(
                          opt.subtitle!,
                          style: const TextStyle(fontSize: 11),
                        )
                      : null,
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () => Navigator.pop(context, opt.value),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
