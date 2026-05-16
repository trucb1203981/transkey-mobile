import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shows a short floating notification at the TOP of the screen.
///
/// Why not SnackBar? `ScaffoldMessenger.showSnackBar` always renders at the
/// bottom of the host Scaffold, which is *behind* any open modal bottom
/// sheet — the user clicks "Copy" inside the sheet and sees nothing.
/// Using `OverlayEntry` puts the toast on the root overlay, above every
/// modal route including bottom sheets and dialogs.
///
/// Use this instead of SnackBar whenever the trigger lives inside a sheet
/// or dialog. For full-screen pages a regular SnackBar is fine.
void showAppToast(BuildContext context, String message,
    {Duration duration = const Duration(milliseconds: 1400)}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  // Use a holder so the entry can reference itself for cleanup.
  late OverlayEntry entry;
  bool removed = false;
  void dismiss() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(builder: (ctx) {
    final mq = MediaQuery.of(ctx);
    final theme = Theme.of(ctx);
    final isDark = theme.brightness == Brightness.dark;
    return Positioned(
      top: mq.padding.top + 12,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: _ToastBubble(
                message: message,
                isDark: isDark,
                duration: duration,
                onDone: dismiss,
              ),
            ),
          ),
        ),
      ),
    );
  });
  overlay.insert(entry);
}

class _ToastBubble extends StatefulWidget {
  const _ToastBubble({
    required this.message,
    required this.isDark,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final bool isDark;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_ToastBubble> createState() => _ToastBubbleState();
}

class _ToastBubbleState extends State<_ToastBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    // After `duration`, reverse-then-remove so the toast fades out smoothly.
    Future.delayed(widget.duration, () async {
      if (!mounted) return;
      await _ctrl.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isDark
                ? const Color(0xFF2A2A40)
                : const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
