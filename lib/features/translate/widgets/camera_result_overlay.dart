import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/camera/bg_color_sampler.dart';
import '../../../core/camera/camera_service.dart';

/// Resolved render geometry for one card — position is LOCKED to the
/// source OCR box (no anti-overlap shifting) and the font size is
/// tuned per-card so the translation fits the original height when
/// possible. Height can grow beyond the source box when even the
/// minimum readable font can't fit the translation, so the user
/// never sees a truncated ("…") translation - DeepL truncates with
/// ellipsis in that case, we stay readable instead.
class _CardLayout {
  _CardLayout({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.fontSize,
  });
  final int index;
  final double left;
  final double top;
  final double width;
  final double height;
  final double fontSize;
}

// Card text inset. _kCardVPad was 0 historically (when the card was
// fixed to the bbox and FittedBox shrank text to fit), which let
// descender/ascender pixels touch the rounded edges and visually clip.
// Now that the card sizes tightly to the rendered text we add real
// padding both axes so glyphs always sit clear of the card border.
const double _kCardHPad = 5.0;
const double _kCardVPad = 4.0;
// Raised 7 → 9. OCR-path bboxes are tight around the text mass (TABD
// per-line + BubbleDetector glyph clusters), so a 7 pt floor produced
// unreadable cards on small dialogue bubbles even when the vision-
// catch-up path on the same page rendered comfortably at 12-14 pt.
// Tried 10 first but adjacent dense bubbles' cards visibly overlapped
// neighbouring text on action pages; 9 keeps the readability gain
// without the overlap regression. Overflow handling stays unchanged:
// the card grows downward when even 9 pt doesn't fit.
const double _kMinFontSize = 9.0;
const double _kMaxFontSize = 28.0;

// Manga cards size their font to the bubble (not to the page like menu
// cards), so they get their own tighter range. Floor 10 keeps the
// translated VI text readable even in a small bubble (the card grows
// downward when it overflows); cap 16 stops a roomy bubble from getting
// an oversized font that bleeds into the neighbouring panel.
// Matches _kMinFontSize so the manga clamp never raises the font back above
// what _fitFont's word-width guard chose (which would re-break words).
const double _kMangaMinFont = 9.0;
const double _kMangaMaxFont = 16.0;
// Absolute floor for the manga WORD-INTACT shrink (below the readable
// _kMangaMinFont): when a bubble is too narrow to fit the widest whole word
// even after growing into the neighbour gap, the font drops to here so the
// word stays in one piece ("không", "Tôi") instead of breaking mid-glyph. A
// small intact word reads far better than a split one.
const double _kMangaWordFloor = 7.0;

// Slack (logical px) added to the widest-word width when sizing a card, so the
// widest word never sits EXACTLY at the wrap boundary. A tight fit re-wraps the
// last glyph ("thương" -> "thươn"/"g") because the rendered Text and the
// TextPainter that measured it can differ by a sub-pixel-to-~1px (rounding, and
// any width-affecting style the Text inherits but the raw painter does not).
// 2 px is invisible but absorbs that gap. Pair this with letterSpacing: 0 on the
// rendered Text (kills the inherited Material letterSpacing the painter lacks).
const double _kWordFitSlack = 2.0;

// The overlay cards honour the device's system text-scale (accessibility
// "Larger Text") but CAP it here: a translation card is sized to its source
// bubble, so an uncapped 1.3-2.0x system scale would overflow small manga
// bubbles badly. 1.15x gives low-vision users a real size bump while keeping
// dense bubbles legible. The SAME capped scale is fed into every TextPainter
// that sizes a card AND the rendered Text, so measure == render (no mid-word
// break). The app's own font-scale slider (widget.fontScale) stacks on top.
const double _kMaxOverlayTextScale = 1.15;

// Client-side last-line guard against a single OCR/Vision/server block
// covering most of the page. Anything above this fraction of the view
// area gets skipped before being rendered as a card. 0.25 = no card may
// exceed a quarter of the screen, which is well above any legitimate
// dialogue bubble while comfortably below a panel-covering merge bug.
const double _kMaxBboxAreaRatio = 0.25;

/// Count of "meaningful" characters - Latin letters, digits, and CJK / kana /
/// hangul codepoints (punctuation / whitespace / symbols don't count). Used to
/// rank two overlapping manga cards so the one carrying the most real text
/// wins the "overlay double" suppression.
int _meaningfulChars(String s) {
  var count = 0;
  for (final rune in s.runes) {
    if ((rune >= 0x30 && rune <= 0x39) || // 0-9
        (rune >= 0x41 && rune <= 0x5A) || // A-Z
        (rune >= 0x61 && rune <= 0x7A) || // a-z
        (rune >= 0xC0 && rune <= 0x24F) || // Latin-1 + extended (accents)
        (rune >= 0x3040 && rune <= 0x30FF) || // hiragana + katakana
        (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK unified
        (rune >= 0xAC00 && rune <= 0xD7AF)) { // hangul syllables
      count++;
    }
  }
  return count;
}

/// Bridges the overlay's internal view state (card visibility + the
/// drag/dismiss edits) out to the host screen so the action-bar buttons
/// (eye toggle + reset) can live in the SAME row as Retake / Copy all
/// instead of floating over the photo and colliding with the top-bar
/// chrome. The overlay owns the actual state; this just exposes a
/// controllable handle + change notifications.
class CameraResultOverlayController extends ChangeNotifier {
  bool _visible = true;
  bool get visible => _visible;

  bool _hasEdits = false;

  /// True when the user has dragged or dismissed at least one card, so
  /// the host can show/hide the reset button.
  bool get hasEdits => _hasEdits;

  /// Wired by the overlay; the host calls [reset] to clear all drags +
  /// dismissals.
  VoidCallback? _resetHook;

  void toggleVisible() {
    _visible = !_visible;
    notifyListeners();
  }

  void reset() => _resetHook?.call();

  // ── Internal: called by the overlay state ──
  void attachResetHook(VoidCallback hook) => _resetHook = hook;

  void setHasEdits(bool value) {
    if (_hasEdits == value) return;
    _hasEdits = value;
    notifyListeners();
  }

  /// Sync visibility set from inside the overlay (tap-anywhere gesture)
  /// without re-triggering a notify loop through [toggleVisible].
  void syncVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }
}

/// Displays OCR text blocks positioned over the captured image.
///
/// Design goals (vs the earlier version + vs DeepL):
///   - Card stays at the exact pixel position the source text occupied.
///     No anti-overlap shifting, no horizontal slide.
///   - Translation is NEVER ellipsised. Font auto-fits inside the source
///     box; if even [_kMinFontSize] doesn't fit, the card grows
///     downward and keeps every character.
///   - Card background colour is sampled from the photo (median of the
///     pixels just outside the bounding box) so the panel blends into
///     the underlying scene rather than chip-stamping over it.
///   - Text colour flips between black / white per-card based on the
///     sampled background's luminance.
class CameraResultOverlay extends StatefulWidget {
  const CameraResultOverlay({
    super.key,
    required this.blocks,
    required this.translations,
    required this.imageSize,
    this.imagePath,
    this.controller,
    this.showOriginal = false,
    this.hideLowConfidence = false,
    this.showOriginalAlways = false,
    this.overlayOpacity = 0.95,
    this.usePrimaryColor = false,
    this.pendingIndices = const {},
    this.mangaMode = false,
    this.menuMode = false,
    this.fontScale = 1.0,
    this.onBackgroundTap,
    this.onExplain,
    this.onBlockTap,
  });

  final List<OcrBlock> blocks;
  final List<String> translations;
  final ui.Size imageSize;

  /// Optional external controller. When provided, the eye toggle + reset
  /// buttons are NOT drawn inside the overlay - the host screen renders
  /// them in its action bar and drives them through this controller.
  final CameraResultOverlayController? controller;

  /// Absolute path of the capture file backing [imageSize]. Used to
  /// sample per-block background colour on the native side. Null means
  /// the sampling is skipped and cards fall back to [BgColorSampler.fallback].
  final String? imagePath;

  /// Force the cards to render the source text instead of the translation
  /// (used by future "show source" toggle - not wired to UI yet).
  final bool showOriginal;

  /// When true, also drop blocks flagged [OcrBlock.isLowConfidence] -
  /// keeps only "good" quality.
  final bool hideLowConfidence;

  /// When true, render the source text under every translation card.
  final bool showOriginalAlways;

  /// Card background opacity (0.4–1.0). Applied on top of the sampled
  /// colour - 1.0 means the card fully replaces what's underneath
  /// (matching DeepL's overlay), lower values let the original text
  /// bleed through.
  final double overlayOpacity;

  /// When true, all cards use a single primary color instead of per-block
  /// sampled background colors.
  final bool usePrimaryColor;

  /// Block indices still awaiting their translation from the server.
  /// Cards at these indices render an animated dashed border.
  final Set<int> pendingIndices;

  final bool mangaMode;

  /// Menu scene: the server blanks non-dish fragments (prices, headers,
  /// hours, address, shop logo) to "". When true, cards with an empty
  /// translation are dropped so only dish names + notes render - the
  /// original noise stays visible on the photo behind the overlay.
  final bool menuMode;

  /// User-tunable multiplier on the overlay font. At 1.0 the auto fitter
  /// chooses a size that fits the source bbox; above 1.0 the text is
  /// rendered at the chosen size WITHOUT being shrunk back to fit, and
  /// is allowed to paint outside the card (the card background stays
  /// anchored to the bbox so only glyphs overflow).
  final double fontScale;

  final VoidCallback? onBackgroundTap;
  final ValueChanged<OcrBlock>? onExplain;
  final void Function(int index, OcrBlock block, String translation)?
      onBlockTap;

  @override
  State<CameraResultOverlay> createState() => _CameraResultOverlayState();
}

class _CameraResultOverlayState extends State<CameraResultOverlay>
    with SingleTickerProviderStateMixin {
  bool _overlayVisible = true;

  /// Drives the marching-ants dash animation on pending cards.
  late final AnimationController _dashAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat();

  /// True when this overlay should render its OWN eye + reset controls.
  /// False when a [CameraResultOverlayController] is supplied - then the
  /// host screen owns those buttons.
  bool get _selfManagedControls => widget.controller == null;

  /// Per-block drag deltas (index → cumulative pan offset). Cleared by
  /// the reset action.
  final Map<int, Offset> _dragOffsets = <int, Offset>{};

  /// Blocks the user dragged into the trash zone. Rendering skips them
  /// until reset.
  final Set<int> _dismissed = <int>{};

  int? _draggingIndex;
  bool _overTrash = false;

  /// Toggle a red outline that draws the raw OCR bounding box mapped to
  /// the view. Used to debug "card not at the source position": if the
  /// red outline already sits in the wrong place, the math from box →
  /// view coords is broken; if the outline is correct but the card is
  /// elsewhere, the issue is in card sizing / Positioned wiring.
  final bool _debugShowBoxes = false;

  /// Background colours filled in asynchronously after the native
  /// sampler returns. Keyed by block index. Until populated for an
  /// index, the card uses [BgColorSampler.fallback].
  final Map<int, Color> _bgColors = <int, Color>{};

  /// System text-scale (capped at [_kMaxOverlayTextScale]) applied to BOTH the
  /// card-sizing TextPainters and the rendered card Text, so the overlay
  /// follows accessibility "Larger Text" without breaking words. Recomputed at
  /// the top of every build from MediaQuery; a plain derived cache, never a
  /// trigger for rebuild.
  TextScaler _overlayScaler = TextScaler.noScaling;

  static const double _kTrashRadius = 80;
  static const double _kTrashBottomGap = 80;

  double get _minFont => _kMinFontSize;
  double get _maxFont => _kMaxFontSize;

  @override
  void initState() {
    super.initState();
    _startBgSampling();
    final c = widget.controller;
    if (c != null) {
      c.attachResetHook(_resetEdits);
      c.addListener(_onControllerChanged);
      _overlayVisible = c.visible;
    }
  }

  @override
  void didUpdateWidget(covariant CameraResultOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onControllerChanged);
      widget.controller?.attachResetHook(_resetEdits);
      widget.controller?.addListener(_onControllerChanged);
    }
    // Re-sample whenever the underlying capture file changes. We
    // identity-check the path: the parent attaches a ValueKey on
    // _capturedPath so a real swap brings us a fresh State, but a
    // retry / retranslate keeps us alive with the same path - and
    // we want to keep the previously-sampled colours in that case.
    if (old.imagePath != widget.imagePath ||
        !identical(old.blocks, widget.blocks)) {
      _bgColors.clear();
      _startBgSampling();
    }
  }

  @override
  void dispose() {
    _dashAnim.dispose();
    widget.controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// React to the host toggling visibility through the controller.
  void _onControllerChanged() {
    final c = widget.controller;
    if (c == null) return;
    if (c.visible != _overlayVisible) {
      setState(() => _overlayVisible = c.visible);
    }
  }

  /// Clear all drag offsets + dismissals. Triggered by the in-overlay
  /// reset chip OR the host's reset button via the controller.
  void _resetEdits() {
    setState(() {
      _dragOffsets.clear();
      _dismissed.clear();
    });
    widget.controller?.setHasEdits(false);
  }

  /// Recompute + publish the "has edits" flag after any drag/dismiss
  /// change so the host's reset button shows/hides correctly.
  void _publishEdits() {
    widget.controller
        ?.setHasEdits(_dragOffsets.isNotEmpty || _dismissed.isNotEmpty);
  }

  Future<void> _startBgSampling() async {
    if (widget.usePrimaryColor) return;
    final path = widget.imagePath;
    if (path == null || widget.blocks.isEmpty) return;
    final rects = widget.blocks.map((b) => b.boundingBox).toList();
    final colors = await BgColorSampler.sample(imagePath: path, rects: rects);
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < colors.length && i < widget.blocks.length; i++) {
        _bgColors[i] = colors[i];
      }
    });
  }

  bool _isOverTrash(Offset point, Size viewSize) {
    // Full-width band across the bottom: cards drag vertically only now (so
    // horizontal swipes page the batch), keeping their column x, so a centred
    // circular zone is unreachable for side cards. Any card dragged far enough
    // DOWN lands in the band; the trash icon stays centred as the visual cue.
    final bandTop = viewSize.height - _kTrashBottomGap - _kTrashRadius * 2;
    return point.dy >= bandTop;
  }

  /// Number of visual lines occupied by the source text inside its
  /// bounding box. ML Kit emits one block per paragraph with `\n`
  /// between lines, so a quick split is enough. Floor at 1 because
  /// some blocks are single tokens with no newline.
  int _sourceLineCount(String text) {
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).length;
    return math.max(1, lines);
  }

  /// Estimate the font size that produced the source text inside a
  /// box of [boxHeight] tall with [lines] visual lines. Line-height
  /// factor of 1.25 mirrors what _BlockCard renders with. Clamped so
  /// extreme aspect ratios (a tall narrow box around a single short
  /// word, or a flat one-line block on a banner) still produce a
  /// readable starting font.
  double _estimateSourceFont(double boxHeight, int lines) {
    final lineH = boxHeight / lines;
    return (lineH / 1.25).clamp(_minFont, _maxFont);
  }

  /// Solve for the font size at which [text] wrapped to [maxWidth]
  /// fits within [maxHeight], starting from [startFont].
  ///
  /// Math: total rendered height H scales as (font / startFont)²
  /// (chars-per-line goes up linearly when font shrinks, total lines
  /// goes down linearly → height shrinks quadratically). One analytic
  /// estimate gets us within a font size of optimal; we then refine
  /// with up to 4 measure-then-shrink steps because wrap discretization
  /// (a line that "almost fits" suddenly breaks) makes the analytic
  /// result a slight under-estimate of the achievable font.
  ///
  /// Returns the chosen font size + the measured height at that font.
  /// If even [_kMinFontSize] overflows, returns [_kMinFontSize] with
  /// its measured (over-)height; the caller grows the card downward
  /// instead of truncating.
  ({double fontSize, double height}) _fitFont({
    required String text,
    required double maxWidth,
    required double maxHeight,
    required double startFont,
    required FontWeight fontWeight,
  }) {
    if (text.isEmpty) {
      return (fontSize: startFont, height: 0);
    }
    // innerW floor matches the SizedBox width inside _BlockCard. The
    // earlier floor of 20 over-measured space when the OCR box was
    // narrow (cardWidth - 8 < 20): the fitter thought text fit at a
    // larger font, but the actual render wrapped to more lines, then
    // FittedBox shrank everything to fit cardHeight - text ended up
    // tiny / unreadable. 8 is a safer floor (one glyph at small font).
    final innerW = math.max(8.0, maxWidth - _kCardHPad * 2);
    final innerH = math.max(0.0, maxHeight - _kCardVPad * 2);

    // fontWeight matches what _BlockCard renders (w500 for translations, w400
    // otherwise). Heavier glyphs are wider so they wrap to more lines, and
    // measuring at the rendered weight is what keeps fit1.height accurate.
    double measureAt(double font) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style:
              TextStyle(fontSize: font, fontWeight: fontWeight, height: 1.25),
        ),
        textDirection: TextDirection.ltr,
        textScaler: _overlayScaler,
      )..layout(maxWidth: innerW);
      return tp.size.height;
    }

    var font = startFont;
    var h = measureAt(font);
    if (h <= innerH || innerH <= 0) {
      return (fontSize: font, height: h + _kCardVPad * 2);
    }

    // Analytic shrink: h scales ~ font². Solve for font that puts h at
    // innerH, clamped to the readable floor.
    final ratio = math.sqrt(innerH / h);
    font = (startFont * ratio).clamp(_minFont, startFont);
    h = measureAt(font);

    // Refine: wrap discretization can leave us still over by a line.
    // Step 1pt at a time until it fits or hits the floor. Safety cap is
    // wide enough to walk the full _kMaxFontSize -> _kMinFontSize range
    // (a low cap used to bail early, leaving an above-floor font whose
    // text still overflowed and produced the debug stripe).
    var safety = 0;
    while (h > innerH && font > _minFont && safety < 30) {
      font = math.max(_minFont, font - 1);
      h = measureAt(font);
      safety++;
    }

    // WORD-WIDTH guard (space-delimited scripts): TextPainter breaks a word
    // mid-glyph when the word is wider than innerW, so "Được" renders as
    // "Đư" / "ợc" - two meaningless fragments. Shrink the font until the
    // WIDEST whole word fits innerW (down to the readable floor) so words stay
    // intact. Skipped for CJK (no inter-word spaces; per-char wrap is correct).
    if (RegExp(r'[A-Za-z]').hasMatch(text)) {
      var wsafety = 0;
      while (_widestWordWidth(text, font, fontWeight) > innerW - _kWordFitSlack &&
          font > _minFont &&
          wsafety < 30) {
        font = math.max(_minFont, font - 1);
        wsafety++;
      }
      h = measureAt(font);
    }

    // h at _kMinFontSize is what the card actually renders; caller
    // grows the box if it overflows.
    return (fontSize: font, height: h + _kCardVPad * 2);
  }

  /// Width of the widest whitespace-delimited word in [text] at [font].
  /// Used by [_fitFont]'s word guard to stop mid-word glyph breaks.
  double _widestWordWidth(
      String text, double font, FontWeight fontWeight) {
    var maxW = 0.0;
    for (final w in text.split(RegExp(r'\s+'))) {
      if (w.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: w,
          style:
              TextStyle(fontSize: font, fontWeight: fontWeight, height: 1.25),
        ),
        textDirection: TextDirection.ltr,
        textScaler: _overlayScaler,
      )..layout();
      if (tp.width > maxW) maxW = tp.width;
    }
    return maxW;
  }

  /// Reduce [font] until the widest whitespace-delimited word fits [innerW]
  /// at the RENDERED size ([font] * [scale]), so a word never breaks
  /// mid-glyph. This is the final guard after build()'s readable floor and
  /// the font-scale slider, both of which can re-inflate a word past the card
  /// width that [_fitFont]'s own guard had already shrunk to fit. Floored at
  /// [_minFont] (an intact word at the floor beats a split one); skipped for
  /// space-less scripts (CJK) where per-character wrap is correct.
  double _clampFontToWordWidth(
    String text,
    double font,
    double innerW,
    FontWeight fontWeight,
    double scale,
  ) {
    if (innerW <= 0 || scale <= 0) return font;
    if (!RegExp(r'[A-Za-z]').hasMatch(text)) return font;
    var f = font;
    var safety = 0;
    while (f > _minFont &&
        _widestWordWidth(text, f * scale, fontWeight) > innerW - _kWordFitSlack &&
        safety < 40) {
      f = math.max(_minFont, f - 0.5);
      safety++;
    }
    return f;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Capped system text-scale, shared by measure + render this build.
        _overlayScaler = TextScaler.linear(math.min(
          MediaQuery.textScalerOf(context).scale(1.0),
          _kMaxOverlayTextScale,
        ));
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final fit = _fitContain(widget.imageSize, viewSize);
        final scaleX = fit.fitW / widget.imageSize.width;
        final scaleY = fit.fitH / widget.imageSize.height;

        // Map every block's bbox to view coords once. A card may grow RIGHT
        // into genuinely empty space (so a longer translation doesn't wrap
        // inside the narrow source box when there's room beside it) - these
        // rects are the neighbours each card must stop short of so the
        // expansion never overruns the next block on the same row.
        final viewRects = <Rect>[
          for (final b in widget.blocks)
            Rect.fromLTWH(
              b.boundingBox.left * scaleX + fit.offsetX,
              b.boundingBox.top * scaleY + fit.offsetY,
              b.boundingBox.width * scaleX,
              b.boundingBox.height * scaleY,
            ),
        ];

        final cards = <_CardLayout>[];
        for (var i = 0; i < widget.blocks.length; i++) {
          if (_dismissed.contains(i)) continue;
          final block = widget.blocks[i];
          if (widget.hideLowConfidence && block.isLowConfidence) continue;
          final box = block.boundingBox;

          // Map source-image bbox to view coordinates. Position is
          // locked to the source - no shift, no expansion to the left.
          final left = box.left * scaleX + fit.offsetX;
          final top = box.top * scaleY + fit.offsetY;
          final boxW = box.width * scaleX;
          final boxH = box.height * scaleY;
          // Client-side panel-cover guard. Any bbox whose mapped area
          // exceeds _kMaxBboxAreaRatio of the view is treated as an
          // OCR/Vision/server-side mis-grouping (multiple bubbles merged
          // into one mega-block, or margin expansion over-inflated) and
          // skipped client-side. This is a last-line of defense: the
          // real fix is upstream (BubbleDetector fill-ratio guard, TABD
          // cluster, server margin cap) - but dropping it here keeps a
          // single bad block from painting a card over an entire panel
          // even if every upstream guard slips.
          final viewArea = viewSize.width * viewSize.height;
          if (viewArea > 0 &&
              (boxW * boxH) / viewArea > _kMaxBboxAreaRatio) {
            continue;
          }
          // Clamp the right edge so a card anchored near the screen
          // edge can't paint off-screen. Left/top stay untouched so the
          // position invariant holds.
          final cardWidth =
              math.min(boxW, math.max(40.0, viewSize.width - left - 4));

          final translation = i < widget.translations.length
              ? widget.translations[i]
              : '';
          // Menu scene: the server returns "" for non-dish fragments
          // (prices, headers, hours, address, shop logo). Drop those cards
          // so only dish names + notes render. Skip the drop while the
          // block is still pending (empty == not-yet-translated, not
          // blanked) and while the user is inspecting originals.
          if (widget.menuMode &&
              !widget.showOriginal &&
              !widget.pendingIndices.contains(i) &&
              translation.trim().isEmpty) {
            continue;
          }
          final isTranslated = !widget.showOriginal &&
              translation.isNotEmpty &&
              translation != block.text;
          final displayText = widget.showOriginal
              ? block.text
              : (isTranslated ? translation : block.text);

          if (widget.mangaMode) {
            // Manga: card = TIGHT to translated text + small padding,
            // anchored at the bbox top-left so it sits exactly where the
            // source text started. Width stays clamped to the bbox so
            // text wraps the same; height grows downward past the bbox
            // when fontScale > 1.0 (the slider scales BOTH the font AND
            // the card so the text always sits inside the card).
            //
            // Font was a hardcoded 6px - below the 9px readable floor, so
            // every bubble rendered unreadable tiny text. Now fit the
            // translation to the bubble (its width clamp + height) at the
            // LARGEST size that fits, floored at a readable minimum and
            // capped so a roomy bubble doesn't get a huge font. When even
            // the floor overflows the bubble height the card grows
            // downward (centred below) instead of shrinking further - a
            // readable 10px line that spills past a tiny vertical-JP
            // bubble beats a 6px line that fits but can't be read.
            final mangaFit = _fitFont(
              text: displayText,
              maxWidth: cardWidth,
              maxHeight: boxH,
              startFont: _kMangaMaxFont,
              fontWeight:
                  isTranslated ? FontWeight.w500 : FontWeight.normal,
            );
            var mangaFont = mangaFit.fontSize
                .clamp(_kMangaMinFont, _kMangaMaxFont)
                .toDouble();
            var renderedManga = mangaFont * widget.fontScale;
            // A vertical-JP bubble is a THIN column, but the horizontal VI word
            // needs width; clamping to the bubble breaks a word mid-glyph
            // ("Cảm" -> "Cả"/"m"). Grow the card (centred on the bubble) to fit
            // the widest WHOLE word, but ONLY into the gap to the nearest
            // neighbour bubble on each side, so cards never overlap. In a dense
            // cluster (no gap) it stays at bubble width and _fitFont's font
            // shrink keeps as much whole as it can.
            final mangaCx = left + boxW / 2;
            final mangaNeedW = _widestWordWidth(
                  displayText,
                  renderedManga,
                  isTranslated ? FontWeight.w500 : FontWeight.normal,
                ) +
                _kCardHPad * 2;
            var mangaLeftLimit = 4.0;
            var mangaRightLimit = viewSize.width - 4;
            for (var j = 0; j < viewRects.length; j++) {
              if (j == i) continue;
              final r = viewRects[j];
              // Same-row only: a neighbour must overlap this bubble vertically
              // by a real amount to cap the sideways growth.
              final ov = math.min(top + boxH, r.bottom) - math.max(top, r.top);
              if (ov < math.min(boxH, r.height) * 0.4) continue;
              if (r.right <= mangaCx && r.right + 4 > mangaLeftLimit) {
                mangaLeftLimit = r.right + 4;
              }
              if (r.left >= mangaCx && r.left - 4 < mangaRightLimit) {
                mangaRightLimit = r.left - 4;
              }
            }
            // Half-width the centred card may use = nearest free gap each side,
            // never below the bubble's own half (the bubble never overlaps a
            // neighbour, so bubble width is always collision-safe).
            final mangaHalf = math.max(boxW / 2,
                math.min(mangaCx - mangaLeftLimit, mangaRightLimit - mangaCx));
            final mangaAllowW =
                math.max(cardWidth, math.min(mangaNeedW, 2 * mangaHalf));
            // The card width is now fixed (it grew into whatever gap the
            // neighbours allowed). If the widest WHOLE word still doesn't fit
            // that width, shrink the font until it does, so the word stays
            // intact instead of breaking mid-glyph ("không" -> "kh"/"ồng",
            // "Tôi" -> "Tô"/"i"). Measured at the RENDERED size and against the
            // SAME inner width the card actually wraps at (below), so the
            // decision matches what paints. Skipped for space-less CJK.
            final mw = isTranslated ? FontWeight.w500 : FontWeight.normal;
            final hasLatinWords = RegExp(r'[A-Za-z]').hasMatch(displayText);
            final mangaInnerW = math.max(8.0, mangaAllowW - 10);
            // 1) Shrink the font so the widest WHOLE word fits the gap-limited
            //    width; floor low (a small intact word beats a split one).
            if (hasLatinWords) {
              var wsafety = 0;
              while (renderedManga > _kMangaWordFloor &&
                  _widestWordWidth(displayText, renderedManga, mw) >
                      mangaInnerW &&
                  wsafety < 80) {
                renderedManga =
                    math.max(_kMangaWordFloor, renderedManga - 0.5);
                wsafety++;
              }
              // _BlockCard renders at fontSize * fontScale, so carry the shrunk
              // size back out through the same scale to keep them in sync.
              if (widget.fontScale > 0) {
                mangaFont = renderedManga / widget.fontScale;
              }
            }
            // 2) If even at the font floor the widest word is STILL wider than
            //    the gap allowed (a thin vertical-JP bubble boxed in by
            //    neighbours), let the layout - and the card below - grow to the
            //    word so it NEVER breaks mid-glyph ("Cảm" -> "Cả"/"m"). The card
            //    is centred on the bubble, so the few extra px spill
            //    symmetrically and barely touch neighbours - far less jarring
            //    than a split word, and the font is already at its floor so the
            //    spill stays minimal.
            final mangaWordW = hasLatinWords
                ? _widestWordWidth(displayText, renderedManga, mw)
                : 0.0;
            // Lay out (and below, size the card) with the widest word PLUS slack
            // so the word never lands exactly on the wrap boundary, where a
            // sub-pixel render/measure gap drops its last glyph to a new line.
            final mangaLayoutW =
                math.max(mangaInnerW, mangaWordW + _kWordFitSlack);
            final tpManga = TextPainter(
              text: TextSpan(
                text: displayText,
                style: TextStyle(
                  fontSize: renderedManga,
                  fontWeight: mw,
                  height: 1.25,
                ),
              ),
              textDirection: TextDirection.ltr,
              textScaler: _overlayScaler,
            )..layout(maxWidth: mangaLayoutW);
            // 5px L + 5px R = 10 horizontal; 4px T + 4px B = 8 vertical.
            // Padding matches the Container padding inside the manga
            // card so glyphs sit clear of the pill border on every side.
            // Card hugs the rendered text. Not capped at mangaAllowW: when a
            // word forced mangaLayoutW past the gap (step 2 above), the card
            // must be allowed that width too, or the text would re-wrap and
            // break the very word we just kept whole.
            // Content width must clear the widest word + slack even if the
            // wrapped layout's longest line measured a hair narrower, so the
            // rendered Text always has room for the word in one piece.
            final mangaTightW =
                math.max(tpManga.size.width, mangaWordW + _kWordFitSlack) + 10;
            // Always size the card to the FULL measured (wrapped) text
            // height - never clamp to boxH. Clamping cut off wrapped lines on
            // small bubbles whose VI translation wraps to more lines than fit
            // in the tiny source box, so the user saw text "wrap then lose
            // characters". Growing past the bbox is fine: the card is centred
            // on the source text (mangaTop below), so it expands symmetrically
            // around the glyphs rather than clipping.
            final mangaTightH = tpManga.size.height + 8;
            // Anchor the card at the CENTER of the bbox in manga mode.
            // Manga bubbles are usually wider than the source text and
            // the text is centered inside the bubble - center anchoring
            // makes the card land near the actual source glyphs even
            // when the OCR/BubbleDetector bbox over-extends across the
            // panel (the case the bbox-area filter can't fully prevent
            // because a panel-spanning bbox can still be under the 10 %
            // page-area cap).
            final mangaLeft = (mangaCx - mangaTightW / 2)
                .clamp(4.0, math.max(4.0, viewSize.width - mangaTightW - 4))
                .toDouble();
            final mangaTop = top + (boxH - mangaTightH) / 2;

            cards.add(_CardLayout(
              index: i,
              left: mangaLeft,
              top: mangaTop,
              width: mangaTightW,
              height: mangaTightH,
              fontSize: mangaFont,
            ));
          } else {
            // Grow the card RIGHT into empty space so a longer translation
            // uses the room beside it instead of wrapping inside the narrow
            // source box. Stop a small gutter short of the nearest block on
            // the SAME row (vertical overlap) so the expansion never paints
            // over a neighbour (dish price, second column, next line).
            final rightEdge = left + boxW;
            final bottomEdge = top + boxH;
            var maxRight = viewSize.width - 4;
            for (var j = 0; j < viewRects.length; j++) {
              if (j == i) continue;
              final r = viewRects[j];
              // Only a SIGNIFICANT vertical overlap counts as the same row.
              // A box on the row above/below whose edge merely grazes this
              // one (common on dense menus like the Korean one) must NOT cap
              // the expansion, or the card never grows and the translation
              // keeps wrapping even though the space beside it is free.
              final overlap =
                  math.min(bottomEdge, r.bottom) - math.max(top, r.top);
              if (overlap < math.min(boxH, r.height) * 0.5) continue;
              if (r.left >= rightEdge && r.left < maxRight) {
                maxRight = r.left - 6;
              }
            }
            var layoutWidth = math.max(cardWidth, maxRight - left);

            // Narrow-source readability floor. A vertical sign strip or a thin
            // menu column has a tiny boxW, and when grow-right is capped by a
            // neighbour the horizontal Vietnamese wraps to 1-2 chars per line
            // (seen on Korean vertical signs: "Piano" -> a column of single
            // letters). If the chosen width can't even hold this card's longest
            // word, widen it to fit that word (capped at the viewport), even if
            // that means slightly overrunning a neighbour - an unreadable
            // 1-char column is worse than a small overlap, and cards are
            // draggable. Only kicks in for genuinely-too-narrow boxes.
            final renderFont = (isTranslated
                    ? math.max(_estimateSourceFont(boxH, 1), 13.0)
                    : _estimateSourceFont(boxH, _sourceLineCount(block.text))) *
                widget.fontScale;
            final neededWordW = _longestWordWidth(
                  displayText,
                  renderFont,
                  isTranslated ? FontWeight.w500 : FontWeight.normal,
                ) +
                _kCardHPad * 2;
            if (layoutWidth < neededWordW) {
              layoutWidth =
                  math.min(viewSize.width - left - 4, neededWordW);
            }

            // Cap DOWNWARD growth at the nearest block BELOW the card's
            // expanded span. The readable-floor font (below) grows the card
            // past a tiny source box, and without this cap the card paints
            // over the next dish row on dense menus - overlapping cards that
            // hide the row underneath. Width expansion stops at same-row
            // neighbours; this is the matching guard for the vertical axis.
            final spanRight = left + layoutWidth;
            var maxBottom = viewSize.height - 4;
            for (var j = 0; j < viewRects.length; j++) {
              if (j == i) continue;
              final r = viewRects[j];
              final hOverlap =
                  math.min(spanRight, r.right) - math.max(left, r.left);
              if (hOverlap <= 0) continue;
              // Only blocks whose top sits under this card's upper half count
              // as "below" - a same-row neighbour with a slightly offset box
              // must not cap the height to a sliver. Lowered 0.6 -> 0.5 so a
              // tightly-stacked next row (dense menus) is caught and caps the
              // card before it paints over that row.
              if (r.top >= top + boxH * 0.5 && r.top < maxBottom) {
                maxBottom = r.top - 3;
              }
            }
            // Cap the card to the real gap down to the next row so it can't
            // bleed over it. Floored at one readable line (so a card never
            // collapses to nothing) but NOT at the full source box: on dense
            // menus the source line boxes themselves nearly touch, and forcing
            // the old `max(boxH, …)` minimum made every card overrun its
            // neighbour by the card padding. The font refit + FittedBox below
            // shrink the text to whatever height this leaves.
            final availHeight = math.max(18.0, maxBottom - top);

            // Normal mode: auto-fit font to source box height.
            final lines = _sourceLineCount(block.text);
            final startFont = _estimateSourceFont(boxH, lines);

            final fit1 = _fitFont(
              text: displayText,
              maxWidth: layoutWidth,
              maxHeight: boxH,
              startFont: startFont,
              fontWeight:
                  isTranslated ? FontWeight.w500 : FontWeight.normal,
            );

            // Readable floor for TRANSLATIONS. This menu's source boxes are
            // only 8-21 px tall (small Japanese print), which otherwise
            // crushes the longer Vietnamese to the 9 px minimum. We give the
            // translation a readable size and let the card grow DOWN to fit
            // (tightH below is no longer hard-capped to the tiny source
            // height); the width already expanded into free space, so the
            // text stays on as few lines as the room allows.
            var fontSize = isTranslated
                ? math.max(fit1.fontSize, 13.0)
                : fit1.fontSize;
            // Keep whole words intact. The readable floor above AND the user's
            // font-scale slider can push a long word past the card width after
            // _fitFont's own guard already ran, which makes TextPainter break
            // it mid-glyph ("Được" -> "Đư" / "ợc", "translation" -> "transla"
            // / "tion"). Re-clamp here at the RENDERED size so the widest word
            // still fits - a smaller intact word reads far better than a split
            // one.
            fontSize = _clampFontToWordWidth(
              displayText,
              fontSize,
              layoutWidth - _kCardHPad * 2,
              isTranslated ? FontWeight.w500 : FontWeight.normal,
              widget.fontScale,
            );
            // Hard-lock the card to the source OCR box height. Earlier
            // versions let it grow when content exceeded the box, but
            // that caused cards to bleed into the row below on dense
            // menus and (when the user pushed the font-scale slider)
            // into the adjacent manga panel. FittedBox(scaleDown) below
            // is the safety net for the rare case where text doesn't
            // fit at the chosen floor - it shrinks visually rather than
            // the card growing into a neighbour. The slider therefore
            // only has visible effect on bubbles whose source box is
            // already roomy enough; tight bubbles stay at the
            // fit-to-box size, which is the right trade-off because the
            // alternative (covering adjacent art) is worse.
            var cardHeight = boxH;

            // "Show original always" rides under the translation - it needs
            // extra height regardless, so grow past the box in that mode.
            if (widget.showOriginalAlways && isTranslated) {
              const origFont = 10.0;
              final origMeasured = _measureText(
                block.text,
                cardWidth - _kCardHPad * 2,
                fontSize: origFont,
                maxLines: 2,
              );
              cardHeight = math.max(cardHeight, fit1.height) +
                  origMeasured +
                  6;
            }

            // TIGHT background: measure the actually-rendered text and
            // shrink the card to fit. Anchored at the bbox top-left so
            // the card sits exactly where the source text was. At
            // fontScale > 1.0 the card grows downward past the bbox so
            // the bigger text stays INSIDE the card (replaces the old
            // OverflowBox approach: text never paints outside the bg).
            // Falls back to full bbox in "show original" mode where the
            // source-text strip needs the full width.
            var tightW = layoutWidth;
            var tightH = cardHeight;
            if (!(widget.showOriginalAlways && isTranslated)) {
              TextPainter measure(double font) => TextPainter(
                    text: TextSpan(
                      text: displayText,
                      style: TextStyle(
                        fontSize: font,
                        fontWeight: isTranslated
                            ? FontWeight.w500
                            : FontWeight.normal,
                        height: 1.25,
                      ),
                    ),
                    textDirection: TextDirection.ltr,
                    textScaler: _overlayScaler,
                  )..layout(
                      maxWidth: math.max(20, layoutWidth - _kCardHPad * 2));

              var tp = measure(fontSize * widget.fontScale);
              // Grow DOWN to fit the rendered text. The readable-floor font
              // above can exceed the tiny source box, and clipping to boxH
              // would cut the translation off. The width already expanded, so
              // height growth stays minimal (mostly one readable line).
              tightH = tp.size.height + _kCardVPad * 2;
              // The readable floor can still overflow the gap to the row
              // below. Refit the font into the available height so the card
              // stops short of the next block instead of painting over it.
              // If even the minimum font can't fit (huge translation over a
              // hairline gap) we keep the overflow - never truncate text.
              // fontScale > 1.0 is the user explicitly asking for bigger
              // text at the cost of overlap, so the slider bypasses this.
              if (tightH > availHeight && widget.fontScale <= 1.0) {
                final fit2 = _fitFont(
                  text: displayText,
                  maxWidth: layoutWidth,
                  maxHeight: availHeight,
                  startFont: fontSize,
                  fontWeight:
                      isTranslated ? FontWeight.w500 : FontWeight.normal,
                );
                fontSize = fit2.fontSize;
                tp = measure(fontSize * widget.fontScale);
                tightH = tp.size.height + _kCardVPad * 2;
              }
              tightW = math.min(layoutWidth, tp.size.width + _kCardHPad * 2);
            }

            cards.add(_CardLayout(
              index: i,
              left: left,
              top: top,
              width: tightW,
              height: tightH,
              fontSize: fontSize,
            ));
          }
        }

        // Z-order: a TRANSLATED card must never be hidden under an
        // overlapping textless one (a not-yet-translated block, or an
        // empty-bubble-fill region that OCR'd a bare sound-effect). The
        // Stack draws later children on top, so sort untranslated cards
        // first (bottom) and translated last (top); ties keep page order.
        bool isTranslatedCard(int idx) {
          final t =
              idx < widget.translations.length ? widget.translations[idx] : '';
          return !widget.showOriginal &&
              t.isNotEmpty &&
              t != widget.blocks[idx].text;
        }

        cards.sort((a, b) {
          final at = isTranslatedCard(a.index) ? 1 : 0;
          final bt = isTranslatedCard(b.index) ? 1 : 0;
          if (at != bt) return at - bt; // untranslated first, translated on top
          // Within a group, draw LARGER cards first (bottom) so a tiny card
          // (e.g. a 2-char bubble like "おい") lands on TOP and isn't covered
          // by an overlapping larger neighbour clipping one of its glyphs.
          final aArea = a.width * a.height;
          final bArea = b.width * b.height;
          if (aArea != bArea) return bArea.compareTo(aArea);
          return a.index.compareTo(b.index); // stable tiebreak
        });

        // Manga "overlay double" suppression - the last line of defence for
        // "block chồng block". The OCR + vision-catch-up pipeline can emit two
        // boxes for ONE speech bubble (a clean partial read that translates,
        // plus the full garbled read that echoes raw source). Their SOURCE
        // boxes don't overlap enough for the upstream dedup, but the rendered
        // cards - each centred on the bubble and grown to fit its text - land
        // on top of each other, so the user sees two stacked cards. When two
        // rendered cards overlap by a MAJORITY of the smaller one, keep the
        // higher-value card (a translated card beats a raw-source one; between
        // equals the longer text wins) and drop the other. Verified on device
        // 2026-06-15: duplicate pairs overlap ~0.7 of the smaller card while
        // genuinely distinct neighbour bubbles overlap <0.15, so 0.5 separates
        // them cleanly. Scoped to manga mode - menu / normal cards have their
        // own grow-right / cap-bottom anti-overlap and must stay untouched.
        final suppressed = <int>{};
        if (widget.mangaMode && cards.length > 1) {
          String shownText(int idx) {
            final t = idx < widget.translations.length
                ? widget.translations[idx]
                : '';
            final translated = !widget.showOriginal &&
                t.isNotEmpty &&
                t != widget.blocks[idx].text;
            return widget.showOriginal
                ? widget.blocks[idx].text
                : (translated ? t : widget.blocks[idx].text);
          }

          double cardScore(_CardLayout c) =>
              (isTranslatedCard(c.index) ? 1e9 : 0.0) +
              _meaningfulChars(shownText(c.index));

          for (var a = 0; a < cards.length; a++) {
            if (suppressed.contains(cards[a].index)) continue;
            for (var b = a + 1; b < cards.length; b++) {
              if (suppressed.contains(cards[b].index)) continue;
              final ra = Rect.fromLTWH(
                  cards[a].left, cards[a].top, cards[a].width, cards[a].height);
              final rb = Rect.fromLTWH(
                  cards[b].left, cards[b].top, cards[b].width, cards[b].height);
              final ix = math.max(0.0,
                  math.min(ra.right, rb.right) - math.max(ra.left, rb.left));
              final iy = math.max(0.0,
                  math.min(ra.bottom, rb.bottom) - math.max(ra.top, rb.top));
              final inter = ix * iy;
              if (inter <= 0) continue;
              final smaller =
                  math.min(ra.width * ra.height, rb.width * rb.height);
              if (smaller <= 0 || inter / smaller <= 0.5) continue;
              final loser = cardScore(cards[a]) >= cardScore(cards[b])
                  ? cards[b]
                  : cards[a];
              suppressed.add(loser.index);
            }
          }
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (widget.mangaMode) {
                    widget.onBackgroundTap?.call();
                  } else {
                    setState(() => _overlayVisible = !_overlayVisible);
                    widget.controller?.syncVisible(_overlayVisible);
                  }
                },
              ),
            ),
            if (_overlayVisible)
              for (final card in cards)
                if (!suppressed.contains(card.index))
                  _BlockCard(
                  block: widget.blocks[card.index],
                  translation: card.index < widget.translations.length
                      ? widget.translations[card.index]
                      : '',
                  left: card.left + (_dragOffsets[card.index]?.dx ?? 0),
                  top: card.top + (_dragOffsets[card.index]?.dy ?? 0),
                  width: card.width,
                  height: card.height,
                  fontSize: card.fontSize,
                  fontScale: widget.fontScale,
                  textScaler: _overlayScaler,
                  showOriginal: widget.showOriginal,
                  showOriginalAlways: widget.showOriginalAlways,
                  overlayOpacity: widget.overlayOpacity,
                  bgColor: widget.usePrimaryColor
                      ? const Color(0xFF6C63FF)
                      : (_bgColors[card.index] ?? BgColorSampler.fallback),
                  isPending: widget.pendingIndices.contains(card.index),
                  dashAnim: _dashAnim,
                  mangaMode: widget.mangaMode,
                  fadedForDelete:
                      _draggingIndex == card.index && _overTrash,
                  onTap: () {
                    final handler = widget.onBlockTap;
                    if (handler == null) return;
                    final idx = card.index;
                    handler(
                      idx,
                      widget.blocks[idx],
                      idx < widget.translations.length
                          ? widget.translations[idx]
                          : '',
                    );
                  },
                  onDragStart: () =>
                      setState(() => _draggingIndex = card.index),
                  onDrag: (delta) {
                    setState(() {
                      final cur =
                          _dragOffsets[card.index] ?? Offset.zero;
                      _dragOffsets[card.index] = cur + delta;
                      final cardCenter = Offset(
                        card.left + (cur.dx + delta.dx) + card.width / 2,
                        card.top +
                            (cur.dy + delta.dy) +
                            card.height / 2,
                      );
                      _overTrash = _isOverTrash(cardCenter, viewSize);
                    });
                  },
                  onDragEnd: () {
                    if (_overTrash) {
                      setState(() {
                        _dismissed.add(card.index);
                        _dragOffsets.remove(card.index);
                        _draggingIndex = null;
                        _overTrash = false;
                      });
                    } else {
                      setState(() {
                        _draggingIndex = null;
                        _overTrash = false;
                      });
                    }
                    _publishEdits();
                  },
                  onExplain: widget.onExplain == null
                      ? null
                      : () => widget.onExplain!(widget.blocks[card.index]),
                ),
            // Debug overlay — raw OCR/Vision bbox outlined in bright red
            // ON TOP of the cards so it stays visible even when the card
            // background blends into a dark panel. Lets the user instantly
            // tell whether a "panel-covering" overlay is actually one
            // mega-bbox (upstream OCR merge / margin over-expansion) or
            // multiple legitimate small bboxes that just happen to sit on
            // a dark scene.
            if (_overlayVisible && _debugShowBoxes)
              for (var i = 0; i < widget.blocks.length; i++)
                if (!_dismissed.contains(i) &&
                    (!widget.hideLowConfidence ||
                        !widget.blocks[i].isLowConfidence))
                  Positioned(
                    left: widget.blocks[i].boundingBox.left * scaleX +
                        fit.offsetX,
                    top: widget.blocks[i].boundingBox.top * scaleY +
                        fit.offsetY,
                    width: widget.blocks[i].boundingBox.width * scaleX,
                    height: widget.blocks[i].boundingBox.height * scaleY,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFF1744),
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
            if (_overlayVisible && _draggingIndex != null)
              Positioned(
                left: viewSize.width / 2 - _kTrashRadius,
                bottom: _kTrashBottomGap,
                width: _kTrashRadius * 2,
                height: _kTrashRadius * 2,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _overTrash ? 84 : 64,
                      height: _overTrash ? 84 : 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _overTrash
                            ? Colors.redAccent.withValues(alpha: 0.85)
                            : Colors.black.withValues(alpha: 0.55),
                        border: Border.all(
                          color: _overTrash
                              ? Colors.redAccent
                              : Colors.white.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: _overTrash ? 36 : 28,
                      ),
                    ),
                  ),
                ),
              ),
            // In-overlay reset chip + eye button ONLY when no external
            // controller is wired (standalone / preview use). With a
            // controller the host renders these in its action bar.
            if (_selfManagedControls &&
                _overlayVisible &&
                (_dragOffsets.isNotEmpty || _dismissed.isNotEmpty))
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _resetEdits,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.restart_alt,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Reset',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
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
            if (_selfManagedControls)
              Positioned(
                bottom: 80,
                right: 12,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () =>
                        setState(() => _overlayVisible = !_overlayVisible),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        _overlayVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Width (px) of the single widest whitespace-delimited word in [text] at
  /// [fontSize]/[fontWeight]. Used to guarantee a card is at least wide enough
  /// to hold its longest word on one line, so a narrow source box (vertical
  /// sign strip, thin menu column) doesn't wrap the horizontal translation
  /// into an unreadable 1-2-char-per-line column.
  double _longestWordWidth(
    String text,
    double fontSize,
    FontWeight fontWeight,
  ) {
    var widest = 0.0;
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: word,
          style: TextStyle(fontSize: fontSize, fontWeight: fontWeight),
        ),
        textDirection: TextDirection.ltr,
        textScaler: _overlayScaler,
        maxLines: 1,
      )..layout();
      if (tp.size.width > widest) widest = tp.size.width;
    }
    return widest;
  }

  double _measureText(
    String text,
    double maxWidth, {
    required double fontSize,
    int? maxLines,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, height: 1.25),
      ),
      textDirection: TextDirection.ltr,
      textScaler: _overlayScaler,
      maxLines: maxLines,
    )..layout(maxWidth: math.max(20, maxWidth));
    return tp.size.height;
  }

  ({double fitW, double fitH, double offsetX, double offsetY}) _fitContain(
    ui.Size image,
    Size view,
  ) {
    final imageAspect = image.width / image.height;
    final viewAspect = view.width / view.height;
    double fitW, fitH, offsetX, offsetY;
    if (imageAspect > viewAspect) {
      fitW = view.width;
      fitH = view.width / imageAspect;
      offsetX = 0;
      offsetY = (view.height - fitH) / 2;
    } else {
      fitH = view.height;
      fitW = view.height * imageAspect;
      offsetX = (view.width - fitW) / 2;
      offsetY = 0;
    }
    return (fitW: fitW, fitH: fitH, offsetX: offsetX, offsetY: offsetY);
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.block,
    required this.translation,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.fontScale,
    required this.textScaler,
    required this.showOriginal,
    required this.showOriginalAlways,
    required this.overlayOpacity,
    required this.bgColor,
    required this.onTap,
    required this.onDrag,
    this.onDragStart,
    this.onDragEnd,
    this.fadedForDelete = false,
    this.isPending = false,
    this.dashAnim,
    this.mangaMode = false,
    this.onExplain,
  });

  final OcrBlock block;
  final String translation;
  final double left;
  final double top;
  final double width;
  final double height;
  final double fontSize;
  // User multiplier on rendered font. At 1.0 = current behavior
  // (FittedBox shrinks to fit bbox). Above 1.0 the renderer multiplies
  // the chosen fontSize by this, drops the FittedBox so the bigger text
  // isn't scaled back, and lets the overflow paint past the card
  // bounds (the card background stays anchored to the bbox so only
  // glyphs spill out). Width still wraps at the card width.
  final double fontScale;
  /// Capped system text-scale, identical to the one the parent used to size
  /// this card, so the rendered glyphs match the measured box (no word break).
  final TextScaler textScaler;
  final bool showOriginal;
  final bool showOriginalAlways;
  final double overlayOpacity;
  final Color bgColor;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final bool fadedForDelete;
  final bool isPending;
  final Animation<double>? dashAnim;
  final bool mangaMode;
  final VoidCallback? onExplain;

  /// Pick white or black for the card text based on the sampled
  /// background's perceived brightness (Rec. 709 luminance). Threshold
  /// 0.55 biases slightly toward white because cards over photos read
  /// better with high-contrast white text than dark text on a near-white
  /// surface (which loses contrast at the edge anti-aliasing).
  Color _textColorFor(Color bg) {
    final r = bg.r * 255.0;
    final g = bg.g * 255.0;
    final b = bg.b * 255.0;
    final luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
    return luminance > 0.55 ? Colors.black : Colors.white;
  }

  Widget _buildMangaCard(String displayText, bool isTranslated, bool low) {
    return Positioned(
      left: left,
      top: top,
      width: width,
      // No fixed height: let the card grow to fit its (wrapped) text. A
      // manually-computed height could be off by a rounding pixel - or, when
      // the rendered width ends up narrower than the width the height was
      // measured at, the text wraps to one more line - and the surplus line
      // gets clipped ("xuống hàng rồi mất chữ"). Constraining only the width
      // lets the column size itself, so nothing is ever cut.
      child: Opacity(
        opacity: fadedForDelete ? 0.5 : 1.0,
        child: Material(
          type: MaterialType.transparency,
          // Pan to drag. Tap (no movement) opens the action sheet via the
          // inner InkWell; long-press is reserved for the action menu
          // (explain / split). Pan needs a small initial slop to fire,
          // so a quick tap never gets misread as a drag.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Vertical-only drag so a HORIZONTAL swipe over a card is NOT
            // claimed here and bubbles up to the result's page-swipe handler.
            // Dense menus cover the whole image with cards; with onPan they ate
            // every swipe and batch paging never fired (manga only worked
            // because its bubbles are sparse). Card still drags DOWN to trash.
            onVerticalDragStart: (_) => onDragStart?.call(),
            onVerticalDragUpdate: (d) => onDrag(d.delta),
            onVerticalDragEnd: (_) => onDragEnd?.call(),
            onVerticalDragCancel: () => onDragEnd?.call(),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                decoration: BoxDecoration(
                  // Was a hardcoded 0.85 black. Now drives off the
                  // user's overlayOpacity slider so manga cards fade
                  // with the same slider that fades normal-mode cards;
                  // dragging the slider shows the original art through
                  // the bubble in real time.
                  color: Colors.black
                      .withValues(alpha: overlayOpacity.clamp(0.0, 1.0)),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                // Card width/height computed by parent to fit the
                // rendered text (fontSize * fontScale) + small padding,
                // so the text sits naturally inside without FittedBox
                // shrink or OverflowBox spill.
                child: Text(
                  displayText,
                  textAlign: TextAlign.center,
                  // Render at EXACTLY the font the parent measured/fitted.
                  // Use the SAME capped system text-scale the parent measured
                  // this card with. A plain Text would inherit the raw
                  // MediaQuery.textScaler (e.g. 1.3x "Larger Text"), rendering
                  // bigger than the box and breaking the widest word mid-glyph
                  // ("Chà" -> "Ch"/"à"). Feeding the capped scaler keeps the
                  // overlay honouring accessibility (up to _kMaxOverlayTextScale)
                  // while measure == render. The app's own slider stacks on top.
                  textScaler: textScaler,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize * fontScale,
                    fontWeight:
                        isTranslated ? FontWeight.w500 : FontWeight.normal,
                    height: 1.25,
                    // Kill any letterSpacing inherited from the ambient
                    // DefaultTextStyle (Material bodyMedium ships 0.25): the
                    // TextPainter that sized this card has none, so an inherited
                    // value renders the text wider than measured and breaks the
                    // widest word mid-glyph.
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayText = showOriginal ? block.text : translation;
    final isTranslated = !showOriginal &&
        translation.isNotEmpty &&
        translation != block.text;
    final low = block.isLowConfidence;

    if (mangaMode) return _buildMangaCard(displayText, isTranslated, low);

    final alpha = overlayOpacity.clamp(0.0, 1.0);
    final fillColor = bgColor.withValues(alpha: alpha);
    final textColor = _textColorFor(bgColor);

    // The parent layout sized this card to exactly fit the rendered
    // text + padding (via TextPainter measurement before adding to the
    // cards list), so the text fits inside the card naturally - no
    // FittedBox shrink, no OverflowBox spill. fontScale > 1.0 already
    // baked into the card width/height by the parent.
    final renderedFont = fontSize * fontScale;
    final innerW = width - _kCardHPad * 2;
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
          Text(
            displayText,
            // Same capped system text-scale the parent measured with (see manga
            // card note), so enlarged system text grows the card instead of
            // overflowing it and breaking a word mid-glyph.
            textScaler: textScaler,
            style: TextStyle(
              color: textColor,
              fontSize: renderedFont,
              fontWeight: isTranslated
                  ? FontWeight.w500
                  : FontWeight.normal,
              height: 1.25,
              // See manga card: ignore inherited letterSpacing so the render
              // matches the TextPainter measurement that sized the card.
              letterSpacing: 0,
            ),
          ),
          if (showOriginalAlways && isTranslated)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: textColor.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Text(
                  block.text,
                  textScaler: textScaler,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.75),
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
    );

    final cardBody = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: _kCardHPad, vertical: _kCardVPad),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: SizedBox(width: innerW, child: textColumn),
    );

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Opacity(
        opacity: fadedForDelete ? 0.5 : 1.0,
        child: Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Vertical-only (see the non-manga card above): horizontal swipes
            // stay free for batch paging; card still drags down to the trash.
            onVerticalDragStart: (_) => onDragStart?.call(),
            onVerticalDragUpdate: (details) => onDrag(details.delta),
            onVerticalDragEnd: (_) => onDragEnd?.call(),
            onVerticalDragCancel: () => onDragEnd?.call(),
            child: InkWell(
              onTap: onTap,
              onLongPress: onExplain,
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  cardBody,
                  // Marching-ants dashed border on cards still awaiting
                  // their translation from the server.
                  if (isPending && dashAnim != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: dashAnim!,
                          builder: (_, __) => CustomPaint(
                            painter: _MarchingAntsPainter(
                              progress: dashAnim!.value,
                              color: textColor.withValues(alpha: 0.6),
                              radius: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (low)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a marching-ants dashed rectangle. The [progress] value (0..1 from
/// a repeating AnimationController) shifts the dash pattern along the
/// perimeter to create the "marching" motion.
class _MarchingAntsPainter extends CustomPainter {
  _MarchingAntsPainter({
    required this.progress,
    required this.color,
    required this.radius,
  });

  final double progress;
  final Color color;
  final double radius;

  static const _strokeWidth = 1.5;
  static const _dashLen = 6.0;
  static const _gapLen = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    final perimeter = _rrectPerimeter(rrect);
    const step = _dashLen + _gapLen;
    final offset = (progress * step * 4) % step;

    var dist = -offset;
    while (dist < perimeter) {
      final start = dist.clamp(0.0, perimeter);
      final end = (dist + _dashLen).clamp(0.0, perimeter);
      if (start < end) {
        canvas.drawPath(
          _extractRRectPath(rrect, start, end, perimeter),
          paint,
        );
      }
      dist += step;
    }
  }

  double _rrectPerimeter(RRect r) {
    return 2 * (r.width - 2 * radius) +
        2 * (r.height - 2 * radius) +
        2 * math.pi * radius;
  }

  Path _extractRRectPath(RRect r, double startDist, double endDist, double total) {
    final pts = <Offset>[];
    final w = r.width;
    final h = r.height;
    final rad = radius;

    pts.add(Offset(rad, 0));
    pts.add(Offset(w - rad, 0));
    pts.add(Offset(w, rad));
    pts.add(Offset(w, h - rad));
    pts.add(Offset(w - rad, h));
    pts.add(Offset(rad, h));
    pts.add(Offset(0, h - rad));
    pts.add(Offset(0, rad));
    pts.add(Offset(rad, 0));

    // Calculate cumulative distances for each segment
    final segLens = <double>[];
    for (var i = 0; i < pts.length - 1; i++) {
      segLens.add((pts[i + 1] - pts[i]).distance);
    }

    final path = Path();
    var accum = 0.0;
    var started = false;
    for (var i = 0; i < segLens.length; i++) {
      final segEnd = accum + segLens[i];
      if (segEnd <= startDist || accum >= endDist) {
        accum = segEnd;
        continue;
      }
      final t0 = (startDist > accum) ? (startDist - accum) / segLens[i] : 0.0;
      final t1 = (endDist < segEnd) ? (endDist - accum) / segLens[i] : 1.0;
      final p0 = Offset.lerp(pts[i], pts[i + 1], t0)!;
      final p1 = Offset.lerp(pts[i], pts[i + 1], t1)!;
      if (!started) {
        path.moveTo(p0.dx, p0.dy);
        started = true;
      }
      path.lineTo(p1.dx, p1.dy);
      accum = segEnd;
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _MarchingAntsPainter old) =>
      progress != old.progress || color != old.color;
}
