import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/camera/camera_service.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Position of a single translation card in view-space, after the
/// anti-overlap pass has shifted it away from its raw OCR bounding box.
class _CardLayout {
  _CardLayout({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.origLeft,
    required this.origTop,
  });
  final int index;
  // Both axes mutable: anti-overlap can shift the card right/left first,
  // then fall back to down.
  double left;
  double top;
  final double width;
  final double height;
  final double origLeft;
  final double origTop;
}

const double _kCardHPad = 6.0;
const double _kCardVPad = 4.0;
const double _kTranslationFontSize = 13.0;
const double _kOriginalFontSize = 11.0;
const int _kCardMaxLines = 3;

/// Displays OCR text blocks positioned over the captured image.
///
/// Two passes:
///   1. Map each OCR box from image-space to view-space using BoxFit.contain,
///      then MEASURE the actual rendered card height with TextPainter
///      (the translation often wraps to 2-3x the height of the OCR box,
///      so using box.height directly produces overlap-prone layouts).
///   2. Anti-overlap pass: sort by top, push later cards down until they
///      clear every earlier card with horizontal+vertical overlap.
class CameraResultOverlay extends StatefulWidget {
  const CameraResultOverlay({
    super.key,
    required this.blocks,
    required this.translations,
    required this.imageSize,
    this.showOriginal = false,
    this.hideLowConfidence = false,
    this.showOriginalAlways = false,
    this.overlayOpacity = 0.80,
    this.onExplain,
    this.onBlockTap,
  });

  final List<OcrBlock> blocks;
  final List<String> translations;
  final ui.Size imageSize;
  /// Force the cards to render the source text instead of the translation
  /// (used by future "show source" toggle — not wired to UI yet).
  final bool showOriginal;
  /// When true, also drop blocks flagged [OcrBlock.isLowConfidence] —
  /// keeps only "good" quality.
  final bool hideLowConfidence;
  /// When true, render the source text under every translation card.
  final bool showOriginalAlways;
  /// Card background opacity (0.4–1.0).
  final double overlayOpacity;
  /// "What is this?" handler — fired by long-press on a card. Receives
  /// the OCR block (callers typically forward to WhatIsThisSheet.show
  /// with block.text). Still useful even though the action sheet from
  /// [onBlockTap] also offers Explain: long-press is a one-gesture
  /// shortcut for power users.
  final ValueChanged<OcrBlock>? onExplain;
  /// Per-block action handler — fired by a clean tap on a card. Receives
  /// the block index (into [blocks] / [translations]), the block itself,
  /// and the current translation string so the caller can open an
  /// action sheet without re-deriving them. Replaces the previous
  /// tap-to-expand behaviour: the sheet hosts everything the expand
  /// state used to (full original text, "What is this?" pill) plus the
  /// new Copy / Retry / Save actions.
  final void Function(int index, OcrBlock block, String translation)?
      onBlockTap;

  @override
  State<CameraResultOverlay> createState() => _CameraResultOverlayState();
}

class _CameraResultOverlayState extends State<CameraResultOverlay> {
  bool _overlayVisible = true;

  // User-applied drag deltas, keyed by block index. Persists for the
  // life of this overlay (i.e. until the user retakes or pops). The
  // top-right reset chip clears all deltas.
  final Map<int, Offset> _dragOffsets = <int, Offset>{};

  /// Blocks the user removed by dragging into the trash zone. Kept as
  /// indices into [widget.blocks]; rendering skips these. The reset chip
  /// clears the set so dismissals are recoverable in one tap.
  final Set<int> _dismissed = <int>{};

  /// Index of the card currently under the finger (null when no drag is
  /// active). Drives the trash zone's visibility — it only appears while a
  /// drag is in progress to keep the result screen visually clean otherwise.
  int? _draggingIndex;

  /// True when [_draggingIndex]'s card center is currently inside the trash
  /// zone. Toggles the trash icon to its "hovered" red-filled state and
  /// arms the dismiss on release.
  bool _overTrash = false;

  /// Trash zone radius (logical px) from its centre. Card center within
  /// this radius counts as "over". 80 is a comfortable thumb-target without
  /// crowding the photo.
  static const double _kTrashRadius = 80;

  /// Vertical offset from the bottom of the view where the trash zone
  /// renders. Keeps it clear of the system gesture inset and the bottom
  /// action chips.
  static const double _kTrashBottomGap = 80;

  /// Returns true when [point] (a card-center position in view-local coords)
  /// is within [_kTrashRadius] of the trash zone's centre. Same geometry the
  /// trash zone widget uses, so the visual snap matches the hit zone.
  bool _isOverTrash(Offset point, Size viewSize) {
    final trashCenter = Offset(
      viewSize.width / 2,
      viewSize.height - _kTrashBottomGap - _kTrashRadius,
    );
    return (point - trashCenter).distance <= _kTrashRadius;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final fit = _fitContain(widget.imageSize, viewSize);

        final scaleX = fit.fitW / widget.imageSize.width;
        final scaleY = fit.fitH / widget.imageSize.height;

        // Build initial layouts at the OCR-reported position, with
        // TextPainter-measured heights. Apply the user's hide-low filter
        // first so dropped blocks don't consume layout slots; also skip
        // blocks the user already dragged into the trash zone.
        final cards = <_CardLayout>[];
        for (var i = 0; i < widget.blocks.length; i++) {
          if (_dismissed.contains(i)) continue;
          final block = widget.blocks[i];
          if (widget.hideLowConfidence && block.isLowConfidence) continue;
          final box = block.boundingBox;

          final origLeft = box.left * scaleX + fit.offsetX;
          final origTop = box.top * scaleY + fit.offsetY;
          // Card width: at least the OCR box width, capped at 92% of the
          // viewport so translations don't wrap to 6+ lines (the earlier
          // 240 px hard cap was tuned for narrow phones and made cards
          // way too tall on modern 400+px screens — aggregate-scene cards
          // in particular pulled the result overlay below the bottom of
          // the screen). Right-edge clamp prevents overflow when the OCR
          // box is anchored near the right side.
          final boxWidth = math.max(40.0, box.width * scaleX);
          final maxCardWidth = viewSize.width * 0.92;
          final cardWidth = math.min(
            math.max(140.0, boxWidth),
            math.min(maxCardWidth, viewSize.width - origLeft - 8),
          );

          final translation = i < widget.translations.length
              ? widget.translations[i]
              : '';
          final displayText = widget.showOriginal ? block.text : translation;
          final isTranslated = !widget.showOriginal &&
              translation.isNotEmpty &&
              translation != block.text;

          final measuredHeight = _measureCardHeight(
            displayText,
            cardWidth,
            isTranslated: isTranslated,
            showOriginal: widget.showOriginal,
            withOriginalUnderneath:
                widget.showOriginalAlways && isTranslated,
            originalText: block.text,
            lowConfidence: block.isLowConfidence,
          );

          cards.add(_CardLayout(
            index: i,
            left: origLeft,
            top: origTop,
            width: cardWidth,
            height: measuredHeight,
            origLeft: origLeft,
            origTop: origTop,
          ));
        }

        _resolveOverlap(cards, viewSize);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () =>
                    setState(() => _overlayVisible = !_overlayVisible),
              ),
            ),
            if (_overlayVisible)
              for (final card in cards)
                _BlockCard(
                  block: widget.blocks[card.index],
                  translation: card.index < widget.translations.length
                      ? widget.translations[card.index]
                      : '',
                  // Auto-layout position + user's drag delta.
                  left: card.left +
                      (_dragOffsets[card.index]?.dx ?? 0),
                  top: card.top +
                      (_dragOffsets[card.index]?.dy ?? 0),
                  width: card.width,
                  showOriginal: widget.showOriginal,
                  showOriginalAlways: widget.showOriginalAlways,
                  overlayOpacity: widget.overlayOpacity,
                  // Half-fade the card center to signal "drop here = delete"
                  // when the trash zone is armed for this exact card.
                  fadedForDelete:
                      _draggingIndex == card.index && _overTrash,
                  // Clean tap → action sheet via parent. Fallback to
                  // a noop when no handler is wired so existing call
                  // sites (e.g. unit tests / preview widgets) don't
                  // require the new callback.
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
                      // Hover-test: is the card's CENTER inside the trash
                      // zone right now? Drives the zone's highlighted state
                      // + arms the dismiss-on-release.
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
                  },
                  onExplain: widget.onExplain == null
                      ? null
                      : () => widget.onExplain!(widget.blocks[card.index]),
                  wasShifted: (card.top - card.origTop).abs() > 4 ||
                      (card.left - card.origLeft).abs() > 4,
                ),
            // Trash zone — only rendered while a drag is in progress so the
            // result screen stays uncluttered otherwise. Centered along the
            // bottom edge above the existing action chips. Highlighted red
            // when the dragged card's center is inside its radius.
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
            // Reset chip — visible once the user has dragged or dismissed
            // anything. Tap snaps positions back AND restores dismissed
            // blocks (one-tap undo for accidental trash drops).
            if (_overlayVisible &&
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
                        onTap: () => setState(() {
                          _dragOffsets.clear();
                          _dismissed.clear();
                        }),
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
            if (!_overlayVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!
                              .cameraTapShowTranslations,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
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

  /// Measure the rendered card height for a given text + max-width.
  /// Must mirror the actual [_BlockCard] render path:
  ///   • horizontal padding 6+6
  ///   • vertical padding 4+4
  ///   • maxLines 3 (collapsed) → ellipsis after that
  ///   • font 13 for translation, 11 for original-only mode
  ///   • line-height 1.25
  /// When [withOriginalUnderneath] is true, also account for the source
  /// text rendered under the translation (4px gap + 4px padding + up to
  /// 2 italic lines at font 11).
  /// When [lowConfidence] is true, account for the "Low quality" badge
  /// row (~13 px).
  double _measureCardHeight(
    String text,
    double cardWidth, {
    required bool isTranslated,
    required bool showOriginal,
    bool withOriginalUnderneath = false,
    String originalText = '',
    bool lowConfidence = false,
  }) {
    final fontSize = showOriginal ? _kOriginalFontSize : _kTranslationFontSize;
    final style = TextStyle(
      fontSize: fontSize,
      height: 1.25,
      fontWeight: isTranslated ? FontWeight.w500 : FontWeight.normal,
    );
    final innerWidth = cardWidth - _kCardHPad * 2;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: _kCardMaxLines,
      ellipsis: '…',
    )..layout(maxWidth: innerWidth);
    var total = tp.size.height + _kCardVPad * 2 + 2;
    if (lowConfidence) total += 13;
    if (withOriginalUnderneath && originalText.isNotEmpty) {
      final ot = TextPainter(
        text: TextSpan(
          text: originalText,
          style: const TextStyle(
            fontSize: _kOriginalFontSize,
            height: 1.25,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: innerWidth);
      total += ot.size.height + 8; // gap + divider padding
    }
    return total;
  }

  /// Greedy top-to-bottom anti-overlap with HORIZONTAL-FIRST resolution.
  ///
  /// For each card, when it collides with a previously placed card we try
  /// the cheapest fix first:
  ///   1. Slide RIGHT of the collider (keeps Y, useful for 2-column
  ///      layouts where one card naturally belongs on the right side).
  ///   2. Slide LEFT of the collider (keeps Y, useful when right edge is
  ///      blocked).
  ///   3. Fallback: push DOWN below the collider (original behaviour).
  /// After any move we re-check against ALL placed cards — a horizontal
  /// slide could land on a different card.
  ///
  /// Clamped to viewSize.height - 60 / viewSize.width to stay visible.
  void _resolveOverlap(List<_CardLayout> cards, Size viewSize) {
    cards.sort((a, b) {
      final dy = a.top.compareTo(b.top);
      if (dy != 0) return dy;
      return a.left.compareTo(b.left);
    });
    const gap = 3.0;
    final maxBottom = viewSize.height - 60;
    final maxRight = viewSize.width;
    final placed = <_CardLayout>[];
    for (final card in cards) {
      var safety = 0;
      while (safety < 100) {
        safety++;
        final collider = _firstCollider(card, placed);
        if (collider == null) break;
        if (_tryShiftRight(card, collider, placed, maxRight, gap)) continue;
        if (_tryShiftLeft(card, collider, placed, gap)) continue;
        // No horizontal fit — push below.
        final newTop = collider.top + collider.height + gap;
        if (newTop <= card.top) {
          // The collider sits ABOVE us already but we still collide — bail.
          card.top += card.height;
        } else {
          card.top = newTop;
        }
      }
      if (card.top + card.height > maxBottom) {
        card.top = math.max(0, maxBottom - card.height);
      }
      placed.add(card);
    }
  }

  _CardLayout? _firstCollider(_CardLayout card, List<_CardLayout> placed) {
    for (final other in placed) {
      if (_horizontallyOverlaps(card, other) &&
          _verticallyOverlaps(card, other)) {
        return other;
      }
    }
    return null;
  }

  bool _tryShiftRight(
    _CardLayout card,
    _CardLayout collider,
    List<_CardLayout> placed,
    double maxRight,
    double gap,
  ) {
    final candidateLeft = collider.left + collider.width + gap;
    if (candidateLeft + card.width > maxRight) return false;
    final originalLeft = card.left;
    card.left = candidateLeft;
    if (_firstCollider(card, placed) != null) {
      card.left = originalLeft;
      return false;
    }
    return true;
  }

  bool _tryShiftLeft(
    _CardLayout card,
    _CardLayout collider,
    List<_CardLayout> placed,
    double gap,
  ) {
    final candidateLeft = collider.left - card.width - gap;
    if (candidateLeft < 0) return false;
    final originalLeft = card.left;
    card.left = candidateLeft;
    if (_firstCollider(card, placed) != null) {
      card.left = originalLeft;
      return false;
    }
    return true;
  }

  bool _horizontallyOverlaps(_CardLayout a, _CardLayout b) {
    final aRight = a.left + a.width;
    final bRight = b.left + b.width;
    return a.left < bRight && b.left < aRight;
  }

  bool _verticallyOverlaps(_CardLayout a, _CardLayout b) {
    final aBottom = a.top + a.height;
    final bBottom = b.top + b.height;
    return a.top < bBottom && b.top < aBottom;
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
    required this.showOriginal,
    required this.showOriginalAlways,
    required this.overlayOpacity,
    required this.onTap,
    required this.onDrag,
    required this.wasShifted,
    this.onDragStart,
    this.onDragEnd,
    this.fadedForDelete = false,
    this.onExplain,
  });

  final OcrBlock block;
  final String translation;
  final double left;
  final double top;
  final double width;
  final bool showOriginal;
  final bool showOriginalAlways;
  final double overlayOpacity;
  final VoidCallback onTap;
  /// Called with the per-frame drag delta while the user pans on the
  /// card. Parent state aggregates these into a per-block offset.
  final ValueChanged<Offset> onDrag;
  /// Fired once at the start of a pan so the overlay can mount its trash
  /// zone widget. Null = no drag-to-delete UX.
  final VoidCallback? onDragStart;
  /// Fired on pan end — the overlay decides whether to dismiss the block
  /// (if the card was released over the trash zone) or just keep its
  /// dragged position.
  final VoidCallback? onDragEnd;
  /// While true, the card renders semi-transparent to signal "drop here =
  /// delete". Driven by the parent's hover-test against the trash zone.
  final bool fadedForDelete;
  final bool wasShifted;
  /// "What is this?" handler. Long-press the card fires this directly;
  /// when null, no long-press shortcut and no explain button is rendered.
  final VoidCallback? onExplain;

  @override
  Widget build(BuildContext context) {
    final displayText = showOriginal ? block.text : translation;
    final isTranslated = !showOriginal &&
        translation.isNotEmpty &&
        translation != block.text;

    // Card tint:
    //  • translated → blue
    //  • untranslated / showing-original → black
    //  • low-confidence OCR → amber overlay so user mistrusts the text
    // Opacity comes from the user's settings (0.4–1.0); we apply it to
    // all three base colours so the user-controlled value is honoured.
    final low = block.isLowConfidence;
    final alpha = overlayOpacity.clamp(0.0, 1.0);
    final baseColor = low
        ? Color.fromRGBO(180, 83, 9, alpha)
        : isTranslated
            ? Color.fromRGBO(37, 99, 235, alpha)
            : Colors.black.withValues(alpha: alpha * 0.75);

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Opacity(
        // Half-fade while the trash zone is armed for THIS card so the user
        // gets a clear "release to delete" signal — the visual cue mirrors
        // how Android's floating bubble dims while over its trash zone.
        opacity: fadedForDelete ? 0.5 : 1.0,
        child: Material(
        type: MaterialType.transparency,
        // GestureDetector handles both tap (toggle expand) and pan (drag
        // to move). Flutter's gesture arena disambiguates: small movement
        // → tap; larger → pan. The Material/InkWell ripple under the
        // GestureDetector still fires on tap so users get tactile feedback.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => onDragStart?.call(),
          onPanUpdate: (details) => onDrag(details.delta),
          onPanEnd: (_) => onDragEnd?.call(),
          onPanCancel: () => onDragEnd?.call(),
          child: InkWell(
            onTap: onTap,
            // Long-press → quick "What is this?" without expanding the
            // card. Discoverable via the explicit button in expanded
            // state (below), but here for power users who don't want
            // the extra tap.
            onLongPress: onExplain,
            borderRadius: BorderRadius.circular(6),
            child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: _kCardHPad, vertical: _kCardVPad),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(6),
              border: wasShifted
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 0.5,
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (low)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 10, color: Colors.white),
                        const SizedBox(width: 3),
                        Text(
                          AppLocalizations.of(context)!.cameraLowQuality,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  displayText,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: showOriginal
                        ? _kOriginalFontSize
                        : _kTranslationFontSize,
                    fontWeight: isTranslated
                        ? FontWeight.w500
                        : FontWeight.normal,
                    height: 1.25,
                  ),
                  // Always truncated on the card. Full text lives in the
                  // action sheet that opens on tap.
                  maxLines: _kCardMaxLines,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showOriginalAlways && isTranslated)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Text(
                        block.text,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
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
        ),
      ),
      ),
    );
  }
}
