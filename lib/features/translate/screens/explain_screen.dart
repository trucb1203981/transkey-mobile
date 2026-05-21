import 'package:flutter/material.dart';

import '../widgets/what_is_this_sheet.dart';

/// Thin host screen for the "What is this?" sheet. Entered from the bubble
/// Lens overlay (long-press on a translated block) — the native overlay
/// can't host a Flutter modal, so we route here, immediately present the
/// sheet, then pop the route back when the user dismisses the sheet.
///
/// The user never *sees* this screen — the sheet covers the screen and
/// closing it returns them to wherever they were before the bubble took
/// over. Background colour matches the system so the brief frame between
/// route push and sheet present doesn't flash light/dark.
class ExplainScreen extends StatefulWidget {
  const ExplainScreen({super.key, required this.text});

  final String text;

  @override
  State<ExplainScreen> createState() => _ExplainScreenState();
}

class _ExplainScreenState extends State<ExplainScreen> {
  @override
  void initState() {
    super.initState();
    // Show the sheet on the next frame so the route is fully mounted before
    // we push a modal on top of it (otherwise WhatIsThisSheet's modal route
    // attaches to a parent that's still settling and the dismiss animation
    // glitches).
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    if (!mounted) return;
    // Empty text → nothing to explain, just pop right away so the user
    // isn't left staring at a blank screen.
    if (widget.text.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    await WhatIsThisSheet.show(context, widget.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Transparent-ish backdrop — the sheet covers everything visible; this
    // just keeps the brief frame between mount and sheet-present from
    // flashing the home screen.
    return const Scaffold(
      backgroundColor: Colors.black54,
      body: SizedBox.expand(),
    );
  }
}
