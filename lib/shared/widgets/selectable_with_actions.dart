import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../features/translate/widgets/result_bottom_sheet.dart';
import '../theme/app_theme.dart';

/// SelectableText wrapper that appends a "TransKey" button to the OS context
/// menu. Tapping it opens ResultBottomSheet pre-filled with the selected text
/// (or the full text when nothing is selected).
class SelectableWithActions extends ConsumerWidget {
  const SelectableWithActions(
    this.text, {
    super.key,
    this.style,
    this.targetLang = 'en',
  });

  final String text;
  final TextStyle? style;
  final String targetLang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SelectableText(
      text,
      style: style,
      contextMenuBuilder: (ctx, editableTextState) {
        final sel = editableTextState.textEditingValue.selection;
        final selectedText =
            sel.isValid && !sel.isCollapsed ? sel.textInside(text) : text;

        final items = List<ContextMenuButtonItem>.from(
          editableTextState.contextMenuButtonItems,
        )..add(
            ContextMenuButtonItem(
              label: 'TransKey',
              onPressed: () {
                ContextMenuController.removeAny();
                // Defer to next frame so context menu dismissal completes first
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _openSheet(context, ref, selectedText);
                });
              },
            ),
          );

        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: items,
        );
      },
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref, String selectedText) {
    final isLoggedIn =
        ref.read(authStateProvider).valueOrNull?.isLoggedIn ?? false;
    if (!isLoggedIn) {
      context.go('/auth/login');
      return;
    }

    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      // Root navigator ensures proper context even from inside nested sheets
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16161A) : Colors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.sheetRadius),
          ),
        ),
        child: ResultBottomSheet(
          sourceText: selectedText,
          targetLang: targetLang,
        ),
      ),
    );
  }
}
