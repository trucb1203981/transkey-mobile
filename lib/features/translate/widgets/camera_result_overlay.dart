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

const double _kCardHPad = 4.0;
const double _kCardVPad = 0.0;
const double _kMinFontSize = 7.0;
const double _kMaxFontSize = 28.0;

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

  static const double _kTrashRadius = 80;
  static const double _kTrashBottomGap = 80;

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
    final trashCenter = Offset(
      viewSize.width / 2,
      viewSize.height - _kTrashBottomGap - _kTrashRadius,
    );
    return (point - trashCenter).distance <= _kTrashRadius;
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
    return (lineH / 1.25).clamp(_kMinFontSize, _kMaxFontSize);
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
    font = (startFont * ratio).clamp(_kMinFontSize, startFont);
    h = measureAt(font);

    // Refine: wrap discretization can leave us still over by a line.
    // Step 1pt at a time until it fits or hits the floor. Safety cap is
    // wide enough to walk the full _kMaxFontSize -> _kMinFontSize range
    // (a low cap used to bail early, leaving an above-floor font whose
    // text still overflowed and produced the debug stripe).
    var safety = 0;
    while (h > innerH && font > _kMinFontSize && safety < 30) {
      font = math.max(_kMinFontSize, font - 1);
      h = measureAt(font);
      safety++;
    }

    // h at _kMinFontSize is what the card actually renders; caller
    // grows the box if it overflows.
    return (fontSize: font, height: h + _kCardVPad * 2);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final fit = _fitContain(widget.imageSize, viewSize);
        final scaleX = fit.fitW / widget.imageSize.width;
        final scaleY = fit.fitH / widget.imageSize.height;

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
          // Clamp the right edge so a card anchored near the screen
          // edge can't paint off-screen. Left/top stay untouched so the
          // position invariant holds.
          final cardWidth =
              math.min(boxW, math.max(40.0, viewSize.width - left - 4));

          final translation = i < widget.translations.length
              ? widget.translations[i]
              : '';
          final isTranslated = !widget.showOriginal &&
              translation.isNotEmpty &&
              translation != block.text;
          final displayText = widget.showOriginal
              ? block.text
              : (isTranslated ? translation : block.text);

          if (widget.mangaMode) {
            // Manga: card = bounding box dimensions, font 6sp.
            // Server handles overlap resolution + margin expansion.
            const mangaFont = 6.0;
            const expandH = 1.10;
            final expW = boxW * expandH;
            var expLeft = left + (boxW - expW) / 2;
            var expCardW =
                math.min(expW, math.max(40.0, viewSize.width - expLeft - 4));
            if (expCardW < expW) {
              expLeft += (expW - expCardW) / 2;
            }

            cards.add(_CardLayout(
              index: i,
              left: expLeft,
              top: top,
              width: expCardW,
              height: boxH,
              fontSize: mangaFont,
            ));
          } else {
            // Normal mode: auto-fit font to source box height.
            final lines = _sourceLineCount(block.text);
            final startFont = _estimateSourceFont(boxH, lines);

            final fit1 = _fitFont(
              text: displayText,
              maxWidth: cardWidth,
              maxHeight: boxH,
              startFont: startFont,
              fontWeight:
                  isTranslated ? FontWeight.w500 : FontWeight.normal,
            );

            final fontSize = fit1.fontSize;
            // Hard-lock the card to the source OCR box height. Earlier
            // versions let it grow when content exceeded the box, but that
            // caused cards to bleed into the row below on dense menus
            // (visible block-on-block overlap). FittedBox(scaleDown) below
            // is the safety net for the rare case where text doesn't fit
            // at _kMinFontSize - it shrinks visually rather than the card
            // growing into a neighbour.
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

            cards.add(_CardLayout(
              index: i,
              left: left,
              top: top,
              width: cardWidth,
              height: cardHeight,
              fontSize: fontSize,
            ));
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
            // Debug — draw the raw OCR bounding box (mapped to view coords)
            // as a thin red outline for every visible card. Lets the user
            // see at a glance whether the card SHOULD have landed exactly
            // there. Toggle with the chip in the top-right corner.
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
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
            if (_overlayVisible)
              for (final card in cards)
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
      height: height,
      child: Opacity(
        opacity: fadedForDelete ? 0.5 : 1.0,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(
                displayText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight:
                      isTranslated ? FontWeight.w500 : FontWeight.normal,
                  height: 1.25,
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

    // FittedBox(scaleDown) + SizedBox(width:innerW) is the safety net for
    // the residual measurement-vs-render gap _fitFont can't fully close
    // (strut metrics, leading distribution etc.). The fitter still picks
    // the primary font size; this wrapper only triggers when actual
    // rendered content slightly exceeds the box, scaling it down
    // uniformly so neighbouring cards never get overlapped.
    final cardBody = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: _kCardHPad, vertical: _kCardVPad),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width - _kCardHPad * 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
          Text(
            displayText,
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: isTranslated
                  ? FontWeight.w500
                  : FontWeight.normal,
              height: 1.25,
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
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.75),
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
        ),
      ),
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
            onPanStart: (_) => onDragStart?.call(),
            onPanUpdate: (details) => onDrag(details.delta),
            onPanEnd: (_) => onDragEnd?.call(),
            onPanCancel: () => onDragEnd?.call(),
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
    final step = _dashLen + _gapLen;
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
