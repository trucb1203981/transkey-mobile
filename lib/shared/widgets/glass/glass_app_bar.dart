import 'package:flutter/material.dart';

import '../../theme/app_glass.dart';

/// A glass capsule holding a row of controls, the iOS 26 toolbar group (as in
/// Slack's header). A single control reads as a glass circle.
///
/// No BackdropFilter: the bar sits over the static aurora, where blur is
/// invisible but costs GPU (the tab bar is the app's one real blur).
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({super.key, required this.children, this.height = 44});

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette.of(context);
    final inner = height - 4;
    return Container(
      height: height,
      constraints: BoxConstraints(minWidth: height),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppGlass.rPill),
        // Top-lit, like the tab bar capsule.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(p.fillFaint, p.fillStrong), p.fill],
        ),
        border: Border.all(color: p.border, width: 0.8),
        boxShadow: [
          BoxShadow(
              color: p.shadow, blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      // Material buttons default to a 48pt tap target; size them to the
      // capsule so the row fits.
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            fixedSize: Size.square(inner),
            minimumSize: Size.square(inner),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// App bar for the Liquid Glass screens: a transparent bar with a centered
/// title, and the back button and actions floating in glass capsules.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, required this.title, this.actions = const []});

  final Widget title;
  final List<Widget> actions;

  static const double _kHeight = kToolbarHeight + 4;

  @override
  Size get preferredSize => const Size.fromHeight(_kHeight);

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return AppBar(
      toolbarHeight: _kHeight,
      automaticallyImplyLeading: false,
      leadingWidth: 64,
      leading: canPop
          ? const Center(child: GlassCapsule(children: [BackButton()]))
          : null,
      title: title,
      actions: [
        if (actions.isNotEmpty) GlassCapsule(children: actions),
        const SizedBox(width: 12),
      ],
    );
  }
}
