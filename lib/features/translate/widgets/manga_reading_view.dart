import 'package:flutter/material.dart';

import '../../../core/camera/camera_service.dart';
import 'package:transkey_mobile/l10n/generated/app_localizations.dart';

/// Clean reading-list display for a single manga page. The vision LLM
/// returns the bubbles in reading order (right-to-left for Japanese
/// manga, etc.), so we just render them as a numbered scrollable list
/// — no AR chips over the art (manga has too many bubbles for AR
/// overlay to be readable; font shrinks to fit tiny bubbles → unreadable).
///
/// Stateless on its own — page navigation between multi-pick pages is
/// handled by the caller's existing batch nav (the `_BatchPageNav` row
/// at the top of the result step). The toggle button here flips the
/// caller back to AR-overlay mode if the user wants to see the art
/// with chips on top.
class MangaReadingView extends StatelessWidget {
  const MangaReadingView({
    super.key,
    required this.blocks,
    required this.translations,
    required this.imagePath,
    required this.onToggleArMode,
    this.toggleLabel = 'AR',
  });

  /// Per-bubble source text (in reading order from the vision prompt).
  final List<OcrBlock> blocks;

  /// Same-length list of Vietnamese (or target-language) translations,
  /// aligned 1:1 with [blocks]. Empty / unchanged entries are still
  /// shown — the user might be reading a sound effect or kept-verbatim
  /// brand name; we don't try to filter them here.
  final List<String> translations;

  /// Captured page path — used as the dimmed background thumbnail so
  /// the user keeps loose spatial context (which page they're on).
  final String? imagePath;

  /// Tap handler for the top-right toggle. Caller flips its own state
  /// to render [CameraResultOverlay] (the AR chips path) instead.
  final VoidCallback onToggleArMode;

  /// Short label for the toggle (defaults to "AR" — caller can localise).
  final String toggleLabel;

  @override
  Widget build(BuildContext context) {
    final n = blocks.length;
    if (n == 0) {
      return Center(
        child: Text(
          AppLocalizations.of(context)?.mangaNoDialogue ?? 'No dialogue found',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Solid dark background. We intentionally do NOT show the art
        // behind: reading mode is about clean prose, the art lives in
        // the AR-overlay toggle. (A future enhancement could be a
        // very-dimmed thumbnail strip on the side; not needed for v1.)
        const ColoredBox(color: Color(0xFF0E0E12)),

        // Bottom-up gradient so the list scrolls under a subtle fade
        // toward the bottom action bar — keeps the page nav legible.
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x66000000)],
                  stops: [0.85, 1.0],
                ),
              ),
            ),
          ),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 56), // clear top app bar
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: n,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final src = blocks[i].text.trim();
                final trans = (i < translations.length ? translations[i] : '').trim();
                final show = trans.isNotEmpty ? trans : src;
                final hasOriginalLine =
                    src.isNotEmpty && trans.isNotEmpty && trans != src;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bubble index — preserves reading order so the user
                      // can refer back to "bubble 5" while skimming.
                      Container(
                        width: 28,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Translation is the headline — readable
                            // 16sp, never shrinks (no bubble clamp).
                            Text(
                              show,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.35,
                              ),
                            ),
                            if (hasOriginalLine) ...[
                              const SizedBox(height: 4),
                              Text(
                                src,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),

        // Top-right toggle to flip into the AR-overlay view (chips over
        // the art). Useful when the user wants to verify a bubble's
        // location on the page, or compare with the source layout.
        Positioned(
          top: 0,
          right: 12,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Material(
                color: Colors.white.withValues(alpha: 0.12),
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onToggleArMode,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.image_outlined,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          toggleLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
