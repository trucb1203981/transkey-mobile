import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_service.dart' show OcrBlock;
import '../../../core/tracking/tracking_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../main.dart' show scaffoldMessengerKey;
import '../../phrasebook/providers/phrasebook_provider.dart';
import 'tts_button.dart';

/// Modal sheet that opens when the user taps a translated block on the
/// camera result overlay. Bundles every per-block action — copy, retry,
/// explain, save — into one place so users don't need to remember which
/// gesture does what. Replaces the previous "tap to expand" inline UI:
/// the sheet shows the same original+translation pair plus all four
/// actions upfront, removing one tap from the common "copy this
/// translation" path.
///
/// Why a bottom sheet over inline buttons:
///   - Per-card buttons would crowd small cards on dense menus.
///   - A sheet lets us show the FULL original + translation text in a
///     readable size even when the card itself is tiny (a 3-char dish
///     name's card is ~80 px wide on screen).
///   - One consistent action surface across all blocks; users don't
///     re-learn where things are per card size.
class BlockActionSheet extends ConsumerWidget {
  const BlockActionSheet({
    super.key,
    required this.block,
    required this.translation,
    required this.scene,
    required this.targetLang,
    required this.sourceLang,
    required this.ttsLang,
    required this.onRetry,
    this.onExplain,
  });

  final OcrBlock block;
  final String translation;
  final String scene;
  final String targetLang;
  /// The user's pinned source lang preference (may be "auto" or null).
  /// Persisted in the phrasebook entry as metadata.
  final String? sourceLang;
  /// Best-effort 2-letter ISO code to drive the TTS voice for the
  /// original text. Server-detected lang wins when available; falls
  /// back to the user's pinned lang. Null → hide the speaker button
  /// (better than guessing English and reading "한국어" with a US voice).
  final String? ttsLang;
  final VoidCallback onRetry;
  final VoidCallback? onExplain;

  static Future<void> show(
    BuildContext context, {
    required OcrBlock block,
    required String translation,
    required String scene,
    required String targetLang,
    required String? sourceLang,
    required String? ttsLang,
    required VoidCallback onRetry,
    VoidCallback? onExplain,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlockActionSheet(
        block: block,
        translation: translation,
        scene: scene,
        targetLang: targetLang,
        sourceLang: sourceLang,
        ttsLang: ttsLang,
        onRetry: onRetry,
        onExplain: onExplain,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final hasTranslation = translation.trim().isNotEmpty &&
        translation.trim() != block.text.trim();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle — universal mobile cue that the sheet is
            // dismissible by swipe-down. Matches the iOS / Material 3
            // bottom-sheet convention.
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Translation block (primary content — what the user came
            // here to read). Shown first because in 95% of cases that's
            // what they want to copy / verify.
            if (hasTranslation)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: SelectableText(
                  translation,
                  style: const TextStyle(fontSize: 16, height: 1.4),
                ),
              ),
            // Source / original — italic + dimmed so it reads as
            // secondary context. Includes the speaker button when
            // we have a usable lang code, so users can hear the
            // original phrase aloud (the core travel-app use case:
            // walking into a shop and saying the dish name).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      block.text,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (ttsLang != null) ...[
                    const SizedBox(width: 8),
                    TtsButton(
                      text: block.text,
                      lang: ttsLang!,
                      size: 18,
                      showOptions: false,
                    ),
                  ],
                ],
              ),
            ),
            // Per-LINE copy section, shown only when the block has 2+
            // non-empty lines. Common case: a storefront sign reads
            // "Tuấn Vũ\nTẠO MẪU TÓC NAM NỮ\nĐT: 0967 678 161\n213
            // TÂY HÒA - Q9" as ONE OCR/vision block — the user
            // typically wants only the phone or only the address to
            // paste into Phone / Maps, not the whole thing. Each
            // detected line gets a tappable row that copies JUST
            // that line. Auto-detects phone-shaped runs and tags them
            // with a phone icon so users can spot the row to tap from
            // across the screen without reading every line.
            ..._buildPerLineCopyRows(context, ref),
            const Divider(height: 1),
            // Action list — Material ListTile so the touch targets get
            // proper Material ink, padding, and a11y semantics for free.
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l.cameraCopyTranslation),
              enabled: hasTranslation,
              onTap: hasTranslation
                  ? () {
                      Navigator.of(context).pop();
                      _copy(context, translation, ref,
                          kind: 'translation');
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.content_copy_outlined),
              title: Text(l.cameraCopyOriginal),
              onTap: () {
                Navigator.of(context).pop();
                _copy(context, block.text, ref, kind: 'original');
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_outlined),
              title: Text(l.cameraRetryBlock),
              onTap: () {
                Navigator.of(context).pop();
                ref.read(trackingServiceProvider).event('block_retry',
                    properties: {
                      'scene': scene,
                    });
                onRetry();
              },
            ),
            if (onExplain != null)
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: Text(l.cameraWhatIsThis),
                onTap: () {
                  Navigator.of(context).pop();
                  onExplain!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: Text(l.cameraSaveBlock),
              enabled: hasTranslation,
              onTap: hasTranslation
                  ? () => _saveToPhrasebook(context, ref)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Build the per-line copy rows when [block.text] spans multiple
  /// non-empty lines (returns an empty list otherwise so the Column
  /// spread is a no-op). Phone-shaped lines get a phone icon, lines
  /// that look like an address pick up a place-marker icon, plain
  /// text rows fall back to a generic copy-line icon. The detection
  /// is intentionally cheap (regex on the line itself) and runs on
  /// build — sheets are short-lived so memoising would add complexity
  /// for no win.
  List<Widget> _buildPerLineCopyRows(BuildContext context, WidgetRef ref) {
    final lines = block.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.length < 2) return const [];

    final l = AppLocalizations.of(context)!;
    return [
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(
          l.cameraCopyLineHeader,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.55),
          ),
        ),
      ),
      for (final line in lines)
        _LineRow(
          line: line,
          icon: _iconForLine(line),
          onTap: () {
            Clipboard.setData(ClipboardData(text: line));
            ref.read(trackingServiceProvider).event('block_copy_line',
                properties: {
                  'kind':  _kindForLine(line),
                  'scene': scene,
                  'lines': lines.length,
                });
            final messenger = scaffoldMessengerKey.currentState;
            messenger?.showSnackBar(
              SnackBar(
                content: Text(l.copied),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      const SizedBox(height: 6),
    ];
  }

  /// Heuristics for line classification. Order matters — phones look
  /// like addresses with digits, so phone matches first; address
  /// keywords come next; everything else gets the generic icon.
  IconData _iconForLine(String line) {
    if (_looksLikePhone(line)) return Icons.phone_outlined;
    if (_looksLikeAddress(line)) return Icons.location_on_outlined;
    return Icons.content_copy_outlined;
  }

  /// Telemetry kind string mirroring [_iconForLine]'s classification.
  String _kindForLine(String line) {
    if (_looksLikePhone(line)) return 'phone';
    if (_looksLikeAddress(line)) return 'address';
    return 'line';
  }

  /// Phone heuristic: at least 8 digits in the line, allowing common
  /// separators (spaces, dots, hyphens, parens) and a leading +. Most
  /// VN / JP / KR / TH numbers fit; doesn't require a specific
  /// country prefix because users scan signs from many countries.
  bool _looksLikePhone(String line) {
    final digitCount = RegExp(r'\d').allMatches(line).length;
    if (digitCount < 8) return false;
    // Reject lines that are mostly text with a small digit token (a
    // dish description "with 2 sides"); require digits to dominate.
    final nonSpace = line.replaceAll(RegExp(r'\s'), '').length;
    if (nonSpace == 0) return false;
    return digitCount / nonSpace >= 0.55;
  }

  /// Address heuristic: matches obvious markers across a few common
  /// scripts. Keep this conservative — false positive (showing the
  /// place-marker icon on a non-address line) is a bigger UX problem
  /// than missing one (user falls back to the generic icon).
  bool _looksLikeAddress(String line) {
    final lower = line.toLowerCase();
    const markers = <String>[
      // English
      'street', 'st.', 'st ', 'road', 'rd.', 'rd ', 'avenue', 'ave.',
      'blvd', 'lane', 'highway',
      // Vietnamese
      'đường', 'phố ', 'quận ', 'p. ', 'q. ', 'phường', 'tp.',
      // Japanese
      '丁目', '番地', '市', '区', '町', '通り',
      // Chinese
      '路', '街', '号', '里',
      // Korean
      '로', '길', '동',
    ];
    for (final m in markers) {
      if (lower.contains(m)) return true;
    }
    return false;
  }

  void _copy(BuildContext context, String text, WidgetRef ref,
      {required String kind}) {
    Clipboard.setData(ClipboardData(text: text));
    ref.read(trackingServiceProvider).event('block_copy',
        properties: {
          'kind':  kind,
          'scene': scene,
        });
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger != null) {
      final l = AppLocalizations.of(context)!;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.copied),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveToPhrasebook(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    // Two-step save: ask for an OPTIONAL note BEFORE the network call.
    // The note input never blocks — empty / Skip / dismiss all save
    // without a note. Solves the "added entry, forgot why I scanned it"
    // problem common on multi-day trips where the user scans 30 dishes
    // / signs and can't tell them apart later.
    final note = await _promptForNote(context);
    if (note == null) return; // user cancelled (vs Skip which returns '')
    if (!context.mounted) return;
    Navigator.of(context).pop();
    final messenger = scaffoldMessengerKey.currentState;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(l.cameraSavingPhrasebook),
        duration: const Duration(seconds: 4),
      ),
    );
    final saved = await ref.read(phrasebookProvider.notifier).save(
          recognizedText: block.text,
          explanation: translation,
          targetLang: targetLang,
          sourceLang: sourceLang,
          // Phrasebook traditionally hosts dishes (scene=menu) but the
          // user wants to save signs / addresses / screen text too; just
          // forward the active scene so we don't lose that signal even
          // though "category" in /phrasebook is menu-flavoured.
          scene: scene,
          originalText: block.text,
          note: note.isEmpty ? null : note,
        );
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(saved != null
            ? l.phrasebookSaved
            : l.phrasebookSaveFailed),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Optional-note dialog. Three exit paths:
  ///   - Save with note → returns the note string (may contain text)
  ///   - Skip (no note) → returns empty string ''
  ///   - Cancel / back / barrier-tap → returns null (no save at all)
  /// The split between '' and null lets the caller distinguish "user
  /// went through the flow but didn't want a note" from "user backed
  /// out of saving entirely".
  Future<String?> _promptForNote(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogCtx) {
          return AlertDialog(
            title: Text(l.cameraSaveBlock),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.cameraSaveNoteLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(dialogCtx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: l.cameraSaveNoteHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) =>
                      Navigator.of(dialogCtx).pop(value.trim()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(null),
                child: Text(l.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(''),
                child: Text(l.cameraSaveSkipNote),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogCtx).pop(controller.text.trim()),
                child: Text(l.phrasebookSave),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}

/// Compact tappable row for a single line of the block's original
/// text. Used by [BlockActionSheet] when a sign / multi-line block
/// holds heterogeneous data (business name, phone, address) and the
/// user wants to copy only ONE piece into another app (Maps, Phone).
/// [icon] is selected upstream based on a heuristic (phone vs address
/// vs generic line).
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.icon,
    required this.onTap,
  });

  final String line;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                line,
                style: const TextStyle(fontSize: 13, height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.copy_outlined,
              size: 14,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}
