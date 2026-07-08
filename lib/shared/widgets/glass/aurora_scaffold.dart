import 'package:flutter/material.dart';

import '../../theme/app_glass.dart';
import 'aurora_background.dart';

/// A [Scaffold] pre-wrapped with the immersive aurora backdrop, so any screen
/// can adopt the Liquid Glass look by swapping `Scaffold(` -> `AuroraScaffold(`.
///
/// The app bar (if any) is drawn transparently over the aurora
/// (`extendBodyBehindAppBar`), relying on the global transparent `appBarTheme`.
class AuroraScaffold extends StatelessWidget {
  const AuroraScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.resizeToAvoidBottomInset,
    this.extendBody = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final bool? resizeToAvoidBottomInset;
  final bool extendBody;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // With extendBodyBehindAppBar the aurora fills behind the transparent app
    // bar, but the body would otherwise slide under it — so inset the body by
    // the app bar + status-bar height. This keeps content clear of the bar
    // while the glow stays continuous top-to-bottom.
    Widget content = body;
    if (appBar != null) {
      final topInset =
          appBar!.preferredSize.height + MediaQuery.of(context).padding.top;
      content = Padding(
        padding: EdgeInsets.only(top: topInset),
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: GlassPalette.forDark(isDark).auroraBase,
      extendBodyBehindAppBar: appBar != null,
      extendBody: extendBody,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      bottomSheet: bottomSheet,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: AuroraBackground(isDark: isDark, child: content),
    );
  }
}
