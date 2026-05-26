import 'dart:math' as math;
import 'dart:ui';

import 'camera_service.dart';

/// Online multi-text tracker for the live camera preview.
///
/// The raw OCR detector (ML Kit) re-runs the whole frame each cycle, so
/// the SAME physical line of text comes back with a slightly different
/// box every time — the on-screen rectangles jitter, flicker in/out on
/// missed frames, and have no notion of "this was the same line a moment
/// ago". A SORT-style tracker fixes that:
///
///   1. PREDICT — each existing track propagates its position forward
///      by Δt using a constant-velocity Kalman filter. The smoothed
///      box stays where the eye expects it even when the detector is
///      between cycles.
///   2. ASSIGN — greedy IoU matching pairs current detections to
///      predicted tracks (the highest-IoU pair wins first, then next,
///      etc.). Optimal-enough for the small N (~10-30) we ever see.
///   3. UPDATE — each matched track folds the new measurement into its
///      Kalman state. The filter naturally averages out detector noise
///      while still tracking real motion.
///   4. LIFECYCLE — unmatched detections start TENTATIVE tracks; they
///      promote to CONFIRMED after [confirmHits] hits (suppresses
///      one-frame spurious detections). Tracks that miss more than
///      [removeMisses] consecutive frames are dropped.
///
/// Output: smoothed [OcrBlock]s with stable identity. Same type as input
/// so the live overlay needs no changes.
class TextTracker {
  TextTracker({
    this.confirmHits = 1,
    this.removeMisses = 3,
    this.iouMatchThreshold = 0.3,
  });

  /// Show a track after this many consecutive detections. 1 = show on
  /// the FIRST detection — critical for perceived responsiveness: at the
  /// 1 Hz live cadence, requiring 2 hits added a full second before any
  /// box appeared and made the camera feel dead on open. The brief cost
  /// is that a one-frame spurious blob can flash for a cycle, but
  /// [removeMisses] clears it quickly and ML Kit rarely phantoms on a
  /// static scene.
  final int confirmHits;

  /// Drop a track after this many consecutive misses. 3 frames ≈ 3 s at
  /// 1 Hz — rides out brief occlusion / autofocus blur on real text,
  /// while clearing a spurious one-frame detection within a few cycles.
  final int removeMisses;

  /// Minimum IoU between a track's predicted box and a detection for
  /// them to be considered the SAME physical text. Below this they
  /// become a separate (new) track. 0.3 tolerates honest detector
  /// jitter without merging adjacent menu lines.
  final double iouMatchThreshold;

  final List<_Track> _tracks = [];
  int _nextId = 0;
  DateTime? _lastUpdate;

  /// Ingest a new detector frame and return the currently visible
  /// (confirmed, not lost) tracks as smoothed [OcrBlock]s. The overlay
  /// can render the result with no awareness it's been tracked.
  List<OcrBlock> update(List<OcrBlock> detections) {
    final now = DateTime.now();
    final dt = _lastUpdate == null
        ? 1.0
        : (now.difference(_lastUpdate!).inMilliseconds / 1000.0)
            .clamp(0.05, 2.5);
    _lastUpdate = now;

    // 1. Predict every track forward by Δt.
    for (final t in _tracks) {
      t.predict(dt);
    }

    // 2. Greedy IoU assignment. Build all (track, det, iou) triples
    //    above the threshold, sort by IoU desc, take in order while
    //    skipping already-assigned indices. Optimal-or-near for small N
    //    and a single O(N·M) pass — Hungarian would be one constant
    //    factor better but isn't worth the complexity here.
    final pairs = <_Pair>[];
    for (var i = 0; i < _tracks.length; i++) {
      for (var j = 0; j < detections.length; j++) {
        final iou = _iou(_tracks[i].box, detections[j].boundingBox);
        if (iou >= iouMatchThreshold) {
          pairs.add(_Pair(trackIdx: i, detIdx: j, iou: iou));
        }
      }
    }
    pairs.sort((a, b) => b.iou.compareTo(a.iou));

    final assignedTracks = <int>{};
    final assignedDets = <int>{};
    for (final p in pairs) {
      if (assignedTracks.contains(p.trackIdx)) continue;
      if (assignedDets.contains(p.detIdx)) continue;
      final track = _tracks[p.trackIdx];
      final det = detections[p.detIdx];
      track.update(det.boundingBox);
      // Refresh recognised text + confidence whenever the new read is at
      // least as long OR more confident — keeps the BEST observation
      // sticking instead of overwriting with a transient bad read.
      final newConf = det.confidence ?? 0;
      final oldConf = track.confidence ?? 0;
      if (det.text.length > track.text.length || newConf > oldConf) {
        track.text = det.text;
        track.confidence = det.confidence;
      }
      assignedTracks.add(p.trackIdx);
      assignedDets.add(p.detIdx);
    }

    // 3. Unmatched existing tracks → miss tick.
    for (var i = 0; i < _tracks.length; i++) {
      if (!assignedTracks.contains(i)) _tracks[i].misses++;
    }

    // 4. Unmatched detections → spawn tentative tracks.
    for (var j = 0; j < detections.length; j++) {
      if (assignedDets.contains(j)) continue;
      final d = detections[j];
      _tracks.add(_Track(
        id: _nextId++,
        initialBox: d.boundingBox,
        text: d.text,
        confidence: d.confidence,
      ));
    }

    // 5. Reap dead tracks.
    _tracks.removeWhere((t) => t.misses > removeMisses);

    // 6. Emit confirmed tracks as smoothed OcrBlocks.
    return _tracks
        .where((t) => t.hits >= confirmHits)
        .map((t) => OcrBlock(
              text: t.text,
              boundingBox: t.box,
              confidence: t.confidence,
            ))
        .toList(growable: false);
  }

  /// Wipe all tracks — call when the live stream stops or restarts so a
  /// new session doesn't inherit stale identities.
  void reset() {
    _tracks.clear();
    _lastUpdate = null;
  }

  static double _iou(Rect a, Rect b) {
    final inter = a.intersect(b);
    if (inter.isEmpty) return 0.0;
    final intArea = inter.width * inter.height;
    final union = a.width * a.height + b.width * b.height - intArea;
    if (union <= 0) return 0.0;
    return intArea / union;
  }
}

/// One tracked text region.
///
/// Decoupled Kalman per dimension (cx, cy, w, h) plus a constant-velocity
/// model on (cx, cy). The full 6×6 joint covariance would only matter if
/// width and height genuinely co-vary with position — they don't for
/// printed text, so a per-axis scalar Kalman is faster and just as
/// accurate. The math degrades to the textbook 1-D form:
///     K = P / (P + R)            innovation gain
///     state += K · (z − state)   correct toward measurement
///     P ← (1 − K) · P            shrink uncertainty
/// with covariance growing by [_Q] per second during predict.
class _Track {
  _Track({
    required this.id,
    required Rect initialBox,
    required this.text,
    this.confidence,
  })  : _cx = initialBox.center.dx,
        _cy = initialBox.center.dy,
        _w = initialBox.width,
        _h = initialBox.height,
        _vx = 0,
        _vy = 0;

  final int id;
  String text;
  double? confidence;

  // Kalman state (4 position dims + 2 velocity dims).
  double _cx, _cy, _w, _h, _vx, _vy;

  // Per-axis uncertainty. Identical initial variance for the 4 measured
  // dims; velocity starts loose so the first few updates dominate it.
  double _pcx = 10.0,
      _pcy = 10.0,
      _pw = 10.0,
      _ph = 10.0,
      _pvx = 100.0,
      _pvy = 100.0;

  int hits = 1;
  int misses = 0;

  /// Process noise σ² per second. Position drifts a little (camera +
  /// device shake), velocity drifts more (user can change pan speed).
  static const double _qPos = 4.0;
  static const double _qSize = 1.0;
  static const double _qVel = 25.0;

  /// Measurement noise σ² — the detector itself is jittery to ~2-4 px
  /// even on a static target. Smaller R makes the filter trust new
  /// measurements more (faster response, more jitter); larger R smooths
  /// harder but lags real motion. 4² = 16 is the empirical sweet spot.
  static const double _rNoise = 16.0;

  /// Current smoothed bounding box (uses the latest Kalman estimate).
  Rect get box => Rect.fromCenter(
        center: Offset(_cx, _cy),
        width: math.max(1, _w),
        height: math.max(1, _h),
      );

  /// Advance the filter by [dt] seconds with the constant-velocity model.
  void predict(double dt) {
    _cx += _vx * dt;
    _cy += _vy * dt;
    // Size assumed stable between frames.
    _pcx += _qPos * dt + _pvx * dt * dt;
    _pcy += _qPos * dt + _pvy * dt * dt;
    _pw += _qSize * dt;
    _ph += _qSize * dt;
    _pvx += _qVel * dt;
    _pvy += _qVel * dt;
  }

  /// Fold a new detection box into the state.
  void update(Rect measurement) {
    final mx = measurement.center.dx;
    final my = measurement.center.dy;
    final mw = measurement.width;
    final mh = measurement.height;

    // Position innovations.
    final innX = mx - _cx;
    final innY = my - _cy;

    // Position Kalman gains + corrections.
    final kx = _pcx / (_pcx + _rNoise);
    final ky = _pcy / (_pcy + _rNoise);
    _cx += kx * innX;
    _cy += ky * innY;
    _pcx *= 1 - kx;
    _pcy *= 1 - ky;

    // Update velocity from the position innovation. Slight damping (0.4)
    // because the innovation already includes detector noise; pushing
    // velocity 1:1 amplifies it.
    final kvx = _pvx / (_pvx + _rNoise * 4);
    final kvy = _pvy / (_pvy + _rNoise * 4);
    _vx += kvx * innX * 0.4;
    _vy += kvy * innY * 0.4;
    _pvx *= 1 - kvx;
    _pvy *= 1 - kvy;

    // Size dims — 1-D Kalman, no velocity term (printed text doesn't
    // breathe between frames).
    final kw = _pw / (_pw + _rNoise);
    final kh = _ph / (_ph + _rNoise);
    _w += kw * (mw - _w);
    _h += kh * (mh - _h);
    _pw *= 1 - kw;
    _ph *= 1 - kh;

    hits++;
    misses = 0;
  }
}

class _Pair {
  const _Pair({required this.trackIdx, required this.detIdx, required this.iou});
  final int trackIdx;
  final int detIdx;
  final double iou;
}
