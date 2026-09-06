import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../providers/setup_status_provider.dart';

/// One numbered instruction. Deliberately plain: a number, one short line.
class NumberedStep extends StatelessWidget {
  const NumberedStep({super.key, required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? AppColors.textPrimary : AppColors.textPrimaryLight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: TextStyle(color: fg, fontSize: 16, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Amber note used for the one thing that makes users abandon setup: the
/// system's own warning dialog when a keyboard is switched on. Telling people
/// it is coming, and that every keyboard triggers it, is what stops them from
/// pressing Cancel.
class SetupNoteCard extends StatelessWidget {
  const SetupNoteCard({super.key, required this.text, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: dark ? 0.14 : 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: dark ? AppColors.textPrimary : AppColors.textPrimaryLight,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The status dot + label used on the setup hub rows.
class SetupStepBadge extends StatelessWidget {
  const SetupStepBadge({super.key, required this.step, required this.label});

  final SetupStep step;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (step) {
      SetupStep.done => (AppColors.green, Icons.check_circle_rounded),
      SetupStep.partial => (AppColors.amber, Icons.radio_button_checked),
      // Never red: "not done yet" is a to-do, not an error the user caused.
      SetupStep.missing => (AppColors.primary, Icons.radio_button_unchecked),
      SetupStep.unknown => (AppColors.textSecondary, Icons.help_outline_rounded),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
