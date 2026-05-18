import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

/// Feedback bottom sheet. Mirrors the form at https://transkey.app/feedback
/// — category picker (bug / feature / other) + message + optional email —
/// so the server-side {bug, feature, other} enum is satisfied (the
/// previous mobile sheet hardcoded `category: 'general'` which the API
/// silently rejected) and so users see the same UX on web and mobile.
class FeedbackSheet extends ConsumerStatefulWidget {
  const FeedbackSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FeedbackSheet(),
    );
  }

  @override
  ConsumerState<FeedbackSheet> createState() => _FeedbackSheetState();
}

enum _Category { bug, feature, other }

extension on _Category {
  /// Server enum value — must stay one of {bug, feature, other}.
  String get apiValue => switch (this) {
        _Category.bug     => 'bug',
        _Category.feature => 'feature',
        _Category.other   => 'other',
      };

  String get icon => switch (this) {
        _Category.bug     => '🐛',
        _Category.feature => '💡',
        _Category.other   => '💬',
      };

  String label(AppLocalizations l) => switch (this) {
        _Category.bug     => l.feedbackCatBug,
        _Category.feature => l.feedbackCatFeature,
        _Category.other   => l.feedbackCatOther,
      };

  String hint(AppLocalizations l) => switch (this) {
        _Category.bug     => l.feedbackHintBug,
        _Category.feature => l.feedbackHintFeature,
        _Category.other   => l.feedbackHintOther,
      };
}

class _FeedbackSheetState extends ConsumerState<FeedbackSheet> {
  final _messageCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  _Category _category = _Category.bug;
  bool _sending = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final l = AppLocalizations.of(context)!;
    try {
      final api = ref.read(apiClientProvider);
      final email = _emailCtrl.text.trim();
      await api.dio.post('/feedback', data: {
        'category': _category.apiValue,
        'message': text,
        if (email.isNotEmpty) 'email': email,
        'source': 'mobile',
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.feedbackThanks)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.feedbackFailed),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.feedbackTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                for (final cat in _Category.values) ...[
                  Expanded(
                    child: _CategoryButton(
                      label: cat.label(l),
                      icon: cat.icon,
                      selected: _category == cat,
                      onTap: () => setState(() => _category = cat),
                    ),
                  ),
                  if (cat != _Category.values.last)
                    const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _messageCtrl,
              maxLines: 5,
              decoration: InputDecoration(hintText: _category.hint(l)),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l.feedbackEmailLabel,
                hintText: 'you@example.com',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.feedbackSend),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.12)
          : (isDark ? AppColors.surface : AppColors.surfaceLight),
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : (isDark ? AppColors.border : AppColors.borderLight),
            ),
          ),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.primary : null,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
