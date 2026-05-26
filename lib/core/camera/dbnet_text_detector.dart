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
///   1. Decode capture → resize so the longer side ≈ [_kTargetMaxSide]
///      and both sides are multiples of 32 (DBNet's stride constraint).
///   2. Normalise to ImageNet stats (mean / std) and emit a NHWC
///      Float32 tensor — TFLite preference after ONNX conversion.
///   3. Run inference. Output is a single-channel probability map
///      sized identically to the resized input.
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

  /// Resize so the longer image edge lands near this many pixels — the
  /// sweet spot between detection recall (more pixels = better) and
  /// inference latency (square-time in pixel count). 960 mirrors the
  /// recommended PaddleOCR mobile preset.
  static const int _kTargetMaxSide = 960;

  /// Probability above which a pixel is considered TEXT. 0.3 is the
  /// PaddleOCR-recommended default; raising trades recall for precision.
  static const double _kBinThreshold = 0.3;

  /// DBNet shrinks the training masks by an "unclip ratio" so the
  /// model learns a tight text region; at inference we expand the
  /// detected polygon back by the same ratio so the box reaches the
  /// actual glyph extents. 1.5 matches the published model config.
  static const double _kUnclipRatio = 1.5;

  /// Minimum connected-component pixel count to keep. Filters out
  /// salt-and-pepper noise from the binarisation step without dropping
  /// real glyphs (even a small CJK kana covers ≥ ~30 pixels at the
  /// 960-px resize).
  static const int _kMinRegionPixels = 24;

  Interpreter? _interpreter;
  bool _loadAttempted = false;

  bool get isAvailable => _interpreter != null;

  /// Try to load the model. Safe to call repeatedly: a successful load
  /// caches the interpreter; a missing-asset failure caches that too
  /// so we don't retry on every detect.
  Future<void> load() async {
    if (_loadAttempted) return;
    _loadAttempted = true;
    try {
      _interpreter = await Interpreter.fromAsset(modelAsset);
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

  // 1. Resize so the longer side ≈ targetMaxSide and both sides are
  //    multiples of 32 (DBNet stride). Track the scale to map boxes
  //    back to original image space at the end.
  final origMax = math.max(decoded.width, decoded.height);
  final ratio = args.targetMaxSide / origMax;
  final newW = ((decoded.width * ratio) / 32).round() * 32;
  final newH = ((decoded.height * ratio) / 32).round() * 32;
  final resized = img.copyResize(
    decoded,
    width: math.max(32, newW),
    height: math.max(32, newH),
    interpolation: img.Interpolation.linear,
  );
  final scaleBackX = decoded.width / resized.width;
  final scaleBackY = decoded.height / resized.height;

  // 2. Preprocess into NHWC Float32 with ImageNet mean/std normalisation
  //    — what the PaddleOCR detector expects.
  final input = Float32List(resized.width * resized.height * 3);
  const meanR = 0.485, meanG = 0.456, meanB = 0.406;
  const stdR = 0.229, stdG = 0.224, stdB = 0.225;
  var idx = 0;
  for (var y = 0; y < resized.height; y++) {
    for (var x = 0; x < resized.width; x++) {
      final p = resized.getPixel(x, y);
      input[idx++] = (p.r / 255.0 - meanR) / stdR;
      input[idx++] = (p.g / 255.0 - meanG) / stdG;
      input[idx++] = (p.b / 255.0 - meanB) / stdB;
    }
  }

  // 3. Run inference. Output is the probability map sized like input.
  //    Some conversions emit [1, H, W, 1] (NHWC) and some [1, 1, H, W]
  //    (NCHW) — we allocate by total element count and read in row-major
  //    order, which works for either layout after a flat reshape.
  final interpreter = Interpreter.fromAddress(args.interpreterAddress);
  final inputTensor = interpreter.getInputTensor(0);
  final outputTensor = interpreter.getOutputTensor(0);
  final outputShape = outputTensor.shape;
  final outputSize = outputShape.fold<int>(1, (a, b) => a * b);
  final output = Float32List(outputSize);
  interpreter.run(
    input.buffer.asFloat32List().reshape(inputTensor.shape),
    output.buffer.asFloat32List().reshape(outputShape),
  );

  // 4. Binarise + 5. connected components in a single pass. We pack the
  //    binary mask into a flat List<bool> for cache friendliness.
  final mapW = resized.width;
  final mapH = resized.height;
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

  // 6 + 7. Per-region axis-aligned bbox + score, unclip-expanded,
  //        scaled back to original image space.
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
    final l = (minX - padX).clamp(0, mapW - 1) * scaleBackX;
    final t = (minY - padY).clamp(0, mapH - 1) * scaleBackY;
    final r = (maxX + padX + 1).clamp(1, mapW) * scaleBackX;
    final b = (maxY + padY + 1).clamp(1, mapH) * scaleBackY;
    detections.add(DetectedRegion(Rect.fromLTRB(l, t, r, b), score));
  }
  return detections;
}
