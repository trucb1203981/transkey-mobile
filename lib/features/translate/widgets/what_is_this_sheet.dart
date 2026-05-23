import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/tracking/tracking_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../main.dart' show scaffoldMessengerKey;
import '../../phrasebook/models/phrasebook_entry.dart';
import '../../phrasebook/providers/phrasebook_provider.dart';
import '../providers/camera_settings_provider.dart';
import '../providers/language_settings_provider.dart';
import '../services/explain_cache.dart';
import '../services/tts_service.dart';

/// Parsed shape of the optional "Recognized as: …" first-line emitted
/// by /explain when the source was OCR-recovered. When non-null, the
/// sheet shows a "Save for later" button bound to this phrase; when
/// null, the input was already clear and no save button is shown.
class _RecognizedResult {
  const _RecognizedResult({required this.phrase, required this.isUncertain});
  final String phrase;
  final bool isUncertain;
}

/// Markers (in 14 locales) the server uses when it cannot recover the
/// OCR text. Matching any of these → suppress the Save button.
const _kUnclearMarkers = <String>[
  'text unclear',
  'văn bản không rõ',
  'テキスト不鮮明',
  '文本不清晰',
  '텍스트 불분명',
  'texte illisible',
  'texto ilegible',
  'text unklar',
  'texto ilegível',
  'текст неразборчив',
  'testo non leggibile',
  'نص غير واضح',
  'ข้อความไม่ชัดเจน',
  'teks tidak jelas',
];

/// Modal sheet that explains a short piece of text the user tapped in
/// the camera live preview. Calls /explain (the existing word/phrase
/// explanation endpoint) with the tapped block's text + the user's
/// target language + the active scene; renders the result and, when
/// the AI confidently recovered a dish/sign name from OCR garbage,
/// offers a "Save for later" action that persists the entry via
/// `/phrasebook` for later retrieval (travel use case: scan a menu
/// abroad → save dishes → show the saved entry to a waiter).
class WhatIsThisSheet extends ConsumerStatefulWidget {
  const WhatIsThisSheet({super.key, required this.text});
  final String text;

  static Future<void> show(BuildContext context, String text) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => WhatIsThisSheet(text: text),
    );
  }

  @override
  ConsumerState<WhatIsThisSheet> createState() => _WhatIsThisSheetState();
}

class _WhatIsThisSheetState extends ConsumerState<WhatIsThisSheet> {
  String? _explanation;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  /// True when [_explanation] came from the cache past its TTL — used
  /// as an offline fallback when the network call failed. UI shows a
  /// "may be outdated" badge so the user knows the result isn't fresh.
  bool _isStaleData = false;
  _RecognizedResult? _recognized;
  String _targetLang = 'en';
  String _scene = 'auto';

  /// The text we send to /explain. Defaults to widget.text but the user can
  /// override via the pencil on the gray source box — useful when the OCR
  /// captured a garbled menu line and the user wants to retype it before
  /// running explain, so the AI sees the clean phrase.
  late String _sourceText;

  /// ISO 639-1 of the original text, used so the speaker button can TTS the
  /// dish/place name with a correct-pronunciation voice (the whole point of
  /// the feature: a traveller plays it aloud to a local). Order of fall-back:
  /// (1) server-detected `detectedSourceLang` from /explain — most accurate,
  /// works for any language; (2) the user's persisted sourceLang IF they
  /// pinned it (not "auto") — useful as a backstop for cached entries from
  /// before the detection rolled out; (3) null → speaker disabled.
  String? _ttsLang;

  /// Editable canonical text that goes into the phrasebook as the title.
  /// Initialised to the AI-recognized phrase (if any) or the raw tapped
  /// text — but the user can override before tapping Save. Lets travellers
  /// correct cases where AI's "Recognized as:" got the dish/sign wrong, or
  /// type a name that AI didn't recognize at all.
  late final TextEditingController _canonicalController;

  @override
  void initState() {
    super.initState();
    _sourceText = widget.text;
    _canonicalController = TextEditingController();
    _fetch();
    ref.read(trackingServiceProvider).event('explain_open', properties: {
      'text_length': widget.text.length,
    });
  }

  @override
  void dispose() {
    _canonicalController.dispose();
    // Closing the sheet should also silence the speaker — otherwise pressing
    // play then swiping the sheet away leaves audio playing with no way to
    // stop it from this UI. ref.read in dispose is safe (no subscription).
    if (ref.read(ttsProvider).isPlaying) {
      ref.read(ttsProvider.notifier).stop();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
      _explanation = null;
      _recognized = null;
      _saved = false;
      _isStaleData = false;
    });
    try {
      final langSettings = ref.read(languageSettingsProvider).valueOrNull;
      final targetLang = langSettings?.targetLang ?? 'en';
      final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
          CameraScene.auto;
      _targetLang = targetLang;
      _scene = scene.id;

      // Backstop source lang: when the user pinned a concrete source language
      // (not "auto") it's still useful for legacy cache entries without
      // detectedSourceLang. Discard "auto" since TTS needs a concrete code.
      final pinnedSourceLang = langSettings?.sourceLang;
      final fallbackSrc = (pinnedSourceLang != null &&
              pinnedSourceLang.isNotEmpty &&
              pinnedSourceLang.toLowerCase() != 'auto')
          ? pinnedSourceLang
          : null;

      // Server's /explain DTO now accepts 1000 chars (was 500); bump
      // the client clip to match so menu paragraphs / multi-line signs
      // / dense document fragments get explained in full rather than
      // silently chopped at the old 500-char boundary. Anything past
      // 1000 still gets truncated as a safety net so we never let a
      // pathological capture (a whole document of text in one block)
      // through to the LLM — that would be expensive AND slow without
      // adding signal.
      final clipped = _sourceText.length > 1000
          ? _sourceText.substring(0, 1000)
          : _sourceText;

      // Reuse a prior result for the same text/lang/scene instead of
      // re-charging tokens when the user reopens the sheet on this block.
      // Cache is disk-backed with a 7-day TTL, so it also survives restarts.
      final cacheKey = ExplainCache.instance.key(clipped, targetLang, scene.id);
      final cached = await ExplainCache.instance.get(cacheKey);
      if (cached != null) {
        if (!mounted) return;
        final recognized = _parseRecognized(cached.explanation);
        setState(() {
          _loading = false;
          _explanation = cached.explanation;
          _recognized = recognized;
          _ttsLang = cached.detectedSourceLang ?? fallbackSrc;
          _canonicalController.text =
              recognized?.phrase ?? _suggestedCanonical(_sourceText);
        });
        return;
      }

      final api = ref.read(apiClientProvider);
      final response = await api.dio.post('/explain', data: {
        'text': clipped,
        'targetLang': targetLang,
        'context': scene.id,
      });
      final data = response.data as Map?;
      final explanation = (data?['explanation'] as String?) ?? '';
      final detected = data?['detectedSourceLang'] as String?;
      if (!mounted) return;
      // put() ignores empty answers, so an empty/error response can still be
      // retried (the retry button calls _fetch again with no cache entry).
      await ExplainCache.instance.put(
        cacheKey,
        explanation,
        detectedSourceLang: detected,
      );
      final recognized = _parseRecognized(explanation);
      setState(() {
        _loading = false;
        _explanation = explanation;
        _recognized = recognized;
        _ttsLang = detected ?? fallbackSrc;
        _canonicalController.text = recognized?.phrase ?? _sourceText;
      });
    } catch (e) {
      if (!mounted) return;
      // Stale fallback: when the network call fails (offline, slow,
      // server unreachable), try to surface a previously-cached result
      // EVEN IF it has expired. The 7-day TTL is fine for normal usage
      // but a traveller might genuinely be offline past it; showing
      // day-1 explain on day 10 with a "may be outdated" badge is
      // strictly better than a hard error.
      try {
        final langSettings = ref.read(languageSettingsProvider).valueOrNull;
        final targetLang = langSettings?.targetLang ?? 'en';
        final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
            CameraScene.auto;
        final pinnedSrc = langSettings?.sourceLang;
        final fallbackSrc = (pinnedSrc != null &&
                pinnedSrc.isNotEmpty &&
                pinnedSrc.toLowerCase() != 'auto')
            ? pinnedSrc
            : null;
        final clipped = _sourceText.length > 1000
            ? _sourceText.substring(0, 1000)
            : _sourceText;
        final cacheKey =
            ExplainCache.instance.key(clipped, targetLang, scene.id);
        final stale = await ExplainCache.instance.getStale(cacheKey);
        if (stale != null && mounted) {
          final recognized = _parseRecognized(stale.explanation);
          setState(() {
            _loading = false;
            _explanation = stale.explanation;
            _recognized = recognized;
            _ttsLang = stale.detectedSourceLang ?? fallbackSrc;
            _canonicalController.text =
                recognized?.phrase ?? _suggestedCanonical(_sourceText);
            _isStaleData = stale.isStale;
            _error = null;
          });
          ref.read(trackingServiceProvider).event('explain_stale_fallback',
              properties: {
                'is_stale':   stale.isStale,
                'target_lang': targetLang,
              });
          return;
        }
      } catch (_) {
        // If even the stale fallback path errors (e.g. cache load
        // failed), fall through to the error UI below.
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Parse the first line of [explanation] looking for a "Label: phrase"
  /// shape (label is one of the 14 native localisations of "Recognized
  /// as"). Returns null if:
  ///   • no colon on the first line (no recovery happened)
  ///   • the phrase matches an unclear marker (server gave up)
  ///   • the first line is too long to plausibly be a label line
  static _RecognizedResult? _parseRecognized(String explanation) {
    if (explanation.trim().isEmpty) return null;
    final firstLine = explanation.split('\n').first.trim();
    final colonIdx = firstLine.indexOf(':');
    if (colonIdx < 0) return null;
    // Heuristic: legit "Label: phrase" line is short. Long first lines
    // are full definitions that happen to contain a colon.
    if (firstLine.length > 120) return null;

    final phrase = firstLine.substring(colonIdx + 1).trim();
    if (phrase.isEmpty) return null;
    final lowerPhrase = phrase.toLowerCase();
    if (_kUnclearMarkers.any((marker) => lowerPhrase.contains(marker))) {
      return null;
    }

    // Strip trailing parenthetical (e.g. "(uncertain)" / "(không chắc)").
    final cleaned =
        phrase.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    if (cleaned.isEmpty) return null;

    final isUncertain = phrase.length != cleaned.length;
    return _RecognizedResult(phrase: cleaned, isUncertain: isUncertain);
  }

  /// Pick a sensible default for the canonical title from raw source text.
  /// Picks the FIRST non-empty line and caps it at 200 chars — multi-line
  /// vision aggregates (signs, document captures) otherwise dump the whole
  /// transcription into the title field, which both reads badly as a
  /// phrasebook label and trips the server's MaxLength validator.
  /// The user can still expand the title via the TextField before saving.
  static String _suggestedCanonical(String text) {
    final firstLine = text
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => text.trim());
    return firstLine.length > 200 ? firstLine.substring(0, 200) : firstLine;
  }

  /// Drop the leading "Recognized as: …" line + any blank separator lines
  /// from an explanation so the saved phrasebook entry stores only the
  /// human-readable definition + examples. The recognized phrase itself is
  /// preserved separately as the entry's title.
  static String _stripRecognizedHeader(String explanation) {
    final lines = explanation.split('\n');
    if (lines.isEmpty) return explanation;
    final rest = lines.sublist(1);
    while (rest.isNotEmpty && rest.first.trim().isEmpty) {
      rest.removeAt(0);
    }
    return rest.join('\n');
  }

  Future<void> _save() async {
    final explanation = _explanation;
    if (explanation == null || explanation.trim().isEmpty) return;

    // Canonical text = whatever's in the editor (defaults to recognized.phrase
    // ?? first-line of _sourceText, but the user may have overridden via
    // TextField / chips). Refuse empty so we don't create a blank entry.
    final canonical = _canonicalController.text.trim();
    if (canonical.isEmpty) return;
    // Validate length against the server cap. Snackbar + refuse-to-save —
    // a silent truncate would discard text the user explicitly typed,
    // which is worse UX than telling them to shorten it themselves.
    if (canonical.length > 1000) {
      final l = AppLocalizations.of(context)!;
      final messenger = scaffoldMessengerKey.currentState ??
          ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(l.phrasebookTitleTooLong),
        duration: const Duration(seconds: 3),
      ));
      return;
    }

    // originalText carries the raw OCR fragment ONLY when it differs from
    // the canonical the user is saving — so the saved entry can show "this
    // is what your camera read" alongside the corrected name. For clear
    // inputs both are the same and storing the original would just
    // duplicate. originalText is auto-set (not user-typed) so we silently
    // truncate to the server cap rather than blocking the save.
    var original = _sourceText != canonical ? _sourceText : null;
    if (original != null && original.length > 1000) {
      original = original.substring(0, 1000);
    }

    // When the explanation begins with a "Recognized as:" line, the saved
    // entry already carries that phrase in [recognizedText] (as the title);
    // surfacing it again in the explanation body would just clutter the
    // phrasebook view. Strip the lead line + any blank lines after it so the
    // stored explanation reads cleanly. We KEEP the recognized line in the
    // live sheet UI — it tells the user the OCR was corrected — but it has
    // no value after the entry is saved.
    final storedExplanation = _recognized != null
        ? _stripRecognizedHeader(explanation)
        : explanation;

    setState(() => _saving = true);
    final dish = await ref.read(phrasebookProvider.notifier).save(
          recognizedText: canonical,
          originalText: original,
          explanation: storedExplanation,
          scene: _scene,
          targetLang: _targetLang,
          // Persist so the saved-list speaker can TTS the entry in the
          // original language without re-running detection.
          sourceLang: _ttsLang,
          // Bucket the entry by the capture scene at save time. User can
          // re-categorise from the phrasebook detail later.
          category: PhrasebookCategory.fromScene(_scene),
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = dish != null;
    });

    // A snackbar shown WHILE this modal sheet is open renders BEHIND the
    // sheet's barrier: the auto-dismiss timer still fires but the user never
    // sees it, and the "View all" action area is intercepted by the barrier
    // so the tap never reaches the SnackBarAction. We pop first, then route
    // the snackbar through the APP-LEVEL [scaffoldMessengerKey] (set on
    // MaterialApp in main.dart). Using the key — not ScaffoldMessenger.of —
    // bypasses the per-Scaffold messenger that the modal sheet's transition
    // can leave in a half-disposed state where the snackbar mounts but its
    // auto-dismiss callback never fires.
    final l = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final rootContext = navigator.context;
    final messenger = scaffoldMessengerKey.currentState ??
        ScaffoldMessenger.of(context);

    if (dish != null) {
      navigator.pop();
      messenger.hideCurrentSnackBar();
      // SnackBar's own duration timer can fail to start cleanly when the
      // snackbar mounts right as a route is transitioning. Belt-and-braces:
      // capture the controller and ALSO call close() ourselves on a hard
      // timer so the snackbar is guaranteed to go away even if the built-in
      // timer never fires. The global [scaffoldMessengerKey] in main.dart
      // is the primary fix; this timer is the backstop.
      final controller = messenger.showSnackBar(SnackBar(
        content: Text(l.phrasebookSaved),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: l.phrasebookViewAll,
          onPressed: () {
            messenger.hideCurrentSnackBar();
            if (rootContext.mounted) rootContext.push('/phrasebook');
          },
        ),
      ));
      Future<void>.delayed(const Duration(milliseconds: 3300), () {
        try {
          controller.close();
        } catch (_) {
          // Already closed by the SnackBar's own timer or user interaction.
        }
      });
    } else {
      // Failure path keeps the sheet open so the user can retry without
      // losing the explanation they were just reading. The snackbar still
      // posts (it'll surface once they dismiss the sheet, and survives that
      // transition because messenger is the app-level one).
      messenger.showSnackBar(SnackBar(
        content: Text(l.phrasebookSaveFailed),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  /// The string the speaker plays. Prefer the OCR-recovered phrase (cleaned-
  /// up, real-language) over the raw tapped text (which may be garbled). If
  /// no recovery happened, fall back to the tapped text.
  String get _textToSpeak {
    final canonical = _canonicalController.text.trim();
    if (canonical.isNotEmpty) return canonical;
    final phrase = _recognized?.phrase;
    if (phrase != null && phrase.isNotEmpty) return phrase;
    return _sourceText;
  }

  /// Open an edit dialog to rewrite the source text before re-running explain.
  /// Useful on menu captures where the OCR garbled the dish name and the user
  /// can read the original better than the camera did. After Save → cache is
  /// effectively bypassed because the key changes (text changed), so /explain
  /// is hit fresh with the corrected input.
  Future<void> _editSource() async {
    final controller = TextEditingController(text: _sourceText);
    final l = AppLocalizations.of(context)!;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Use the EDIT-text key here, not cameraExplainTitle: the dialog
        // is for rewriting the OCR source so AI re-explains the corrected
        // phrase. Reusing the "What is this?" title was misleading.
        title: Text(l.cameraEditTextTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l.cameraReExplain),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || result == _sourceText) return;
    setState(() => _sourceText = result);
    await _fetch();
  }

  /// Speaker icon next to the original text. Plays [_textToSpeak] using
  /// [_ttsLang] (server-detected or pinned source lang). Disabled — and
  /// shown grey — when no usable source lang or the explanation hasn't
  /// loaded yet. Toggles between play / stop icons based on TTS state so
  /// the same button cancels in-flight speech.
  Widget _buildSpeakButton() {
    final lang = _ttsLang;
    final enabled = !_loading && _error == null && lang != null;
    final tts = ref.watch(ttsProvider);
    final isPlayingMine =
        tts.isPlaying && tts.currentText == _textToSpeak.trim();
    return IconButton(
      iconSize: 22,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(),
      tooltip: lang == null
          ? null
          : '${_textToSpeak.length > 30 ? "${_textToSpeak.substring(0, 30)}…" : _textToSpeak} · ${lang.toUpperCase()}',
      icon: Icon(
        isPlayingMine ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
        color: enabled
            ? (isPlayingMine ? Colors.amberAccent : Colors.lightBlueAccent)
            : Colors.white24,
      ),
      onPressed: enabled
          ? () {
              if (isPlayingMine) {
                ref.read(ttsProvider.notifier).stop();
              } else {
                // Use the user's persisted TTS rate from settings — they
                // adjust it via the bubble TTS settings sheet, and travel
                // pronunciation should honour that same preference (no
                // hidden per-surface override).
                ref.read(ttsProvider.notifier).speak(
                      _textToSpeak,
                      lang: lang,
                    );
                ref.read(trackingServiceProvider).event(
                      'explain_tts',
                      properties: {'lang': lang},
                    );
              }
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1F2937),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.psychology_outlined,
                        color: Colors.lightBlueAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.cameraExplainTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: _sourceText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l.copied),
                          duration: const Duration(seconds: 1)),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _sourceText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Pencil to rewrite the source before re-running
                        // explain — for menu captures where OCR garbled the
                        // dish name, the user can retype it to get a more
                        // accurate explanation.
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.white60, size: 18),
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          onPressed: _loading ? null : _editSource,
                        ),
                        _buildSpeakButton(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: Colors.lightBlueAccent),
                    ),
                  )
                else if (_error != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.cameraExplainError,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _fetch,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.lightBlueAccent,
                          side: const BorderSide(
                              color: Colors.lightBlueAccent),
                        ),
                        child: Text(l.cameraRetake),
                      ),
                    ],
                  )
                else ...[
                  if (_isStaleData)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.5),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_outlined,
                                size: 14, color: Colors.amberAccent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l.cameraExplainStaleBadge,
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Text(
                    (_explanation == null || _explanation!.trim().isEmpty)
                        ? l.cameraExplainEmpty
                        : _explanation!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
                // Disclaimer for menu / sign / auto scenes — the AI may
                // recover the wrong dish or misread a sign's intent, so
                // for travel-critical use cases (ordering food, obeying
                // signage) warn the user the result is informational.
                if (!_loading &&
                    _error == null &&
                    (_scene == 'menu' || _scene == 'sign' || _scene == 'auto'))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB45309)
                            .withValues(alpha: 0.18), // amber-700 tint
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFFBBF24)
                              .withValues(alpha: 0.4), // amber-300
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline,
                              size: 14, color: Color(0xFFFBBF24)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l.cameraExplainDisclaimer,
                              style: const TextStyle(
                                color: Color(0xFFFDE68A), // amber-200
                                fontSize: 11,
                                height: 1.4,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Save to phrasebook — visible after a successful explain.
                // We pre-fill an editable text field with the AI's recognized
                // phrase (or the raw tapped text when no recovery happened),
                // and offer two quick chips to swap between AI / OCR when the
                // user wants to override. Travellers can also free-type to fix
                // a name AI got wrong. The saved entry's title is whatever's
                // in the field at the moment Save is tapped.
                if (!_loading &&
                    _error == null &&
                    _explanation != null &&
                    _explanation!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _canonicalController,
                          enabled: !_saved && !_saving,
                          // Hard cap matching the server's MaxLength so the
                          // user physically can't type past the limit. The
                          // counter (rendered below by InputDecoration when
                          // maxLength is set) gives a live "X / 1000" hint.
                          maxLength: 1000,
                          // Rebuild on each keystroke so the helperText
                          // warning below toggles in real time as the user
                          // approaches the cap. ValueListenableBuilder over
                          // the controller would be cleaner but setState on
                          // a sheet of this size is cheap.
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            filled: true,
                            fillColor:
                                Colors.white.withValues(alpha: 0.05),
                            // Hide the default "N / 1000" counter until the
                            // user gets close — 800 chars is a generous
                            // headroom (typical save is 5-50 chars), past
                            // that the counter appears as a warning.
                            counterText:
                                _canonicalController.text.length < 800
                                    ? ''
                                    : null,
                            counterStyle: TextStyle(
                              color: _canonicalController.text.length > 900
                                  ? Colors.amberAccent
                                  : Colors.white60,
                              fontSize: 11,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                  color: Colors.white
                                      .withValues(alpha: 0.1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Colors.lightBlueAccent),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                  color: Colors.white
                                      .withValues(alpha: 0.08)),
                            ),
                          ),
                        ),
                        // Reference chips for swapping the canonical text. The
                        // OCR chip is always shown when we have source text —
                        // it lets the user "revert to what the camera saw"
                        // even when AI didn't flag a correction (common on
                        // clean menus where the LLM thinks the OCR was fine
                        // but the user still wants to verify). The AI chip
                        // appears only when AI's recognized phrase differs
                        // from the source (otherwise it'd duplicate OCR).
                        if (_sourceText.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (_recognized != null &&
                                    _recognized!.phrase != _sourceText)
                                  ActionChip(
                                    avatar: const Icon(
                                        Icons.smart_toy_outlined,
                                        size: 14,
                                        color: Colors.lightBlueAccent),
                                    label: Text(
                                      'AI: ${_recognized!.phrase}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onPressed: _saved || _saving
                                        ? null
                                        : () => _canonicalController.text =
                                            _recognized!.phrase,
                                  ),
                                ActionChip(
                                  avatar: const Icon(
                                      Icons.camera_alt_outlined,
                                      size: 14,
                                      color: Colors.white70),
                                  label: Text(
                                    '${l.cameraOriginalLabel}: $_sourceText',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: _saved || _saving
                                      ? null
                                      : () => _canonicalController.text =
                                          _sourceText,
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: Icon(_saved
                                ? Icons.bookmark
                                : Icons.bookmark_add_outlined),
                            label: Text(
                              _saving
                                  ? l.phrasebookSave
                                  : (_saved
                                      ? l.phrasebookSaved
                                      : l.phrasebookSave),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _saved
                                  ? Colors.green
                                  : Colors.lightBlueAccent,
                              foregroundColor: _saved
                                  ? Colors.white
                                  : Colors.black87,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: (_saving || _saved) ? null : _save,
                          ),
                        ),
                      ],
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
