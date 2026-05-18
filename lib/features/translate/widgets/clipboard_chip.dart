import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

/// Suggestion chip shown above the input field when fresh clipboard text
/// is detected. Tap the body to drop the clipboard text into the input;
/// tap × to dismiss the suggestion (host remembers the dismissed string
/// so the same clip doesn't re-prompt on every resume).
class ClipboardChip extends StatelessWidget {
  const ClipboardChip({
    super.key,
    required this.text,
    required this.onUse,
    required this.onDismiss,
  });

  final String text;
  final VoidCallback onUse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        onTap: onUse,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.content_paste,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close, size: 16),
                color: AppColors.primary,
                onPressed: onDismiss,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
