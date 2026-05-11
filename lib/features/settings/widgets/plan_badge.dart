import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key, required this.plan, this.trialEndsAt});

  final String plan;
  final DateTime? trialEndsAt;

  @override
  Widget build(BuildContext context) {
    final config = _planConfig;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        config.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: config.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  _PlanVisual get _planConfig {
    switch (plan) {
      case 'trial':
        final daysLeft = trialEndsAt != null
            ? trialEndsAt!.difference(DateTime.now()).inDays
            : 7;
        return _PlanVisual(
          label: 'TRIAL · ${daysLeft}d left',
          color: const Color(0xFF3B82F6),
        );
      case 'mobile':
        return const _PlanVisual(
          label: '📱 MOBILE',
          color: Color(0xFF8B5CF6),
        );
      case 'pro':
        return const _PlanVisual(
          label: '⭐ PRO',
          color: Color(0xFFF59E0B),
        );
      case 'banned':
        return const _PlanVisual(
          label: 'BANNED',
          color: AppColors.red,
        );
      default:
        return const _PlanVisual(
          label: 'FREE',
          color: Color(0xFF9CA3AF),
        );
    }
  }
}

class _PlanVisual {
  const _PlanVisual({required this.label, required this.color});
  final String label;
  final Color color;
}
