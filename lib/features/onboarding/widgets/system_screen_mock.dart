import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';

enum MockTrailing { none, chevron, toggleOff, toggleOn }

/// One row of the fake system-settings list drawn by [SystemScreenMock].
@immutable
class MockRow {
  /// A neighbouring row: dimmed, present only so the picture reads as a list.
  const MockRow(this.label, {this.icon, this.trailing = MockTrailing.none})
      : isTarget = false;

  /// The row the user is hunting for: real TransKey icon, full contrast, and a
  /// pulsing highlight so the eye lands on it before reading anything.
  const MockRow.target(this.label, {this.trailing = MockTrailing.toggleOff})
      : icon = null,
        isTarget = true;

  final String label;
  final IconData? icon;
  final MockTrailing trailing;
  final bool isTarget;
}

/// A drawn preview of the system screen the user is about to be dropped into.
///
/// The app cannot follow the user into system settings, and it cannot draw over
/// those screens either (Android hides non-system overlays on permission flows).
/// So the only help that survives the trip is help the user has already seen:
/// a picture of the row they must find, carrying the real app icon and the
/// exact label, shown BEFORE they leave.
///
/// [screenTitle] is a description of the screen, not a quotation of it. Phone
/// makers word these differently, and a title that does not match what the user
/// is looking at destroys trust faster than no title at all - which is why
/// [footnote] exists to say the wording may differ.
class SystemScreenMock extends StatefulWidget {
  const SystemScreenMock({
    super.key,
    required this.screenTitle,
    required this.rows,
    this.footnote,
  });

  final String screenTitle;
  final List<MockRow> rows;
  final String? footnote;

  @override
  State<SystemScreenMock> createState() => _SystemScreenMockState();
}

class _SystemScreenMockState extends State<SystemScreenMock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final frame = dark ? AppColors.surface : AppColors.surfaceLight;
    final page = dark ? AppColors.bgDark : const Color(0xFFEFEFF4);
    final title = dark ? AppColors.textPrimary : AppColors.textPrimaryLight;
    final muted = dark ? AppColors.textSecondary : AppColors.textSecondaryLight;

    return Container(
      decoration: BoxDecoration(
        color: page,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: muted.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.screenTitle,
            style: TextStyle(
              color: title,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: frame,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < widget.rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 52,
                      color: muted.withValues(alpha: 0.18),
                    ),
                  _row(widget.rows[i], title, muted),
                ],
              ],
            ),
          ),
          if (widget.footnote != null) ...[
            const SizedBox(height: 10),
            Text(
              widget.footnote!,
              style: TextStyle(color: muted, fontSize: 12.5, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(MockRow row, Color title, Color muted) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          _leading(row, muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                // Neighbours stay dim on purpose: the target row must be the
                // only thing the eye can land on.
                color: row.isTarget ? title : muted,
                fontSize: 15,
                fontWeight: row.isTarget ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          _trailing(row, muted),
        ],
      ),
    );

    if (!row.isTarget) return content;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06 + 0.10 * _pulse.value),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.45 + 0.55 * _pulse.value),
            width: 2,
          ),
        ),
        child: child,
      ),
      child: content,
    );
  }

  Widget _leading(MockRow row, Color muted) {
    if (row.isTarget) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.asset('assets/images/logo.png', width: 28, height: 28),
      );
    }
    return Icon(row.icon ?? Icons.apps_rounded, size: 24, color: muted.withValues(alpha: 0.6));
  }

  Widget _trailing(MockRow row, Color muted) {
    switch (row.trailing) {
      case MockTrailing.none:
        return const SizedBox.shrink();
      case MockTrailing.chevron:
        return Icon(Icons.chevron_right, size: 20, color: muted.withValues(alpha: 0.6));
      case MockTrailing.toggleOff:
      case MockTrailing.toggleOn:
        final on = row.trailing == MockTrailing.toggleOn;
        return Container(
          width: 40,
          height: 24,
          decoration: BoxDecoration(
            color: on ? AppColors.green : muted.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Align(
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        );
    }
  }
}
