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
      // Cap the sheet at 85% of the screen and scroll inside it. Without
      // this a long block (long translation + original + per-line rows)
      // makes the min-size Column taller than the screen, pushing the
      // action items (Copy / Dịch lại / Save) off the bottom with no way
      // to scroll to them.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
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
            // Per-line "split" rows only for menu / sign - the scenes where
            // breaking a block into lines (a dish per row, a sign's phone /
            // address per row) is the point. On other scenes (manga,
            // document, auto) a long multi-line block would emit a row per
            // line, bloating the sheet, so we skip them there. Sign gets the
            // SEMANTIC split (store name / phone / address groups) instead
            // of raw lines.
            if (scene == 'sign')
              ..._buildSignSplitRows(context, ref)
            else if (scene == 'menu')
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

  /// Semantic split for SIGN blocks. A storefront sign aggregates into
  /// ONE block ("Tuấn Vũ\nTẠO MẪU TÓC NAM NỮ\nĐT: 0967 678 161\n213
  /// TÂY HÒA - Q9") and the user almost always wants exactly one of
  /// three things out of it: the STORE NAME (to search), a PHONE
  /// NUMBER (to dial) or the ADDRESS (to paste into Maps). Instead of
  /// one raw row per line we classify and regroup:
  ///   - phone numbers are EXTRACTED from their line (the "ĐT:" label
  ///     is dropped, a line holding two numbers becomes two rows, the
  ///     copied text is stripped to a dial-ready number);
  ///   - consecutive address lines are joined into one row ("213 TÂY
  ///     HÒA", "Q9" → "213 TÂY HÒA, Q9") so Maps gets the full address
  ///     in one paste;
  ///   - the leading non-phone non-address lines are joined as the
  ///     store name (signs put the brand on top, often across 2 lines).
  /// Lines that fit nowhere stay as generic copy rows so nothing is
  /// ever lost by the grouping.
  List<Widget> _buildSignSplitRows(BuildContext context, WidgetRef ref) {
    final lines = block.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.length < 2) return const [];

    final phones = <String>[];
    final addressLines = <String>[];
    final nameLines = <String>[];
    final otherLines = <String>[];
    // The store name is the LEADING run of unclassified lines; once a
    // phone / address line appears, later unclassified lines (slogans,
    // opening hours) go to the generic bucket instead.
    var headerDone = false;

    for (final line in lines) {
      final extracted = _extractPhoneRuns(line);
      var rest = line;
      for (final run in extracted) {
        rest = rest.replaceFirst(run, ' ');
      }
      if (extracted.isNotEmpty) {
        phones.addAll(extracted.map(_dialReadyPhone));
        headerDone = true;
        // A pure phone line ("ĐT: 0967 678 161") is fully consumed;
        // a mixed line keeps its non-phone remainder for classification.
        rest = rest.replaceAll(_phoneLabelRe, ' ').trim();
        if (_letterCount(rest) < 3) continue;
      }
      if (_looksLikeAddress(rest)) {
        addressLines.add(rest);
        headerDone = true;
      } else if (!headerDone) {
        nameLines.add(rest);
      } else {
        otherLines.add(rest);
      }
    }

    // Nothing classified → fall back to the plain per-line rows rather
    // than showing one giant unlabeled "store name".
    if (phones.isEmpty && addressLines.isEmpty) {
      return _buildPerLineCopyRows(context, ref);
    }

    final l = AppLocalizations.of(context)!;
    final storeName = nameLines.join(' ');
    final address = addressLines.join(', ');

    void track(String kind) {
      ref.read(trackingServiceProvider).event('block_copy_line',
          properties: {
            'kind': kind,
            'scene': scene,
            'lines': lines.length,
          });
    }

    void copyWithSnack(String text, String kind) {
      Clipboard.setData(ClipboardData(text: text));
      track(kind);
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(l.copied),
          duration: const Duration(seconds: 2),
        ),
      );
    }

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
      if (storeName.isNotEmpty)
        _LineRow(
          line: storeName,
          label: l.cameraSignStoreName,
          icon: Icons.storefront_outlined,
          onTap: () => copyWithSnack(storeName, 'store'),
        ),
      for (final phone in phones)
        _LineRow(
          line: phone,
          label: l.cameraSignPhone,
          icon: Icons.phone_outlined,
          onTap: () => copyWithSnack(phone, 'phone'),
        ),
      if (address.isNotEmpty)
        _LineRow(
          line: address,
          label: l.cameraSignAddress,
          icon: Icons.location_on_outlined,
          onTap: () => copyWithSnack(address, 'address'),
        ),
      for (final line in otherLines)
        _LineRow(
          line: line,
          icon: Icons.content_copy_outlined,
          onTap: () => copyWithSnack(line, 'line'),
        ),
      const SizedBox(height: 6),
    ];
  }

  /// Phone-shaped digit runs inside a line: an optional +, then digits
  /// with common separators, at least 8 digits total. Catches "0967 678
  /// 161", "0909.123.456", "(028) 3812 3456". A line listing TWO numbers
  /// ("0946 123 032 - 0902 111 222") matches as ONE run because hyphen /
  /// space are both separators; [_splitJoinedRun] breaks it apart after.
  static final RegExp _phoneRunRe = RegExp(r'\+?\d[\d\s().\-]{6,}\d');

  /// Label tokens that commonly precede a phone number on signs. Used
  /// to blank the label out of a phone line's remainder so "ĐT:" alone
  /// doesn't survive as a fake store-name/slogan line.
  static final RegExp _phoneLabelRe = RegExp(
    r'(điện thoại|đt|sđt|d\.?t\.?|tel|telephone|phone|hotline|fax|zalo|whatsapp|mobile|call|電話|전화|โทร)\s*[:.]*',
    caseSensitive: false,
  );

  /// Extract dial-worthy runs (≥ 8 digits) from [line]; returns the
  /// matched substrings as they appear so the caller can blank them out.
  List<String> _extractPhoneRuns(String line) {
    return _phoneRunRe
        .allMatches(line)
        .map((m) => m.group(0)!)
        .expand(_splitJoinedRun)
        .where((run) => _digitCount(run) >= 8)
        .toList();
  }

  /// Split a run holding TWO phone numbers ("0946 123 032 - 0902 111
  /// 222") into one run per number. Only splits on a hyphen / slash /
  /// pipe where BOTH sides keep ≥ 8 digits — so a number with internal
  /// hyphens ("555-123-4567") stays whole (each side of its hyphens is
  /// under 8 digits).
  List<String> _splitJoinedRun(String run) {
    for (final sep in RegExp(r'\s*[-/|]\s*').allMatches(run)) {
      final leftPart = run.substring(0, sep.start);
      final rightPart = run.substring(sep.end);
      if (_digitCount(leftPart) >= 8 && _digitCount(rightPart) >= 8) {
        return [..._splitJoinedRun(leftPart), ..._splitJoinedRun(rightPart)];
      }
    }
    return [run];
  }

  int _digitCount(String s) => RegExp(r'\d').allMatches(s).length;

  /// Strip separators so the copied number pastes straight into the
  /// dialer: "0967 678.161" → "0967678161", keeps a leading +.
  String _dialReadyPhone(String run) {
    final plus = run.trimLeft().startsWith('+') ? '+' : '';
    return plus + run.replaceAll(RegExp(r'\D'), '');
  }

  /// Letters (any script) in [s] — digits/punctuation excluded. Used to
  /// decide whether a phone line has meaningful text besides the number.
  int _letterCount(String s) =>
      RegExp(r'[^\W\d_]', unicode: true).allMatches(s).length;

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
      'hẻm', 'ngõ', 'đại lộ', 'thị trấn', 'khu phố',
      // Japanese
      '丁目', '番地', '市', '区', '町', '通り',
      // Chinese
      '路', '街', '号', '里',
      // Korean
      '로', '길', '동',
      // Thai
      'ถนน', 'ซอย',
    ];
    for (final m in markers) {
      if (lower.contains(m)) return true;
    }
    // VN compact district/ward token: "Q9", "Q.9", "P 12". Word-bounded
    // so a dish code "Q9" alone matches too — acceptable on the sign
    // scene where this runs.
    if (RegExp(r'(^|[\s,.-])[qp]\.?\s?\d{1,2}($|[\s,.-])').hasMatch(lower)) {
      return true;
    }
    // House-number lead ("213 Tây Hòa", "25/3A Lê Lợi") — digits then a
    // separator then a real word. Require ≥3 letters in the line so a
    // bare price/quantity ("65.000đ") doesn't classify as an address.
    if (RegExp(r'^\d{1,4}[a-z]?[\s/,.-]').hasMatch(lower) &&
        _letterCount(line) >= 3) {
      return true;
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
    this.label,
  });

  final String line;
  final IconData icon;
  final VoidCallback onTap;

  /// Optional semantic caption rendered above the value (sign split:
  /// "Store name" / "Phone number" / "Address"). Null = plain copy row.
  final String? label;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(
                        label!,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  Text(
                    line,
                    style: const TextStyle(fontSize: 13, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
