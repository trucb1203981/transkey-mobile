import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

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
  });

  final String text;
  final Rect boundingBox;

  /// Average confidence across all lines (Android only, null on iOS).
  final double? confidence;

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
  /// is expensive), closed in [stopTextStream]. Running all scripts is what
  /// lets the live preview detect CJK, not just Latin.
  final List<TextRecognizer> _streamRecognizers = [];

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
  Future<String> captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw StateError('Camera not initialised');
    }
    if (_isStreaming) await stopTextStream();
    final xFile = await _controller!.takePicture();
    return xFile.path;
  }

  /// Downscale + re-encode a captured JPEG before it's base64'd and POSTed
  /// to the vision LLM. A full-res capture (several MB) costs more vision
  /// input tokens and uploads slower over mobile data without reading signs
  /// or menus any better — vision OCR is fine at ~1600 px. Caps the long
  /// edge at 1600 px and re-encodes at quality 82 (≈250-450 KB). Runs in an
  /// isolate (decode/resize is CPU-heavy). Returns the original bytes on any
  /// failure so capture never breaks because of compression.
  Future<Uint8List> compressForVision(Uint8List bytes) async {
    try {
      final out = await compute(_compressForVisionIsolate, bytes);
      return out ?? bytes;
    } catch (_) {
      return bytes;
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
  Future<void> startTextStream(
    void Function(List<OcrBlock> blocks) onBlocks,
  ) async {
    if (_controller == null || _isStreaming) return;
    _isStreaming = true;
    _isProcessing = false;

    // Spin up one recognizer per script so the live preview detects CJK +
    // Latin (and Devanagari), not just Latin. Reused across frames.
    if (_streamRecognizers.isEmpty) {
      _streamRecognizers.addAll(
        TextRecognitionScript.values.map((s) => TextRecognizer(script: s)),
      );
    }

    await _controller!.startImageStream((image) async {
      if (!_isStreaming || _isProcessing) return;

      final now = DateTime.now();
      if (now.difference(_lastOcrTime) < _ocrInterval) return;

      _isProcessing = true;
      _lastOcrTime = now;

      try {
        final inputImage = _cameraImageToInputImage(image);
        // Fan out to every script recognizer, keep the one that read the
        // most characters — same "pick best script" heuristic the capture
        // path uses. This is what surfaces CJK boxes in the live overlay.
        final results = await Future.wait(_streamRecognizers.map((recognizer) async {
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

  /// Stop the live camera stream + release the per-script recognizers.
  Future<void> stopTextStream() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      await _controller?.stopImageStream();
    } catch (_) {}
    for (final recognizer in _streamRecognizers) {
      try {
        recognizer.close();
      } catch (_) {}
    }
    _streamRecognizers.clear();
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
        perLine: perLine);
    final binarizeFuture = _preprocessAndRecognize(
        imagePath, _PreprocessMode.binarize,
        perLine: perLine);

    final results =
        await Future.wait([originalFuture, contrastFuture, binarizeFuture]);
    final merged = <OcrBlock>[...results[0], ...results[1], ...results[2]];
    final deduped = _dedupeAndFilter(merged);
    return _mergeForScene(deduped, scene);
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
  Future<List<OcrBlock>> _preprocessAndRecognize(
    String imagePath,
    _PreprocessMode mode, {
    bool perLine = false,
  }) async {
    try {
      final processedPath = await _writePreprocessedImage(imagePath, mode);
      if (processedPath == null) return const [];
      try {
        return await _recognizeWithScript(
          processedPath,
          TextRecognitionScript.latin,
          perLine: perLine,
        );
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
  Future<String?> _writePreprocessedImage(
    String imagePath,
    _PreprocessMode mode,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/ocr_${mode.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ok = await compute(_runPreprocessIsolate, _PreprocessArgs(
      inputPath: imagePath,
      outputPath: outputPath,
      mode: mode,
    ));
    return ok ? outputPath : null;
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
    final filtered = blocks.where(_isMeaningful).toList();

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
      final isDup = kept.any((other) {
        final iou = _iou(block.boundingBox, other.boundingBox);
        final otherNorm = _normalizeForDedupe(other.text);
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

    // Restore reading order (top-to-bottom, left-to-right). Pixel delta —
    // NOT compareTo — so the 12 px row-grouping tolerance actually fires.
    // The earlier compareTo version collapsed everything into "same row"
    // because compareTo only returns ±1, never > 12.
    kept.sort((a, b) {
      final dy = a.boundingBox.top - b.boundingBox.top;
      if (dy.abs() > 12) return dy < 0 ? -1 : 1;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });
    return kept;
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
    for (final recognizer in _streamRecognizers) {
      try {
        recognizer.close();
      } catch (_) {}
    }
    _streamRecognizers.clear();
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

  /// Grayscale → contrast → luminance threshold (pure black/white).
  /// Recovers BOLD stylized display fonts (sign lettering, neon, 3D
  /// text) where colour gradients and anti-aliasing confuse the OCR
  /// detector. Binarization collapses the gradient to a crisp edge.
  binarize,
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
/// thread. Returns true when the output file was written.
///
/// We deliberately do NOT invert the image: ML Kit handles white-on-black
/// chalkboards fine once contrast is boosted; inverting also broke colour
/// printed documents we saw in production.
bool _runPreprocessIsolate(_PreprocessArgs args) {
  try {
    final bytes = File(args.inputPath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return false;

    // Cap longest side at 2000 px — anything larger only slows ML Kit
    // without improving accuracy (its detection grid is fixed).
    var working = decoded;
    final maxSide = working.width > working.height ? working.width : working.height;
    if (maxSide > 2000) {
      final scale = 2000 / maxSide;
      working = img.copyResize(
        working,
        width: (working.width * scale).round(),
        height: (working.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    // Both variants start grayscale (colour is noise for OCR).
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
        // Normalize → strong contrast → threshold to black/white. The
        // threshold collapses anti-aliased stylized strokes into crisp
        // shapes ML Kit's detector locks onto more reliably.
        img.normalize(working, min: 0, max: 255);
        img.adjustColor(working, contrast: 1.3, saturation: 0);
        img.luminanceThreshold(working, threshold: 0.5);
    }

    final out = img.encodeJpg(working, quality: 92);
    File(args.outputPath).writeAsBytesSync(out);
    return true;
  } catch (_) {
    return false;
  }
}

/// Long-edge cap for the vision upload. 1600 px keeps small menu text legible
/// while bounding payload + vision token cost. (OCR-mode captures don't go
/// through here — they OCR on-device and only the text is uploaded.)
const int _visionMaxEdge = 1600;

/// Isolate entry point: decode the captured JPEG, bake EXIF orientation into
/// pixels, downscale so the long edge is ≤ [_visionMaxEdge], re-encode JPEG
/// at quality 82. Returns null on failure so the caller can fall back to the
/// original bytes.
Uint8List? _compressForVisionIsolate(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Phone captures can carry an EXIF orientation tag instead of rotated
    // pixels; bake it in so the vision model sees an upright image. No-op
    // when orientation is already normal.
    var working = img.bakeOrientation(decoded);

    final maxSide =
        working.width > working.height ? working.width : working.height;
    if (maxSide > _visionMaxEdge) {
      final scale = _visionMaxEdge / maxSide;
      working = img.copyResize(
        working,
        width: (working.width * scale).round(),
        height: (working.height * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }

    return img.encodeJpg(working, quality: 82);
  } catch (_) {
    return null;
  }
}
