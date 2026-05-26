import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:path_provider/path_provider.dart';

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

/// Text block with bounding box and OCR confidence from ML Kit.
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.boundingBox,
    this.confidence,
    this.bgColor,
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

  /// Return a copy with [bgColor] swapped — keeps the field final so
  /// the rest of the pipeline still treats blocks as immutable.
  OcrBlock copyWith({Color? bgColor}) => OcrBlock(
        text: text,
        boundingBox: boundingBox,
        confidence: confidence,
        bgColor: bgColor ?? this.bgColor,
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
    final back = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    _controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller!.initialize();
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
  }) async {
    // Menu + screenshot expect ONE OcrBlock per LINE (one dish row, one
    // UI label / chat message), not per ML Kit "block" (which can bundle
    // adjacent rows into a single multi-line group). Aggregate scenes
    // (document / sign / auto) collapse everything later so block-level
    // is fine and slightly faster.
    final perLine = scene == 'menu' || scene == 'screenshot';
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
    final originalFuture = autoDetect
        ? _recognizeAuto(imagePath, perLine: perLine)
        : _recognizeWithScript(imagePath, TextRecognitionScript.latin,
            perLine: perLine);
    if (!aggressivePasses) {
      // Fast path: single pass. If result is empty the caller falls back
      // to the vision LLM, so we don't lose the difficult-image case.
      final result = await originalFuture;
      final deduped = _dedupeAndFilter(result);
      return _mergeForScene(deduped, scene);
    }
    final contrastFuture = _preprocessAndRecognize(
        imagePath, _PreprocessMode.contrast,
        perLine: perLine, autoDetect: autoDetect);
    final binarizeFuture = _preprocessAndRecognize(
        imagePath, _PreprocessMode.binarize,
        perLine: perLine, autoDetect: autoDetect);
    // 4th pass: upscaled copy to recover fine print (menu address,
    // footnotes) that ML Kit's detector skips at native resolution.
    // Runs in parallel so it adds isolate CPU, not wall-clock latency.
    final upscaleFuture = _preprocessAndRecognize(
        imagePath, _PreprocessMode.upscale,
        perLine: perLine, autoDetect: autoDetect);

    final results = await Future.wait(
        [originalFuture, contrastFuture, binarizeFuture, upscaleFuture]);
    final merged = <OcrBlock>[
      ...results[0],
      ...results[1],
      ...results[2],
      ...results[3],
    ];

    // OPTIONAL safety-net pass: DBNet (PaddleOCR) detector for regions
    // ML Kit missed. Only fires when the TFLite model is bundled; in
    // that case we ask DBNet for every text region in the capture, drop
    // any that already overlap an ML Kit block, and recognise just the
    // uncovered ones with ML Kit on a per-crop call. Vision LLM still
    // owns the truly-difficult fallback path — this tier catches
    // cheap-to-fix ML Kit misses without a network round-trip.
    final dbnetExtras = await _dbnetFillIn(imagePath, merged);
    merged.addAll(dbnetExtras);

    final deduped = _dedupeAndFilter(merged);
    return _mergeForScene(deduped, scene);
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
        final filtered = _filterMenuMetadata(blocks)
            .where((b) => !_isMenuNoise(b.text))
            .toList();
        final merged = _mergeSameLine(filtered, hGapMultiplier: 1.2);
        return merged
            .map((block) {
              final stripped = _stripTrailingPrice(block.text);
              if (stripped == block.text) return block;
              return OcrBlock(
                text: stripped,
                boundingBox: block.boundingBox,
                confidence: block.confidence,
              );
            })
            // After stripping prices, re-run the noise filter on the result
            // in case the "dish" was actually "65k" hiding behind a token
            // the first pass didn't catch.
            .where((block) =>
                block.text.trim().isNotEmpty && !_isMenuNoise(block.text))
            .toList();

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
        return _mergeParagraph(
          _mergeSameLine(blocks, hGapMultiplier: 1.2),
          vGapMultiplier: 0.9,
          hOverlapRatio: 0.4,
          heightRatioMin: 0.8,
          heightRatioMax: 1.3,
        );

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
  }) async {
    try {
      final processed = await _writePreprocessedImage(imagePath, mode);
      if (processed == null) return const [];
      final (processedPath, scale) = processed;
      try {
        // CJK menus: the preprocess passes used to run Latin-only, so on a
        // Japanese / Chinese / Korean capture they produced garbage that
        // the content filter dropped - leaving recall at effectively one
        // (the original auto pass). Running the multi-script auto detector
        // here lets contrast / binarize / upscale each contribute real
        // CJK reads, which is the dominant recall win on dense menus.
        final blocks = autoDetect
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

  /// Heavy CPU work — runs in an isolate via [compute] so the UI thread
  /// stays responsive while the JPEG is decoded, filtered, and re-encoded.
  /// Returns the output path AND the resize scale (processed ÷ original
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

  /// Drop OCR blocks that are pure menu metadata — prices, phone
  /// numbers, opening hours, "delivery + phone" service lines. These
  /// are already visible on the original photo so translating them is
  /// noise (clutters overlay + wastes LLM tokens). The user only cares
  /// about dish NAMES and dish DESCRIPTIONS — those pass through.
  ///
  /// Patterns are deliberately conservative — they must match the
  /// ENTIRE trimmed text. A block containing a price PLUS a dish name
  /// (e.g. "Phở bò 65k") doesn't match the pure-price pattern and is
  /// kept; the server prompt then strips the price from the translation
  /// output. Standalone metadata is dropped here.
  List<OcrBlock> _filterMenuMetadata(List<OcrBlock> blocks) {
    return blocks.where((block) => !_isMenuMetadata(block.text)).toList();
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
    'jpy', 'krw', 'twd', 'hkd', 'cny', 'rmb', '¥', '₩', '元',
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
    r'''(?:rp\.?|rm|hk\$|s\$|nt\$|us\$|[\$€¥£₫đ₩₹฿])\s*[\d.,]+'''  // currency-prefixed: "Rp. 15.000", "$12"
    r'''|[\d]+[.,][\d]{3}(?:[.,][\d]{3})*\s*(?:[kK]|đ|₫|vnd|usd|idr|rp|rm)?'''  // thousands: "15.000", "15,000"
    r'''|[\d.,]+\s*[kK]\b'''                            // k-suffix: "65k", "1.5k"
    r'''|[\d]{4,}\s*(?:đ|₫|vnd|usd|idr|rp|rm)?'''       // 4+ bare digits: "15000"
    r'''|[\d.,]+\s*(?:đ|₫|vnd|usd|eur|jpy|krw|thb|idr|myr|php|inr|sgd)\b'''  // suffix code: "25 VND"
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
  /// Scene-tuned via [hGapMultiplier]: menu rows pass 3.0 to catch dish
  /// names separated from prices by leader dots / wide whitespace;
  /// document/screenshot pass 1.2 for tight prose.
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
    }

    final out = img.encodeJpg(working, quality: 92);
    File(args.outputPath).writeAsBytesSync(out);
    return scale;
  } catch (_) {
    return -1;
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
      final isText = lum * count < sum * factor;
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
