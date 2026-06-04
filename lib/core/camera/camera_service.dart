import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation, MethodChannel;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:path_provider/path_provider.dart';

import 'bubble_detector.dart';
import 'dbnet_text_detector.dart';

/// Text quality based on OCR confidence.
enum TextQuality {
  good,  // confidence >= 0.7
  fair,  // 0.4 <= confidence < 0.7
  poor,  // confidence < 0.4
}

/// Confidence floor — blocks below this are pure noise (random pixels,
/// shadows, watermarks) and emitting them just wastes translator tokens
/// and clutters the overlay. iOS doesn't report confidence so this only
/// fires on Android, which is fine because iOS Vision's recall is already
/// stricter than ML Kit's.
const double kOcrConfidenceFloor = 0.30;

/// Below this, the block is rendered with a "low quality" badge so the
/// user knows the translation may be unreliable.
const double kOcrLowConfidenceBadge = 0.50;

/// One discrete sub-item carried inside a block — present when vision
/// OCR groups multiple distinct items (dish + price pairs on a single
/// menu row) under one bounding box. Lets the explain picker show
/// user-readable translation chips instead of forcing them to bôi đen
/// source-language text. Null on the parent block means "no sub-items;
/// treat the block as a single unit."
class OcrBlockItem {
  const OcrBlockItem({required this.original, required this.translation});
  final String original;
  final String translation;
}

/// Text block with bounding box and OCR confidence from ML Kit.
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.boundingBox,
    this.confidence,
    this.bgColor,
    this.items,
  });

  final String text;
  final Rect boundingBox;

  /// Average confidence across all lines (Android only, null on iOS).
  final double? confidence;

  /// Median background colour sampled in a thin strip just outside the
  /// bounding box. Null until [BgColorSampler] has filled it in (the
  /// camera flow attaches it post-OCR). The overlay paints this as the
  /// card's solid fill so the translation visually replaces the source
  /// text at the exact same position instead of being chip-stamped on
  /// top of it.
  final Color? bgColor;

  /// Discrete items grouped under this block. Set when vision OCR
  /// detects multiple sub-items on a single visual row (menu rows).
  /// Null when the block is a single unit.
  final List<OcrBlockItem>? items;

  /// Return a copy with [bgColor] swapped — keeps the field final so
  /// the rest of the pipeline still treats blocks as immutable.
  OcrBlock copyWith({Color? bgColor}) => OcrBlock(
        text: text,
        boundingBox: boundingBox,
        confidence: confidence,
        bgColor: bgColor ?? this.bgColor,
        items: items,
      );

  TextQuality get quality {
    if (confidence == null) return TextQuality.good;
    if (confidence! >= 0.7) return TextQuality.good;
    if (confidence! >= 0.4) return TextQuality.fair;
    return TextQuality.poor;
  }

  /// True when the block survived the confidence floor but is in the
  /// "fair" range — UI surfaces this so users can mistrust the translation
  /// if the underlying OCR was shaky.
  bool get isLowConfidence {
    final conf = confidence;
    if (conf == null) return false;
    return conf < kOcrLowConfidenceBadge;
  }
}

/// Manages camera initialisation, capture, streaming OCR, and ML Kit.
class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  /// Optional DBNet (PaddleOCR) detector used as a safety-net pass for
  /// regions the ML Kit 4-pass pipeline misses. No-op until the TFLite
  /// model asset is bundled (see docs/dbnet-conversion.md).
  final DbnetTextDetector _dbnet = DbnetTextDetector();

  bool _isInitialized = false;
  bool _isStreaming = false;
  bool _isProcessing = false;
  DateTime _lastOcrTime = DateTime.fromMillisecondsSinceEpoch(0);
  // Live-preview OCR runs slightly slower than before (1 s vs 800 ms) since
  // it now fans out to all script recognizers per frame; the extra 200 ms
  // keeps frames from piling up on mid-range devices.
  static const _ocrInterval = Duration(milliseconds: 1000);

  /// Persistent recognizers for the live stream — one per script (latin /
  /// chinese / japanese / korean / devanagari). Created once in
  /// [startTextStream], reused every frame (creating a recognizer per frame
  /// is expensive), closed in [stopTextStream]. Keyed by script so the
  /// stream can run JUST the recognizer matching the user's pinned source
  /// language (one ML Kit call ≈ 150 ms) instead of fanning out to all
  /// five (≈ 800-1500 ms) — a big cut to first-box latency when the
  /// source is known.
  final Map<TextRecognitionScript, TextRecognizer> _streamRecognizers = {};

  /// When false the live stream skips OCR entirely (still does blur /
  /// sharpness). The camera screen flips this so live text boxes only
  /// run for the `menu` / `sign` scenes — the modes where aiming at
  /// individual items matters. Other scenes (document / screenshot /
  /// auto) translate the whole capture, so per-line live boxes are noise
  /// and waste CPU + battery.
  bool liveDetectionEnabled = true;

  /// Pinned source language (ISO 639-1) for the live stream, or null for
  /// auto. When concrete + script-supported, the stream runs only that
  /// script's recognizer for lower latency.
  String? liveSourceHint;

  // ── Blur detection (live preview) ─────────────────────────────────
  //
  // Runs alongside OCR at a higher cadence (250 ms vs 1 s) so the
  // "Hold steady" overlay reacts within a couple of motion frames
  // instead of trailing a full OCR cycle behind. Computed on the Y
  // plane only (luma), downsampled, single-pass running variance —
  // sub-ms per frame even on mid-range devices.
  DateTime _lastBlurTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _blurInterval = Duration(milliseconds: 250);

  /// Laplacian-variance threshold below which the current preview
  /// frame is treated as blurry. Calibrated empirically against the
  /// downsampled (8×) Y-plane. Sharp natural scenes land at 300+,
  /// hand-held but in-focus typically 100-250, motion blur or
  /// out-of-focus 20-60. 80 is the rough boundary where ML Kit OCR
  /// recall starts degrading sharply.
  static const double _blurThreshold = 80.0;

  /// Laplacian variance treated as "fully sharp" (100%). Sharp natural
  /// scenes land at 300+, so 250 maps the realistic in-focus range to
  /// the top of the meter without needing a tripod-perfect shot to ever
  /// read 100%.
  static const double _sharpVariance = 250.0;

  /// Map a Laplacian variance to a 0-100 sharpness percentage for the
  /// live focus meter. Anchored so the OCR-usable [_blurThreshold] reads
  /// 60% (the "ready / green" line): below threshold scales 0→60% so a
  /// shaky frame visibly drops; above it scales 60→100% toward
  /// [_sharpVariance]. Both segments clamp.
  double _sharpnessPct(double variance) {
    if (variance <= 0) return 0;
    if (variance < _blurThreshold) {
      return (variance / _blurThreshold * 60).clamp(0, 60);
    }
    final extra = (variance - _blurThreshold) /
        (_sharpVariance - _blurThreshold) *
        40;
    return (60 + extra).clamp(60, 100);
  }

  /// Last reported blur state — so we only fire the callback on edge
  /// transitions, not every frame. Starts as `false` (assumed sharp)
  /// so the overlay doesn't flash on stream startup before we have
  /// any real frame data.
  bool _lastBlurState = false;

  // Zoom — populated during [init]. Pinch-to-zoom in the camera screen
  // clamps to [minZoom, maxZoom]; current value is tracked so we don't
  // call setZoomLevel for sub-pixel changes.
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;

  bool get isInitialized => _isInitialized;
  CameraController? get controller => _controller;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  double get currentZoom => _currentZoom;
  bool get supportsZoom => _maxZoom > _minZoom + 0.01;

  /// Discover cameras and initialise the back-facing one.
  Future<void> init() async {
    if (_isInitialized) return;
    _cameras = await availableCameras();
    debugPrint('[CameraSvc] availableCameras -> ${_cameras.length}');
    if (_cameras.isEmpty) {
      throw CameraException('no_cameras', 'availableCameras() returned empty');
    }
    final back = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    _controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
    );
    debugPrint('[CameraSvc] controller.initialize() ...');
    // Timeout so a stuck AVFoundation session surfaces an error instead of
    // an infinite loading spinner (the caller pops + logs on throw).
    await _controller!.initialize().timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw TimeoutException(
          'CameraController.initialize() timed out after 12s'),
    );
    debugPrint('[CameraSvc] initialized=${_controller!.value.isInitialized}');
    try {
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _currentZoom = _minZoom;
    } catch (_) {
      _minZoom = 1.0;
      _maxZoom = 1.0;
      _currentZoom = 1.0;
    }
    _isInitialized = true;
  }

  /// Clamp + apply zoom. Returns the actually-applied value (after
  /// clamping) so the caller can update its display indicator.
  Future<double> setZoom(double zoom) async {
    if (_controller == null) return _currentZoom;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    if ((clamped - _currentZoom).abs() < 0.01) return _currentZoom;
    try {
      await _controller!.setZoomLevel(clamped);
      _currentZoom = clamped;
    } catch (_) {/* fail silently — UI will just snap back */}
    return _currentZoom;
  }

  /// Capture a single frame and return the file path.
  ///
  /// CameraX on Android 0.11.x doesn't reliably bake an EXIF orientation
  /// tag into the JPEG when the device is held landscape with no
  /// orientation lock — the file is written portrait-dimensioned but
  /// contains landscape pixel content, leaving the sign sideways for
  /// every downstream consumer (Image.file display, ML Kit OCR, vision
  /// LLM). We compensate here so callers always see an upright JPEG:
  ///   1. Read [CameraValue.deviceOrientation] at capture time — the
  ///      plugin tracks this even when the activity doesn't recreate.
  ///   2. Rotate the saved JPEG to portrait-up if the device wasn't
  ///      already in portrait-up, writing the rotated bytes back over
  ///      the same path so downstream code stays oblivious.
  /// If the rotation step fails for any reason (decode error, disk
  /// write, isolate crash), we return the original path — wrong
  /// orientation is still better than a broken capture.
  Future<String> captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw StateError('Camera not initialised');
    }
    if (_isStreaming) await stopTextStream();
    final xFile = await _controller!.takePicture();

    // Plugin's own deviceOrientation reports portraitUp even when the
    // device is held landscape (verified on real devices when the
    // activity has configChanges="orientation"). Fall back to the
    // native sensor reading first; only use the plugin value if the
    // native call fails.
    DeviceOrientation orientation;
    try {
      final native = await NativeDeviceOrientationCommunicator()
          .orientation(useSensor: true);
      orientation = _mapNativeToFlutter(native) ??
          _controller!.value.deviceOrientation;
    } catch (_) {
      orientation = _controller!.value.deviceOrientation;
    }

    final degrees = _rotationDegreesForOrientation(orientation);
    if (degrees != 0) {
      try {
        await compute(
          _rotateJpegFileIsolate,
          _RotateJpegArgs(path: xFile.path, degrees: degrees),
        );
      } catch (e) {
        // Don't fail the capture — downstream still gets a JPEG, just
        // possibly sideways. Logged so we can see if this path matters
        // in field metrics.
        debugPrint('[CameraService] orientation normalize failed: $e');
      }
    }
    return xFile.path;
  }

  /// Maps the device orientation reported by the plugin to the angle
  /// needed to rotate the captured JPEG into upright portrait. The
  /// `image` package treats positive angles as clockwise, so the
  /// chosen signs follow that convention.
  ///
  /// Reasoning: when the activity has configChanges="orientation"
  /// (we do) the camera plugin keeps rotating sensor data INTO
  /// portrait dimensions even though the user is holding the phone
  /// landscape — the JPEG ends up portrait-dimensioned with the
  /// landscape scene rotated 90° sideways inside it. We undo that
  /// here by applying the OPPOSITE rotation to what the device was
  /// actually held at:
  ///   - portraitUp     → 0   (plugin's portrait label matches reality)
  ///   - portraitDown   → 180 (phone upside down — scene reads inverted)
  ///   - landscapeLeft  → -90 (home on LEFT, device rotated 90° CW
  ///                           from portrait → rotate scene 90° CCW
  ///                           to put it back upright)
  ///   - landscapeRight → 90  (home on RIGHT, device rotated 90° CCW
  ///                           → rotate scene 90° CW)
  int _rotationDegreesForOrientation(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.portraitDown:
        return 180;
      // Empirically verified on a real device: the plugin pre-rotates
      // sensor pixels assuming portraitUp, so when the device is
      // actually held landscape we have to UNDO that rotation — and
      // the undo direction is opposite of the device tilt. landscapeLeft
      // (device tilted CW from portrait) needs CCW undo; landscapeRight
      // (device tilted CCW) needs CW undo. With the older +90/-90
      // pairing the result still landed sideways (sky ended up on the
      // wrong edge), so we go with the flipped signs here.
      case DeviceOrientation.landscapeLeft:
        return -90;
      case DeviceOrientation.landscapeRight:
        return 90;
    }
  }

  /// Translate the native_device_orientation enum value to Flutter's
  /// own DeviceOrientation. Returns null on `unknown` so the caller
  /// can fall back to the plugin's (probably-wrong) value rather than
  /// silently picking portraitUp.
  DeviceOrientation? _mapNativeToFlutter(NativeDeviceOrientation n) {
    switch (n) {
      case NativeDeviceOrientation.portraitUp:
        return DeviceOrientation.portraitUp;
      case NativeDeviceOrientation.portraitDown:
        return DeviceOrientation.portraitDown;
      case NativeDeviceOrientation.landscapeLeft:
        return DeviceOrientation.landscapeLeft;
      case NativeDeviceOrientation.landscapeRight:
        return DeviceOrientation.landscapeRight;
      case NativeDeviceOrientation.unknown:
        return null;
    }
  }

  /// Downscale + re-encode a captured JPEG before it's base64'd and POSTed
  /// to the vision LLM. A full-res capture (several MB) costs more
  /// vision input tokens and uploads slower over mobile data without
  /// improving recognition past a point. The long-edge cap is now
  /// SCENE-AWARE because the tradeoff differs:
  ///   - document / menu: small body text + descriptions matter
  ///     (allergens, ingredients, footnotes) → bump to 2048 px so a
  ///     dense paragraph stays readable
  ///   - sign: text is huge by design (storefronts, road signs) →
  ///     1200 px is plenty and saves ~50% bandwidth + tokens
  ///   - screenshot / auto: balanced default at 1600 px
  /// Quality stays at 82 (≈ 250-650 KB depending on scene). Runs in an
  /// isolate (decode/resize is CPU-heavy). Returns the original bytes
  /// on any failure so capture never breaks because of compression.
  Future<Uint8List> compressForVision(
    Uint8List bytes, {
    String scene = 'auto',
  }) async {
    try {
      final out = await compute(
        _compressForVisionIsolate,
        _CompressArgs(bytes: bytes, maxEdge: _maxEdgeForScene(scene)),
      );
      return out ?? bytes;
    } catch (_) {
      return bytes;
    }
  }

  /// Long-edge cap (px) the vision compression isolate should target
  /// for a given scene. Exposed as a tiny pure function so tests can
  /// pin the values per scene without booting the isolate.
  static int _maxEdgeForScene(String scene) {
    switch (scene) {
      case 'document':
      case 'menu':
        return 2048;
      case 'sign':
        return 1200;
      case 'screenshot':
      case 'auto':
      default:
        return 1600;
    }
  }

  /// Toggle flash on/off.
  Future<void> setFlash(bool on) async {
    if (_controller == null) return;
    try {
      on
          ? await _controller!.setFlashMode(FlashMode.torch)
          : await _controller!.setFlashMode(FlashMode.off);
    } catch (_) {}
  }

  /// Tap-to-focus: drive autofocus + exposure metering to [point], a
  /// normalized preview coordinate (0..1, top-left origin). Lets the user
  /// tell the camera which text to focus on — the mode (scene) only affects
  /// post-capture processing, not optical focus, so this is the real lever
  /// for sharp captures. Swallows errors: not all devices support a focus
  /// point, and a failure here must never break the live preview.
  Future<void> focusOnPoint(Offset point) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setExposurePoint(point);
      await c.setFocusPoint(point);
    } catch (_) {}
  }

  /// Clear the tap-to-focus point and return to the default continuous
  /// autofocus / center-weighted metering. Called after the tap-to-focus
  /// ring times out so the camera doesn't stay locked on a stale region.
  Future<void> resumeAutoFocus() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setFocusPoint(null);
      await c.setExposurePoint(null);
    } catch (_) {}
  }

  // ── Streaming OCR ──────────────────────────────────────────────────

  /// Start live camera stream with periodic OCR.
  /// [onBlocks] is called with detected text blocks every ~800ms.
  ///
  /// Optional [onBlurChange] fires when the preview transitions between
  /// sharp and blurry (edge-triggered, not per-frame) so the camera
  /// screen can toggle a "Hold steady" overlay. Computed on luma at
  /// ~4 Hz independently of OCR — the user wants instant feedback when
  /// they steady the phone, not a 1 s lag.
  Future<void> startTextStream(
    void Function(List<OcrBlock> blocks) onBlocks, {
    void Function(bool isBlurry)? onBlurChange,
    void Function(double sharpnessPct)? onSharpness,
  }) async {
    if (_controller == null || _isStreaming) return;
    _isStreaming = true;
    _isProcessing = false;
    _lastBlurState = false;

    // Spin up one recognizer per script so the live preview detects CJK +
    // Latin (and Devanagari), not just Latin. Reused across frames.
    if (_streamRecognizers.isEmpty) {
      for (final s in TextRecognitionScript.values) {
        _streamRecognizers[s] = TextRecognizer(script: s);
      }
    }

    await _controller!.startImageStream((image) async {
      if (!_isStreaming) return;

      final now = DateTime.now();

      // Blur check runs faster than OCR and independent of the OCR
      // _isProcessing gate, so the overlay stays responsive even while
      // an OCR pass is in flight. Skipping when an earlier blur check
      // is itself in-flight would just drop frames here; the math is
      // cheap enough to run inline.
      if ((onBlurChange != null || onSharpness != null) &&
          now.difference(_lastBlurTime) >= _blurInterval) {
        _lastBlurTime = now;
        try {
          final variance = _computeBlurVariance(image);
          // Continuous sharpness % fires EVERY check (not edge-triggered)
          // so the live meter tracks smoothly while the user steadies the
          // phone or waits for autofocus.
          onSharpness?.call(_sharpnessPct(variance));
          final isBlurry = variance < _blurThreshold;
          if (onBlurChange != null && isBlurry != _lastBlurState) {
            _lastBlurState = isBlurry;
            onBlurChange(isBlurry);
          }
        } catch (_) {
          // Frame format edge cases (corrupt plane / stride mismatch)
          // shouldn't kill the stream.
        }
      }

      // Scene gate: live boxes only run for menu / sign. Other scenes
      // translate the whole capture, so per-line live boxes are noise.
      if (!liveDetectionEnabled) return;
      if (_isProcessing) return;
      if (now.difference(_lastOcrTime) < _ocrInterval) return;

      _isProcessing = true;
      _lastOcrTime = now;

      try {
        final inputImage = _cameraImageToInputImage(image);
        // Pick which recognizers to run. With a pinned source language we
        // run JUST that script's recognizer (one ML Kit call, low latency
        // to first box); on auto we still fan out to every script and
        // keep whichever read the most characters (surfaces CJK boxes).
        final recognizers = _liveRecognizersForHint(liveSourceHint);
        final results = await Future.wait(recognizers.map((recognizer) async {
          try {
            final result = await recognizer.processImage(inputImage);
            final blocks = _extractBlocks(result);
            final chars = blocks.fold<int>(
              0,
              (sum, block) =>
                  sum + block.text.replaceAll(RegExp(r'\s'), '').length,
            );
            return (blocks: blocks, chars: chars);
          } catch (_) {
            return (blocks: <OcrBlock>[], chars: 0);
          }
        }));
        if (!_isStreaming) return;
        final best = results.reduce(
          (current, next) => current.chars >= next.chars ? current : next,
        );
        onBlocks(_dedupeAndFilter(best.blocks));
      } catch (_) {
        // Silently skip failed frames.
      } finally {
        _isProcessing = false;
      }
    });
  }

  /// Recognizers to run for the live stream given a source-language hint.
  /// A concrete, ML-Kit-supported hint → just that one script's
  /// recognizer (≈150 ms — fast first box). Auto / unsupported script →
  /// all recognizers (the pick-best fan-out that surfaces CJK boxes).
  Iterable<TextRecognizer> _liveRecognizersForHint(String? hint) {
    final script = _scriptForLang(hint);
    if (script != null) {
      final r = _streamRecognizers[script];
      if (r != null) return [r];
    }
    return _streamRecognizers.values;
  }

  /// Map an ISO 639-1 language to its ML Kit script recognizer, or null
  /// when auto / a script ML Kit can't read (those route to the vision
  /// LLM anyway, so the live stream just fans out to all).
  TextRecognitionScript? _scriptForLang(String? lang) {
    if (lang == null) return null;
    final code = lang.toLowerCase().split(RegExp(r'[-_]')).first;
    switch (code) {
      case 'ja':
        return TextRecognitionScript.japanese;
      case 'ko':
        return TextRecognitionScript.korean;
      case 'zh':
        return TextRecognitionScript.chinese;
      case 'hi':
      case 'mr':
      case 'ne':
        return TextRecognitionScript.devanagiri;
      case 'en':
      case 'vi':
      case 'fr':
      case 'de':
      case 'es':
      case 'it':
      case 'pt':
      case 'id':
      case 'ms':
      case 'nl':
      case 'pl':
      case 'tr':
      case 'sv':
      case 'da':
      case 'no':
      case 'fi':
      case 'cs':
      case 'ro':
      case 'hu':
      case 'hr':
      case 'sk':
      case 'sl':
      case 'et':
      case 'lv':
      case 'lt':
      case 'tl':
      case 'sw':
      case 'af':
        return TextRecognitionScript.latin;
      default:
        return null; // auto / unsupported → run all
    }
  }

  /// Stop the live camera stream + release the per-script recognizers.
  Future<void> stopTextStream() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    for (final recognizer in _streamRecognizers.values) {
      try {
        recognizer.close();
      } catch (_) {}
    }
    _streamRecognizers.clear();
  }

  /// Variance of a Laplacian applied to the downsampled luma plane —
  /// the standard "is this image blurry?" metric. Higher = sharper.
  ///
  /// Design notes:
  ///   - **Y plane only.** Luma is where text edges live; chroma adds
  ///     noise without signal. Both iOS (BGRA) and Android (YUV) give
  ///     the Y plane in `image.planes[0]`.
  ///   - **8× downsample.** A 1280×720 frame would be 920k pixels; we
  ///     stride by 8 in each axis (≈14k samples). Sub-ms on mid-range
  ///     phones, no perceptible accuracy loss for the
  ///     sharp-vs-blurry question.
  ///   - **Single-pass variance** using sum and sum-of-squares. Avoids
  ///     allocating a list of laplacian values per frame.
  ///   - **iOS quirk.** On iOS the Y plane is actually the full BGRA
  ///     buffer, so we approximate luma by reading the green channel
  ///     (best single-channel proxy for luminance). On Android the
  ///     plane really is Y.
  double _computeBlurVariance(CameraImage image) {
    final plane = image.planes[0];
    final bytes = plane.bytes;
    final width = image.width;
    final height = image.height;
    final bytesPerRow = plane.bytesPerRow;

    // On iOS the single plane is BGRA8888 (4 bytes per pixel); read the
    // green channel as luma. On Android it's 1 byte per pixel luma.
    final pixelStride = Platform.isIOS ? 4 : 1;
    final pixelOffset = Platform.isIOS ? 1 : 0; // G in BGRA

    const stride = 8;
    if (width < stride * 3 || height < stride * 3) return 0;

    int sampleAt(int x, int y) =>
        bytes[y * bytesPerRow + x * pixelStride + pixelOffset];

    var sum = 0.0;
    var sumSq = 0.0;
    var count = 0;
    final maxX = width - stride;
    final maxY = height - stride;
    for (var y = stride; y < maxY; y += stride) {
      for (var x = stride; x < maxX; x += stride) {
        // 4-neighbour Laplacian kernel: ∇²f ≈ f(↑)+f(↓)+f(←)+f(→) − 4·f(·)
        // Range is [-1020, 1020] for 8-bit luma; fits in a Dart int.
        final l = sampleAt(x, y - stride) +
            sampleAt(x, y + stride) +
            sampleAt(x - stride, y) +
            sampleAt(x + stride, y) -
            4 * sampleAt(x, y);
        sum += l;
        sumSq += l * l;
        count++;
      }
    }
    if (count == 0) return 0;
    final mean = sum / count;
    return sumSq / count - mean * mean;
  }

  /// Convert [CameraImage] to [InputImage] for ML Kit.
  InputImage _cameraImageToInputImage(CameraImage image) {
    final rotation = InputImageRotationValue.fromRawValue(
      _controller?.description.sensorOrientation ?? 0,
    ) ?? InputImageRotation.rotation0deg;

    if (Platform.isIOS) {
      // iOS gives BGRA8888 — single plane, use directly.
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    // Android: convert YUV_420_888 → NV21 for ML Kit.
    final nv21 = _yuv420ToNv21(image);
    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
  }

  /// Convert YUV_420_888 (3 planes: Y, U, V) to NV21 (Y + interleaved VU).
  Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final nv21 = Uint8List(width * height * 3 ~/ 2);

    // Copy Y plane row by row (handle stride > width).
    var destIndex = 0;
    for (var row = 0; row < height; row++) {
      final srcOffset = row * yPlane.bytesPerRow;
      nv21.setRange(destIndex, destIndex + width, yPlane.bytes, srcOffset);
      destIndex += width;
    }

    // Interleave V and U planes (NV21 = VU ordering).
    final uvHeight = height ~/ 2;
    final uvWidth = width ~/ 2;
    for (var row = 0; row < uvHeight; row++) {
      final vOffset = row * vPlane.bytesPerRow;
      final uOffset = row * uPlane.bytesPerRow;
      for (var col = 0; col < uvWidth; col++) {
        nv21[destIndex++] = vPlane.bytes[vOffset + col];
        nv21[destIndex++] = uPlane.bytes[uOffset + col];
      }
    }

    return nv21;
  }

  // ── Static OCR (capture mode) ──────────────────────────────────────

  /// Run ML Kit text recognition on the image at [imagePath].
  ///
  /// Two-stage pipeline for capture mode:
  ///   1. OCR the original photo with the script auto-detector.
  ///   2. OCR a contrast-boosted variant (helps chalkboard / low-contrast
  ///      handwriting where ML Kit struggles on the raw frame).
  /// Take the union of both, dedupe by IoU, drop noise blocks, then
  /// apply SCENE-AWARE merge so each capture scene gets the granularity
  /// that matches what the user is actually looking at:
  ///   - document:   paragraph merge (one card per paragraph, multi-line)
  ///   - menu:       wide same-line merge (dish name + price on the row)
  ///   - sign:       aggregate merge (whole sign as one card)
  ///   - screenshot: paragraph merge (message / snippet as one block)
  ///   - auto:       conservative same-line only (safe default)
  Future<List<OcrBlock>> recognizeText(
    String imagePath, {
    bool autoDetect = true,
    String scene = 'auto',
    bool aggressivePasses = true,
    bool? perLineOverride,
  }) async {
    // Menu + screenshot expect ONE OcrBlock per LINE (one dish row, one
    // UI label / chat message), not per ML Kit "block" (which can bundle
    // adjacent rows into a single multi-line group). Aggregate scenes
    // (document / sign / auto) collapse everything later so block-level
    // is fine and slightly faster.
    //
    // [perLineOverride] forces per-line vs per-block irrespective of
    // scene — used by the manga OCR-hybrid path where we need many
    // small bboxes (matching the per-bubble layout vision returns)
    // even though the scene is "manga".
    final perLine =
        perLineOverride ?? (scene == 'menu' || scene == 'screenshot');

    // iOS: one Apple Vision pass replaces the ML Kit 4-pass + DBNet pipeline.
    // Vision reads stylized / low-contrast text natively on the Neural Engine,
    // so the preprocessing crutches below (which exist to compensate for ML
    // Kit) are unnecessary and just add latency.
    if (Platform.isIOS) {
      return _recognizeTextVision(imagePath, scene: scene);
    }
    // Up to three OCR passes run in parallel — union of all gives the best
    // recall for stylized / low-contrast signage and handwriting:
    //   1. ORIGINAL (auto-detect all scripts) — base quality, catches
    //      CJK that the latin-only preprocessed passes miss.
    //   2. CONTRAST variant (latin) — histogram-stretched + sharpened;
    //      recovers faded / low-contrast print.
    //   3. BINARIZE variant (latin) — Otsu-style threshold to pure
    //      black/white; recovers BOLD stylized display fonts (sign
    //      lettering, neon, 3D text) where colour gradients confuse OCR.
    // [aggressivePasses=false] skips 2+3 — useful for gallery picks where
    // the user already chose a clear photo and running 3-pass on a 1600px
    // image adds 4-6 s of latency for little quality gain. Live capture
    // keeps all three passes because camera frames are often noisy.
    // Downscale the capture before any OCR pass. Modern phone cameras produce
    // 4000x3000+ JPEGs that ML Kit processes slowly for marginal quality gain
    // vs a 1600px image. Reduces per-pass latency from ~12s to ~1-2s.
    final ocrReadyPath = await _writeDownscaled(imagePath, maxEdge: 1600);

    final originalFuture = autoDetect
        ? _recognizeAuto(ocrReadyPath, perLine: perLine)
        : _recognizeWithScript(ocrReadyPath, TextRecognitionScript.latin,
            perLine: perLine);
    if (!aggressivePasses) {
      final result = await originalFuture;
      final deduped = _dedupeAndFilter(result);
      return _mergeForScene(deduped, scene);
    }
    // 4-pass OCR (original + contrast + binarize + binarizeBright).
    // Upscale dropped: it recovered marginal extra text at 2x cost.
    // DBNet fill-in below covers the missed-region case cheaper.
    // Binarize (dark adaptive threshold) recovers bold stylized DARK fonts;
    // binarizeBright (the mirror, bright threshold) recovers WHITE / light
    // text on dark OR light backgrounds. It REPLACES the old fillOutline
    // pass (heavy blur + dilation, slower, niche outlined-text only) at the
    // same pass count and ~the same per-pass cost (one integral pass).
    // Preprocess passes run a SINGLE recognizer instead of the 5-way auto
    // fan-out. That fan-out (3 preprocess × 5 scripts = 15 ML Kit calls) was
    // the bulk of the ~12s OCR. Use the pinned source script when known,
    // else Latin (the common menu case). The ORIGINAL pass above stays
    // auto-detect, so a CJK capture on source=auto is still read; only the
    // preprocess recall for an UNPINNED CJK capture is traded away — for
    // roughly half the latency, which is the stated priority.
    final ppScript =
        _scriptForLang(liveSourceHint) ?? TextRecognitionScript.latin;
    final contrastFuture = _preprocessAndRecognize(
        ocrReadyPath, _PreprocessMode.contrast,
        perLine: perLine, script: ppScript);
    final binarizeFuture = _preprocessAndRecognize(
        ocrReadyPath, _PreprocessMode.binarize,
        perLine: perLine, script: ppScript);
    final binarizeBrightFuture = _preprocessAndRecognize(
        ocrReadyPath, _PreprocessMode.binarizeBright,
        perLine: perLine, script: ppScript);

    final sw = Stopwatch()..start();
    final results = await Future.wait(
        [originalFuture, contrastFuture, binarizeFuture, binarizeBrightFuture]);
    debugPrint('[OCR] 4-pass ML Kit: ${sw.elapsedMilliseconds}ms');
    final merged = <OcrBlock>[
      ...results[0],
      ...results[1],
      ...results[2],
      ...results[3],
    ];
    debugPrint('[OCR] merged ${merged.length} raw blocks');

    // OPTIONAL safety-net pass: DBNet (PaddleOCR) detector for regions
    // ML Kit missed. Only fires when the TFLite model is bundled; in
    // that case we ask DBNet for every text region in the capture, drop
    // any that already overlap an ML Kit block, and recognise just the
    // uncovered ones with ML Kit on a per-crop call. Vision LLM still
    // owns the truly-difficult fallback path — this tier catches
    // cheap-to-fix ML Kit misses without a network round-trip.
    sw.reset();
    final dbnetExtras = await _dbnetFillIn(imagePath, merged);
    debugPrint('[OCR] DBNet fill-in: ${sw.elapsedMilliseconds}ms (${dbnetExtras.length} extras)');
    merged.addAll(dbnetExtras);

    final deduped = _dedupeAndFilter(merged);
    return _mergeForScene(deduped, scene);
  }

  static const MethodChannel _visionChannel =
      MethodChannel('transkey/vision_ocr');

  /// iOS-only OCR via Apple Vision (single pass, Neural Engine). Mirrors the
  /// ML Kit path's output: [OcrBlock]s in downscaled-image pixel coords with
  /// Vision's top-candidate confidence (0..1), which the camera screen's
  /// weakness / short-text fallback heuristics consume the same as ML Kit's
  /// (so a clear short sign isn't needlessly escalated to the server, but an
  /// uncertain read still is). Returns an empty list on failure or for scripts
  /// Vision can't read (Arabic / Thai / Indic) — the camera screen's server
  /// vision-LLM fallback then takes over, same as a sparse ML Kit read.
  Future<List<OcrBlock>> _recognizeTextVision(
    String imagePath, {
    required String scene,
  }) async {
    final ocrReadyPath = await _writeDownscaled(imagePath, maxEdge: 1600);
    final langs = _visionLangsForHint(liveSourceHint);
    List<dynamic>? raw;
    try {
      final sw = Stopwatch()..start();
      raw = await _visionChannel.invokeMethod<List<dynamic>>('recognize', {
        'path': ocrReadyPath,
        'languages': langs,
        'level': 'accurate',
      });
      debugPrint('[OCR] Vision 1-pass: ${sw.elapsedMilliseconds}ms '
          '(${raw?.length ?? 0} lines)');
    } catch (e) {
      debugPrint('[OCR] Vision failed: $e');
      return const <OcrBlock>[];
    }
    if (raw == null || raw.isEmpty) return const <OcrBlock>[];

    // Vision returns NORMALIZED [0..1] boxes. Map them into the same space the
    // overlay uses: the EXIF-applied dimensions of the ORIGINAL capture (which
    // camera_screen computes via instantiateImageCodec for its `size`). Without
    // this, boxes stay in the downscaled OCR pixel space and shrink into the
    // top-left corner whenever the capture is larger than the 1600px OCR image.
    double imgW = 0, imgH = 0;
    try {
      final origBytes = await File(imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(origBytes);
      final frame = await codec.getNextFrame();
      imgW = frame.image.width.toDouble();
      imgH = frame.image.height.toDouble();
      frame.image.dispose();
      codec.dispose();
    } catch (e) {
      debugPrint('[OCR] Vision size decode failed: $e');
      return const <OcrBlock>[];
    }

    final blocks = <OcrBlock>[];
    for (final item in raw) {
      final m = (item as Map).cast<String, dynamic>();
      final text = (m['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      blocks.add(OcrBlock(
        text: text,
        boundingBox: Rect.fromLTWH(
          (m['left'] as num).toDouble() * imgW,
          (m['top'] as num).toDouble() * imgH,
          (m['width'] as num).toDouble() * imgW,
          (m['height'] as num).toDouble() * imgH,
        ),
        confidence: (m['confidence'] as num?)?.toDouble(),
      ));
    }
    final deduped = _dedupeAndFilter(blocks);
    // Vision returns per-LINE boxes; ML Kit returns per-block. The menu merge's
    // row clustering is tuned for ML Kit's coarser blocks and over-merges Vision's
    // lines across grid columns (17 dish lines collapsed to 3 wide bands). For the
    // menu scene, Vision's clean per-line boxes ARE the per-dish granularity we
    // want — just drop price / phone / hours noise so each dish keeps its own
    // positioned card. Aggregate scenes (document / sign / auto) still merge fine.
    if (scene == 'menu') {
      // Vision often grabs the row's list bullet / leading dash as part of the
      // line ("－焼き餃子", "ーソトックソトック"). Strip leading bullet chars so the
      // dish name is clean for display AND for the /explain + translate lookup.
      final bullet = RegExp(r'^[\s\-‐-―ー－・•·*]+');
      final items = deduped
          .where((b) =>
              b.text.trim().isNotEmpty &&
              !_isMenuNoise(b.text) &&
              !_isMenuMetadata(b.text))
          .map((b) {
            final cleaned = b.text.replaceFirst(bullet, '').trim();
            return cleaned == b.text
                ? b
                : OcrBlock(
                    text: cleaned,
                    boundingBox: b.boundingBox,
                    confidence: b.confidence,
                  );
          })
          .where((b) => b.text.isNotEmpty)
          .toList();
      debugPrint('[OCR] menu (vision per-line): ${deduped.length} -> ${items.length} items');
      return items;
    }
    return _mergeForScene(deduped, scene);
  }

  /// Map an app source-language hint to Vision recognition-language codes.
  /// Returns null when unknown so Vision auto-detects (iOS 16+). Listing the
  /// pinned language first improves accuracy for that script; the native side
  /// drops any code this OS version doesn't support.
  List<String>? _visionLangsForHint(String? hint) {
    switch (hint) {
      case 'zh':
        return const ['zh-Hans', 'zh-Hant', 'en-US'];
      case 'ja':
        return const ['ja-JP', 'en-US'];
      case 'ko':
        return const ['ko-KR', 'en-US'];
      case 'ru':
        return const ['ru-RU', 'en-US'];
      case 'uk':
        return const ['uk-UA', 'en-US'];
      case 'fr':
        return const ['fr-FR', 'en-US'];
      case 'de':
        return const ['de-DE', 'en-US'];
      case 'es':
        return const ['es-ES', 'en-US'];
      case 'it':
        return const ['it-IT', 'en-US'];
      case 'pt':
        return const ['pt-BR', 'en-US'];
      case 'en':
        return const ['en-US'];
      case 'vi':
        return const ['vi-VT', 'en-US'];
      default:
        // Auto / unknown source. Vision's automaticallyDetectsLanguage often
        // MISSES CJK (it biases to Latin), so pass an explicit broad set that
        // turns the CJK recognizers on. The native side drops any code this
        // OS version doesn't support, and CJK scripts are visually distinct so
        // mixing them with Latin doesn't hurt Latin recall. Order = priority.
        return const ['ja-JP', 'zh-Hans', 'zh-Hant', 'ko-KR', 'en-US'];
    }
  }

  /// Detect text regions via DBNet then ML-Kit-OCR each region
  /// individually. Returns per-region [OcrBlock]s with bbox + text +
  /// confidence. Used by the manga gallery hybrid path so each speech
  /// bubble is its own block (matching what the vision LLM returns)
  /// while the actual recognition stays on-device and free.
  ///
  /// Returns an empty list if DBNet is unavailable (model not bundled)
  /// or finds nothing — callers should fall back to plain ML Kit OCR.
  ///
  /// [scriptHint] selects which ML Kit recognizer to use for the
  /// per-region OCR. Pass the dominant script of the page (Japanese
  /// for manga, Chinese for manhua, Korean for manhwa). Latin falls
  /// back to the default Latin recognizer.
  /// Find image regions that carry text-like edge density but are NOT
  /// covered by any rect in [covered]. These are the catch-up targets
  /// for a vision-LLM pass: the on-device pipeline detected the
  /// PRESENCE of glyphs (dense local edges) but couldn't READ them
  /// (text too small / stylized for ML Kit, border too broken for
  /// flood-fill). Returns rects in ORIGINAL image coordinates, capped
  /// at [maxRegions] (largest-density first) to bound the number of
  /// downstream vision calls. Empty list when the page is fully
  /// covered or has no unread text-dense areas.
  Future<List<Rect>> findUncoveredTextRegions(
    String imagePath,
    List<Rect> covered, {
    int maxRegions = 3,
  }) async {
    try {
      return await compute(
        _uncoveredRegionsIsolate,
        _UncoveredArgs(
          imagePath: imagePath,
          covered: covered
              .map((r) => [r.left, r.top, r.right, r.bottom])
              .toList(),
          maxRegions: maxRegions,
        ),
      );
    } catch (e) {
      debugPrint('[CameraService] findUncoveredTextRegions failed: $e');
      return const [];
    }
  }

  /// Crop [rect] (original-image coords) out of the image at
  /// [imagePath] and return it as JPEG bytes. Used by the vision
  /// catch-up pass to send a focused crop (not the whole page) to
  /// the vision LLM. Returns null on decode failure or a degenerate
  /// rect.
  Future<Uint8List?> cropRegionJpeg(String imagePath, Rect rect) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final l = rect.left.clamp(0, decoded.width - 1).round();
      final t = rect.top.clamp(0, decoded.height - 1).round();
      final w = rect.width.clamp(1, decoded.width - l).round();
      final h = rect.height.clamp(1, decoded.height - t).round();
      if (w < 16 || h < 16) return null;
      final crop = img.copyCrop(decoded, x: l, y: t, width: w, height: h);
      return Uint8List.fromList(img.encodeJpg(crop, quality: 90));
    } catch (e) {
      debugPrint('[CameraService] cropRegionJpeg failed: $e');
      return null;
    }
  }

  Future<List<OcrBlock>> recognizePerRegion(
    String imagePath, {
    String? scriptHint,
  }) async {
    // Region candidates come from two detectors stacked: DBNet for
    // photographic / printed-text scenes, BubbleDetector for manga-style
    // line-art speech bubbles. DBNet has zero recall on manga (verified
    // empirically: 0 regions returned across 5 manga pages); the bubble
    // detector picks up the closed-contour bubbles classical CV finds
    // trivially without an ML model.
    await _dbnet.load();
    final dbnetBoxes = <Rect>[];
    if (_dbnet.isAvailable) {
      try {
        final regions = await _dbnet.detect(imagePath);
        debugPrint('[CameraService] recognizePerRegion: '
            'DBNet detected ${regions.length} regions in $imagePath');
        dbnetBoxes.addAll(regions.map((r) => r.box));
      } catch (e) {
        debugPrint('[CameraService] recognizePerRegion: DBNet error: $e');
      }
    } else {
      debugPrint('[CameraService] recognizePerRegion: DBNet model not loaded');
    }

    // Group DBNet per-line boxes into one region per speech bubble.
    // BubbleDetector returns accurate bubble SHAPES; we use those shapes
    // only to DECIDE which lines share a card, but each emitted region is
    // the TIGHT UNION of the DBNet text lines inside the bubble - NOT the
    // whole-bubble crop. Feeding whole-bubble crops to the per-region OCR
    // previously mis-placed vertical-JP cards (the tighten step collapsed
    // to the crop top-left) and tripped the 10%-area filter; the tight
    // DBNet text-union avoids both and IS the card position (no tighten on
    // this path). Lines outside every bubble fall back to area-capped
    // single-link clustering so a tall multi-panel page can't chain into
    // one giant box.
    var clusteredDbnet = dbnetBoxes;
    final bubbleShapes = <Rect>[];
    if (dbnetBoxes.isNotEmpty) {
      var maxR = 1.0, maxB = 1.0;
      for (final b in dbnetBoxes) {
        if (b.right > maxR) maxR = b.right;
        if (b.bottom > maxB) maxB = b.bottom;
      }
      // Two passes union (same dedup as the no-DBNet fallback below).
      final passResults = await Future.wait([
        BubbleDetector.detect(imagePath),
        BubbleDetector.detect(imagePath, whiteThreshold: 200),
      ]);
      final pass1 = passResults[0];
      final pass2 = passResults[1];
      bubbleShapes.addAll(pass1);
      for (final b2 in pass2) {
        if (pass1.any((b1) => _iouRect(b1, b2) > 0.5)) continue;
        if (pass1.where((b1) => _rectContains(b2, b1)).length >= 2) continue;
        bubbleShapes.add(b2);
      }
      clusteredDbnet = _groupDbnetByBubbles(
        dbnetBoxes,
        bubbleShapes,
        orphanThresh: math.min(maxR, maxB) * 0.03,
        pageArea: maxR * maxB,
        maxAreaRatio: 0.20,
      );
      debugPrint('[CameraService] recognizePerRegion: grouped '
          '${dbnetBoxes.length} DBNet lines via ${bubbleShapes.length} '
          'bubbles -> ${clusteredDbnet.length} regions');
    }
    final boxes = <Rect>[...clusteredDbnet];
    final bubbleBoxes = <Rect>[...bubbleShapes];
    if (boxes.isEmpty) {
      // Multi-pass union: pass 1 @220 catches solid-white-interior bubbles;
      // pass 2 @200 catches light-screentone flashback bubbles. Parallel
      // compute() isolates so cost is latency-overlapped.
      final passResults = await Future.wait([
        BubbleDetector.detect(imagePath),
        BubbleDetector.detect(imagePath, whiteThreshold: 200),
      ]);
      final pass1 = passResults[0];
      final pass2 = passResults[1];
      bubbleBoxes.addAll(pass1);
      for (final b2 in pass2) {
        if (pass1.any((b1) => _iouRect(b1, b2) > 0.5)) continue;
        if (pass1.where((b1) => _rectContains(b2, b1)).length >= 2) continue;
        bubbleBoxes.add(b2);
      }
      debugPrint('[CameraService] recognizePerRegion: '
          'BubbleDetector pass1=${pass1.length} pass2=${pass2.length} '
          'union=${bubbleBoxes.length} in $imagePath');
      boxes.addAll(bubbleBoxes);
    }

    // Text-Anchored Bubble Discovery (TABD). Bubbles satisfy two
    // complementary signals: SHAPE (closed contour, what flood-fill
    // catches) AND CONTENT (text inside, what ML Kit catches).
    // When SHAPE detection fails — border with a 2 px gap,
    // adjacent bubbles whose borders share a gradient and merge
    // into one giant component, screentone-filled flashback
    // bubbles whose interior isn't bright enough — the CONTENT
    // signal is still there. We run ML Kit auto-script on the
    // whole page, then add any text block that isn't already
    // covered by a shape detection. Pattern's "no per-line CJK
    // fallback" rule is honored by dropping any block whose area
    // exceeds 30% of the page (the giant-block symptom).
    try {
      final pageBytes = await File(imagePath).readAsBytes();
      final pageImg = img.decodeImage(pageBytes);
      // Skip TABD's 3 full-page ML Kit passes (~2 s) when DBNet already
      // produced regions — it covers the page (TABD adds ~0 orphans then).
      // TABD stays as the content-signal fallback only when shape
      // detection (DBNet/Bubble) came back empty.
      if (pageImg != null && dbnetBoxes.isEmpty) {
        final pageW = pageImg.width.toDouble();
        final pageH = pageImg.height.toDouble();
        final pageArea = pageW * pageH;
        // Three candidate streams in parallel:
        //   - perBlock auto (paragraph-grained, robust to all scripts)
        //   - perLine Latin (line-grained, catches small italic /
        //     handwritten English text the block grouping skips)
        //   - perLine Latin on BINARIZED image (Otsu-style B/W
        //     threshold). Recovers bold stylized display fonts
        //     (scream bubbles, shouting hearts) and boosts faint /
        //     low-contrast small text by flattening the histogram.
        //     This is what unlocked the page-5 flashback bubble
        //     cluster ("IT DID NOT OCCUR TO ME", "SHE WAS JUST A
        //     CHILD", "A LONG TIME AGO", "IT WAS IN A COUNTRY", etc.)
        //     that pure auto + perLine couldn't read.
        // Tried adding contrast + fillOutline preprocess streams to
        // catch the last 1-2 bubbles ("I'LL WAIT UNTIL DEATH" witch
        // whisper, "AAA QUEEN CANDELLE" decorative shouting). Neither
        // ML Kit pass surfaced them — those bubbles appear to sit
        // below ML Kit's intrinsic text detection threshold even
        // with the most aggressive preprocessing. Reverted to keep
        // batch latency reasonable.
        // Pattern bans perLine for CJK because the recognizer
        // collapses each page to one giant block, but Latin perLine
        // is the opposite — it OVER-segments, which the area / IoU
        // filters below thin back down.
        final tabdResults = await Future.wait([
          _recognizeAuto(imagePath, perLine: false),
          _recognizeWithScript(imagePath, TextRecognitionScript.latin,
              perLine: true),
          _preprocessAndRecognize(imagePath, _PreprocessMode.binarize,
              perLine: true, autoDetect: false),
        ]);
        final textBlocks = <OcrBlock>[
          ...tabdResults[0],
          ...tabdResults[1],
          ...tabdResults[2],
        ];
        // Filter each candidate against the existing SHAPE detections
        // first (faster path, skips obvious duplicates early).
        final filtered = <Rect>[];
        for (final b in textBlocks) {
          final bb = b.boundingBox;
          final area = bb.width * bb.height;
          // Noise floor 0.1 % of page area. Lowered from the original
          // 0.3 % (which dropped witch "I'LL WAIT" + decorative
          // shouting "QUEEN CAUDELLE"). Going to 0.05 % was tried and
          // REVERTED — it let through enough sub-glyph noise that
          // per-region OCR produced spurious overlays and corrupted
          // the other pages. 0.1 % is the empirical sweet spot.
          if (area < pageArea * 0.001) continue;     // noise
          if (area > pageArea * 0.30) continue;      // giant CJK block
          final containedByOrphan = boxes
              .where((existing) => _rectContains(bb, existing))
              .length;
          if (containedByOrphan >= 2) continue;       // multi-bubble merge
          final cx = (bb.left + bb.right) / 2;
          final cy = (bb.top + bb.bottom) / 2;
          final coveredByShape = boxes.any((existing) =>
              cx >= existing.left &&
              cx <= existing.right &&
              cy >= existing.top &&
              cy <= existing.bottom);
          if (coveredByShape) continue;
          filtered.add(bb);
        }
        // Greedy area-descending dedup: prefer the larger candidate
        // when two overlap, so a paragraph block trumps its constituent
        // lines and the per-region OCR only fires once per bubble.
        filtered.sort((a, b) =>
            (b.width * b.height).compareTo(a.width * a.height));
        final greedy = <Rect>[];
        for (final bb in filtered) {
          final dup = greedy.any((kept) =>
              _rectContains(kept, bb) ||
              _iouRect(kept, bb) > 0.3);
          if (dup) continue;
          greedy.add(bb);
        }
        // Single-link cluster the survivors by edge-to-edge distance.
        // Pure perLine catches that no paragraph block contains (when
        // the bubble's interior fragments at the auto-detector level)
        // would otherwise emit one orphan PER LINE — bad UX, the user
        // sees a stack of tiny cards. Threshold uses the SHORTER page
        // edge × 3 % (~24 px on a 800-wide image) so it merges intra-
        // bubble line spacing (~12-20 px) without crossing the inter-
        // bubble gutter (~40+ px). The earlier 4 % × longer-edge
        // formula clustered "YOU THINK I GOT ANY STRONGER?" with the
        // separate "JUST LIKE MAMA!!" bubble below it.
        final clusterThresh = math.min(pageW, pageH) * 0.03;
        final orphans = _clusterRectsSingleLink(greedy, clusterThresh);
        // Pad orphans outward by ~6 % of the box's longer side so
        // the per-region OCR pulls a slight margin around the
        // recognized text — captures glyph descenders / quote marks
        // the ML Kit "block" bbox typically clips. Clamp to image
        // bounds so the per-region crop doesn't fail.
        final padded = orphans.map((bb) {
          final pad = math.max(bb.width, bb.height) * 0.06;
          return Rect.fromLTRB(
            (bb.left - pad).clamp(0.0, pageW),
            (bb.top - pad).clamp(0.0, pageH),
            (bb.right + pad).clamp(0.0, pageW),
            (bb.bottom + pad).clamp(0.0, pageH),
          );
        }).toList();
        boxes.addAll(padded);
        bubbleBoxes.addAll(padded);
        debugPrint('[CameraService] recognizePerRegion: '
            'TABD textBlocks=${textBlocks.length} '
            'orphans=${orphans.length} in $imagePath');
      }
    } catch (e) {
      debugPrint('[CameraService] TABD failed: $e');
    }

    // Debug-only annotated dump so you can adb-pull the temp file
    // and see which detector contributed which box (DBNet blue,
    // Bubble red — TABD orphans render as red too since they go
    // into bubbleBoxes). Stripped in release builds via kDebugMode.
    if (kDebugMode) {
      unawaited(_dumpDetectionDebug(imagePath, dbnetBoxes, bubbleBoxes));
    }

    if (boxes.isEmpty) return const [];

    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return const [];

      // Reject panel-sized bboxes before per-region OCR. BubbleDetector
      // pass 2 (whiteThreshold 200) on a dark night panel can flood-fill
      // the entire panel as a single "bubble" and pass-1 dedup doesn't
      // catch the case when there are NO pass-1 boxes in the same area.
      // The per-region OCR then runs on the whole panel and ML Kit
      // returns a garbled mega-block whose card sits at the panel
      // TOP-LEFT instead of the actual bubble text inside. Anything
      // above 10 % of page area is empirically a mis-detection - the
      // largest legitimate manga speech bubble is well under that
      // (sound-effect bubbles are flagged by the TABD area cap earlier).
      // Only the BubbleDetector / TABD fallback (no DBNet) can emit a
      // panel-sized flood-fill box. DBNet-derived regions are tight text
      // unions already capped at 20 % in _groupDbnetByBubbles, so skip this
      // 10 % cull on that path - it was dropping legitimately large bubbles.
      final pageAreaPx = decoded.width.toDouble() * decoded.height.toDouble();
      if (dbnetBoxes.isEmpty) {
        const kMaxBoxAreaRatio = 0.10;
        boxes.removeWhere((b) {
          return pageAreaPx > 0 &&
              (b.width * b.height) / pageAreaPx > kMaxBoxAreaRatio;
        });
        if (boxes.isEmpty) return const [];
      }

      // Always run Latin recognizer; add scriptHint recognizer when
      // it's a different script (Japanese / Chinese / Korean). Manga
      // is mostly Japanese, but English / Spanish / French manga
      // exist and Japanese recognizer on Latin text returns garbage
      // (1-2 chars per bubble), which fails the >= 2 char floor and
      // surfaces as untranslated bubbles on the rendered page.
      final hintedScript = _scriptForLang(scriptHint);
      final recognizers = <TextRecognitionScript, TextRecognizer>{
        TextRecognitionScript.latin:
            TextRecognizer(script: TextRecognitionScript.latin),
      };
      if (hintedScript != null && hintedScript != TextRecognitionScript.latin) {
        recognizers[hintedScript] = TextRecognizer(script: hintedScript);
      }
      final tempDir = await getTemporaryDirectory();
      final logLines = <String>[];
      try {
        // Parallel per-region pipeline: write crop → OCR (one call
        // per script in parallel) → pick best by meaningful char
        // count → cleanup. ML Kit's processImage has an internal
        // queue per recognizer; running multiple recognizers in
        // parallel is fine and the per-crop file IO overlaps too.
        final futures = boxes.map<Future<OcrBlock?>>((box) async {
          final l = box.left.clamp(0, decoded.width - 1).round();
          final t = box.top.clamp(0, decoded.height - 1).round();
          final w = box.width.clamp(1, decoded.width - l).round();
          final h = box.height.clamp(1, decoded.height - t).round();
          // ML Kit's InputImage requires BOTH sides >= 32 px or
          // processImage throws "InputImage width and height should
          // be at least 32". A thrown exception here used to bubble up
          // through Future.wait and abort the WHOLE page's OCR, which
          // returned [] → the caller fell back to a full-page vision
          // call (27 blocks, gemini, ~$0.0065 cost spike). Skip the
          // sub-32 crop instead.
          if (w < 32 || h < 32) return null;
          final cropped =
              img.copyCrop(decoded, x: l, y: t, width: w, height: h);
          // Unique enough — microsecond + Object.identityHash collision
          // requires same μs AND same VM-allocated identity, vanishingly
          // unlikely. Avoids the duplicate filenames that microseconds
          // alone would produce when futures fire within the same μs.
          final cropPath =
              '${tempDir.path}/dbnet_region_${DateTime.now().microsecondsSinceEpoch}'
              '_${identityHashCode(box)}.jpg';
          try {
            await File(cropPath)
                .writeAsBytes(img.encodeJpg(cropped, quality: 90));
            final input = InputImage.fromFilePath(cropPath);
            final scriptList = recognizers.entries.toList();
            final ocrResults = await Future.wait(
                scriptList.map((e) => e.value.processImage(input)));
            // Pick best per "meaningful char count" — letters /
            // digits / CJK only. Punctuation and whitespace don't
            // count, so a 5-char garbage like "* * *" loses to a
            // 4-char real word.
            var bestText = '';
            var bestScore = 0;
            var bestScript = '';
            int bestIdx = -1;
            for (var i = 0; i < ocrResults.length; i++) {
              final name = scriptList[i].key.name;
              final isCjk = name == 'japanese' ||
                  name == 'chinese' ||
                  name == 'korean';
              // CJK: rebuild vertical reading order from line boxes; Latin
              // keeps ML Kit's order.
              final cand = (isCjk
                      ? _cjkVerticalReadingOrder(ocrResults[i])
                      : ocrResults[i].text)
                  .trim();
              final score = _meaningfulCharCount(cand);
              if (score > bestScore) {
                bestScore = score;
                bestText = cand;
                bestScript = name;
                bestIdx = i;
              }
            }
            if (kDebugMode) {
              logLines.add(
                  '[$bestScript] bbox=$l,$t+${w}x$h score=$bestScore '
                  'text="${bestText.replaceAll('\n', ' / ')}"');
            }
            if (bestText.isEmpty || bestScore < 2) return null;
            // Tighten the bbox to the UNION of the per-line glyph rects
            // ML Kit reports inside the crop, mapped back to source
            // image coords. Without this the OcrBlock carries the input
            // crop region as its bbox - which can be a panel-spanning
            // BubbleDetector match wrapping a single small bubble - and
            // the downstream overlay then renders the card at the top-
            // left of the panel rather than where the source text
            // actually sits. Line bboxes are in CROP-LOCAL coords so we
            // add the crop origin (l, t) to map back.
            // On the DBNet path the input box is ALREADY the tight text-line
            // union (the real ink position) - re-tightening to ML Kit's
            // in-crop line rects mis-places vertical-JP cards, so keep the
            // DBNet box as-is. Tighten only the BubbleDetector / TABD
            // fallback, where the box can be a whole-bubble crop.
            Rect tightBox = box;
            if (dbnetBoxes.isEmpty && bestIdx >= 0) {
              double? minX, minY, maxX, maxY;
              for (final blk in ocrResults[bestIdx].blocks) {
                for (final line in blk.lines) {
                  final lr = line.boundingBox;
                  final lx0 = lr.left.toDouble();
                  final ly0 = lr.top.toDouble();
                  final lx1 = lr.right.toDouble();
                  final ly1 = lr.bottom.toDouble();
                  minX = (minX == null) ? lx0 : math.min(minX, lx0);
                  minY = (minY == null) ? ly0 : math.min(minY, ly0);
                  maxX = (maxX == null) ? lx1 : math.max(maxX, lx1);
                  maxY = (maxY == null) ? ly1 : math.max(maxY, ly1);
                }
              }
              if (minX != null &&
                  minY != null &&
                  maxX != null &&
                  maxY != null &&
                  maxX > minX &&
                  maxY > minY) {
                // Pad by 4 % of the longer side so descender / ascender
                // pixels aren't clipped by the card border.
                final pad = math.max(maxX - minX, maxY - minY) * 0.04;
                tightBox = Rect.fromLTRB(
                  (l + minX - pad).clamp(0.0, decoded.width.toDouble()),
                  (t + minY - pad).clamp(0.0, decoded.height.toDouble()),
                  (l + maxX + pad).clamp(0.0, decoded.width.toDouble()),
                  (t + maxY + pad).clamp(0.0, decoded.height.toDouble()),
                );
              }
            }
            return OcrBlock(
              text: bestText,
              boundingBox: tightBox,
              confidence: null,
            );
          } catch (e) {
            // Defense in depth: a single bad crop (ML Kit throw, IO
            // error) must NOT abort the whole page's OCR. Skip just
            // this region — Future.wait then still resolves the rest.
            debugPrint('[CameraService] per-region OCR skipped: $e');
            return null;
          } finally {
            try {
              await File(cropPath).delete();
            } catch (_) {}
          }
        }).toList();
        final results = await Future.wait(futures);
        if (kDebugMode && logLines.isNotEmpty) {
          unawaited(_dumpOcrLog(imagePath, logLines));
        }
        // Post-OCR text+geometry dedup. Each bbox (SHAPE from
        // BubbleDetector + TABD orphans + DBNet text boxes) ran an
        // independent per-region OCR; when two bboxes covered the same
        // bubble the OCR text comes out near-identical on both, and the
        // upstream center-inside filter at the bbox-build stage can miss
        // pairs whose centers happen to land outside each other (tight
        // glyph bbox vs whole-bubble shape bbox is the common case).
        // The translation pipeline downstream sees these as two distinct
        // blocks: one usually translates cleanly while the other lands
        // on a structural-untranslatable / cache-miss path and renders
        // as RAW SOURCE TEXT next to the translated card - the user
        // perceives this as "overlay double".
        //
        // Dedup rule: pairs whose normalized text matches AND bboxes
        // overlap (or one contains the other) collapse to the larger
        // bbox - the larger one is empirically the bubble-shape match
        // and keeps the user's tap region intuitive.
        final ocrBlocks = results.whereType<OcrBlock>().toList();
        return _dedupSameTextOverlapping(ocrBlocks);
      } finally {
        for (final r in recognizers.values) {
          r.close();
        }
      }
    } catch (e) {
      debugPrint('[CameraService] recognizePerRegion failed: $e');
      return const [];
    }
  }

  /// Snap LLM-estimated vision boxes onto on-device BubbleDetector shapes.
  ///
  /// A vision model returns boxes in the image pixel space (verified: no
  /// coordinate bug), but the coordinates are an LLM GUESS - usually close,
  /// occasionally off, and small adjacent bubbles render as overlapping
  /// cards. BubbleDetector finds accurate bubble contours, so we replace
  /// each vision box with the best-matching bubble box: snap when the
  /// vision box overlaps a bubble (IoU) or its centre sits inside one. A
  /// grossly-misplaced box that overlaps NO bubble is left untouched (the
  /// LLM put it in the wrong place and there's nothing to snap to).
  ///
  /// [imageBytes] MUST be the SAME image sent to the vision endpoint (the
  /// compressed capture) so the bubble boxes land in the same coordinate
  /// space as [boxes]. Returns a list the same length/order as [boxes].
  Future<List<Rect>> snapVisionBoxesToBubbles(
    Uint8List imageBytes,
    List<Rect> boxes,
  ) async {
    if (boxes.isEmpty) return boxes;
    String? tmpPath;
    try {
      final dir = await getTemporaryDirectory();
      tmpPath = '${dir.path}/snap_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(tmpPath).writeAsBytes(imageBytes);
      // Two-pass union, same dedup as recognizePerRegion's bubble path.
      final passes = await Future.wait([
        BubbleDetector.detect(tmpPath),
        BubbleDetector.detect(tmpPath, whiteThreshold: 200),
      ]);
      final bubbles = <Rect>[...passes[0]];
      for (final b2 in passes[1]) {
        if (passes[0].any((b1) => _iouRect(b1, b2) > 0.5)) continue;
        bubbles.add(b2);
      }
      if (bubbles.isEmpty) return boxes;
      final out = <Rect>[];
      final used = <int>{};
      var snapped = 0;
      for (final v in boxes) {
        final cx = (v.left + v.right) / 2;
        final cy = (v.top + v.bottom) / 2;
        var best = -1;
        var bestScore = 0.0;
        for (var j = 0; j < bubbles.length; j++) {
          if (used.contains(j)) continue;
          final bb = bubbles[j];
          final inside =
              cx >= bb.left && cx <= bb.right && cy >= bb.top && cy <= bb.bottom;
          // Centre-inside is the strong signal (the LLM box sits within the
          // bubble); IoU handles partial overlap. Combine so a clean
          // centre-hit always wins over a marginal edge overlap.
          final score = _iouRect(v, bb) + (inside ? 0.5 : 0.0);
          if (score > bestScore) {
            bestScore = score;
            best = j;
          }
        }
        if (best >= 0 && bestScore >= 0.25) {
          out.add(bubbles[best]);
          used.add(best);
          snapped++;
        } else {
          out.add(v); // no bubble to snap to - keep the LLM box
        }
      }
      debugPrint('[CameraService] snapVisionBoxesToBubbles: boxes=${boxes.length} '
          'bubbles=${bubbles.length} snapped=$snapped');
      return out;
    } catch (e) {
      debugPrint('[CameraService] snapVisionBoxesToBubbles failed: $e');
      return boxes;
    } finally {
      if (tmpPath != null) {
        try {
          await File(tmpPath).delete();
        } catch (_) {}
      }
    }
  }

  /// Run DBNet on [imagePath] and return only the regions that don't
  /// overlap an existing [mlkitBlocks] block (IoU > 0.3 considered the
  /// same line). For each uncovered region, crop the capture and run an
  /// ML Kit Latin recognizer on the crop — Latin handles the Latin /
  /// price-tag content ML Kit's text detector often skips on dense menus
  /// (CJK menus already win recall via the multi-script preprocess
  /// passes above). Empty list when the model isn't bundled.
  Future<List<OcrBlock>> _dbnetFillIn(
    String imagePath,
    List<OcrBlock> mlkitBlocks,
  ) async {
    if (!_dbnet.isAvailable) return const [];
    try {
      final regions = await _dbnet.detect(imagePath);
      if (regions.isEmpty) return const [];
      // Filter out regions already covered by ML Kit's reads.
      final uncovered = regions.where((r) {
        for (final b in mlkitBlocks) {
          if (_iou(b.boundingBox, r.box) > 0.3) return false;
        }
        return true;
      }).toList();
      if (uncovered.isEmpty) return const [];

      // Read the capture once; crop + recognise from the in-memory copy
      // so we don't write 20 temp files for 20 regions.
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return const [];

      final tempDir = await getTemporaryDirectory();
      final extras = <OcrBlock>[];
      // Single Latin recognizer reused across crops — instantiating a
      // recognizer per crop loads the 3 MB model each time and dwarfs
      // the actual recognition cost.
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        for (final region in uncovered) {
          final box = region.box;
          final l = box.left.clamp(0, decoded.width - 1).round();
          final t = box.top.clamp(0, decoded.height - 1).round();
          final w =
              (box.width).clamp(1, decoded.width - l).round();
          final h =
              (box.height).clamp(1, decoded.height - t).round();
          if (w < 8 || h < 8) continue; // too small to OCR usefully
          final cropped = img.copyCrop(decoded, x: l, y: t, width: w, height: h);
          final cropPath =
              '${tempDir.path}/dbnet_crop_${DateTime.now().microsecondsSinceEpoch}.jpg';
          try {
            await File(cropPath).writeAsBytes(img.encodeJpg(cropped, quality: 90));
            final result =
                await recognizer.processImage(InputImage.fromFilePath(cropPath));
            final text = result.text.trim();
            if (text.isEmpty || text.length < 2) continue;
            extras.add(OcrBlock(
              text: text,
              boundingBox: box,
              confidence: region.score,
            ));
          } finally {
            try { await File(cropPath).delete(); } catch (_) {}
          }
        }
      } finally {
        recognizer.close();
      }
      if (extras.isNotEmpty) {
        debugPrint('[CameraService] DBNet filled in ${extras.length} '
            'region(s) ML Kit missed');
      }
      return extras;
    } catch (e) {
      debugPrint('[CameraService] DBNet fill-in failed: $e');
      return const [];
    }
  }

  /// Scene-aware merge dispatcher. Each scene defines an explicit
  /// clustering strategy so the translator sees the granularity that
  /// matches what the user actually wants per content type:
  ///
  ///   ┌─────────────┬───────────────────────────────────┬────────────────────┐
  ///   │ Scene       │ Strategy                          │ One block =        │
  ///   ├─────────────┼───────────────────────────────────┼────────────────────┤
  ///   │ document    │ paragraph merge → aggregate ALL   │ whole document     │
  ///   │ sign        │ dominant cluster → paragraph →    │ whole signage      │
  ///   │             │ aggregate ALL                     │ (background dropped)│
  ///   │ auto        │ paragraph merge → aggregate ALL   │ whole capture      │
  ///   │ menu        │ row-level + metadata filter       │ one dish row       │
  ///   │ screenshot  │ same-line + light vertical merge  │ UI element /       │
  ///   │             │                                   │ chat message       │
  ///   └─────────────┴───────────────────────────────────┴────────────────────┘
  ///
  /// Aggregate scenes (document / sign / auto): user reads the result
  /// as one continuous block — "translate this whole thing for me".
  /// Multi-card scenes (menu / screenshot): user matches each card
  /// against a corresponding region of the source — dish lines, UI
  /// labels — so they must stay separate.
  ///
  /// Per-scene parameters are tuned from real-world capture patterns —
  /// see each case's comment for the empirical reasoning. When adding
  /// a new scene, decide the "one block = ?" goal FIRST, then pick
  /// tolerances that achieve it.
  List<OcrBlock> _mergeForScene(List<OcrBlock> blocks, String scene) {
    switch (scene) {
      case 'document':
        // User-confirmed expectation: capturing a document = "translate
        // the WHOLE document as one continuous passage". Pipeline:
        //   1. Same-line + aggressive paragraph merge to consolidate
        //      lines into paragraph blocks (keeps reading order).
        //   2. Aggregate any remaining paragraphs into ONE block — the
        //      translator then sees the entire document text as a single
        //      prompt, produces coherent translation that respects the
        //      original structure via "\n" separators.
        //
        // Why aggregate (not just pairwise merge): a document with
        // distinct sections (heading + body + bullets + signature) has
        // multi-column-ish layout or large section breaks that pairwise
        // criteria can't bridge. Aggregation collapses all dominant
        // text into one prompt; the user gets one card with all
        // translated content in order.
        final sameLine = _mergeSameLine(blocks, hGapMultiplier: 1.2);
        final paragraphs = _mergeParagraph(
          sameLine,
          vGapMultiplier: 3.0,
          hOverlapRatio: 0.05,
          heightRatioMin: 0.25,
          heightRatioMax: 4.0,
        );
        if (paragraphs.length <= 1) return paragraphs;
        return [_aggregateBlocks(paragraphs)];

      case 'menu':
        // Each dish on its own row is what the user wants to see in
        // the overlay (so they can compare prices visually). NO
        // paragraph merge — adjacent dish rows must stay separate.
        //
        // Price stripping has TWO client-side passes so it works even
        // when the server prompt (which also strips inline prices) isn't
        // deployed yet:
        //   1. _filterMenuMetadata — drops STANDALONE price / phone /
        //      hours blocks ("65k", "Rp. 15,000", "0946 123 032").
        //   2. _stripTrailingPrice — removes a price that's MERGED into
        //      a dish row ("Phở bò 65k" → "Phở bò"), since the user
        //      already sees the price on the source photo.
        // Smart row pairing: cluster blocks into visual rows, then within
        // each row group every dish with the price (+ reading) that follow it
        // into ONE wide block (dish → price span). This is what the user
        // asked for - "1 món + 1 giá = 1 block" - and it FIXES the wrap: a
        // dish's box now spans the whole row width, so the (longer) Vietnamese
        // translation fits on one line instead of wrapping inside the narrow
        // dish column. Multi-column menus stay split because a dish that
        // follows a completed dish+price pair (or a column-gutter gap) starts
        // a new group. Replaces the old detect-columns + same-line approach,
        // which over-split the dish↔price gap into separate columns.
        final kept = blocks
            .where((b) => b.text.trim().isNotEmpty && !_isMenuNoise(b.text))
            .toList();
        final allRows = <OcrBlock>[];
        for (final row in _clusterByRow(kept)) {
          allRows.addAll(_pairRowSegments(row));
        }
        // Drop anything still pure metadata (a standalone phone / hours block
        // that shared a row with no dish).
        final cleaned = allRows
            .where((b) => !_isMenuMetadata(b.text) && !_isMenuNoise(b.text))
            .toList();
        // Reading order: top-to-bottom, left-to-right within a row.
        cleaned.sort((a, b) {
          final dy = a.boundingBox.top - b.boundingBox.top;
          if (dy.abs() > 12) return dy < 0 ? -1 : 1;
          return a.boundingBox.left.compareTo(b.boundingBox.left);
        });
        return cleaned;

      case 'sign':
        // A sign reads as ONE message. Same-line + paragraph merge,
        // then aggregate ALL remaining paragraphs into one block.
        // The translator sees the entire sign as one prompt regardless
        // of multi-column layout (logo-left, info-right, address-bottom).
        //
        // Background text bleed: tested adding a "dominant cluster"
        // filter that picks the densest text region by character area
        // / proximity — but real signs span far enough vertically
        // (logo top vs phone bottom = 300+px) that the filter often
        // split the sign itself into multiple clusters and kept only
        // one (address/phone alone). Empirically, the cleaner trade-off
        // is: aggregate everything in frame, ask the user to frame
        // tighter when background bleeds in.
        final sameLine = _mergeSameLine(blocks, hGapMultiplier: 2.0);
        final paragraphs = _mergeParagraph(
          sameLine,
          vGapMultiplier: 2.5,
          hOverlapRatio: 0.10,
          heightRatioMin: 0.3,
          heightRatioMax: 3.0,
        );
        if (paragraphs.length <= 1) return paragraphs;
        return [_aggregateBlocks(paragraphs)];

      case 'screenshot':
        // Chat messages, article snippets, notifications — multi-line
        // content within ONE UI element should merge; distinct UI
        // elements should stay separate. Tight parameters mid-way
        // between document and auto.
        //
        //   • vGap 0.9 — only tightly-grouped lines (same bubble)
        //   • hOverlap 0.4 — UI elements usually align well
        //   • heightRatio 0.8–1.3 — same UI element uses uniform font
        return _separateVertically(_mergeParagraph(
          _mergeSameLine(blocks, hGapMultiplier: 1.2),
          vGapMultiplier: 0.9,
          hOverlapRatio: 0.4,
          heightRatioMin: 0.8,
          heightRatioMax: 1.3,
        ));

      case 'auto':
      default:
        // Default expectation: "translate the whole capture as one
        // unit". Same pipeline as document/sign but with medium-strict
        // tolerances — slightly tighter so menus / multi-photo captures
        // hitting `auto` by mistake don't collapse unrelated content.
        // Still falls through to aggregate so the final card count is 1.
        final sameLine = _mergeSameLine(blocks, hGapMultiplier: 1.2);
        final paragraphs = _mergeParagraph(
          sameLine,
          vGapMultiplier: 1.8,
          hOverlapRatio: 0.20,
          heightRatioMin: 0.4,
          heightRatioMax: 2.5,
        );
        if (paragraphs.length <= 1) return paragraphs;
        return [_aggregateBlocks(paragraphs)];
    }
  }

  /// Preprocess the image with [mode], run latin OCR on the result.
  /// Returns empty on any failure (we still have the original pass).
  ///
  /// CRITICAL: the preprocess step resizes the image (down for huge
  /// captures, UP for the small-text pass). ML Kit reports bounding
  /// boxes in the PROCESSED image's pixel space, so we divide every box
  /// by the resize scale to map it back to the ORIGINAL capture's
  /// coordinate space - the only space the overlay knows how to render.
  /// Skipping this made preprocess-pass boxes land in the wrong place
  /// whenever they won dedup over the original pass.
  Future<List<OcrBlock>> _preprocessAndRecognize(
    String imagePath,
    _PreprocessMode mode, {
    bool perLine = false,
    bool autoDetect = false,
    TextRecognitionScript? script,
  }) async {
    try {
      final processed = await _writePreprocessedImage(imagePath, mode);
      if (processed == null) return const [];
      final (processedPath, scale) = processed;
      try {
        // Recognizer selection, in priority order:
        //   1. [script] given  → ONE recognizer (the latency win: the
        //      caller picks Latin / the pinned CJK script so a preprocess
        //      pass costs 1 ML Kit call, not the 5-way auto fan-out).
        //   2. [autoDetect]    → all 5 scripts (legacy callers that need
        //      CJK recall without knowing the script up front).
        //   3. otherwise       → Latin only.
        final blocks = script != null
            ? await _recognizeWithScript(processedPath, script,
                perLine: perLine)
            : autoDetect
                ? await _recognizeAuto(processedPath, perLine: perLine)
                : await _recognizeWithScript(
                    processedPath,
                    TextRecognitionScript.latin,
                    perLine: perLine,
                  );
        if (scale == 1.0) return blocks;
        final inv = 1.0 / scale;
        return blocks
            .map((b) => OcrBlock(
                  text: b.text,
                  confidence: b.confidence,
                  boundingBox: Rect.fromLTRB(
                    b.boundingBox.left * inv,
                    b.boundingBox.top * inv,
                    b.boundingBox.right * inv,
                    b.boundingBox.bottom * inv,
                  ),
                ))
            .toList();
      } finally {
        // Cleanup temp file — best-effort, ignore failure.
        try { await File(processedPath).delete(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('[CameraService] preprocess failed: $e');
      return const [];
    }
  }

  /// Downscales [imagePath] so its longest edge is at most [maxEdge] pixels,
  /// writes the result to a temp file, and returns that path. Uses area-
  /// averaging interpolation which preserves text sharpness better than
  /// bilinear. Returns the original [imagePath] unchanged if already small.
  Future<String> _writeDownscaled(String imagePath, {int maxEdge = 1600}) async {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return imagePath;
    final longest = math.max(decoded.width, decoded.height);
    if (longest <= maxEdge) return imagePath;
    final scale = maxEdge / longest;
    final resized = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
    final tmpDir = await Directory.systemTemp.createTemp('tk_ocr_');
    final outPath = '${tmpDir.path}/downscaled.jpg';
    await File(outPath).writeAsBytes(
      img.encodeJpg(resized, quality: 90),
    );
    return outPath;
  }

  /// longest side) so the caller can map ML Kit boxes back to original
  /// coordinates, or null on failure.
  Future<(String, double)?> _writePreprocessedImage(
    String imagePath,
    _PreprocessMode mode,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/ocr_${mode.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final scale = await compute(_runPreprocessIsolate, _PreprocessArgs(
      inputPath: imagePath,
      outputPath: outputPath,
      mode: mode,
    ));
    if (scale <= 0) return null;
    return (outputPath, scale);
  }

  Future<List<OcrBlock>> _recognizeWithScript(
    String imagePath,
    TextRecognitionScript script, {
    bool perLine = false,
  }) async {
    final recognizer = TextRecognizer(script: script);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(inputImage);
      return _extractBlocks(result, perLine: perLine);
    } finally {
      recognizer.close();
    }
  }

  /// Run all recognizers in parallel, pick the one with the most text.
  Future<List<OcrBlock>> _recognizeAuto(String imagePath,
      {bool perLine = false}) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    const scripts = TextRecognitionScript.values;
    final futures = scripts.map((script) async {
      final recognizer = TextRecognizer(script: script);
      try {
        final result = await recognizer.processImage(inputImage);
        final blocks = _extractBlocks(result, perLine: perLine);
        final chars = blocks.fold<int>(
          0,
          (sum, block) => sum + block.text.replaceAll(RegExp(r'\s'), '').length,
        );
        return (blocks: blocks, chars: chars);
      } catch (_) {
        return (blocks: <OcrBlock>[], chars: 0);
      } finally {
        recognizer.close();
      }
    });
    final results = await Future.wait(futures);
    final best = results.reduce(
      (current, next) => current.chars >= next.chars ? current : next,
    );
    return best.blocks;
  }

  /// Convert ML Kit's recognised text into our [OcrBlock] list. By default
  /// one OcrBlock = one ML Kit "block" (paragraph-shaped grouping). With
  /// [perLine] = true we descend to ML Kit's line level and emit one
  /// OcrBlock per LINE — used for menu / screenshot scenes where the user
  /// expects each dish row / chat bubble as its own translation card.
  List<OcrBlock> _extractBlocks(
    RecognizedText result, {
    bool perLine = false,
  }) {
    final blocks = <OcrBlock>[];
    for (final block in result.blocks) {
      if (perLine) {
        for (final line in block.lines) {
          final lineText = line.text.trim();
          if (lineText.isEmpty) continue;
          blocks.add(OcrBlock(
            text: lineText,
            boundingBox: line.boundingBox,
            confidence: line.confidence,
          ));
        }
        continue;
      }
      final text = block.text.trim();
      if (text.isEmpty) continue;

      // Compute average confidence from lines.
      double? avgConfidence;
      final lineConfidences = block.lines
          .map((line) => line.confidence)
          .whereType<double>()
          .toList();
      if (lineConfidences.isNotEmpty) {
        avgConfidence = lineConfidences.reduce((a, b) => a + b) /
            lineConfidences.length;
      }

      blocks.add(OcrBlock(
        text: text,
        boundingBox: block.boundingBox,
        confidence: avgConfidence,
      ));
    }
    return blocks;
  }

  /// Remove duplicate / noise blocks. Two reasons we get duplicates:
  ///   1. The preprocessed pass picks up the same text as the original pass.
  ///   2. ML Kit occasionally emits overlapping blocks for the same line.
  /// Two blocks are considered duplicates when their boxes overlap by
  /// IoU > 0.5 AND their normalised text matches. Among duplicates we keep
  /// the one with higher confidence (falls back to longer text).
  List<OcrBlock> _dedupeAndFilter(List<OcrBlock> blocks) {
    // Drop pure-noise blocks: empty / single-character / only punctuation.
    // Also drop low-confidence blocks whose bbox is tiny (< 16 px tall):
    // ML Kit's geometric accuracy degrades sharply on text that small,
    // so the resulting card lands metres away from the actual glyphs.
    // Captured menus put the address / phone / opening-hours at that
    // size; the user prefers nothing over "Low quality" cards at the
    // wrong position. 16 px is calibrated for 1080p+ captures - real
    // body copy on those is 30+ px tall.
    final filtered = blocks.where((b) {
      if (!_isMeaningful(b)) return false;
      final tooSmall = b.boundingBox.height < 16;
      final lowConf = (b.confidence ?? 1.0) < 0.5;
      if (tooSmall && lowConf) return false;
      return true;
    }).toList();

    // Sort by descending confidence then descending length — first match
    // wins during dedupe, so the highest-quality version of a duplicate
    // group survives.
    filtered.sort((a, b) {
      final ca = a.confidence ?? 0.0;
      final cb = b.confidence ?? 0.0;
      final byConf = cb.compareTo(ca);
      if (byConf != 0) return byConf;
      return b.text.length.compareTo(a.text.length);
    });

    final kept = <OcrBlock>[];
    for (final block in filtered) {
      final normalized = _normalizeForDedupe(block.text);
      // Aggressive cull for low-confidence detections: a block with
      // confidence < 0.5 that overlaps ANY kept block by IoU > 0.2 is
      // treated as a duplicate, regardless of text. ML Kit's 3-pass
      // pipeline (original / contrast / binarize) routinely emits 3-4
      // near-identical bboxes around small text (menu address, phone
      // number) - each with slightly different coords and minor text
      // variations (a stray comma, a kana ↔ kanji confusion). The
      // standard IoU > 0.5 rule misses these because the bboxes are
      // small enough that a 5 px shift drops IoU below 0.5. The visual
      // result was a stack of 3-4 "Low quality" cards at the bottom,
      // each with a bg colour mis-sampled because neighbours filled
      // every strip the sampler tried.
      final lowConfBlock = (block.confidence ?? 1.0) < 0.5;
      final isDup = kept.any((other) {
        final iou = _iou(block.boundingBox, other.boundingBox);
        final otherNorm = _normalizeForDedupe(other.text);
        if (lowConfBlock && iou > 0.2) return true;
        // SAME normalised text + ANY box overlap → duplicate. IoU alone
        // misses the case the user hit: the 3 OCR passes grouped the
        // same physical text differently (one pass = the whole
        // paragraph box, another = a single tight line box). Their IoU
        // can fall below 0.3 even though they describe identical text,
        // so both survived and the SAME translation rendered twice in
        // two stacked cards. Gating on identical text keeps genuinely
        // repeated labels (three "¥500" tags on different dish rows)
        // separate - those don't overlap at all (intersect == empty).
        if (otherNorm == normalized && iou > 0.0) return true;
        // Containment: a tight line box sitting INSIDE a paragraph box
        // covers little of the union (low IoU) but is ~fully enclosed.
        // Catch it via overlap-vs-smaller-area instead of IoU.
        if (_containment(block.boundingBox, other.boundingBox) > 0.6 &&
            (otherNorm == normalized ||
                otherNorm.contains(normalized) ||
                normalized.contains(otherNorm))) {
          return true;
        }
        // NEAR-duplicate text: two OCR passes read the same physical
        // text slightly differently ("...của nhà hàng chúng tôi..." vs
        // "...của chúng tôi...") so neither contains the other and the
        // exact-match rules miss them. When the boxes overlap AND the
        // character content is ≥80 % shared, treat as a duplicate and
        // keep the higher-confidence / longer one (we iterate in that
        // order). Genuinely different adjacent dishes share far fewer
        // characters, so this doesn't merge distinct rows.
        if ((iou > 0.3 ||
                _containment(block.boundingBox, other.boundingBox) > 0.5) &&
            _charOverlapRatio(normalized, otherNorm) > 0.8) {
          return true;
        }
        // Exact text match + decent box overlap → duplicate.
        if (iou > 0.5 && otherNorm == normalized) return true;
        // Different text but heavy box overlap → keep the longer one only
        // (handles two passes producing slightly different bounding boxes
        // around the same line).
        if (iou > 0.7) return true;
        // Prefix / substring duplicate — same text content but one OCR
        // pass truncated. Catches the "Thêm tham số" vs "Thêm tham s"
        // case where boxes overlap moderately. We're already iterating
        // in confidence-desc order so `other` is the better candidate.
        if (iou > 0.3 && (
              otherNorm.startsWith(normalized) ||
              normalized.startsWith(otherNorm) ||
              otherNorm.contains(normalized) ||
              normalized.contains(otherNorm)
            )) {
          return true;
        }
        return false;
      });
      if (!isDup) kept.add(block);
    }

    // Final geometric overlap pass. Text-based dedup above can still
    // leave two boxes physically overlapping when their CONTENT differs
    // (garbled stylized logos read as different junk per pass, or a
    // mixed-script grouping the heuristics didn't catch). Cards drawn at
    // those boxes visibly stack. Here we drop any block whose box
    // overlaps an already-kept block by IoU > 0.45 regardless of text -
    // genuinely separate lines of a menu sit at IoU well below that
    // (stacked rows ≈ 0.0-0.25), so this only removes true visual
    // collisions. `kept` is in confidence-desc order, so the survivor is
    // the higher-confidence read.
    final spaced = <OcrBlock>[];
    for (final block in kept) {
      final collides = spaced.any(
          (other) => _iou(block.boundingBox, other.boundingBox) > 0.45);
      if (!collides) spaced.add(block);
    }

    // Restore reading order (top-to-bottom, left-to-right). Pixel delta —
    // NOT compareTo — so the 12 px row-grouping tolerance actually fires.
    // The earlier compareTo version collapsed everything into "same row"
    // because compareTo only returns ±1, never > 12.
    spaced.sort((a, b) {
      final dy = a.boundingBox.top - b.boundingBox.top;
      if (dy.abs() > 12) return dy < 0 ? -1 : 1;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });
    return spaced;
  }

  bool _isMeaningful(OcrBlock block) {
    // Count Unicode "letters" in any script — Latin, CJK ideographs,
    // Hiragana, Katakana, Hangul, Arabic, Devanagari, Thai, Cyrillic, etc.
    // The earlier `\W` strip used Dart's ASCII-only `\w` (even with the
    // unicode flag), so CJK-only blocks ended up empty after the strip
    // and got filtered out as noise — i.e. Japanese/Chinese/Korean menus
    // wouldn't even reach the translator.
    final letterCount =
        RegExp(r'\p{L}', unicode: true).allMatches(block.text).length;
    if (letterCount < 2) return false;
    // Hard confidence floor — anything below this is pure OCR noise.
    // We trust ML Kit's confidence on Android; iOS returns null and is
    // already stricter, so it's exempt.
    final conf = block.confidence;
    if (conf != null && conf < kOcrConfidenceFloor) return false;
    return true;
  }

  String _normalizeForDedupe(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      // Keep letters + digits in ALL scripts. The earlier `[^\w\s]+` strip
      // used Dart's ASCII-only `\w` even with the unicode flag, so CJK /
      // Hangul / Arabic chars were stripped out and two genuinely-different
      // CJK blocks collapsed to the same empty string → all but one were
      // dropped as duplicates.
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), '')
      .trim();

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;
    final intArea = intersection.width * intersection.height;
    final unionArea =
        a.width * a.height + b.width * b.height - intArea;
    if (unionArea <= 0) return 0.0;
    return intArea / unionArea;
  }

  /// Fraction of the SMALLER box that the intersection covers. Unlike
  /// IoU, this stays high when a tight line box sits inside a much
  /// larger paragraph box (IoU is dragged down by the big box's area,
  /// but the small box is still ~fully contained). Used to dedupe the
  /// "paragraph vs single-line" grouping mismatch across OCR passes.
  double _containment(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;
    final intArea = intersection.width * intersection.height;
    final smaller = math.min(a.width * a.height, b.width * b.height);
    if (smaller <= 0) return 0.0;
    return intArea / smaller;
  }

  /// Multiset character-overlap ratio of the shorter string against the
  /// longer (0..1). 1.0 = every char of the shorter appears in the
  /// longer. Robust across scripts (works on CJK with no spaces) and
  /// order-independent, so it catches two OCR passes that read the same
  /// physical text with a small insertion/substitution. Distinct dishes
  /// share far fewer characters, so a high threshold won't merge them.
  double _charOverlapRatio(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    final counts = <int, int>{};
    for (final c in longer.codeUnits) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    var match = 0;
    for (final c in shorter.codeUnits) {
      final n = counts[c] ?? 0;
      if (n > 0) {
        match++;
        counts[c] = n - 1;
      }
    }
    return match / shorter.length;
  }

  /// Currency / unit tokens that may appear in pure-price blocks. Match
  /// is case-insensitive and word-boundary-aware (regex below). New
  /// currencies: add to this list — the strip-and-check algorithm
  /// auto-handles them.
  static const List<String> _currencyTokens = [
    // Indonesian / Malaysian
    'rp', 'rm', 'idr', 'myr',
    // Vietnamese
    'vnd', 'đ', '₫',
    // East Asia
    'jpy', 'krw', 'twd', 'hkd', 'cny', 'rmb', '¥', '₩', '元', '円', '圓',
    // Western
    'usd', 'eur', 'gbp', 'aud', 'cad', '\$', '€', '£', 'us\\\$',
    // South / SE Asia
    'thb', 'sgd', 'php', 'inr', '฿', '₹', '₱', 's\\\$', 'nt\\\$', 'hk\\\$',
  ];

  /// Service / delivery keywords across the major target languages.
  /// A block that contains BOTH one of these phrases AND a phone-like
  /// digit sequence is treated as "delivery info" and dropped.
  static const List<String> _deliveryKeywords = [
    // Vietnamese
    'giao hàng', 'tận nơi', 'liên hệ', 'đặt hàng', 'gọi món', 'hotline',
    'đặt bàn',
    // English
    'delivery', 'order online', 'call us', 'contact', 'reservation',
    // Japanese
    '配達', '出前', '連絡', '予約',
    // Chinese
    '送餐', '外送', '联系', '订餐', '预订',
    // Korean
    '배달', '주문', '연락', '예약',
    // Indonesian / Malay
    'pengiriman', 'pesan online', 'hubungi', 'reservasi',
  ];

  /// Pre-compiled strip patterns.
  static final RegExp _currencyStripPattern = RegExp(
    // Match any currency token from the list, word-boundary-protected
    // and tolerant of a trailing dot (e.g. "Rp." for Rupiah).
    '\\b(${_currencyTokens.join('|')})\\b\\.?',
    caseSensitive: false,
  );

  /// Symbols + digits + separators + common price-unit chars. Stripping
  /// these from a "pure price / phone / time" block leaves the string
  /// empty. Includes:
  ///   digits 0-9
  ///   thousands & decimal separators . , ' ’ ` ·
  ///   range dashes - – — ~
  ///   k/K/m/M (size markers: "65k", "1M", "2.5m")
  ///   time chars : ;  h H (Vietnamese hour notation)
  ///   AM/PM (post-strip via word boundary handled separately)
  ///   parens / plus for phone formatting
  ///   currency symbols not covered by [_currencyStripPattern]
  ///   Real dish names have many letters besides k/m/h, so adding these
  ///   to the strip set is safe — "Phở" stays "Phở", "Pho 24K" stays
  ///   "Pho", but "65k", "1M", "65 k" all collapse to empty.
  static final RegExp _stripChars = RegExp(
    r"""[\d.,'’`·\-–—~/\\:;hHkKmM()+ \t\$€¥£₫đ₩₹₱฿]""",
  );
  static final RegExp _ampmStrip = RegExp(r'\b(am|pm)\b', caseSensitive: false);
  static final RegExp _phoneSeq = RegExp(r'\d[\d\s\-\(\)\.]{5,}\d');

  /// Pure-divider pattern: a row made entirely of separator glyphs that
  /// OCR readers sometimes pick up as text ("------", "=====", "•••",
  /// "____", "....."). Real dishes always include at least one letter.
  static final RegExp _dividerOnly = RegExp(
    r'^[\s\-=_~*•·.…¯\\/|]+$',
  );

  /// Letter (any script) — used for letter-ratio + minimum-letter checks
  /// that knock out blocks where OCR mostly grabbed background texture.
  static final RegExp _anyLetter = RegExp(r'\p{L}', unicode: true);

  /// Returns true if [text] looks like OCR noise rather than a real menu
  /// row. Conservative — we only reject when the block fails one of these
  /// clear signs of garbage:
  ///   • length ≤ 1 (single char, almost never a dish name);
  ///   • pure divider chars ("----", "=====", "•••");
  ///   • fewer than 2 letters total (digits + symbols only);
  ///   • letter ratio < 30 % of the trimmed text (mostly symbols/digits);
  ///   • all letters identical 3+ times ("aaa", "BBB", "XXXX").
  /// Acronyms like "BBQ", "VIP", "USA" survive (3+ letters, mixed chars).
  /// This runs ONLY on the menu scene; document/sign/auto leave it alone.
  bool _isMenuNoise(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= 1) return true;
    if (_dividerOnly.hasMatch(trimmed)) return true;

    final letterCount = _anyLetter.allMatches(trimmed).length;
    if (letterCount < 2) return true;
    if (letterCount / trimmed.length < 0.3) return true;

    // All letters identical (e.g. "aaaa" — common watermark / texture
    // misread). Compare lowercase; ignore non-letters when assessing.
    final letters = _anyLetter
        .allMatches(trimmed)
        .map((m) => m[0]!.toLowerCase())
        .toList();
    if (letters.length >= 3 && letters.every((c) => c == letters.first)) {
      return true;
    }

    return false;
  }

  /// Returns true if [text] is PURE menu metadata (price, phone, time,
  /// currency-only) — i.e. after removing all currency tokens, digits,
  /// separators, and time/phone formatting, nothing meaningful remains.
  /// This is more robust than per-pattern regex because it handles any
  /// of dozens of currency code variants (Rp., RM, HK$, NT$, ₩, ฿, etc.)
  /// from one declarative list.
  bool _isMenuMetadata(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;

    // Single-pass strip: currency words → AM/PM → digits/separators.
    final stripped = trimmed
        .replaceAll(_currencyStripPattern, '')
        .replaceAll(_ampmStrip, '')
        .replaceAll(_stripChars, '')
        .trim();
    if (stripped.isEmpty) return true;

    // Mixed content but matches delivery-info shape: keyword + phone.
    final lower = trimmed.toLowerCase();
    final hasKeyword = _deliveryKeywords.any((kw) => lower.contains(kw));
    final hasPhoneSequence = _phoneSeq.hasMatch(trimmed);
    if (hasKeyword && hasPhoneSequence) return true;

    return false;
  }

  /// Trailing-price matcher for menu dish rows. Matches a price token at
  /// the END of a string only when it's CLEARLY a price — i.e. it has a
  /// currency marker (Rp/RM/$/€/¥/£/₫/đ/₩/₹/฿/k-suffix) OR a thousands
  /// pattern (15,000 / 15.000) OR 4+ bare digits. A bare 1-3 digit number
  /// without any marker is NOT stripped (could be part of a dish name:
  /// "Phở 24", "Combo 2", "Set 3").
  static final RegExp _trailingPrice = RegExp(
    r'''[\s\-–—:]+'''                                  // separator before price
    r'''(?:'''
    r'''(?:rp\.?|rm|hk\$|s\$|nt\$|us\$|[\$€¥£₫đ₩₹฿円圓元])\s*[\d.,]+'''  // currency-prefixed: "Rp. 15.000", "$12", "¥800"
    r'''|[\d]+[.,][\d]{3}(?:[.,][\d]{3})*\s*(?:[kK]|đ|₫|vnd|usd|idr|rp|rm)?'''  // thousands: "15.000", "15,000"
    r'''|[\d.,]+\s*[kK]\b'''                            // k-suffix: "65k", "1.5k"
    r'''|[\d]{4,}\s*(?:đ|₫|vnd|usd|idr|rp|rm)?'''       // 4+ bare digits: "15000"
    r'''|[\d.,]+\s*(?:đ|₫|vnd|usd|eur|jpy|krw|thb|idr|myr|php|inr|sgd)\b'''  // suffix code: "25 VND"
    r'''|[\d.,]+\s*[円圓元¥₩₫đ฿₹₱]'''                    // currency-SYMBOL suffix: "800円", "5000₩", "20000₫" (the JP-yen leak)
    r''')\s*$''',
    caseSensitive: false,
  );

  /// Remove a trailing price from a menu dish row. "Phở bò 65k" → "Phở bò".
  /// Returns the input unchanged when there's no clear trailing price, or
  /// when stripping would leave nothing (the whole thing was a price —
  /// that case is already handled by [_isMenuMetadata] dropping it).
  String _stripTrailingPrice(String text) {
    final stripped = text.replaceFirst(_trailingPrice, '').trimRight();
    if (stripped.trim().isEmpty) return text; // don't empty the block
    return stripped;
  }

  /// Merge OCR blocks that visually belong to the same horizontal line.
  ///
  /// ML Kit occasionally splits one logical line into multiple TextBlocks
  /// at small visual gaps (a colon, a price tag mid-line, a thin separator
  /// that the OCR engine reads as a paragraph break).
  ///
  /// Merge criteria (must satisfy ALL):
  ///   • Y midpoints within ½ × min(height) of each other (same baseline)
  ///   • Heights within 1.67× of each other (similar font / not header+body)
  ///   • Horizontal gap < [hGapMultiplier] × line height
  ///   • B is to the right of A (gap >= small overlap tolerance)
  ///
  /// Scene-tuned via [hGapMultiplier]: all current scenes pass 1.2 (tight
  /// prose / same-row fragments). Menu price stripping + vertical de-overlap
  /// happen in [_mergeForScene] and [_separateVertically] after this step.
  List<OcrBlock> _mergeSameLine(List<OcrBlock> blocks, {double hGapMultiplier = 1.2}) {
    if (blocks.length < 2) return blocks;
    final sorted = [...blocks];
    sorted.sort((a, b) {
      // Pixel delta — NOT compareTo. The earlier compareTo+abs>12 pattern
      // never triggered the row-grouping branch, so menu rows were being
      // walked in left-to-right order across the whole page instead of
      // row-by-row.
      final dy = a.boundingBox.top - b.boundingBox.top;
      if (dy.abs() > 12) return dy < 0 ? -1 : 1;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });

    final result = <OcrBlock>[];
    OcrBlock? pending;
    for (final block in sorted) {
      if (pending == null) {
        pending = block;
        continue;
      }
      if (_sameLine(pending, block, hGapMultiplier: hGapMultiplier)) {
        pending = _mergeBlocks(pending, block, separator: ' ');
      } else {
        result.add(pending);
        pending = block;
      }
    }
    if (pending != null) result.add(pending);
    return result;
  }

  /// True when [text] is a PURE price / number token (only digits, currency
  /// and separators remain after stripping). Such a block belongs WITH the
  /// dish on its row, not as its own card.
  static final RegExp _hasDigit = RegExp(r'\d');
  bool _isPriceBlock(String text) {
    final t = text.trim();
    if (t.isEmpty || !_hasDigit.hasMatch(t)) return false;
    final stripped = t
        .replaceAll(_currencyStripPattern, '')
        .replaceAll(_ampmStrip, '')
        .replaceAll(_stripChars, '')
        .trim();
    return stripped.isEmpty;
  }

  static final RegExp _letterRe = RegExp(r'\p{L}', unicode: true);
  bool _hasLetters(String text) => _letterRe.hasMatch(text);

  /// Cluster blocks into visual ROWS by vertical midpoint. Two blocks share a
  /// row when their centres are within 0.6 × the taller box — tight enough to
  /// keep stacked dish rows apart, loose enough to group a dish with the price
  /// (and any phonetic reading) sitting on the same line.
  List<List<OcrBlock>> _clusterByRow(List<OcrBlock> blocks) {
    final sorted = [...blocks]
      ..sort((a, b) =>
          a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
    final rows = <List<OcrBlock>>[];
    for (final b in sorted) {
      final my = b.boundingBox.center.dy;
      final h = b.boundingBox.height;
      List<OcrBlock>? target;
      for (final r in rows) {
        final ry =
            r.map((c) => c.boundingBox.center.dy).reduce((a, c) => a + c) /
                r.length;
        final rh = r.map((c) => c.boundingBox.height).reduce(math.max);
        if ((my - ry).abs() < math.max(h, rh) * 0.6) {
          target = r;
          break;
        }
      }
      if (target != null) {
        target.add(b);
      } else {
        rows.add([b]);
      }
    }
    return rows;
  }

  /// MENU smart row pairing. Within one visual row, group each dish with the
  /// price (and reading) that follow it, emitting ONE wide block per dish that
  /// spans dish → price. A new group starts at a dish that follows an
  /// already-completed dish+price pair (the next column's entry) OR across a
  /// column-gutter-sized gap — so a 2-/3-column menu keeps each "món + giá" as
  /// its own block instead of merging across columns. Price text is stripped
  /// (the user reads it off the photo); the wide box is what stops the
  /// translation wrapping inside a narrow dish column.
  List<OcrBlock> _pairRowSegments(List<OcrBlock> row) {
    if (row.length < 2) return row;
    final sorted = [...row]
      ..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    final groups = <List<OcrBlock>>[];
    var current = <OcrBlock>[];
    var hasPrice = false;
    for (final b in sorted) {
      final isPrice = _isPriceBlock(b.text);
      final isDish = !isPrice && _hasLetters(b.text);
      if (current.isEmpty) {
        current = [b];
        hasPrice = isPrice;
        continue;
      }
      final prevRight = current.last.boundingBox.right;
      final lineH = current.map((c) => c.boundingBox.height).reduce(math.max);
      final bigGap = (b.boundingBox.left - prevRight) > lineH * 4;
      if (isDish && (hasPrice || bigGap)) {
        groups.add(current);
        current = [b];
        hasPrice = false;
      } else {
        current.add(b);
        if (isPrice) hasPrice = true;
      }
    }
    if (current.isNotEmpty) groups.add(current);

    final out = <OcrBlock>[];
    for (final g in groups) {
      var box = g.first.boundingBox;
      final parts = <String>[];
      var confSum = 0.0;
      var confN = 0;
      for (final b in g) {
        box = box.expandToInclude(b.boundingBox);
        final stripped = _stripTrailingPrice(b.text).trim();
        if (stripped.isNotEmpty && _hasLetters(stripped)) parts.add(stripped);
        final c = b.confidence;
        if (c != null) {
          confSum += c;
          confN++;
        }
      }
      final text = parts.join(' ').trim();
      if (text.isEmpty) continue; // pure-price / metadata group → drop
      out.add(OcrBlock(
        text: text,
        boundingBox: box,
        confidence: confN > 0 ? confSum / confN : null,
      ));
    }
    return out;
  }

  bool _sameLine(OcrBlock a, OcrBlock b, {required double hGapMultiplier}) {
    final aBox = a.boundingBox;
    final bBox = b.boundingBox;

    final aMidY = aBox.top + aBox.height / 2;
    final bMidY = bBox.top + bBox.height / 2;
    final yTolerance = math.min(aBox.height, bBox.height) * 0.5;
    if ((aMidY - bMidY).abs() > yTolerance) return false;

    if (aBox.height <= 0 || bBox.height <= 0) return false;
    final hRatio = aBox.height / bBox.height;
    if (hRatio < 0.6 || hRatio > 1.67) return false;

    final gap = bBox.left - aBox.right;
    final maxGap = math.max(aBox.height, bBox.height) * hGapMultiplier;
    if (gap < -10 || gap > maxGap) return false;

    return true;
  }

  /// Merge OCR blocks that visually belong to the same paragraph — i.e.
  /// stacked vertically in the same column with small vertical gap and
  /// similar font height. Joined with "\n" so the translator sees the
  /// paragraph as a unit and produces a coherent multi-line translation.
  ///
  /// Scenes that benefit: document (formal prose with many adjacent
  /// lines), sign (multi-line signage reading as one message),
  /// screenshot (multi-line chat messages / article snippets).
  ///
  /// All 4 tolerances are tunable per-scene because the right balance
  /// differs by content type:
  ///   • document: dense prose, mixed font sizes (heading→body) →
  ///     loose vGap + low hOverlap + wide heightRatio
  ///   • sign: short, close lines, similar size → loose vGap + loose
  ///     hOverlap + medium heightRatio
  ///   • screenshot: distinct UI elements but multi-line messages →
  ///     tight vGap + medium hOverlap + tight heightRatio
  ///
  /// Criteria (must satisfy ALL):
  ///   • B sits directly below A: 0 ≤ vertical gap ≤ vGapMultiplier × line height
  ///   • Same column: horizontal overlap ≥ hOverlapRatio × smaller box width
  ///   • Similar font: height ratio between heightRatioMin and heightRatioMax
  List<OcrBlock> _mergeParagraph(
    List<OcrBlock> blocks, {
    double vGapMultiplier = 0.8,
    double hOverlapRatio = 0.5,
    double heightRatioMin = 0.7,
    double heightRatioMax = 1.4,
  }) {
    if (blocks.length < 2) return blocks;
    final sorted = [...blocks];
    sorted.sort((a, b) {
      final dy = a.boundingBox.top.compareTo(b.boundingBox.top);
      if (dy != 0) return dy;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });

    final result = <OcrBlock>[];
    OcrBlock? pending;
    for (final block in sorted) {
      if (pending == null) {
        pending = block;
        continue;
      }
      if (_sameParagraph(
        pending,
        block,
        vGapMultiplier: vGapMultiplier,
        hOverlapRatio: hOverlapRatio,
        heightRatioMin: heightRatioMin,
        heightRatioMax: heightRatioMax,
      )) {
        pending = _mergeBlocks(pending, block, separator: '\n');
      } else {
        result.add(pending);
        pending = block;
      }
    }
    if (pending != null) result.add(pending);
    return result;
  }

  bool _sameParagraph(
    OcrBlock a,
    OcrBlock b, {
    required double vGapMultiplier,
    required double hOverlapRatio,
    required double heightRatioMin,
    required double heightRatioMax,
  }) {
    final aBox = a.boundingBox;
    final bBox = b.boundingBox;

    // Vertical: B starts at or just below A's bottom.
    final verticalGap = bBox.top - aBox.bottom;
    if (verticalGap < -5) return false; // overlap → likely different element
    final maxLineHeight = math.max(aBox.height, bBox.height);
    if (verticalGap > maxLineHeight * vGapMultiplier) return false;

    // Same column: horizontal overlap covers ≥ ratio of the smaller width.
    if (aBox.width <= 0 || bBox.width <= 0) return false;
    final hOverlap =
        math.min(aBox.right, bBox.right) - math.max(aBox.left, bBox.left);
    final minWidth = math.min(aBox.width, bBox.width);
    if (hOverlap < minWidth * hOverlapRatio) return false;

    // Similar font height. Document tolerates more variance because
    // headings + first body line + nested bullets all sit close together.
    if (aBox.height <= 0 || bBox.height <= 0) return false;
    final hRatio = aBox.height / bBox.height;
    if (hRatio < heightRatioMin || hRatio > heightRatioMax) return false;

    return true;
  }


  /// Collapse N blocks into ONE — text concatenated in reading order
  /// (top-to-bottom, left-to-right within a row), bounding box is the
  /// union, confidence is the length-weighted average.
  ///
  /// Used by SIGN scene where every detected fragment is part of the
  /// same physical sign and must be translated as one message. Unlike
  /// pairwise paragraph merge (which requires column overlap), this
  /// works across multi-column layouts (logo-left + info-right) that
  /// signs commonly have.
  OcrBlock _aggregateBlocks(List<OcrBlock> blocks) {
    assert(blocks.isNotEmpty);
    if (blocks.length == 1) return blocks.first;

    // Reading order — group blocks into rows by Y (12 px tolerance),
    // then left-to-right within each row. The delta is in IMAGE PIXELS
    // (a.boundingBox.top - b.boundingBox.top), NOT a compareTo result;
    // earlier versions had `dy = compareTo(...)` which only returns ±1
    // so the >12 row-grouping check never triggered and everything
    // collapsed into "same row" + left-to-right — i.e. blocks shuffled
    // out of reading order any time they differed in X.
    final sorted = [...blocks];
    sorted.sort((a, b) {
      final dy = a.boundingBox.top - b.boundingBox.top;
      if (dy.abs() > 12) return dy < 0 ? -1 : 1;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });

    final text = sorted.map((block) => block.text.trim()).where((t) => t.isNotEmpty).join('\n');
    var minLeft = double.infinity;
    var minTop = double.infinity;
    var maxRight = -double.infinity;
    var maxBottom = -double.infinity;
    for (final block in sorted) {
      final box = block.boundingBox;
      if (box.left < minLeft) minLeft = box.left;
      if (box.top < minTop) minTop = box.top;
      if (box.right > maxRight) maxRight = box.right;
      if (box.bottom > maxBottom) maxBottom = box.bottom;
    }

    // Length-weighted confidence — longer text dominates so a tiny
    // low-confidence fragment doesn't drag the whole block's badge into
    // amber when most of the sign was read cleanly.
    double? confidence;
    var totalLength = 0;
    var weightedConfidence = 0.0;
    for (final block in sorted) {
      final value = block.confidence;
      if (value == null) continue;
      final length = block.text.length;
      weightedConfidence += value * length;
      totalLength += length;
    }
    if (totalLength > 0) confidence = weightedConfidence / totalLength;

    return OcrBlock(
      text: text,
      boundingBox: Rect.fromLTRB(minLeft, minTop, maxRight, maxBottom),
      confidence: confidence,
    );
  }

  /// Remove vertical overlap between adjacent blocks IN THE SAME COLUMN.
  ///
  /// ML Kit adds small leading/descender padding to each bounding box.
  /// On a dense menu (rows 5–10 px apart) adjacent boxes often overlap
  /// by 1–5 px — low enough to escape the IoU > 0.45 dedup threshold
  /// but enough to make two overlay cards visually stack.
  ///
  /// IMPORTANT: only shifts blocks that share horizontal extent (same
  /// column region). Two blocks from different columns that happen to
  /// have the same Y are NOT shifted — a naive top-only sort would push
  /// the right-column block down even though it visually belongs to the
  /// same row as the left-column block.
  List<OcrBlock> _separateVertically(List<OcrBlock> blocks) {
    if (blocks.length < 2) return blocks;
    final sorted = [...blocks]
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final result = <OcrBlock>[sorted.first];
    for (var i = 1; i < sorted.length; i++) {
      final prev = result.last;
      final curr = sorted[i];
      final vOverlap = prev.boundingBox.bottom - curr.boundingBox.top;
      // Horizontal overlap: positive means the two blocks share column space.
      final hOverlap =
          math.min(prev.boundingBox.right, curr.boundingBox.right) -
          math.max(prev.boundingBox.left, curr.boundingBox.left);
      // Only shift when BOTH vertically and horizontally overlapping —
      // i.e. the blocks are in the same column and the rows bleed into
      // each other. Different-column blocks at the same Y have hOverlap ≤ 0
      // and must not be shifted.
      if (vOverlap <= 0 || hOverlap <= 0) {
        result.add(curr);
        continue;
      }
      // Move curr's top flush with prev's bottom. Keep at least 4 px
      // of height so the card stays tappable.
      final newTop = prev.boundingBox.bottom;
      final newBottom = math.max(newTop + 4.0, curr.boundingBox.bottom);
      result.add(OcrBlock(
        text: curr.text,
        boundingBox: Rect.fromLTRB(
          curr.boundingBox.left,
          newTop,
          curr.boundingBox.right,
          newBottom,
        ),
        confidence: curr.confidence,
        items: curr.items,
      ));
    }
    return result;
  }

  OcrBlock _mergeBlocks(OcrBlock a, OcrBlock b, {required String separator}) {
    final text = '${a.text.trim()}$separator${b.text.trim()}';
    final box = Rect.fromLTRB(
      math.min(a.boundingBox.left, b.boundingBox.left),
      math.min(a.boundingBox.top, b.boundingBox.top),
      math.max(a.boundingBox.right, b.boundingBox.right),
      math.max(a.boundingBox.bottom, b.boundingBox.bottom),
    );
    // Weighted-by-length average confidence — longer text dominates.
    double? conf;
    if (a.confidence != null && b.confidence != null) {
      final aLen = a.text.length;
      final bLen = b.text.length;
      final total = aLen + bLen;
      conf = total > 0
          ? (a.confidence! * aLen + b.confidence! * bLen) / total
          : a.confidence;
    } else {
      conf = a.confidence ?? b.confidence;
    }
    return OcrBlock(text: text, boundingBox: box, confidence: conf);
  }

  void dispose() {
    _isStreaming = false;
    // Stop image stream before disposing the controller to prevent native crash
    try {
      _controller?.stopImageStream();
    } catch (_) {}
    for (final recognizer in _streamRecognizers.values) {
      try {
        recognizer.close();
      } catch (_) {}
    }
    _streamRecognizers.clear();
    _dbnet.close();
    _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }

  /// Intersection-over-union for two axis-aligned rectangles. Returns
  /// 0 when disjoint, 1 when identical. Used to dedupe the multi-pass
  /// BubbleDetector union in [recognizePerRegion].
  static double _iouRect(Rect a, Rect b) {
    final l = math.max(a.left, b.left);
    final t = math.max(a.top, b.top);
    final r = math.min(a.right, b.right);
    final bo = math.min(a.bottom, b.bottom);
    if (r <= l || bo <= t) return 0.0;
    final inter = (r - l) * (bo - t);
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0.0 : inter / union;
  }

  /// Single-link agglomerative clustering on [rects]. Two rects join
  /// the same cluster if their edge-to-edge distance is below [thresh].
  /// Each cluster's bbox is the axis-aligned union of its members.
  /// Used by [recognizePerRegion]'s TABD step to fuse per-line
  /// detections (one orphan per text line) into one orphan per bubble
  /// so the user sees a single overlay card, not a stack.
  static List<Rect> _clusterRectsSingleLink(
      List<Rect> rects, double thresh) {
    final n = rects.length;
    if (n <= 1) return List<Rect>.of(rects);
    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      var root = i;
      while (parent[root] != root) {
        root = parent[root];
      }
      // path compression
      var cur = i;
      while (parent[cur] != root) {
        final next = parent[cur];
        parent[cur] = root;
        cur = next;
      }
      return root;
    }
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (_rectGapDistance(rects[i], rects[j]) < thresh) {
          final ri = find(i);
          final rj = find(j);
          if (ri != rj) parent[ri] = rj;
        }
      }
    }
    final groups = <int, List<Rect>>{};
    for (var i = 0; i < n; i++) {
      groups.putIfAbsent(find(i), () => <Rect>[]).add(rects[i]);
    }
    return groups.values.map(_unionBbox).toList();
  }

  /// Like [_clusterRectsSingleLink] but REJECTS any cluster whose union
  /// bbox exceeds [maxAreaRatio] of [pageArea]. Single-link chains text
  /// boxes across a tall multi-panel manga page into one giant box (the
  /// unclip-expanded DBNet lines touch down the whole page), which would
  /// paint ONE translation card over the entire page. An over-cap cluster
  /// falls back to its individual member boxes — more cards, but each
  /// correctly placed — instead of one catastrophic mega-box.
  static List<Rect> _clusterRectsCapped(
      List<Rect> rects, double thresh, double pageArea, double maxAreaRatio) {
    final n = rects.length;
    if (n <= 1) return List<Rect>.of(rects);
    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      var root = i;
      while (parent[root] != root) {
        root = parent[root];
      }
      var cur = i;
      while (parent[cur] != root) {
        final next = parent[cur];
        parent[cur] = root;
        cur = next;
      }
      return root;
    }
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (_rectGapDistance(rects[i], rects[j]) < thresh) {
          final ri = find(i);
          final rj = find(j);
          if (ri != rj) parent[ri] = rj;
        }
      }
    }
    final groups = <int, List<Rect>>{};
    for (var i = 0; i < n; i++) {
      groups.putIfAbsent(find(i), () => <Rect>[]).add(rects[i]);
    }
    final out = <Rect>[];
    for (final members in groups.values) {
      final bb = _unionBbox(members);
      if (pageArea > 0 && bb.width * bb.height > maxAreaRatio * pageArea) {
        out.addAll(members); // over-merge → keep members individually
      } else {
        out.add(bb);
      }
    }
    return out;
  }

  /// Group DBNet per-line boxes into one region PER SPEECH BUBBLE using the
  /// accurate bubble SHAPES from [BubbleDetector]. Each line is assigned to
  /// the SMALLEST bubble whose box contains the line's centre, and the
  /// emitted region is the tight UNION of that bubble's assigned lines (the
  /// real ink position - used directly as the card box, no tighten step).
  /// Two safety valves keep a mis-detected panel-sized "bubble" from
  /// painting one card over the page:
  ///   - a bubble whose line-union exceeds [maxAreaRatio] of [pageArea] is
  ///     treated as a flood-fill panel; its members go back to the orphan
  ///     pool instead of merging.
  ///   - lines inside no bubble fall back to area-capped single-link
  ///     clustering ([_clusterRectsCapped]) on [orphanThresh].
  static List<Rect> _groupDbnetByBubbles(
    List<Rect> lines,
    List<Rect> bubbles, {
    required double orphanThresh,
    required double pageArea,
    required double maxAreaRatio,
  }) {
    if (lines.isEmpty) return const [];
    final assigned = List<bool>.filled(lines.length, false);
    final perBubble = <int, List<Rect>>{};
    for (var i = 0; i < lines.length; i++) {
      final cx = (lines[i].left + lines[i].right) / 2;
      final cy = (lines[i].top + lines[i].bottom) / 2;
      var best = -1;
      var bestArea = double.infinity;
      for (var j = 0; j < bubbles.length; j++) {
        final b = bubbles[j];
        if (cx >= b.left && cx <= b.right && cy >= b.top && cy <= b.bottom) {
          final a = b.width * b.height;
          if (a < bestArea) {
            bestArea = a;
            best = j;
          }
        }
      }
      if (best >= 0) {
        (perBubble[best] ??= <Rect>[]).add(lines[i]);
        assigned[i] = true;
      }
    }
    final orphans = <Rect>[];
    for (var i = 0; i < lines.length; i++) {
      if (!assigned[i]) orphans.add(lines[i]);
    }
    final result = <Rect>[];
    for (final group in perBubble.values) {
      final u = _unionBbox(group);
      if (pageArea > 0 && u.width * u.height > maxAreaRatio * pageArea) {
        orphans.addAll(group); // flood-fill panel mis-detect → recluster
      } else {
        result.add(u);
      }
    }
    final withText = result.length;
    // RECALL FILL: bubbles BubbleDetector found but DBNet had NO text in.
    // At 640px on a tall page (720x1600 → 0.4x) DBNet loses small / faint
    // text - whole top-row and sound-effect bubbles come back untranslated.
    // BubbleDetector's contour recall is higher, so OCR those bubble crops
    // directly; the per-region OCR's >= 2 meaningful-char floor drops the
    // genuinely empty ones. Band-limit to skip panel-sized boxes and
    // sub-noise specks.
    var emptyFill = 0;
    for (var j = 0; j < bubbles.length; j++) {
      if (perBubble.containsKey(j) || pageArea <= 0) continue;
      final b = bubbles[j];
      final ratio = (b.width * b.height) / pageArea;
      // A real speech bubble DBNet missed is SMALL and roughly round; a
      // panel-sized box (e.g. 403x342 ~ 12% of page) or a tall art / hair
      // strip (e.g. 128x342) is a BubbleDetector false positive that OCRs
      // to nothing - just wasted ML Kit queue time. Keep only boxes in the
      // speech-bubble size band AND with a sane aspect ratio.
      if (ratio < 0.005 || ratio > 0.06) continue;
      final aspect = b.width >= b.height
          ? b.width / math.max(b.height, 1.0)
          : b.height / math.max(b.width, 1.0);
      if (aspect > 2.5) continue;
      result.add(b);
      emptyFill++;
    }
    if (orphans.isNotEmpty) {
      result.addAll(
          _clusterRectsCapped(orphans, orphanThresh, pageArea, maxAreaRatio));
    }
    debugPrint('[CameraService] _groupDbnetByBubbles: withText=$withText '
        'emptyBubbleFill=$emptyFill orphans=${orphans.length}');
    return result;
  }

  /// Euclidean distance between two axis-aligned rectangles' nearest
  /// edges. Zero when they overlap or touch. Used as the cluster
  /// linkage metric for [_clusterRectsSingleLink].
  static double _rectGapDistance(Rect a, Rect b) {
    final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right));
    final dy = math.max(0.0, math.max(a.top - b.bottom, b.top - a.bottom));
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Axis-aligned bounding box that encloses every rect in [rects].
  static Rect _unionBbox(List<Rect> rects) {
    var l = rects[0].left;
    var t = rects[0].top;
    var r = rects[0].right;
    var bo = rects[0].bottom;
    for (var i = 1; i < rects.length; i++) {
      if (rects[i].left < l) l = rects[i].left;
      if (rects[i].top < t) t = rects[i].top;
      if (rects[i].right > r) r = rects[i].right;
      if (rects[i].bottom > bo) bo = rects[i].bottom;
    }
    return Rect.fromLTRB(l, t, r, bo);
  }

  /// True when [outer] geometrically contains [inner] (with a 2-px
  /// tolerance so a slightly-larger outer box still passes when the
  /// inner detection bbox sits flush to its bounds).
  static bool _rectContains(Rect outer, Rect inner) {
    const slack = 2.0;
    return outer.left - slack <= inner.left &&
        outer.top - slack <= inner.top &&
        outer.right + slack >= inner.right &&
        outer.bottom + slack >= inner.bottom;
  }

  /// Collapse OcrBlocks that are the same bubble detected twice.
  ///
  /// Picking the right keeper of an overlapping pair turns out to need
  /// TWO axes, not one:
  ///   - **Position (bbox)** — must come from the LARGER bbox so the
  ///     card lands at the bubble-shape boundary (BubbleDetector match)
  ///     instead of the tight-glyph rectangle (TABD orphan / DBNet).
  ///     Picking the small bbox makes the rendered card sit visibly
  ///     off-centre inside the original speech bubble.
  ///   - **Text** — must come from the OCR pass with the BEST read of
  ///     the bubble (more meaningful characters), regardless of which
  ///     bbox produced it. Picking the small-bbox text can be a
  ///     garbled fragment that the downstream translate pipeline then
  ///     hands back unchanged, surfacing as RAW SOURCE next to a clean
  ///     translation - the original "overlay double" complaint.
  ///
  /// So for each cluster of overlapping blocks we MERGE: bbox = the
  /// largest, text = the one with the most meaningful chars. This way
  /// the card sits where the bubble actually is, AND downstream
  /// translation gets the cleanest source text.
  ///
  /// Overlap rule: rectContains in either direction (SHAPE + TABD-orphan
  /// pair) OR IoU > 0.4 (two SHAPE candidates from multi-threshold).
  /// Sibling close-but-not-overlapping bubbles stay untouched.
  static List<OcrBlock> _dedupSameTextOverlapping(List<OcrBlock> blocks) {
    if (blocks.length < 2) return blocks;
    // Union-find clusters of overlapping blocks. O(n²) is fine — per
    // page n is typically < 30.
    final parent = List<int>.generate(blocks.length, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    bool overlap(Rect a, Rect b) {
      if (_rectContains(a, b) || _rectContains(b, a)) return true;
      return _iouRect(a, b) > 0.4;
    }

    for (var i = 0; i < blocks.length; i++) {
      for (var j = i + 1; j < blocks.length; j++) {
        if (overlap(blocks[i].boundingBox, blocks[j].boundingBox)) {
          union(i, j);
        }
      }
    }

    final clusters = <int, List<int>>{};
    for (var i = 0; i < blocks.length; i++) {
      clusters.putIfAbsent(find(i), () => []).add(i);
    }

    final merged = <OcrBlock>[];
    for (final members in clusters.values) {
      if (members.length == 1) {
        merged.add(blocks[members.first]);
        continue;
      }
      // Pick the SMALLEST bbox for the keeper position. When a cluster
      // contains a tight glyph-rectangle bbox (TABD orphan / DBNet)
      // AND a much larger bbox (BubbleDetector shape, or a panel-sized
      // mis-detection that swept in via union-find chaining), the small
      // bbox is the more reliable estimate of where the actual text
      // pixels sit in the original art. Picking the large bbox makes
      // the card render at the bubble/panel TOP-LEFT instead of the
      // text position - user reports "block đặt không đúng vị trí bóng,
      // không phải vị trí viền mà vị trí text của art".
      int bestBboxIdx = members.first;
      double bestArea = double.infinity;
      for (final m in members) {
        final r = blocks[m].boundingBox;
        final a = r.width * r.height;
        if (a < bestArea) {
          bestArea = a;
          bestBboxIdx = m;
        }
      }
      // Pick the OCR text with the most meaningful characters.
      int bestTextIdx = members.first;
      int bestScore = -1;
      for (final m in members) {
        final s = _meaningfulCharCount(blocks[m].text);
        if (s > bestScore) {
          bestScore = s;
          bestTextIdx = m;
        }
      }
      merged.add(OcrBlock(
        text: blocks[bestTextIdx].text,
        boundingBox: blocks[bestBboxIdx].boundingBox,
        confidence: blocks[bestBboxIdx].confidence,
      ));
    }
    return merged;
  }

  /// Count "meaningful" characters in [s] — Latin letters, digits, and
  /// CJK / kana / hangul codepoints. Punctuation, whitespace, and
  /// symbols don't count. Used to pick the better OCR result when
  /// running multiple ML Kit script recognizers on the same crop.
  static int _meaningfulCharCount(String s) {
    var count = 0;
    for (final rune in s.runes) {
      if ((rune >= 0x30 && rune <= 0x39) ||              // 0-9
          (rune >= 0x41 && rune <= 0x5A) ||              // A-Z
          (rune >= 0x61 && rune <= 0x7A) ||              // a-z
          (rune >= 0x3040 && rune <= 0x309F) ||          // hiragana
          (rune >= 0x30A0 && rune <= 0x30FF) ||          // katakana
          (rune >= 0x4E00 && rune <= 0x9FFF) ||          // CJK unified
          (rune >= 0xAC00 && rune <= 0xD7AF)) {          // hangul syllables
        count++;
      }
    }
    return count;
  }

  /// Re-join ML Kit lines in vertical-CJK reading order.
  ///
  /// ML Kit concatenates recognized lines in a Latin layout order
  /// (top-to-bottom, left-to-right). Vertical Japanese / Chinese reads
  /// top-to-bottom WITHIN a column and columns RIGHT-to-LEFT, so the
  /// default `.text` scrambles the sentence: a bubble that reads
  /// "何度も質問をして" comes back as "して / 質問を / 何度も" (columns in
  /// left-to-right order). Measured on real manga pages.
  ///
  /// When the lines look columnar (most are taller than wide) we re-sort
  /// by column center-x DESCENDING (rightmost first), ties by center-y
  /// ASCENDING (top first), and join with no separator (CJK has no
  /// inter-word spaces). Horizontal text (few tall lines) keeps ML Kit's
  /// own order untouched.
  static String _cjkVerticalReadingOrder(RecognizedText r) {
    final lines = <TextLine>[];
    for (final b in r.blocks) {
      lines.addAll(b.lines);
    }
    if (lines.length <= 1) return r.text.trim();
    var tall = 0;
    for (final l in lines) {
      if (l.boundingBox.height > l.boundingBox.width) tall++;
    }
    // Majority of lines must be vertical columns; else trust ML Kit.
    if (tall * 2 < lines.length) return r.text.trim();
    final avgW =
        lines.fold<double>(0, (s, l) => s + l.boundingBox.width) /
            lines.length;
    final colTol = math.max(avgW * 0.6, 8.0);
    final sorted = [...lines]..sort((a, b) {
        final ax = a.boundingBox.center.dx;
        final bx = b.boundingBox.center.dx;
        if ((ax - bx).abs() > colTol) {
          return bx.compareTo(ax); // rightmost column first (RTL)
        }
        return a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy);
      });
    return sorted.map((l) => l.text).join();
  }

  /// Persist the per-region OCR log to a text file next to the JPEG
  /// debug dump. Debug builds only — gated at the call site.
  Future<void> _dumpOcrLog(String imagePath, List<String> lines) async {
    try {
      final dir = await getTemporaryDirectory();
      final out =
          '${dir.path}/ocr_log_${DateTime.now().millisecondsSinceEpoch}.txt';
      final src = imagePath.split('/').last;
      final body = 'src=$src\n${lines.join('\n')}\n';
      await File(out).writeAsString(body);
      debugPrint('[CameraService] OCR log → $out (${lines.length} regions)');
    } catch (e) {
      debugPrint('[CameraService] OCR log dump failed: $e');
    }
  }

  /// Annotate the input capture with the per-detector boxes and write
  /// a JPEG to the temp dir. Debug builds only — kDebugMode gates the
  /// call site so release users don't accumulate dump files.
  /// DBNet boxes render blue, BubbleDetector boxes render red.
  Future<void> _dumpDetectionDebug(
    String imagePath,
    List<Rect> dbnetBoxes,
    List<Rect> bubbleBoxes,
  ) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;
      for (final box in dbnetBoxes) {
        img.drawRect(
          decoded,
          x1: box.left.round(),
          y1: box.top.round(),
          x2: box.right.round(),
          y2: box.bottom.round(),
          color: img.ColorRgb8(40, 120, 255),
          thickness: 3,
        );
      }
      for (final box in bubbleBoxes) {
        img.drawRect(
          decoded,
          x1: box.left.round(),
          y1: box.top.round(),
          x2: box.right.round(),
          y2: box.bottom.round(),
          color: img.ColorRgb8(255, 80, 80),
          thickness: 3,
        );
      }
      final dir = await getTemporaryDirectory();
      final out =
          '${dir.path}/lens_debug_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(out).writeAsBytes(img.encodeJpg(decoded, quality: 80));
      debugPrint(
          '[CameraService] debug dump → $out (DBNet=blue Bubble=red)');
    } catch (e) {
      debugPrint('[CameraService] debug dump failed: $e');
    }
  }
}

/// Isolate transport for [CameraService.findUncoveredTextRegions].
class _UncoveredArgs {
  _UncoveredArgs({
    required this.imagePath,
    required this.covered,
    required this.maxRegions,
  });
  final String imagePath;
  // Each covered rect as [left, top, right, bottom] in original coords.
  final List<List<double>> covered;
  final int maxRegions;
}

/// Edge-density text detector minus already-covered regions. Returns
/// the bounding rects (original coords) of text-dense areas that no
/// existing detection covers — vision-LLM catch-up targets. Mirrors
/// the SHAPE/CONTENT detectors' downscale-600 + Sobel + integral-image
/// approach so coordinates line up.
List<Rect> _uncoveredRegionsIsolate(_UncoveredArgs args) {
  const procW = 600;
  const sobelThresh = 40;
  const windowSize = 16;
  const densityThresh = 0.18;
  // Slightly larger min than EdgeDensity's own — we only want
  // bubble-sized unread areas here, not single stray glyphs.
  const minAreaRatio = 0.0015;
  const maxAreaRatio = 0.20;
  try {
    final bytes = File(args.imagePath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const [];
    final origW = decoded.width;
    final origH = decoded.height;
    final scale = procW / origW;
    final procH = (origH * scale).toInt();
    if (procH < 8) return const [];
    final small = img.copyResize(decoded,
        width: procW, height: procH, interpolation: img.Interpolation.linear);

    // Luminance.
    final lum = Uint8List(procW * procH);
    for (var y = 0; y < procH; y++) {
      for (var x = 0; x < procW; x++) {
        final p = small.getPixel(x, y);
        lum[y * procW + x] =
            (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b).toInt();
      }
    }
    // Sobel |gx|+|gy| → edge mask.
    final edge = Uint8List(procW * procH);
    for (var y = 1; y < procH - 1; y++) {
      final ym1 = (y - 1) * procW, y0 = y * procW, yp1 = (y + 1) * procW;
      for (var x = 1; x < procW - 1; x++) {
        final gx = -lum[ym1 + x - 1] +
            lum[ym1 + x + 1] +
            -2 * lum[y0 + x - 1] +
            2 * lum[y0 + x + 1] +
            -lum[yp1 + x - 1] +
            lum[yp1 + x + 1];
        final gy = -lum[ym1 + x - 1] -
            2 * lum[ym1 + x] -
            lum[ym1 + x + 1] +
            lum[yp1 + x - 1] +
            2 * lum[yp1 + x] +
            lum[yp1 + x + 1];
        edge[y0 + x] = (gx.abs() + gy.abs()) > sobelThresh ? 1 : 0;
      }
    }
    // Integral image.
    const iw = procW + 1;
    final ih = procH + 1;
    final integral = Int32List(iw * ih);
    for (var y = 1; y <= procH; y++) {
      var rowSum = 0;
      for (var x = 1; x <= procW; x++) {
        rowSum += edge[(y - 1) * procW + (x - 1)];
        integral[y * iw + x] = integral[(y - 1) * iw + x] + rowSum;
      }
    }
    // Covered mask in proc coords.
    final coveredMask = Uint8List(procW * procH);
    for (final c in args.covered) {
      final cl = (c[0] * scale).floor().clamp(0, procW - 1);
      final ct = (c[1] * scale).floor().clamp(0, procH - 1);
      final cr = (c[2] * scale).ceil().clamp(0, procW - 1);
      final cb = (c[3] * scale).ceil().clamp(0, procH - 1);
      for (var y = ct; y <= cb; y++) {
        for (var x = cl; x <= cr; x++) {
          coveredMask[y * procW + x] = 1;
        }
      }
    }
    // Text-candidate mask = high density AND not covered.
    const half = windowSize ~/ 2;
    const winArea = windowSize * windowSize;
    final cand = Uint8List(procW * procH);
    for (var y = 0; y < procH; y++) {
      final y1 = math.max(0, y - half);
      final y2 = math.min(procH - 1, y + half - 1);
      for (var x = 0; x < procW; x++) {
        if (coveredMask[y * procW + x] == 1) continue;
        final x1 = math.max(0, x - half);
        final x2 = math.min(procW - 1, x + half - 1);
        final sum = integral[(y2 + 1) * iw + (x2 + 1)] -
            integral[y1 * iw + (x2 + 1)] -
            integral[(y2 + 1) * iw + x1] +
            integral[y1 * iw + x1];
        if (sum / winArea > densityThresh) cand[y * procW + x] = 1;
      }
    }
    // Connected components.
    final visited = Uint8List(procW * procH);
    final found = <List<num>>[]; // [area, l, t, r, b]
    final stack = <int>[];
    final totalArea = procW * procH;
    final minArea = (totalArea * minAreaRatio).toInt();
    final maxArea = (totalArea * maxAreaRatio).toInt();
    for (var seed = 0; seed < cand.length; seed++) {
      if (visited[seed] != 0 || cand[seed] == 0) continue;
      stack.clear();
      stack.add(seed);
      visited[seed] = 1;
      var minX = procW, minY = procH, maxX = 0, maxY = 0, area = 0;
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        final cx = cur % procW, cy = cur ~/ procW;
        area++;
        if (cx < minX) minX = cx;
        if (cy < minY) minY = cy;
        if (cx > maxX) maxX = cx;
        if (cy > maxY) maxY = cy;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = cx + dx, ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= procW || ny >= procH) continue;
            final n = ny * procW + nx;
            if (visited[n] == 0 && cand[n] == 1) {
              visited[n] = 1;
              stack.add(n);
            }
          }
        }
      }
      if (area < minArea || area > maxArea) continue;
      found.add([area, minX, minY, maxX, maxY]);
    }
    // Largest-density-area first, cap to maxRegions.
    found.sort((a, b) => (b[0]).compareTo(a[0]));
    final inv = 1.0 / scale;
    final out = <Rect>[];
    for (var i = 0; i < found.length && i < args.maxRegions; i++) {
      final f = found[i];
      // Pad outward so the vision crop has bubble context.
      const pad = 10.0;
      final l = ((f[1] - pad) * inv).clamp(0.0, origW.toDouble());
      final t = ((f[2] - pad) * inv).clamp(0.0, origH.toDouble());
      final r = ((f[3] + pad) * inv).clamp(0.0, origW.toDouble());
      final b = ((f[4] + pad) * inv).clamp(0.0, origH.toDouble());
      out.add(Rect.fromLTRB(l, t, r, b));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Preprocessing variants for the multi-pass OCR pipeline. Each targets
/// a different failure mode of ML Kit's recognizer.
enum _PreprocessMode {
  /// Histogram-stretch + contrast + sharpen. Recovers faded / low-
  /// contrast printed text and chalkboard handwriting.
  contrast,

  /// Grayscale → contrast → ADAPTIVE (Bradley) threshold. Recovers BOLD
  /// stylized display fonts AND copy under uneven lighting (one half of
  /// a menu in shadow): a global threshold blows out the dark half,
  /// whereas a local-mean threshold adapts per-region.
  binarize,

  /// Grayscale → UPSCALE 2x (cubic) → normalize → unsharp. Targets the
  /// fine-print failure mode (menu address / footnotes): ML Kit's
  /// detector misses sub-16 px glyphs, and feeding it a crisply
  /// upscaled copy gives those glyphs enough pixels to register. Boxes
  /// come back in 2x space and are scaled back by [_preprocessAndRecognize].
  upscale,

  /// Grayscale → heavy Gaussian blur → threshold. The blur "fills in"
  /// hollow/outlined text (colored border, white interior) making it
  /// appear solid before thresholding to pure B&W that ML Kit can read.
  fillOutline,

  /// Grayscale → contrast → BRIGHT adaptive threshold. The mirror of
  /// [binarize]: marks a pixel as text when it is BRIGHTER than its local
  /// neighbourhood (not darker) and outputs it black. This is the fix for
  /// WHITE / light text — on a dark background (high contrast, already ~OK)
  /// and on a light background (low contrast) — which the dark-only Bradley
  /// threshold structurally cannot catch. One integral pass, so it is as
  /// cheap as [binarize] (no extra blur / dilation).
  binarizeBright,
}

class _PreprocessArgs {
  const _PreprocessArgs({
    required this.inputPath,
    required this.outputPath,
    required this.mode,
  });
  final String inputPath;
  final String outputPath;
  final _PreprocessMode mode;
}

/// Isolate entry point: decode JPEG, apply the [_PreprocessMode] filter
/// chain, re-encode. Heavy on CPU + memory so it must run off the UI
/// thread. Returns the resize SCALE applied (processed ÷ original
/// longest side) so the caller can map ML Kit boxes back to original
/// coordinates; returns -1 on failure.
///
/// We deliberately do NOT invert the image: ML Kit handles white-on-black
/// chalkboards fine once contrast is boosted; inverting also broke colour
/// printed documents we saw in production.
double _runPreprocessIsolate(_PreprocessArgs args) {
  try {
    final bytes = File(args.inputPath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return -1;

    final origMax =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    var working = decoded;
    double scale = 1.0;

    if (args.mode == _PreprocessMode.upscale) {
      // Upscale 2x to give sub-16 px glyphs enough pixels for ML Kit's
      // detector, but cap the result at 3600 px so we don't OOM or
      // exceed ML Kit's effective input ceiling on huge captures.
      const targetMax = 3600;
      final desired = (origMax * 2).clamp(origMax, targetMax);
      scale = desired / origMax;
      if (scale != 1.0) {
        working = img.copyResize(
          working,
          width: (working.width * scale).round(),
          height: (working.height * scale).round(),
          interpolation: img.Interpolation.cubic,
        );
      }
    } else {
      // Cap longest side at 2000 px — anything larger only slows ML Kit
      // without improving accuracy (its detection grid is fixed).
      if (origMax > 2000) {
        scale = 2000 / origMax;
        working = img.copyResize(
          working,
          width: (working.width * scale).round(),
          height: (working.height * scale).round(),
          interpolation: img.Interpolation.linear,
        );
      }
    }

    // All variants start grayscale (colour is noise for OCR).
    img.grayscale(working);

    switch (args.mode) {
      case _PreprocessMode.contrast:
        // Stretch dynamic range, boost contrast, sharpen edges. Best
        // for faded print + chalkboard.
        img.normalize(working, min: 0, max: 255);
        img.adjustColor(working, contrast: 1.5, saturation: 0);
        img.gaussianBlur(working, radius: 1);
        img.convolution(
          working,
          filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
          div: 1,
        );
      case _PreprocessMode.binarize:
        // Normalize → strong contrast → ADAPTIVE threshold. Local-mean
        // (Bradley) instead of a single global cut so a menu half in
        // shadow keeps its text instead of crushing to black.
        img.normalize(working, min: 0, max: 255);
        img.adjustColor(working, contrast: 1.3, saturation: 0);
        _bradleyThreshold(working);
      case _PreprocessMode.upscale:
        // Already upscaled. Normalize + a light unsharp so the cubic
        // interpolation's softening doesn't cost edge definition.
        img.normalize(working, min: 0, max: 255);
        img.convolution(
          working,
          filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
          div: 1,
        );
      case _PreprocessMode.fillOutline:
        // White-fill text with colored border on white background.
        // Both text and bg are white → normal threshold sees no text.
        // Strategy: detect the colored border (high saturation pixels),
        // dilate inward to fill letter interiors → solid dark text.
        img.normalize(working, min: 0, max: 255);
        // Step 1: mask — colored pixels (high saturation) → black,
        // everything else (gray/white) → white.
        for (var y = 0; y < working.height; y++) {
          for (var x = 0; x < working.width; x++) {
            final p = working.getPixel(x, y);
            final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
            final mx = math.max(r, math.max(g, b));
            final mn = math.min(r, math.min(g, b));
            final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
            working.setPixelRgb(x, y, sat > 0.25 ? 0 : 255, 0, 0);
          }
        }
        // Step 2: dilate black border pixels inward to fill letter body.
        _dilateDark(working, 6);
      case _PreprocessMode.binarizeBright:
        // White / light text. normalize + contrast, then the BRIGHT
        // adaptive threshold fills glyphs that are brighter than their
        // local surround (black-on-white for ML Kit). A lower t (0.08)
        // than the dark binarize makes it catch lower-contrast white-on-
        // light copy too. Single integral pass, so it is as fast as
        // binarize - it REPLACES the slower fillOutline pass.
        img.normalize(working, min: 0, max: 255);
        img.adjustColor(working, contrast: 1.4, saturation: 0);
        _bradleyThreshold(working, bright: true, t: 0.08);
    }

    final out = img.encodeJpg(working, quality: 92);
    File(args.outputPath).writeAsBytesSync(out);
    return scale;
  } catch (_) {
    return -1;
  }
}

/// Morphological dilation of dark regions using separable min-filter.
/// O(w*h*2*(2r+1)) — fast even on 1600 px images.
void _dilateDark(img.Image image, int radius) {
  final w = image.width;
  final h = image.height;
  if (w < 3 || h < 3) return;

  final buf = List<int>.filled(w * h, 255);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      buf[y * w + x] = image.getPixel(x, y).r.toInt();
    }
  }

  // Horizontal min-filter pass.
  final tmp = List<int>.filled(w * h, 255);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var mn = 255;
      final x0 = math.max(0, x - radius);
      final x1 = math.min(w - 1, x + radius);
      for (var xx = x0; xx <= x1; xx++) {
        final v = buf[y * w + xx];
        if (v < mn) mn = v;
      }
      tmp[y * w + x] = mn;
    }
  }

  // Vertical min-filter pass.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var mn = 255;
      final y0 = math.max(0, y - radius);
      final y1 = math.min(h - 1, y + radius);
      for (var yy = y0; yy <= y1; yy++) {
        final v = tmp[yy * w + x];
        if (v < mn) mn = v;
      }
      buf[y * w + x] = mn;
    }
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = buf[y * w + x];
      image.setPixelRgb(x, y, v, v, v);
    }
  }
}

/// Bradley-Roth adaptive threshold on a grayscale [img.Image] (in place).
///
/// Each pixel becomes black when its luminance is more than [t] percent
/// below the mean of the surrounding [windowFraction]-of-width window,
/// else white. The window mean is computed in O(1) per pixel via an
/// integral (summed-area) image, so the whole pass is O(w·h) - cheap
/// enough for an OCR preprocess even on a 2000 px image.
///
/// Adaptive thresholding beats a global cut on real captures because
/// lighting is rarely uniform: a single threshold either crushes the
/// shadowed side to solid black or blows the lit side to solid white,
/// erasing text either way. The local window tracks the gradient.
void _bradleyThreshold(
  img.Image image, {
  double windowFraction = 0.125,
  double t = 0.15,
  bool bright = false,
}) {
  final w = image.width;
  final h = image.height;
  if (w < 3 || h < 3) return;

  // Integral image of luminance (use red channel - already grayscale).
  // (w+1)*(h+1) with a zero border simplifies the area lookup.
  final integral = List<int>.filled((w + 1) * (h + 1), 0);
  for (var y = 0; y < h; y++) {
    var rowSum = 0;
    for (var x = 0; x < w; x++) {
      rowSum += image.getPixel(x, y).r.toInt();
      final above = integral[y * (w + 1) + (x + 1)];
      integral[(y + 1) * (w + 1) + (x + 1)] = above + rowSum;
    }
  }

  final half = math.max(1, (w * windowFraction / 2).round());
  final factor = 1.0 - t;

  for (var y = 0; y < h; y++) {
    final y1 = math.max(0, y - half);
    final y2 = math.min(h - 1, y + half);
    for (var x = 0; x < w; x++) {
      final x1 = math.max(0, x - half);
      final x2 = math.min(w - 1, x + half);
      final count = (x2 - x1 + 1) * (y2 - y1 + 1);
      // Summed-area lookup: A - B - C + D on the +1-offset integral.
      final sum = integral[(y2 + 1) * (w + 1) + (x2 + 1)] -
          integral[(y1) * (w + 1) + (x2 + 1)] -
          integral[(y2 + 1) * (w + 1) + (x1)] +
          integral[(y1) * (w + 1) + (x1)];
      final pixel = image.getPixel(x, y);
      final lum = pixel.r.toInt();
      // Dark text: pixel darker than local mean by t. Bright text (white
      // on a light/dark bg): the mirror - pixel BRIGHTER than local mean.
      // Same single integral pass, just the comparison flips.
      final isText = bright
          ? lum * count > sum * (1.0 + t)
          : lum * count < sum * factor;
      final v = isText ? 0 : 255;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
}

/// Isolate args for [_compressForVisionIsolate]. The max edge is now
/// per-call (scene-aware) instead of a fixed constant — see the
/// caller's `_maxEdgeForScene` switch for the per-scene values.
class _CompressArgs {
  _CompressArgs({required this.bytes, required this.maxEdge});
  final Uint8List bytes;
  final int maxEdge;
}

/// Isolate entry point: decode the captured JPEG, bake EXIF orientation into
/// pixels, downscale so the long edge is ≤ [args.maxEdge], re-encode JPEG
/// at quality 82. Returns null on failure so the caller can fall back to the
/// original bytes.
Uint8List? _compressForVisionIsolate(_CompressArgs args) {
  try {
    final decoded = img.decodeImage(args.bytes);
    if (decoded == null) return null;

    // Phone captures can carry an EXIF orientation tag instead of rotated
    // pixels; bake it in so the vision model sees an upright image. No-op
    // when orientation is already normal.
    var working = img.bakeOrientation(decoded);

    final maxSide =
        working.width > working.height ? working.width : working.height;
    if (maxSide > args.maxEdge) {
      final scale = args.maxEdge / maxSide;
      working = img.copyResize(
        working,
        width: (working.width * scale).round(),
        height: (working.height * scale).round(),
        // Area-averaging beats bilinear for DOWNSCALING text: it averages
        // every source pixel that maps into a target pixel, so thin glyph
        // strokes survive instead of aliasing into noise. Bilinear samples
        // only 4 neighbours and blurs small characters, which the vision
        // OCR then misreads — letting us keep the same legibility at a
        // smaller (cheaper) resolution.
        interpolation: img.Interpolation.average,
      );
    }

    return img.encodeJpg(working, quality: 82);
  } catch (_) {
    return null;
  }
}

/// Isolate args for [_rotateJpegFileIsolate]. A plain class instead of a
/// record because compute() requires top-level message types that
/// survive the isolate boundary, and Dart records currently can't
/// declare a public-name top-level type alias the way classes can.
class _RotateJpegArgs {
  _RotateJpegArgs({required this.path, required this.degrees});
  final String path;
  final int degrees;
}

/// Isolate entry: decode the JPEG at [args.path], rotate by
/// [args.degrees], re-encode at quality 92 (preserves OCR detail), and
/// write the rotated bytes back over the original path. Returns true on
/// success, false on any failure so the caller can decide whether to
/// surface or swallow. We don't throw because the camera capture must
/// not break just because orientation normalization couldn't run.
///
/// Quality 92: the file feeds BOTH ML Kit OCR (which is sensitive to
/// JPEG artifacts at low quality on small characters) AND the result
/// overlay's [Image.file] preview. The vision path re-encodes at q82
/// downstream after downscaling, so re-encoding here at 92 doesn't
/// fight that — the second pass operates on already-rotated pixels.
bool _rotateJpegFileIsolate(_RotateJpegArgs args) {
  try {
    final file = File(args.path);
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return false;
    // bakeOrientation first in case EXIF IS set (rare on the failing
    // captures but possible on the working ones); applying it before
    // our manual rotation keeps the two compatible.
    final baked = img.bakeOrientation(decoded);
    final rotated = img.copyRotate(baked, angle: args.degrees);
    final out = img.encodeJpg(rotated, quality: 92);
    file.writeAsBytesSync(out, flush: true);
    return true;
  } catch (_) {
    return false;
  }
}
