import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/generated/app_localizations.dart';

/// First-run + on-demand "how to use the camera" tips. Shown automatically
/// the first time the user opens the camera (flag persisted in prefs) and
/// reopenable any time via the "?" button in the camera top bar.
///
/// Content focuses on the things that aren't self-evident: scene modes, the
/// source-language nuance (needed for non-Latin scripts), and the hidden
/// gestures (long-press to explain, drag-to-trash, gallery import).
class CameraTipsSheet extends StatelessWidget {
  const CameraTipsSheet({super.key});

  static const _kSeenKey = 'tk_camera_tips_seen_v1';

  /// Show the sheet automatically on first camera open. No-op if already
  /// seen. Call once from the camera screen's initState.
  static Future<void> showIfFirstTime(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kSeenKey) ?? false) return;
    await prefs.setBool(_kSeenKey, true);
    if (!context.mounted) return;
    await show(context);
  }

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CameraTipsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final tips = <(IconData, String, String)>[
      (Icons.tune, l.cameraTip1Title, l.cameraTip1Body),
      (Icons.translate, l.cameraTip2Title, l.cameraTip2Body),
      (Icons.psychology_outlined, l.cameraTip3Title, l.cameraTip3Body),
      (Icons.delete_outline, l.cameraTip4Title, l.cameraTip4Body),
      (Icons.photo_library_outlined, l.cameraTip5Title, l.cameraTip5Body),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1F2937),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: Colors.amberAccent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.cameraTipsTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    itemCount: tips.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, i) {
                      final (icon, title, body) = tips[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.lightBlueAccent
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(icon,
                                color: Colors.lightBlueAccent, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  body,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.lightBlueAccent,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(l.cameraTipsGotIt),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
