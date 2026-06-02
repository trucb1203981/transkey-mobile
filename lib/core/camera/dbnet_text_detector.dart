import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// One text region returned by [DbnetTextDetector]. Axis-aligned for v1
/// (rotated min-area rect can come later if menu captures need it).
/// [score] is the average probability over the binarised region — higher
/// = more confident the polygon really contains text.
class DetectedRegion {
  const DetectedRegion(this.box, this.score);
  final Rect box;
  final double score;
}

/// DBNet (Differentiable Binarization) text detector running on TFLite.
///
/// Targets the PaddleOCR `ch_PP-OCRv4_det` mobile model converted to
/// TFLite (PaddleLite → ONNX → TFLite — see docs/dbnet-conversion.md).
/// That model carries strong CJK + Latin recall and is the practical
/// answer when ML Kit misses lines on dense menus / stylised signs.
///
/// ## Pipeline
///
///   1. Decode capture → LETTERBOX into a fixed [_kTargetMaxSide] square:
///      scale the long edge to the model side preserving aspect, centre,
///      pad the remainder black. The bundled model has a FIXED input, so
///      we cannot feed an arbitrary aspect-preserving frame.
///   2. Normalise to ImageNet stats (mean / std) and emit a NHWC
///      Float32 tensor — TFLite preference after ONNX conversion.
///   3. Run inference. Output is a single-channel probability map the same
///      size as the letterboxed square.
///   4. Threshold at [_kBinThreshold] → binary mask.
///   5. 4-connected component labelling → pixel sets per region.
///   6. Per region: axis-aligned bbox + average probability score,
///      expanded by [_kUnclipRatio] (DBNet shrinks text masks during
///      training; we need to grow the box back to glyph extents).
///   7. Scale boxes back from resized-image space → original capture
///      space so the overlay can render them directly.
///
/// ## Lifecycle
///
/// Single instance per camera session; [load] is cheap on a hit (the
/// TFLite asset is mapped, not copied), so on first use ~80-150 ms,
/// thereafter inference itself dominates (~150-300 ms on a Snapdragon
/// 7+ Gen 2 for 960 × 720 input).
///
/// ## Graceful degradation
///
/// When the model asset isn't bundled (initial deploys, debug builds),
/// [load] catches the asset-missing exception and leaves [isAvailable]
/// false. [detect] then returns an empty list and the camera service
/// falls through to the existing ML Kit 4-pass pipeline. No runtime
/// surprises for users on devices that don't yet have the model.
class DbnetTextDetector {
  DbnetTextDetector({this.modelAsset = _kDefaultAsset});

  /// Default asset path the conversion guide places the converted
  /// PaddleOCR model at. Override for A/B-testing alternative models.
  final String modelAsset;

  static const String _kDefaultAsset = 'assets/models/dbnet_paddleocr.tflite';

  /// The bundled model's FIXED input side. The capture is letterboxed into
  /// a [_kTargetMaxSide]×[_kTargetMaxSide] square before inference. This
  /// MUST match the converted model's static input (see
  /// docs/dbnet-conversion.md). Dropped from 960 to 640 because on a
  /// mid-range phone 960² inference was ~4.5 s (CPU); 640² is ~2× cheaper
  /// and still detects manga / menu text well (text is large enough).
  // 640 (not 960): 960^2 inference is ~2.25x heavier and, in the parallel
  // batch path (_runBatchParallelVision fires all pages concurrently), the
  // concurrent 960 interpreters exhaust device memory/CPU and HANG the app
  // mid-batch (verified: app froze on the 3rd of 4 pages). 640 keeps each
  // inference ~2s and the batch stable; recall gaps are filled by the
  // empty-bubble OCR pass + vision fallback instead.
  static const int _kTargetMaxSide = 640;

  /// Probability above which a pixel is considered TEXT. PaddleOCR's
  /// default is 0.3, but at our 640-px input small / faint manga text
  /// (top-row bubbles, sound-effect kana) produces a weak probability
  /// map and gets dropped, so the manga page comes back with whole
  /// bubbles untranslated. 0.2 recovers them; the downstream OCR >= 2
  /// meaningful-char floor + area-cap grouping discard the extra noise.
  static const double _kBinThreshold = 0.2;

  /// DBNet shrinks the training masks by an "unclip ratio" so the
  /// model learns a tight text region; at inference we expand the
  /// detected polygon back by the same ratio so the box reaches the
  /// actual glyph extents. 1.5 matches the published model config.
  static const double _kUnclipRatio = 1.5;

  /// Minimum connected-component pixel count to keep. Filters out
  /// salt-and-pepper noise from the binarisation step without dropping
  /// real glyphs. Scales with the square of the input side; 10 is tuned
  /// for the 640-px input (the original 24 was a 960-px value that
  /// silently dropped small text once we moved to 640).
  static const int _kMinRegionPixels = 10;

  Interpreter? _interpreter;
  bool _loadAttempted = false;

  /// tflite's `Interpreter.run()` is NOT thread-safe. The manga batch path
  /// (`_runBatchParallelVision`) fires several `detect()` calls concurrently
  /// - one per page - and every call runs `_runIsolate` against the SAME
  /// native interpreter (shared via `Interpreter.fromAddress`). Concurrent
  /// `run()` on one interpreter HANGS / corrupts the app (verified: a 5-page
  /// batch froze on the 3rd-4th page). This tail future serialises detect()
  /// so only one inference is ever in flight.
  Future<void> _inferTail = Future<void>.value();

  bool get isAvailable => _interpreter != null;

  /// Try to load the model. Safe to call repeatedly: a successful load
  /// caches the interpreter; a missing-asset failure caches that too
  /// so we don't retry on every detect.
  Future<void> load() async {
    if (_loadAttempted) return;
    _loadAttempted = true;
    try {
      // Multi-threaded CPU (XNNPACK) inference. The conv-heavy DBNet ran
      // ~4.5 s single-threaded at 960² on a mid-range phone; threads + the
      // smaller 640² input cut that by several×.
      _interpreter = await Interpreter.fromAsset(
        modelAsset,
        options: InterpreterOptions()..threads = 4,
      );
      debugPrint('[DbnetTextDetector] model loaded: $modelAsset');
    } catch (e) {
      _interpreter = null;
      debugPrint(
          '[DbnetTextDetector] model not available ($modelAsset): $e — '
          'falling through to ML Kit');
    }
  }

  /// Run detection on [imagePath]. Returns axis-aligned boxes in the
  /// ORIGINAL image's pixel coordinates. Empty when the model isn't
  /// loaded — the caller should then route to its fallback detector.
  Future<List<DetectedRegion>> detect(String imagePath) async {
    await load();
    final interpreter = _interpreter;
    if (interpreter == null) return const [];
    // Serialise: chain onto the previous inference so concurrent batch
    // pages never call run() on the shared interpreter at the same time.
    final prev = _inferTail;
    final gate = Completer<void>();
    _inferTail = gate.future;
    try {
      await prev;
    } catch (_) {
      // A prior inference's failure must not wedge the queue.
    }
    try {
      return await compute(_runIsolate, _DbnetArgs(
        imagePath: imagePath,
        interpreterAddress: interpreter.address,
        targetMaxSide: _kTargetMaxSide,
        binThreshold: _kBinThreshold,
        unclipRatio: _kUnclipRatio,
        minRegionPixels: _kMinRegionPixels,
      ));
    } catch (e) {
      debugPrint('[DbnetTextDetector] detect failed: $e');
      return const [];
    } finally {
      gate.complete();
    }
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _loadAttempted = false;
  }
}

class _DbnetArgs {
  _DbnetArgs({
    required this.imagePath,
    required this.interpreterAddress,
    required this.targetMaxSide,
    required this.binThreshold,
    required this.unclipRatio,
    required this.minRegionPixels,
  });
  final String imagePath;
  final int interpreterAddress;
  final int targetMaxSide;
  final double binThreshold;
  final double unclipRatio;
  final int minRegionPixels;
}

/// Isolate entry — keeps the 100-500 ms CPU off the UI thread. Reuses
/// the interpreter by address (the TFLite C++ object stays in the main
/// isolate's memory, the worker just calls run() on it).
List<DetectedRegion> _runIsolate(_DbnetArgs args) {
  final bytes = File(args.imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const [];
  final sw = Stopwatch()..start();

  // 1. LETTERBOX into a fixed target×target canvas. The bundled DBNet
  //    model has a FIXED 1×960×960×3 input: dynamic-shape conversions bake
  //    the internal FPN resize ops to wrong sizes (verified — non-960 input
  //    produces a broadcast-shape crash), so we cannot feed an
  //    aspect-preserving multiple-of-32 frame like a dynamic model. Instead
  //    scale the long edge to `target` preserving aspect, centre it, and
  //    pad the rest black. Box coords are mapped back through the same
  //    scale + pad offset at the end. `target` MUST equal the model's fixed
  //    input side (see [_kTargetMaxSide]).
  final target = args.targetMaxSide;
  final scale = target / math.max(decoded.width, decoded.height);
  final nw = (decoded.width * scale).round().clamp(1, target);
  final nh = (decoded.height * scale).round().clamp(1, target);
  final resized = img.copyResize(
    decoded,
    width: nw,
    height: nh,
    interpolation: img.Interpolation.linear,
  );
  final padLeft = (target - nw) ~/ 2;
  final padTop = (target - nh) ~/ 2;

  // 2. Preprocess into the fixed NHWC target×target×3 Float32 tensor with
  //    ImageNet mean/std normalisation (what PaddleOCR det expects). Pixels
  //    outside the letterboxed content stay black (0).
  // Read the resized image as ONE flat RGB byte buffer. getPixel() per
  // pixel goes through the image package's iterator and is ~100× slower —
  // over 921 600 px (960²) that was a big chunk of the on-device latency.
  final rgb = resized.getBytes(order: img.ChannelOrder.rgb);
  final input = Float32List(target * target * 3);
  const meanR = 0.485, meanG = 0.456, meanB = 0.406;
  const stdR = 0.229, stdG = 0.224, stdB = 0.225;
  var idx = 0;
  for (var y = 0; y < target; y++) {
    final sy = y - padTop;
    final inRow = sy >= 0 && sy < nh;
    for (var x = 0; x < target; x++) {
      final sx = x - padLeft;
      double r = 0, g = 0, b = 0;
      if (inRow && sx >= 0 && sx < nw) {
        final o = (sy * nw + sx) * 3;
        r = rgb[o].toDouble();
        g = rgb[o + 1].toDouble();
        b = rgb[o + 2].toDouble();
      }
      input[idx++] = (r / 255.0 - meanR) / stdR;
      input[idx++] = (g / 255.0 - meanG) / stdG;
      input[idx++] = (b / 255.0 - meanB) / stdB;
    }
  }

  final tPre = sw.elapsedMilliseconds;

  // 3. Run inference. Output is the target×target single-channel
  //    probability map, read row-major (works for [1,H,W,1] NHWC after a
  //    flat reshape).
  final interpreter = Interpreter.fromAddress(args.interpreterAddress);
  // A fromAddress wrapper in this worker isolate does NOT inherit the
  // "allocated" flag the main isolate set, so invoke() / tensor .data throw
  // "Interpreter not allocated". allocateTensors() here sets it up; the model
  // is fixed-shape so this is idempotent on the shared native interpreter,
  // and detect() is serialised so no other isolate touches it concurrently.
  interpreter.allocateTensors();
  final inputTensor = interpreter.getInputTensor(0);
  final outputTensor = interpreter.getOutputTensor(0);
  final outputShape = outputTensor.shape;
  final outputSize = outputShape.fold<int>(1, (a, b) => a * b);
  // Low-level inference path (weak-device optimisation). The high-level
  // run() needs Dart objects shaped to the tensors, and List.reshape() builds
  // a DEEP nested list of boxed doubles for BOTH the input ([1,640,640,3] ~
  // 1.2M) and output ([1,640,640,1] ~ 410k) on EVERY call, plus a 410k-element
  // copy loop to flatten the output. That per-call allocation made inference
  // time creep up across a batch and is exactly what GC-thrashes a low-end
  // phone. Instead: write the input bytes straight into the native input
  // tensor, invoke(), and read the native output buffer as a flat Float32List
  // - zero nested lists, zero copy loop.
  //
  // (The old comment warned a "flat-buffer read returned zeros"; that was a
  // different mistake - passing a flat list to run(), which writes into the
  // passed Dart object, not the native buffer. Reading outputTensor.data
  // AFTER invoke() reads the native buffer the model actually wrote.)
  inputTensor.data = input.buffer.asUint8List();
  interpreter.invoke();
  final outBytes = outputTensor.data;
  final output =
      outBytes.buffer.asFloat32List(outBytes.offsetInBytes, outputSize);

  final tInf = sw.elapsedMilliseconds;

  // 4. Binarise + 5. connected components on the target×target map.
  final mapW = target;
  final mapH = target;
  final binary = List<bool>.filled(mapW * mapH, false);
  for (var i = 0; i < binary.length; i++) {
    binary[i] = output[i] > args.binThreshold;
  }
  final visited = List<bool>.filled(mapW * mapH, false);
  final regions = <List<int>>[]; // packed pixel indices per region
  final stack = <int>[];
  for (var seed = 0; seed < binary.length; seed++) {
    if (!binary[seed] || visited[seed]) continue;
    stack.clear();
    stack.add(seed);
    final region = <int>[];
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      if (visited[p] || !binary[p]) continue;
      visited[p] = true;
      region.add(p);
      final x = p % mapW;
      final y = p ~/ mapW;
      if (x + 1 < mapW) stack.add(p + 1);
      if (x - 1 >= 0) stack.add(p - 1);
      if (y + 1 < mapH) stack.add(p + mapW);
      if (y - 1 >= 0) stack.add(p - mapW);
    }
    if (region.length >= args.minRegionPixels) regions.add(region);
  }

  // 6 + 7. Per-region bbox + score, unclip-expanded in letterbox space,
  //        then mapped back to ORIGINAL image coords by undoing the
  //        letterbox (subtract pad offset, divide by scale).
  final origW = decoded.width.toDouble();
  final origH = decoded.height.toDouble();
  double toOrigX(num v) => ((v - padLeft) / scale).clamp(0.0, origW);
  double toOrigY(num v) => ((v - padTop) / scale).clamp(0.0, origH);
  final detections = <DetectedRegion>[];
  for (final region in regions) {
    var minX = mapW, minY = mapH, maxX = 0, maxY = 0;
    var sumScore = 0.0;
    for (final p in region) {
      final x = p % mapW;
      final y = p ~/ mapW;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      sumScore += output[p];
    }
    final score = sumScore / region.length;
    // Unclip expansion — grow the tight DBNet box back to glyph extents.
    final boxW = (maxX - minX + 1);
    final boxH = (maxY - minY + 1);
    final padX = (boxW * (args.unclipRatio - 1) / 2).round();
    final padY = (boxH * (args.unclipRatio - 1) / 2).round();
    final l = toOrigX((minX - padX).clamp(0, mapW - 1));
    final t = toOrigY((minY - padY).clamp(0, mapH - 1));
    final r = toOrigX((maxX + padX + 1).clamp(1, mapW));
    final b = toOrigY((maxY + padY + 1).clamp(1, mapH));
    detections.add(DetectedRegion(Rect.fromLTRB(l, t, r, b), score));
  }
  debugPrint('[DBNet] img=${decoded.width}x${decoded.height} '
      'pre=${tPre}ms inf=${tInf - tPre}ms cc+map=${sw.elapsedMilliseconds - tInf}ms '
      'total=${sw.elapsedMilliseconds}ms regions=${detections.length}');
  return detections;
}
