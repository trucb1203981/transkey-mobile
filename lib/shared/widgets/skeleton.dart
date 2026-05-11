import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

class SkeletonLine extends StatefulWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 4,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonLine> createState() => _SkeletonLineState();
}

class _SkeletonLineState extends State<SkeletonLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? AppColors.border : const Color(0xFFE0E0E0);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shimmer = Tween<double>(begin: -1, end: 2).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        );
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(shimmer.value - 0.3, 0),
              end: Alignment(shimmer.value, 0),
              colors: [
                baseColor,
                isDark ? const Color(0xFF2A2A35) : const Color(0xFFF0F0F0),
                baseColor,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton card for history list shimmer.
class HistorySkeletonCard extends StatelessWidget {
  const HistorySkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: 180, height: 14),
                SizedBox(height: AppSpacing.sm),
                SkeletonLine(height: 12),
                SizedBox(height: 4),
                SkeletonLine(width: 120, height: 12),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          SkeletonLine(width: 32, height: 32, borderRadius: 8),
        ],
      ),
    );
  }
}

/// Full skeleton list for history page.
class HistorySkeletonList extends StatelessWidget {
  const HistorySkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (_, __) => const HistorySkeletonCard(),
    );
  }
}
