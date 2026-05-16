import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import 'toast.dart';

class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.label,
    this.iconSize = 20,
  });

  final String text;
  final String? label;
  final double iconSize;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    HapticFeedback.lightImpact();

    setState(() => _copied = true);

    if (mounted) {
      // Use overlay toast so it stays visible even when this button is
      // rendered inside a modal bottom sheet (Settings screens, history
      // detail sheet, etc).
      showAppToast(context, AppLocalizations.of(context)!.copied);
    }

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _copied ? Icons.check : Icons.copy_outlined,
                key: ValueKey(_copied),
                size: widget.iconSize,
                color: _copied
                    ? AppColors.green
                    : (isDark ? AppColors.textSecondary : AppColors.textSecondaryLight),
              ),
            ),
            if (widget.label != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                widget.label!,
                style: TextStyle(
                  fontSize: 12,
                  color: _copied
                      ? AppColors.green
                      : (isDark ? AppColors.textSecondary : AppColors.textSecondaryLight),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
