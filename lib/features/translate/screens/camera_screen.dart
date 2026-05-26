import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/auth/session_store.dart';
import '../../../core/camera/camera_service.dart';
import '../../../core/camera/text_tracker.dart';
import '../../../core/tracking/tracking_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../../translate/providers/camera_settings_provider.dart';
import '../../translate/providers/features_provider.dart';
import '../../translate/providers/language_settings_provider.dart';
import '../services/translation_cache.dart';
import '../widgets/block_action_sheet.dart';
import '../widgets/camera_live_overlay.dart';
import '../widgets/camera_result_overlay.dart';
import '../widgets/camera_settings_sheet.dart';
import '../widgets/camera_tips_sheet.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/scene_picker_row.dart';
import '../widgets/what_is_this_sheet.dart';

enum _CameraStep { preview, translating, result }

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  final _cameraService = CameraService();
  _CameraStep _step = _CameraStep.preview;
  bool _flashOn = false;

  String? _capturedPath;
  ui.Size? _capturedImageSize;
  List<OcrBlock> _liveBlocks = [];
  List<OcrBlock> _blocks = [];

  /// SORT-style Kalman tracker for the live overlay. Detector boxes go
  /// in raw; smoothed, identity-stable boxes come out. See [TextTracker].
  final _liveTracker = TextTracker();
  List<String> _translations = [];

  /// Tracks the InteractiveViewer's transform so we can flip pan on/off
  /// based on the current zoom level - pan stays disabled at scale=1
  /// (preserves card drag-to-trash) and turns on once the user has
  /// pinched in, so they can drag around the magnified menu.
  final TransformationController _zoomController = TransformationController();

  /// Cache of /split-block results keyed by the block's source text.
  /// A repeat long-press on the same card (same OCR output) reuses the
  /// result instead of paying for another LLM call. Text-keyed (not
  /// index-keyed) so a fresh capture with different blocks at the same
  /// indices doesn't accidentally hit stale data.
  final Map<String, List<OcrBlockItem>> _splitCache =
      <String, List<OcrBlockItem>>{};
  String? _error;

  /// Block indices still waiting for their server translation. Cards at
  /// these indices show a marching-ants dashed border.
  Set<int> _pendingIndices = {};

  /// Drives the result overlay's card visibility + reset from the action
  /// bar so the eye / reset buttons sit in the same row as Copy all
  /// instead of floating over the photo.
  final _overlayController = CameraResultOverlayController();

  /// Server's self-assessed quality for the current vision capture
  /// ("high" | "medium" | "low"), or null when the result came from ML
  /// Kit OCR (which has per-block confidence already surfaced on each
  /// card). The result screen renders a top-left chip when non-null so
  /// the user always knows whether to trust the AI read — critical
  /// for the sign scene (a misread STOP sign isn't a small UX issue).
  String? _visionConfidence;

  /// Server's guess at what the image actually is ("menu" / "sign" /
  /// "document" / "screenshot" / "other"), independent of the scene the
  /// user pre-selected. Surfaced as a small "Detected: …" chip below
  /// the confidence chip — but only when the user-selected scene is
  /// `auto`, otherwise the chip is redundant noise (they already know
  /// what they picked).
  String? _detectedScene;

  /// Server-detected source language for the current capture (ISO 639-1
  /// 2-letter code, lowercase). Vision path: the LLM returns it as part
  /// of the /translate-image JSON. ML Kit path: /translate-batch
  /// derives it from the input text via script-class detection. Used
  /// by the per-block action sheet to drive a TTS playback button —
  /// without this the speaker would default to English even on a CJK
  /// menu, picking the wrong accent silently.
  String? _captureSourceLang;

  /// True when the result screen should render the "Detected: …" chip.
  /// Gated by the user's active scene being `auto` so we only surface
  /// the AI's guess in the case the user actually delegated detection
  /// to it. When `_detectedScene` is "other" we also hide — that label
  /// tells the user nothing they can act on.
  bool get _showDetectedSceneChip {
    if (_detectedScene == null || _detectedScene == 'other') return false;
    final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
        CameraScene.auto;
    return scene == CameraScene.auto;
  }

  // Pinch-to-zoom — pinned to the camera service's clamped range.
  // [_zoomBaseline] is the zoom level at the start of a scale gesture so
  // we can compute the new level as baseline * gesture.scale.
  double _zoom = 1.0;
  double _zoomBaseline = 1.0;

  // Tap-to-focus — [_focusRingPos] is the tap location in preview-view
  // coordinates (null = ring hidden); [_focusResetTimer] returns the camera
  // to continuous AF a few seconds after the tap.
  Offset? _focusRingPos;
  Timer? _focusResetTimer;

  // Blur overlay state. CameraService fires onBlurChange on every
  // sharp↔blurry edge; we debounce only the "blurry → show overlay"
  // direction (500 ms) so quick motion glitches don't flicker the
  // hint, while the "sharp → hide overlay" direction is immediate
  // (no reason to keep nagging once the user has steadied).
  bool _isBlurry = false;
  Timer? _blurDebounce;

  /// Live focus quality 0-100 from the Laplacian-variance meter. Drives
  /// the sharpness pill above the shutter so the user knows WHEN the
  /// frame is crisp enough to capture instead of firing the instant the
  /// camera opens (before autofocus settles). 60+ = green/ready.
  double _sharpness = 0;

  /// "Ready" line: at/above this the shutter shows green and capture is
  /// encouraged. Mirrors the service's 60% anchor for [_blurThreshold].
  static const double _kSharpReady = 60;

  /// Anchors the RepaintBoundary that wraps the result body so the
  /// Share action can rasterise it to a PNG without dragging the
  /// rest of the Scaffold (top bar, action chips) into the
  /// screenshot. Set on the inner sub-tree, not on _buildResult
  /// itself, so the boundary is created once per capture and
  /// re-rendered cheaply when state inside it changes.
  final GlobalKey _resultRepaintKey = GlobalKey();

  /// Snapshots of all captures in the current gallery-batch flow. In
  /// single-capture mode this stays a 1-element list mirroring the
  /// active singletons (`_capturedPath`, `_blocks`, etc.) — the
  /// arrow nav at the top of the result screen only renders when
  /// length > 1. Each entry is a frozen copy of the per-capture
  /// state we restore into the singletons on prev/next swap.
  final List<_BatchSnapshot> _batchQueue = [];
  int _activeBatchIndex = 0;

  /// True while [_pickFromGallery] is processing a multi-pick batch.
  /// Used by [_processImage] / [_translateAndShow] / [_captureWithVision]
  /// to suppress the `_step = _CameraStep.result` transition between
  /// images — we want to stay on the translating spinner all the way
  /// through the batch and only flip to result once the FIRST image's
  /// snapshot is restored.
  bool _isBatchProcessing = false;
  int _batchTotal = 0;
  int _batchDone = 0;

  /// Hard cap on how many images one gallery pick can process. Prevents
  /// a 20-image flood from monopolising the OCR pipeline + LLM quota.
  /// 5 covers a typical menu (2-4 pages); larger numbers tank the UX
  /// without unlocking a real use case.
  static const int _kMaxBatchImages = 5;

  /// Lifecycle: timer that auto-stops the camera stream when the app stays
  /// in the background for too long (saves battery / avoids camera LED drain).
  static const _backgroundStopDelay = Duration(minutes: 3);
  Timer? _backgroundTimer;
  bool _cameraStoppedForBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    // First-run tips — shown once, after the first frame so the sheet has a
    // mounted scaffold to attach to. Reopenable later via the "?" top-bar
    // button.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CameraTipsSheet.showIfFirstTime(context);
    });
    final langs = ref.read(languageSettingsProvider).valueOrNull;
    ref.read(trackingServiceProvider).event('camera_open', properties: {
      'source_lang': langs?.sourceLang ?? 'auto',
      'target_lang': langs?.targetLang ?? 'en',
    });
  }

  /// Defence-in-depth check: even though [_handleCameraTap] in home_screen
  /// gates the entry, deep links / back-stack tricks / cached navigation
  /// could land a non-camera-plan user here. Read the `camera` feature
  /// flag (same one /admin/plans toggles) to match server policy exactly —
  /// hardcoding `isPro` would diverge if admin disabled camera for pro.
  bool _isCameraAllowed() {
    return ref.read(featuresProvider).flags.camera;
  }

  Future<void> _initCamera() async {
    // Plan gate FIRST — don't pop the OS permission dialog for users
    // who can't use the feature anyway.
    if (!_isCameraAllowed()) {
      final l = AppLocalizations.of(context)!;
      // Defer to next frame so we can pop the route safely after build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        UpgradeNudgeSheet.show(context, featureName: l.cameraTitle);
      });
      return;
    }

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.cameraPermission)),
        );
        Navigator.of(context).pop();
      }
      return;
    }
    try {
      await _cameraService.init();
      if (mounted) {
        setState(() {});
        _startStream();
      }
    } catch (e) {
      debugPrint('[Camera] Init failed: $e');
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// Push the current scene + source language into the camera service so
  /// the live OCR stream knows (a) whether to run at all — boxes only for
  /// menu / sign — and (b) which single script recognizer to use when the
  /// source is pinned (lower first-box latency). Called on stream start
  /// and whenever the scene / source changes.
  void _syncLiveDetectionConfig() {
    final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
        CameraScene.auto;
    final enabled =
        scene == CameraScene.menu || scene == CameraScene.sign;
    _cameraService.liveDetectionEnabled = enabled;
    _cameraService.liveSourceHint =
        ref.read(languageSettingsProvider).valueOrNull?.sourceLang;
    // Disabled now → clear any boxes left from a menu/sign session.
    if (!enabled && _liveBlocks.isNotEmpty) {
      _liveTracker.reset();
      setState(() => _liveBlocks = const []);
    }
  }

  void _startStream() {
    // Fresh stream → fresh tracker identities. Otherwise a track from a
    // previous preview session could linger and merge with new text.
    _liveTracker.reset();
    _syncLiveDetectionConfig();
    _cameraService.startTextStream(
      (blocks) {
        if (mounted && _step == _CameraStep.preview) {
          // Run the raw detector boxes through the SORT-style tracker.
          // The overlay then renders smoothed, identity-stable boxes -
          // no jitter, no per-frame flicker on missed detections.
          setState(() => _liveBlocks = _liveTracker.update(blocks));
        }
      },
      onBlurChange: _handleBlurChange,
      onSharpness: (pct) {
        if (!mounted || _step != _CameraStep.preview) return;
        // Smooth a little so the pill doesn't jitter frame-to-frame.
        final smoothed = _sharpness * 0.5 + pct * 0.5;
        if ((smoothed - _sharpness).abs() < 1) return;
        setState(() => _sharpness = smoothed);
      },
    );
  }

  /// Edge-triggered callback from CameraService; debounce the
  /// blurry → visible transition so a brief shake doesn't pop the
  /// overlay, but hide instantly when the user steadies.
  void _handleBlurChange(bool isBlurry) {
    _blurDebounce?.cancel();
    if (isBlurry) {
      _blurDebounce = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        if (_step != _CameraStep.preview) return;
        if (_isBlurry) return;
        setState(() => _isBlurry = true);
      });
    } else if (_isBlurry) {
      setState(() => _isBlurry = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backgroundTimer?.cancel();
    _focusResetTimer?.cancel();
    _blurDebounce?.cancel();
    _cameraService.dispose();
    _overlayController.dispose();
    _zoomController.dispose();
    // Per-session scope: cache must not leak into a later camera open
    // (different scene, prompt update on app launch, etc.).
    TranslationCache.instance.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    switch (state) {
      case AppLifecycleState.paused:
        // User left the app — schedule camera teardown to save battery.
        _backgroundTimer?.cancel();
        _backgroundTimer = Timer(_backgroundStopDelay, () {
          if (!mounted) return;
          _stopCameraForBackground();
        });
      case AppLifecycleState.resumed:
        _backgroundTimer?.cancel();
        _backgroundTimer = null;
        if (_cameraStoppedForBackground) {
          _reinitCameraAfterBackground();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// Release camera resources after the app has been backgrounded long enough.
  void _stopCameraForBackground() {
    if (_step != _CameraStep.preview) return;
    _cameraService.dispose();
    _cameraStoppedForBackground = true;
    _liveBlocks = [];
    _liveTracker.reset();
    debugPrint('[Camera] Stopped for background (battery save)');
    if (mounted) setState(() {});
  }

  /// Re-initialize the camera when the user returns after a background stop.
  Future<void> _reinitCameraAfterBackground() {
    _cameraStoppedForBackground = false;
    return _initCamera();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Re-sync the live OCR gates when the user switches scene
    // (ScenePickerRow → menu/sign turns boxes on, others off) or pins a
    // different source language (lets the stream pick the matching
    // single recognizer instead of fanning out to all five).
    ref.listen(cameraSettingsProvider, (_, __) => _syncLiveDetectionConfig());
    ref.listen(languageSettingsProvider, (_, __) => _syncLiveDetectionConfig());
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBody(l),
          _buildTopBar(l),
          if (_step == _CameraStep.preview) _buildBottomControls(l),
          if (_step == _CameraStep.preview && _isBlurry) _buildBlurOverlay(l),
          if (_cameraStoppedForBackground)
            _buildBackgroundPauseOverlay(l),
        ],
      ),
    );
  }

  /// Top-center hint shown when the preview has been blurry for at
  /// least the debounce window. Anchored just below the top bar so
  /// it's instantly visible without occluding the captured subject
  /// in the middle of the frame.
  Widget _buildBlurOverlay(AppLocalizations l) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: 1.0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.55),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pan_tool_alt_outlined,
                        color: Colors.amberAccent, size: 16),
                    const SizedBox(width: 7),
                    Text(
                      l.cameraHoldSteady,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
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

  /// Full-screen overlay shown when the camera was auto-stopped after the app
  /// sat in the background past [_backgroundStopDelay]. Tapping anywhere
  /// re-initializes the camera.
  Widget _buildBackgroundPauseOverlay(AppLocalizations l) {
    return GestureDetector(
      onTap: _reinitCameraAfterBackground,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined,
                color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            Text(
              l.cameraPausedTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.cameraPausedTapToResume,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l) {
    return switch (_step) {
      _CameraStep.preview => _buildPreview(),
      _CameraStep.translating => _buildTranslating(l),
      _CameraStep.result => _buildResult(),
    };
  }

  Widget _buildPreview() {
    final controller = _cameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final imageSize = controller.value.previewSize;
    final size = imageSize != null
        ? ui.Size(imageSize.height, imageSize.width) // swap for portrait
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Pinch-to-zoom + tap-to-focus share one detector over the whole
            // preview. A clean tap (no pan/pinch) focuses; a moving gesture
            // zooms. Taps that land on a live OCR block are absorbed by the
            // overlay above (→ "What is this?"), so only empty-area taps
            // reach here and trigger focus.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                _zoomBaseline = _zoom;
              },
              onScaleUpdate: (details) async {
                if (!_cameraService.supportsZoom) return;
                final target = _zoomBaseline * details.scale;
                final applied = await _cameraService.setZoom(target);
                if (mounted && (applied - _zoom).abs() > 0.01) {
                  setState(() => _zoom = applied);
                }
              },
              onTapUp: (details) =>
                  _handleFocusTap(details.localPosition, viewSize, size),
              child: Center(child: CameraPreview(controller)),
            ),
            if (size != null && _liveBlocks.isNotEmpty)
              CameraLiveOverlay(
                blocks: _liveBlocks,
                imageSize: size,
                onBlockTap: _explainBlock,
              ),
            // "Scanning" reassurance: camera is live but no text boxes yet
            // (the inherent camera-init + first-OCR window). Without it the
            // preview looks dead for ~1-1.5 s and users think it's broken.
            // Only shown when live detection is on (menu / sign scenes —
            // other scenes don't run live OCR so a "scanning" pill there
            // would be a lie). Hidden once any box appears or while the
            // blur hint is up.
            if (size != null &&
                _liveBlocks.isEmpty &&
                !_isBlurry &&
                _cameraService.liveDetectionEnabled)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(top: 56),
                    child: Center(child: _ScanningPill()),
                  ),
                ),
              ),
            if (_focusRingPos != null)
              Positioned(
                left: _focusRingPos!.dx - 28,
                top: _focusRingPos!.dy - 28,
                child: IgnorePointer(
                  child: _FocusRing(key: ValueKey(_focusRingPos)),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Map a tap on the preview (view coordinates) to a normalized focus point
  /// and drive the camera there, then show the focus ring and schedule a
  /// return to continuous AF. Uses the same letterbox-fit math as
  /// [CameraLiveOverlay] so the point lands where the user actually tapped
  /// on the displayed (possibly letterboxed) preview.
  void _handleFocusTap(Offset localPos, Size viewSize, ui.Size? imageSize) {
    if (imageSize == null || viewSize.width == 0 || viewSize.height == 0) {
      return;
    }
    final imageAspect = imageSize.width / imageSize.height;
    final viewAspect = viewSize.width / viewSize.height;
    double fitW, fitH, offsetX, offsetY;
    if (imageAspect > viewAspect) {
      fitW = viewSize.width;
      fitH = viewSize.width / imageAspect;
      offsetX = 0;
      offsetY = (viewSize.height - fitH) / 2;
    } else {
      fitH = viewSize.height;
      fitW = viewSize.height * imageAspect;
      offsetX = (viewSize.width - fitW) / 2;
      offsetY = 0;
    }
    final nx = ((localPos.dx - offsetX) / fitW).clamp(0.0, 1.0);
    final ny = ((localPos.dy - offsetY) / fitH).clamp(0.0, 1.0);

    _cameraService.focusOnPoint(Offset(nx, ny));
    setState(() => _focusRingPos = localPos);

    _focusResetTimer?.cancel();
    _focusResetTimer = Timer(const Duration(seconds: 3), () {
      _cameraService.resumeAutoFocus();
      if (mounted) setState(() => _focusRingPos = null);
    });
  }

  /// CameraResultOverlay wrapped in a Builder so the RepaintBoundary
  /// above (which only re-renders this subtree on actual state changes
  /// inside it) gets a stable identity per capture. Pulled out of the
  /// inline build so the per-capture key (`ValueKey(_capturedPath)`)
  /// stays attached even after I moved the overlay into the
  /// share-screenshot subtree.
  Widget _buildShareableOverlay(CameraSettings settings) {
    return CameraResultOverlay(
      // Per-capture Key forces a FRESH State instance every time the
      // captured file changes. Without this, drag offsets from a
      // previous capture would apply to the new translations.
      key: ValueKey(_capturedPath),
      blocks: _blocks,
      translations: _translations,
      imageSize: _capturedImageSize!,
      imagePath: _capturedPath,
      controller: _overlayController,
      hideLowConfidence: settings.hideLowConfidence,
      showOriginalAlways: settings.showOriginalAlways,
      overlayOpacity: settings.overlayOpacity,
      usePrimaryColor: settings.usePrimaryOverlayColor,
      pendingIndices: _pendingIndices,
      onExplain: _explainBlock,
      onBlockTap: _openBlockActionSheet,
    );
  }

  /// `_CameraStep.result` for normal single-capture flows; stays on
  /// `translating` while a multi-pick batch is in flight so we don't
  /// flash each intermediate image's result before the batch finishes.
  /// Used in place of literal `_step = _CameraStep.result` at every
  /// site that transitions out of the translating spinner.
  _CameraStep _resultStepRespectingBatch() =>
      _isBatchProcessing ? _CameraStep.translating : _CameraStep.result;

  /// Frozen snapshot of every per-capture singleton, used by the
  /// multi-pick batch flow to swap between processed gallery images
  /// without re-running OCR / vision. Caller restores via
  /// [_restoreFromSnapshot] after switching [_activeBatchIndex].
  _BatchSnapshot _snapshotActive() {
    return _BatchSnapshot(
      path: _capturedPath!,
      imageSize: _capturedImageSize!,
      blocks: List<OcrBlock>.from(_blocks),
      translations: List<String>.from(_translations),
      visionConfidence: _visionConfidence,
      detectedScene: _detectedScene,
      sourceLang: _captureSourceLang,
      error: _error,
    );
  }

  /// Inverse of [_snapshotActive]: copy a captured page's state back
  /// into the singletons that the result UI reads from. Callers wrap
  /// in setState so the rebuild picks up the swap.
  void _restoreFromSnapshot(_BatchSnapshot s) {
    _capturedPath = s.path;
    _capturedImageSize = s.imageSize;
    _blocks = s.blocks;
    _translations = s.translations;
    _visionConfidence = s.visionConfidence;
    _detectedScene = s.detectedScene;
    _captureSourceLang = s.sourceLang;
    _error = s.error;
  }

  /// Switch the displayed result to a different page in the batch.
  /// Saves the active singletons back into [_batchQueue] first so any
  /// edits the user made (block dismissals, retried translations) are
  /// preserved on next visit. Out-of-range targets become no-ops.
  void _switchBatch(int newIndex) {
    if (newIndex == _activeBatchIndex) return;
    if (newIndex < 0 || newIndex >= _batchQueue.length) return;
    setState(() {
      _batchQueue[_activeBatchIndex] = _snapshotActive();
      _activeBatchIndex = newIndex;
      _restoreFromSnapshot(_batchQueue[_activeBatchIndex]);
    });
  }

  /// Show the per-block action sheet (Copy / Retry / Explain / Save).
  /// Wired from [CameraResultOverlay.onBlockTap].
  void _openBlockActionSheet(int index, OcrBlock block, String translation) {
    final langs = ref.read(languageSettingsProvider).valueOrNull;
    final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
        CameraScene.auto;
    // Source-lang resolution order for the TTS button in the sheet:
    //   1. The capture's server-detected lang (most accurate — based on
    //      what was actually OCR'd / vision-read).
    //   2. The user's pinned sourceLang IF non-"auto" (backstop when
    //      server didn't return a detection).
    //   3. null → TTS button hides.
    final pinnedSrc = langs?.sourceLang;
    final ttsLang = _captureSourceLang ??
        ((pinnedSrc != null && pinnedSrc.toLowerCase() != 'auto')
            ? pinnedSrc
            : null);
    BlockActionSheet.show(
      context,
      block: block,
      translation: translation,
      scene: scene.id,
      targetLang: langs?.targetLang ?? 'en',
      sourceLang: pinnedSrc,
      ttsLang: ttsLang,
      onRetry: () => _retryBlock(index, block),
      onExplain: () => _explainBlock(block),
    );
  }

  /// Re-translate ONE block in place. Bypasses the per-session cache
  /// (otherwise we'd just return the same answer the user is unhappy
  /// with) and updates [_translations] when the server replies. UX:
  /// optimistic snackbar while in flight, swap when it lands, error
  /// snackbar on failure — no full-screen spinner because the rest of
  /// the result is still useful while one card refreshes.
  Future<void> _retryBlock(int index, OcrBlock block) async {
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.cameraBlockRetrying),
        duration: const Duration(seconds: 6),
      ),
    );
    final fresh = await _translateBatch([block.text], forceRefresh: true);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (fresh.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.cameraNoText),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final updated = fresh.first;
    if (index < 0 || index >= _translations.length) return;
    setState(() {
      _translations = [
        for (var i = 0; i < _translations.length; i++)
          if (i == index) updated else _translations[i],
      ];
    });
  }

  /// Open the "What is this?" sheet for a block. Picker preference:
  ///   1. Server-supplied `items` (vision_boxes path) - chips show the
  ///      translation, tap returns original.
  ///   2. Per-line pairing (2+ source lines aligned 1:1 with the same
  ///      number of translation lines). Cheap, no LLM round-trip - just
  ///      uses the per-block translation we already have.
  ///   3. Lazy /split-block call (menu / sign scenes only, multi-item
  ///      single-line blocks). Result cached per block text.
  ///   4. Direct explain on the whole block.
  Future<void> _explainBlock(OcrBlock block) async {
    var items = block.items;

    // (2) Per-line pairing: when the block holds multiple lines and the
    // translation preserved the same line count (the LLM prompt enforces
    // `preserve_structure`), zip them 1:1. No extra LLM call.
    if (items == null || items.length < 2) {
      final pairedItems = _pairLineItems(block);
      if (pairedItems != null && pairedItems.length >= 2) {
        items = pairedItems;
      }
    }

    // (3) Lazy /split-block for menu / sign multi-item single-line blocks.
    if (items == null || items.length < 2) {
      final lazyItems = await _maybeLazySplit(block);
      if (lazyItems != null && lazyItems.length >= 2) {
        items = lazyItems;
      }
    }

    String? textToExplain;

    if (items != null && items.length >= 2) {
      textToExplain = await _pickFromItems(block, items);
      if (textToExplain == null) return;
    } else {
      // (4) Single discrete unit: explain the whole block directly.
      textToExplain = block.text;
    }

    ref.read(trackingServiceProvider).event('region_explain', properties: {
      'length':     textToExplain.length,
      'step':       _step.name,
      'multi_item': textToExplain != block.text,
      'whole':      textToExplain == block.text,
      'source':     items != null && items.length >= 2 ? 'items' : 'fallback',
    });
    await _cameraService.stopTextStream();
    if (!mounted) return;
    await WhatIsThisSheet.show(context, textToExplain);
    if (!mounted) return;
    if (_step == _CameraStep.preview) _startStream();
  }

  /// Build items[] from the block's per-line source + translation when
  /// both share the same line count. translate-batch's prompt enforces
  /// `preserve_structure` so multi-line source usually ships back with
  /// matching translation line structure - that lets us pair them 1:1
  /// without spending another LLM call. Returns null when:
  ///   - the block has < 2 source lines, OR
  ///   - we don't have a translation for this block yet, OR
  ///   - source and translation line counts don't match (LLM dropped /
  ///     merged a line - the pairing would be misaligned).
  List<OcrBlockItem>? _pairLineItems(OcrBlock block) {
    final idx = _blocks.indexOf(block);
    if (idx < 0 || idx >= _translations.length) return null;
    final translation = _translations[idx];
    if (translation.isEmpty || translation == block.text) return null;

    final srcLines = block.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (srcLines.length < 2) return null;

    final trLines = translation
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (trLines.length != srcLines.length) return null;

    return [
      for (var i = 0; i < srcLines.length; i++)
        OcrBlockItem(original: srcLines[i], translation: trLines[i]),
    ];
  }

  /// Lazy /split-block call - only fires when:
  ///   - scene is menu or sign (server rejects other scenes), AND
  ///   - the block looks multi-item (length > 15 or contains a price
  ///     pattern). Short blocks aren't worth the round-trip.
  /// Result is cached per block text so repeat long-press is free.
  /// Returns null on miss/error (caller falls back to the drag-select
  /// picker). Shows a brief snackbar while in flight.
  Future<List<OcrBlockItem>?> _maybeLazySplit(OcrBlock block) async {
    final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
        CameraScene.auto;
    if (scene != CameraScene.menu && scene != CameraScene.sign) return null;

    final text = block.text.trim();
    if (text.length <= 15) return null;
    final priceLike =
        RegExp(r'[¥₩元$€£฿₽]|円|won|yen|\d{2,}\s*(yen|VND|đ|usd)', caseSensitive: false);
    final hasMultiItemSignal = text.contains('\n') ||
        priceLike.allMatches(text).length >= 2 ||
        text.length > 40;
    if (!hasMultiItemSignal) return null;

    final cached = _splitCache[text];
    if (cached != null) return cached;

    final langs = ref.read(languageSettingsProvider).valueOrNull;
    final targetLang = langs?.targetLang ?? 'en';
    final sourceLang = _captureSourceLang ??
        ((langs?.sourceLang != null && langs!.sourceLang.toLowerCase() != 'auto')
            ? langs.sourceLang
            : null);

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Splitting items…'),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio
          .post('/split-block', data: {
            'text': text,
            'targetLang': targetLang,
            if (sourceLang != null) 'sourceLang': sourceLang,
            'scene': scene.id,
          })
          .timeout(const Duration(seconds: 30));
      messenger?.hideCurrentSnackBar();
      final data = response.data as Map?;
      final raw = data?['items'];
      if (raw is! List || raw.isEmpty) return null;
      final parsed = <OcrBlockItem>[];
      for (final it in raw) {
        if (it is! Map) continue;
        final o = (it['original'] as String?)?.trim() ?? '';
        final t = (it['translation'] as String?)?.trim() ?? '';
        if (o.isEmpty && t.isEmpty) continue;
        parsed.add(OcrBlockItem(original: o, translation: t));
      }
      if (parsed.length < 2) return null;
      _splitCache[text] = parsed;
      return parsed;
    } catch (e) {
      debugPrint('[Camera] split-block failed: $e');
      messenger?.hideCurrentSnackBar();
      return null;
    }
  }

  /// Server-supplied items picker. Chips show the TRANSLATION (so the
  /// user picks the dish they recognise without reading source script);
  /// tapping returns the ORIGINAL of that item (the LLM gets source
  /// language to explain, which it handles better than the translation).
  /// `items` is passed in directly from the long-pressed block — it
  /// belongs only to that block, never mixed with another block's
  /// sub-items.
  Future<String?> _pickFromItems(OcrBlock block, List<OcrBlockItem> items) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: Text(
                'Whole block',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              subtitle: Text(
                items.map((it) => it.translation).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(ctx, block.text),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 12,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    // Translation = user-readable label.
                    title: Text(item.translation),
                    // Original kept as small subtitle so the user can
                    // sanity-check that the pair matches what they see
                    // on the menu before tapping.
                    subtitle: Text(
                      item.original,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    // Explain the ORIGINAL — the LLM is fluent in source
                    // and gives a richer answer than re-explaining a
                    // translation.
                    onTap: () => Navigator.pop(ctx, item.original),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslating(AppLocalizations l) {
    // Replace the generic spinner label with batch progress when a
    // multi-pick gallery flow is in flight. _batchTotal can be 0 in
    // single-capture mode (no batch ever started), in which case we
    // fall back to the original label.
    final showBatchProgress = _isBatchProcessing && _batchTotal > 0;
    final label = showBatchProgress
        ? l.cameraBatchProgress(_batchDone + 1, _batchTotal)
        : l.cameraTranslating;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_capturedPath != null)
          Image.file(File(_capturedPath!), fit: BoxFit.contain),
        Container(
          color: Colors.black45,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    if (_capturedPath == null || _capturedImageSize == null) {
      return const SizedBox.shrink();
    }
    final settings = ref.watch(cameraSettingsProvider).valueOrNull ??
        CameraSettings.defaults;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Shareable sub-tree: everything users want in the exported PNG
        // (captured image, translation overlay, confidence chips). Top
        // bar + discoverability hint + action chip row stay OUTSIDE the
        // boundary so a screenshot from the Share action doesn't bake
        // its own button into the export.
        RepaintBoundary(
          key: _resultRepaintKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Pinch-to-zoom on the image + translation overlay as a
              // unit so dense menus where text shrinks below comfortable
              // reading size can be magnified. Pan is conditional: at
              // scale 1 it stays disabled so single-finger drag belongs
              // to the card (drag-to-trash); once the user pinches in,
              // ValueListenableBuilder flips it on so they can drag the
              // magnified view around to read different areas.
              ValueListenableBuilder<Matrix4>(
                valueListenable: _zoomController,
                builder: (ctx, matrix, child) {
                  final scale = matrix.getMaxScaleOnAxis();
                  return InteractiveViewer(
                    transformationController: _zoomController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    panEnabled: scale > 1.01,
                    child: child!,
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Image.file(
                            File(_capturedPath!), fit: BoxFit.contain),
                      ),
                    ),
                    if (_blocks.isNotEmpty && _translations.isNotEmpty)
                      _buildShareableOverlay(settings),
                  ],
                ),
              ),
              if (_error != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.black54,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              if (_visionConfidence != null || _showDetectedSceneChip)
                Positioned(
                  top: 0,
                  left: 16,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 56),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_visionConfidence != null)
                            _ConfidenceChip(level: _visionConfidence!),
                          if (_showDetectedSceneChip) ...[
                            const SizedBox(height: 6),
                            _DetectedSceneChip(scene: _detectedScene!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Multi-pick batch nav — shown only when the gallery flow
        // produced more than one image. Centered horizontally at the
        // top so it doesn't fight either confidence chip (left) or
        // the close X (also left in the top bar — different row).
        // Outside the RepaintBoundary so a Share screenshot doesn't
        // bake "2 / 4" + arrow controls into the exported PNG.
        if (_batchQueue.length > 1)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 56),
                child: Center(
                  child: _BatchPageNav(
                    currentIndex: _activeBatchIndex,
                    total: _batchQueue.length,
                    onPrev: () => _switchBatch(_activeBatchIndex - 1),
                    onNext: () => _switchBatch(_activeBatchIndex + 1),
                  ),
                ),
              ),
            ),
          ),
        // Discoverability hint for the new per-card "What is this?"
        // gesture. Stays subtle (white12 background, small font) so it
        // doesn't compete with the translation cards. Anchored above
        // the action bar so the user notices it while scanning the
        // result screen.
        Positioned(
          left: 0,
          right: 0,
          bottom: 100,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.psychology_outlined,
                      size: 12, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)!.cameraResultExplainHint,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: AnimatedBuilder(
            animation: _overlayController,
            builder: (context, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Left cluster: view controls (eye + help + reset). Round
                // icon buttons so they read as a distinct group from the
                // labelled Retake / Copy actions on the right.
                _RoundIconButton(
                  icon: _overlayController.visible
                      ? Icons.visibility
                      : Icons.visibility_off,
                  tooltip: AppLocalizations.of(context)!
                      .cameraTapShowTranslations,
                  onTap: () => _overlayController.toggleVisible(),
                ),
                const SizedBox(width: 8),
                _RoundIconButton(
                  icon: Icons.help_outline,
                  tooltip: AppLocalizations.of(context)!.cameraTipsTitle,
                  onTap: () {
                    ref.read(trackingServiceProvider).event(
                      'camera_tips_open',
                      properties: {'source': 'result_help_button'},
                    );
                    CameraTipsSheet.show(context);
                  },
                ),
                if (_overlayController.hasEdits) ...[
                  const SizedBox(width: 8),
                  _RoundIconButton(
                    icon: Icons.restart_alt,
                    tooltip: 'Reset',
                    onTap: () => _overlayController.reset(),
                  ),
                ],
                const SizedBox(width: 16),
                _ActionChip(
                  icon: Icons.refresh,
                  label: AppLocalizations.of(context)!.cameraRetake,
                  onTap: _retake,
                ),
                const SizedBox(width: 12),
                _ActionChip(
                  icon: Icons.copy,
                  label: AppLocalizations.of(context)!.cameraCopyAll,
                  onTap: _copyAll,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(AppLocalizations l) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Row(
                children: [
                  // Source → Target language selector. Letting the user set
                  // the SOURCE matters for accuracy: a concrete non-Latin
                  // source (Thai / Arabic / Russian …) routes the capture
                  // straight to the vision LLM, which reads scripts ML Kit
                  // can't. "Auto" keeps the on-device-first behaviour.
                  _LangPill(
                    label: _sourceLabel(l),
                    onTap: _changeSourceLang,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 1),
                    child: Icon(Icons.arrow_right_alt,
                        color: Colors.white70, size: 18),
                  ),
                  _LangPill(
                    label: (ref
                                .watch(languageSettingsProvider)
                                .valueOrNull
                                ?.targetLang ??
                            'en')
                        .toUpperCase(),
                    onTap: _changeTargetLang,
                  ),
                  if (_step == _CameraStep.preview)
                    IconButton(
                      icon: Icon(
                        _flashOn ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                      ),
                      onPressed: _toggleFlash,
                    ),
                  // Help lives in the top bar only OUTSIDE the result
                  // screen; on the result screen it moves into the action
                  // bar's view-control cluster so it doesn't crowd the
                  // settings button.
                  if (_step != _CameraStep.result)
                    IconButton(
                      icon: const Icon(Icons.help_outline,
                          color: Colors.white),
                      tooltip: l.cameraTipsTitle,
                      onPressed: () {
                        ref.read(trackingServiceProvider).event(
                              'camera_tips_open',
                              properties: {'source': 'help_button'},
                            );
                        CameraTipsSheet.show(context);
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.tune, color: Colors.white),
                    tooltip: l.cameraSettingsTitle,
                    onPressed: () => CameraSettingsSheet.show(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(AppLocalizations l) {
    final langSettings = ref.watch(languageSettingsProvider).valueOrNull;
    final targetLang = langSettings?.targetLang ?? 'en';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Column(
          children: [
            const ScenePickerRow(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.touch_app,
                        color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l.cameraWhatIsThisHint,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 1,
                      height: 12,
                      color: Colors.white24,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.language, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _langDisplay(targetLang),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_cameraService.supportsZoom) _buildZoomPresets(),
            const SizedBox(height: 10),
            _buildSharpnessPill(l),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Gallery button on the left — left slot uses Expanded so
                // the capture circle stays perfectly centered regardless of
                // the gallery button's own width.
                Expanded(
                  child: Center(
                    child: _GalleryButton(onTap: _pickFromGallery),
                  ),
                ),
                GestureDetector(
                  onTap: _capture,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Ring turns green once the frame is sharp enough to
                      // capture, so the user has an at-a-glance "go" signal
                      // instead of guessing when autofocus has settled.
                      border: Border.all(
                        color: _sharpness >= _kSharpReady
                            ? const Color(0xFF22C55E)
                            : Colors.white,
                        width: 4,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                // Symmetric right slot keeps capture centered.
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Live focus-quality pill above the shutter. Language-neutral by
  /// design (icon + bar + %) so it needs no new i18n keys: a colour goes
  /// red → amber → green as the Laplacian-variance meter climbs, with a
  /// check icon at the ready line. Tells the user WHEN autofocus has
  /// settled so they stop firing the shutter on a blurry first frame.
  Widget _buildSharpnessPill(AppLocalizations l) {
    final pct = _sharpness.round();
    final ready = _sharpness >= _kSharpReady;
    final Color color;
    if (_sharpness >= _kSharpReady) {
      color = const Color(0xFF22C55E); // green
    } else if (_sharpness >= 40) {
      color = const Color(0xFFF59E0B); // amber
    } else {
      color = const Color(0xFFEF4444); // red
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ready ? Icons.check_circle : Icons.center_focus_strong,
              color: color,
              size: 15,
            ),
            const SizedBox(width: 7),
            // Thin progress bar fills with the focus %.
            SizedBox(
              width: 70,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (_sharpness / 100).clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: 7),
            SizedBox(
              width: 34,
              child: Text(
                '$pct%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Three pill buttons (1×, 2×, max) sitting above the capture button.
  /// Tapping snaps the camera to that zoom level; pinch-to-zoom on the
  /// preview keeps working in parallel and the active pill follows it.
  ///
  /// The "max" pill is hidden when maxZoom is below 3× — most front-facing
  /// cameras and basic back cameras report ~1.0–2.0× as their range, and
  /// surfacing a "max" that's basically the same as "2×" is just noise.
  Widget _buildZoomPresets() {
    final min = _cameraService.minZoom;
    final max = _cameraService.maxZoom;
    // Candidate presets in ascending order; filter out anything beyond
    // what this camera actually supports.
    final raw = <double>[1.0, 2.0, if (max >= 3.0) max];
    final presets = raw.where((z) => z >= min - 0.01 && z <= max + 0.01).toList();
    if (presets.length < 2) {
      // Nothing meaningful to show; rely on pinch only.
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final z in presets) ...[
            _ZoomPresetPill(
              label: _zoomLabel(z, max),
              zoom: z,
              isActive: (_zoom - z).abs() < 0.15,
              onTap: () async {
                final applied = await _cameraService.setZoom(z);
                if (mounted) setState(() => _zoom = applied);
              },
            ),
            const SizedBox(width: 4),
          ],
          // Trim the trailing SizedBox.
        ].sublist(0, presets.length * 2 - 1),
      ),
    );
  }

  String _zoomLabel(double zoom, double maxZoom) {
    if ((zoom - maxZoom).abs() < 0.01 && maxZoom >= 3.0) return 'Max';
    if (zoom == zoom.roundToDouble()) return '${zoom.toInt()}×';
    return '${zoom.toStringAsFixed(1)}×';
  }

  /// Set when the user taps the shutter while the frame is still blurry
  /// and we ask them to wait for focus. A second tap within the window
  /// captures anyway (so we never fully block a deliberate shot).
  bool _focusNudgeShown = false;

  Future<void> _capture() async {
    // Focus guard: if the frame isn't sharp yet AND the user hasn't
    // already insisted, nudge them to wait for autofocus instead of
    // baking a blurry capture. Re-centre autofocus to speed it up. A
    // second tap (or once the ring goes green) proceeds normally.
    if (_sharpness < _kSharpReady && !_focusNudgeShown) {
      _focusNudgeShown = true;
      _cameraService.focusOnPoint(const Offset(0.5, 0.5));
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1600),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
          content: Text(
            AppLocalizations.of(context)!.cameraWaitFocus,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
      // Allow an immediate retry to override after a short beat.
      Timer(const Duration(milliseconds: 1800), () {
        if (mounted) _focusNudgeShown = false;
      });
      return;
    }
    _focusNudgeShown = false;

    // Instant UI feedback: switch to the translating screen IMMEDIATELY
    // when the user taps. The 2 s OCR pipeline otherwise leaves the user
    // staring at the live preview wondering whether the tap registered.
    // [_capturedPath] is still null at this point so [_buildTranslating]
    // falls back to the spinner-over-black layout until the picture is
    // ready, then the captured frame is drawn behind the spinner.
    setState(() {
      _step = _CameraStep.translating;
      // Clear last capture's vision rating — if this capture routes to
      // ML Kit, the chip should stay hidden; if it routes to vision,
      // _captureWithVision will repopulate.
      _visionConfidence = null;
      _detectedScene = null;
      _captureSourceLang = null;
      // Single-shutter capture replaces any prior multi-pick batch.
      _batchQueue.clear();
      _activeBatchIndex = 0;
      _isBatchProcessing = false;
      _batchTotal = 0;
      _batchDone = 0;
    });

    // Stop stream — will re-run full OCR on the captured image.
    await _cameraService.stopTextStream();

    try {
      final path = await _cameraService.captureImage();
      await _processImage(path);
    } catch (e) {
      debugPrint('[Camera] Capture failed: $e');
      _recoverToPreview();
    }
  }

  /// Pick existing photos from the gallery and run them through the same
  /// OCR + scene pipeline as a live capture. Useful when the user
  /// already has photos of the menu/sign/document or the lighting at
  /// the moment is bad. Multi-pick is the common case for restaurant
  /// menus (2-4 pages); the batch flow surfaces arrow nav at the top of
  /// the result so the user can flip between pages without re-picking.
  Future<void> _pickFromGallery() async {
    final List<XFile> rawPicked;
    try {
      rawPicked = await ImagePicker().pickMultiImage(
        // Cap dimensions to 1600 px so OCR + (optional) vision upload run
        // fast on a gallery pick — going larger only adds latency without
        // improving recognition (ML Kit's detection grid plateaus before
        // 2000 px). Matches the same long-edge cap used for vision uploads.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
    } catch (e) {
      debugPrint('[Camera] Gallery pick failed: $e');
      return;
    }
    if (rawPicked.isEmpty) return; // user cancelled
    if (!mounted) return;

    // Cap picks at _kMaxBatchImages - over-picking is almost always a
    // mistake (a 20-image flood monopolises OCR + LLM cost), so we keep
    // the first 5 and surface a snackbar so the user knows.
    final List<XFile> picked = rawPicked.length > _kMaxBatchImages
        ? rawPicked.sublist(0, _kMaxBatchImages)
        : rawPicked;
    if (rawPicked.length > _kMaxBatchImages) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Max $_kMaxBatchImages images per batch - using the first $_kMaxBatchImages',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    ref.read(trackingServiceProvider).event('gallery_pick', properties: {
      'count':   picked.length,
      'capped':  rawPicked.length > _kMaxBatchImages,
      'raw':     rawPicked.length,
    });
    setState(() {
      _step = _CameraStep.translating;
      _visionConfidence = null;
      _detectedScene = null;
      _captureSourceLang = null;
      _batchQueue.clear();
      _activeBatchIndex = 0;
      _isBatchProcessing = picked.length > 1;
      _batchTotal = picked.length;
      _batchDone = 0;
    });
    await _cameraService.stopTextStream();

    final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
        CameraScene.auto;
    final sourceLang =
        ref.read(languageSettingsProvider).valueOrNull?.sourceLang;
    final visionOnly =
        scene == CameraScene.sign || _sourceNeedsVision(sourceLang);

    if (visionOnly) {
      // Vision-only scenes (sign + non-ML-Kit scripts) keep the original
      // sequential flow because /translate-image and its scene/source-lang
      // chip wiring live inside _captureWithVision which mutates shared
      // state. Parallelising them would race the singletons; this path
      // is also a less-common gallery use case.
      await _runBatchSequential(picked);
    } else {
      // Menu / document / screenshot / auto — the common gallery case.
      // Parallelise the ML Kit OCR step (decode + recognizeText, both
      // pure / no shared-state mutation) so 5 images take ~max(OCR)
      // instead of sum(OCR); translation still runs per-image because
      // it threads through stateful helpers, but the first ready
      // OCR's translation surfaces immediately so the user sees a
      // result long before the last image finishes.
      await _runBatchParallelOcr(picked, scene: scene);
    }

    if (!mounted) return;
    setState(() => _isBatchProcessing = false);

    if (_batchQueue.isEmpty) {
      _recoverToPreview();
      return;
    }
    // First-completed is already restored by the parallel/sequential
    // helper; this block is a safety net for the sequential path which
    // doesn't auto-restore mid-loop.
    if (_step != _CameraStep.result) {
      setState(() {
        _activeBatchIndex = 0;
        _restoreFromSnapshot(_batchQueue[0]);
        _step = _resultStepRespectingBatch();
      });
    }
  }

  /// Sequential batch fallback for scenes that depend on shared-state
  /// helpers (sign, vision-only sources). Same loop the gallery flow
  /// used to run unconditionally - kept for the rare cases parallel
  /// can't cover.
  Future<void> _runBatchSequential(List<XFile> picked) async {
    for (var i = 0; i < picked.length; i++) {
      if (!mounted) return;
      try {
        await _processImage(picked[i].path, aggressivePasses: true);
        if (!mounted) return;
        if (_capturedPath != null && _capturedImageSize != null) {
          _batchQueue.add(_snapshotActive());
        }
        setState(() {
          _batchDone = i + 1;
          if (i < picked.length - 1) {
            _blocks = [];
            _translations = [];
            _error = null;
            _visionConfidence = null;
            _detectedScene = null;
            _captureSourceLang = null;
          }
        });
      } catch (e) {
        debugPrint('[Camera] Gallery batch item $i failed: $e');
      }
    }
  }

  /// Parallel-OCR batch path for the common menu/document gallery flow.
  /// All ML Kit OCR calls fire in parallel via Future.wait (each
  /// recognizeText is pure - no shared state writes). The for-loop
  /// below the await drains the futures in pick-order and runs the
  /// stateful translate step for each. The FIRST image's translated
  /// snapshot transitions the UI out of the spinner immediately so
  /// the user can browse it while later images finish in the
  /// background.
  Future<void> _runBatchParallelOcr(
    List<XFile> picked, {
    required CameraScene scene,
  }) async {
    final settings = ref.read(cameraSettingsProvider).valueOrNull ??
        CameraSettings.defaults;

    // Phase 1: kick off ALL OCR jobs in parallel. Each future decodes
    // its own image and returns the per-image OCR result (or null on
    // failure). Construction with .toList() materialises the futures
    // so they all start before any awaits below.
    final ocrJobs = picked.map((file) => _runOcrPure(
          file.path,
          scene: scene.id,
          confidenceThreshold: settings.confidenceThreshold,
        )).toList();

    // Phase 2: drain in pick-order and translate sequentially. First
    // completed translation flips the UI out of the spinner.
    for (var i = 0; i < ocrJobs.length; i++) {
      if (!mounted) return;
      final ocr = await ocrJobs[i];
      if (!mounted) return;
      if (ocr == null) {
        setState(() => _batchDone = i + 1);
        continue;
      }
      // Move this image's OCR result into the shared singletons so the
      // existing _translateAndShow path (which reads from state) can
      // translate it. setState here is safe because the for-loop is
      // serial — only one image is "active" at a time.
      setState(() {
        _capturedPath = ocr.path;
        _capturedImageSize = ocr.size;
        _blocks = ocr.blocks;
        _translations = List<String>.filled(ocr.blocks.length, '');
        _error = ocr.blocks.isEmpty ? 'No text found' : null;
        _visionConfidence = null;
        _detectedScene = null;
        _captureSourceLang = null;
      });
      if (ocr.blocks.isNotEmpty) {
        try {
          await _translateAndShow();
        } catch (e) {
          debugPrint('[Camera] Gallery translate $i failed: $e');
        }
      }
      if (!mounted) return;
      if (_capturedPath == ocr.path && _capturedImageSize != null) {
        _batchQueue.add(_snapshotActive());
      }
      setState(() {
        _batchDone = i + 1;
        // First successful image: transition out of the translating
        // spinner so the user starts browsing while the rest process.
        if (_batchQueue.length == 1) {
          _isBatchProcessing = false;
          _step = _resultStepRespectingBatch();
        }
      });
    }
  }

  /// Pure (no shared-state writes) decode + ML Kit OCR pass used by
  /// the parallel batch path. Returns the per-image data needed to
  /// later run translation through the existing stateful helpers.
  Future<_BatchOcrResult?> _runOcrPure(
    String path, {
    required String scene,
    required double confidenceThreshold,
  }) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      final raw = await _cameraService.recognizeText(
        path,
        scene: scene,
        aggressivePasses: true,
      );
      final blocks = confidenceThreshold <= kOcrConfidenceFloor
          ? raw
          : raw.where((b) {
              final c = b.confidence;
              return c == null || c >= confidenceThreshold;
            }).toList();
      return _BatchOcrResult(path: path, size: size, blocks: blocks);
    } catch (e) {
      debugPrint('[Camera] Parallel OCR failed for $path: $e');
      return null;
    }
  }

  /// Shared pipeline for live captures + gallery picks: load bytes, decode
  /// dimensions, route to vision (sign scene) or on-device OCR + translate
  /// (everything else). Assumes the caller already switched [_step] to
  /// translating and stopped the OCR stream.
  ///
  /// [aggressivePasses] forwards to [CameraService.recognizeText]:
  /// true (default) = 3-pass original+contrast+binarize for live capture
  /// quality; false = single-pass for gallery picks that don't need it
  /// and would otherwise add 4-6 s of latency.
  Future<void> _processImage(String path, {bool aggressivePasses = true}) async {
    final sw = Stopwatch()..start();
    // Surface the source image as soon as it's available so the user sees
    // something other than a black screen while OCR runs.
    if (mounted) setState(() => _capturedPath = path);
    final image = File(path);
    final bytes = await image.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    debugPrint('[Camera] Latency: image decode ${sw.elapsedMilliseconds}ms');

    final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
        CameraScene.auto;

    // Scene=sign uses the VISION LLM path instead of on-device OCR.
    // Signs are mostly stylized / cursive / decorative fonts that ML
    // Kit OCR can't read. The vision model reads them like a human.
    if (scene == CameraScene.sign) {
      ref.read(trackingServiceProvider).event('vision_fallback', properties: {
        'reason': 'sign_scene',
        'scene':  scene.id,
      });
      await _captureWithVision(path, bytes, size, scene: scene.id);
      return;
    }

    // ML Kit's on-device OCR only supports 5 scripts: Latin, Chinese,
    // Japanese, Korean, Devanagari. A traveller in Thailand / the Middle
    // East etc. scans a script ML Kit literally cannot read (Thai,
    // Arabic, Cyrillic, Greek, Hebrew, Khmer, …). When the user has
    // EXPLICITLY pinned source to such a language, skip ML Kit entirely
    // and go straight to vision — ML Kit can't help, and worse: any
    // Latin scraps it does pick up (background prices, English logos,
    // "WiFi" stickers, etc.) can mask the real non-Latin content from
    // the weak-result fallback below, leading to either garbage Latin
    // translations or — when the vision retry path also gives up — a
    // blank "No text found" on what is actually a fully-readable menu.
    // Respecting the user's source pick costs us the mixed-script case
    // (a Thai storefront with a Latin logo) — but in that case the user
    // can switch to source=auto, which is the path that stays on the
    // ML-Kit-first pipeline below.
    final sourceLang =
        ref.read(languageSettingsProvider).valueOrNull?.sourceLang;
    final sourceWantsVision = _sourceNeedsVision(sourceLang);

    if (sourceWantsVision) {
      ref.read(trackingServiceProvider).event('vision_fallback', properties: {
        'reason':      'source_vision_only',
        'scene':       scene.id,
        'source_lang': sourceLang,
      });
      await _captureWithVision(path, bytes, size, scene: scene.id);
      return;
    }

    // Default OCR path for document / menu / screenshot / auto.
    final rawBlocks = await _cameraService.recognizeText(
      path,
      scene: scene.id,
      aggressivePasses: aggressivePasses,
    );

    final settings = ref.read(cameraSettingsProvider).valueOrNull ??
        CameraSettings.defaults;
    final blocks = settings.confidenceThreshold <= kOcrConfidenceFloor
        ? rawBlocks
        : rawBlocks.where((b) {
            final c = b.confidence;
            return c == null || c >= settings.confidenceThreshold;
          }).toList();

    if (!mounted) return;

    // Count meaningful (whitespace-stripped) characters across all blocks.
    // ML Kit can't read stylized storefront signage (3D / decorative /
    // neon CJK + Latin) — it returns a few garbage Latin chars (e.g. a
    // "MINISO" logo read as "MINI SOU", a Korean "다이소" read as "Casio")
    // and misses the real CJK entirely. Those scraps are non-empty so the
    // plain isEmpty check below wouldn't catch them. When the TOTAL text
    // found is tiny, treat it as "OCR basically failed on a hard image"
    // and escalate to the vision LLM, which reads stylized signs like a
    // human. 12 chars is the baseline minimum below which any "result"
    // is almost certainly garbage; the confidence + scene checks below
    // refine that for the legitimately-short cases.
    final totalChars = blocks.fold<int>(
      0,
      (sum, b) => sum + b.text.replaceAll(RegExp(r'\s'), '').length,
    );

    // Per-scene char threshold below which we suspect ML Kit missed
    // most of the content. Signs are legitimately short ("STOP",
    // "EXIT", "営業中"); menus / documents / screenshots are almost
    // never that short, so a tiny result there really does mean OCR
    // failed.
    final shortThreshold = _shortTextThresholdForScene(scene.id);

    // A high-confidence ML Kit block carries enough signal on its
    // own — a "¥980" price tag or a "SALE" sign is short but the
    // OCR confidence is high. Falling back to vision in that case
    // wastes a round-trip + tokens. Only fire the fallback when the
    // short result is ALSO low-confidence (suggesting ML Kit guessed
    // at noise rather than reading something real).
    final hasHighConfBlock = blocks.any(
      (b) => b.confidence != null && b.confidence! >= 0.7,
    );

    // Composite "ML Kit weakness" score (0..1) — a multi-signal proxy
    // for "this on-device read is unreliable / incomplete, escalate to
    // Vision". No single signal is sufficient (you can't know what OCR
    // MISSED without re-running it), so we blend the cheap signals ML
    // Kit + the capture give us. See _mlkitWeakness for the formula.
    final weakness = _mlkitWeakness(
      blocks: blocks,
      imageSize: size,
      totalChars: totalChars,
      shortThreshold: shortThreshold,
    );

    // Fall back when empty, OR the short+low-conf legacy rule fires, OR
    // the composite score crosses the tuned threshold. Keeping the
    // legacy rule preserves the well-tuned "tiny garbage result" path.
    final shouldFallbackToVision = blocks.isEmpty ||
        (totalChars < shortThreshold && !hasHighConfBlock) ||
        weakness >= _kWeaknessThreshold;

    if (shouldFallbackToVision) {
      debugPrint(
        '[Camera] OCR weak (chars=$totalChars, weakness=${weakness.toStringAsFixed(2)}, '
        'hasHighConf=$hasHighConfBlock, scene=${scene.id}, '
        'sourceVision=$sourceWantsVision) — vision fallback',
      );
      ref.read(trackingServiceProvider).event('vision_fallback', properties: {
        'reason':            sourceWantsVision ? 'source_vision_only' : 'weak_ocr',
        'scene':             scene.id,
        'total_chars':       totalChars,
        'weakness':          double.parse(weakness.toStringAsFixed(2)),
        'has_high_conf':     hasHighConfBlock,
        if (sourceWantsVision) 'source_lang': sourceLang,
      });
      // Hybrid tier 2: try Google Cloud Vision OCR (cheap, high recall)
      // BEFORE the pricier vision LLM. It returns true when it produced a
      // result; false when the server has no Vision key or found nothing,
      // in which case we fall through to the LLM tier below.
      if (await _captureWithGoogleVision(path, bytes, size, scene: scene.id)) {
        return;
      }
      // Carry the user's selected scene into the vision path. This is the
      // critical bit for handwritten / chalkboard menus: with scene=menu,
      // the response gets split per-line so each dish row is its own card
      // instead of one giant aggregate block.
      await _captureWithVision(path, bytes, size, scene: scene.id);
      return;
    }

    setState(() {
      _capturedPath = path;
      _capturedImageSize = size;
      _blocks = blocks;
      _step = _CameraStep.translating;
    });
    debugPrint('[Camera] Latency: OCR total ${sw.elapsedMilliseconds}ms '
        '(${blocks.length} blocks)');

    ref.read(trackingServiceProvider).event('camera_capture', properties: {
      'scene':        scene.id,
      'source_lang':  sourceLang ?? 'auto',
      'target_lang':
          ref.read(languageSettingsProvider).valueOrNull?.targetLang ?? 'en',
      'block_count':  blocks.length,
      'total_chars':  totalChars,
      'path':         'mlkit',
    });

    // MUST await: the gallery-batch flow snapshots singletons in
    // [_pickFromGallery] immediately after _processImage returns. With
    // fire-and-forget, the snapshot grabs blocks but EMPTY translations
    // (the network call's still in flight), and by the time it
    // resolves it writes to whichever image's singletons are now live
    // → translations end up on the wrong page. Single capture's UX is
    // unchanged: the translating spinner stays up until done either
    // way.
    await _translateAndShow();
  }

  /// ISO 639-1 codes whose script ML Kit's on-device recognizer cannot read
  /// (it only supports Latin / Chinese / Japanese / Korean / Devanagari).
  /// A capture in any of these goes straight to the vision LLM. Covers the
  /// major travel scripts: Thai, Arabic family, Hebrew, Cyrillic, Greek,
  /// Armenian, Georgian, non-Devanagari Indic, and mainland SE-Asian +
  /// Ethiopic scripts.
  static const _visionOnlyLangs = <String>{
    'th', // Thai
    'ar', 'fa', 'ur', 'ps', 'sd', // Arabic script
    'he', 'yi', // Hebrew
    'ru', 'uk', 'bg', 'sr', 'mk', 'be', 'kk', 'ky', 'mn', 'tg', // Cyrillic
    'el', // Greek
    'hy', // Armenian
    'ka', // Georgian
    'bn', 'ta', 'te', 'kn', 'ml', 'gu', 'pa', 'si', 'or', // non-Devanagari Indic
    'km', 'lo', 'my', // Khmer / Lao / Myanmar
    'am', 'ti', // Ethiopic
  };

  /// Map the server's per-image self-assessed confidence ("high" | "medium"
  /// | "low") onto the same 0..1 scale ML Kit OCR uses, so the existing
  /// low-confidence UI (amber tint + warning badge) fires uniformly across
  /// both code paths. The chosen thresholds:
  ///
  ///   - "low"               → 0.30  always badge (below [kOcrLowConfidenceBadge])
  ///   - "medium" + sign     → 0.45  badge — safety bias for road signs /
  ///                                 prohibition signs, where a "medium"
  ///                                 mis-read can be actively dangerous
  ///   - "medium" (other)    → 0.70  no badge — "okay-ish" is acceptable for
  ///                                 menus / docs that the user can re-shoot
  ///                                 trivially
  ///   - "high" / null       → 1.0   full trust
  ///
  /// Null / unknown is treated as high — the server only OMITS the field on
  /// legacy responses where this client previously assumed 1.0 anyway, so
  /// we don't want to suddenly badge every result on older API versions.
  double _mapVisionConfidenceToScore(String? confidence, String scene) {
    switch (confidence) {
      case 'low':
        return 0.30;
      case 'medium':
        return scene == 'sign' ? 0.45 : 0.70;
      case 'high':
      default:
        return 1.0;
    }
  }

  /// Per-scene minimum total chars below which a ML Kit result is
  /// considered "OCR basically failed". The default (auto / document /
  /// menu / screenshot) keeps the legacy 12-char floor — those scenes
  /// rarely produce a legitimately tiny result. Signs DO ("STOP",
  /// "EXIT", "営業中", "¥980"), so the sign threshold drops to 3:
  /// combined with the confidence check at the call site, a 3-char
  /// high-confidence read is accepted instead of triggering an
  /// unnecessary vision round-trip.
  int _shortTextThresholdForScene(String sceneId) {
    switch (sceneId) {
      case 'sign':
        return 3;
      default:
        return 12;
    }
  }

  /// Composite "ML Kit weakness" threshold. At/above this the capture is
  /// escalated to Google Vision. Tuned conservatively (0.5) so a clean
  /// read never pays for a Vision call; raise to be stingier, lower to
  /// favour recall over cost.
  static const double _kWeaknessThreshold = 0.5;

  /// Blend cheap, on-device signals into a 0..1 estimate of how UNRELIABLE
  /// / INCOMPLETE the ML Kit read is. Higher = weaker = prefer Vision.
  ///
  /// You can't know what OCR *missed* without re-running it, so every term
  /// is a proxy; we combine four so no single noisy signal dominates:
  ///
  ///   • confidence  (0.45) — mean ML Kit line confidence. The strongest
  ///       signal for "the model is guessing". Null on iOS → treated as a
  ///       neutral 0.7 so the term neither helps nor hurts there.
  ///   • lowConfFrac (0.25) — share of blocks under 0.5 confidence; catches
  ///       a few garbage reads dragging down an otherwise-ok mean.
  ///   • coverage    (0.15) — text-box area ÷ image area, normalised to a
  ///       12% "well-covered" target. Low coverage on a dense capture hints
  ///       at missed regions. Weighted low: a legit sparse sign also reads
  ///       low here, so it must not dominate.
  ///   • blur        (0.15) — from the live sharpness meter; a soft frame
  ///       degrades OCR recall. Skipped (0) for gallery picks with no
  ///       preview sharpness.
  double _mlkitWeakness({
    required List<OcrBlock> blocks,
    required ui.Size imageSize,
    required int totalChars,
    required int shortThreshold,
  }) {
    if (blocks.isEmpty) return 1.0;

    final confs = blocks
        .map((b) => b.confidence)
        .whereType<double>()
        .toList();
    final meanConf = confs.isEmpty
        ? 0.7 // iOS / unknown → neutral
        : confs.reduce((a, b) => a + b) / confs.length;
    final lowConfFrac = confs.isEmpty
        ? 0.0
        : confs.where((c) => c < 0.5).length / confs.length;

    final imgArea = imageSize.width * imageSize.height;
    final boxArea = blocks.fold<double>(
      0,
      (sum, b) => sum + b.boundingBox.width * b.boundingBox.height,
    );
    final coverage = imgArea <= 0 ? 0.0 : (boxArea / imgArea);
    // Normalise: 12% text area = fully covered (score 1). Below → <1.
    final coverageScore = (coverage / 0.12).clamp(0.0, 1.0);

    final blurPenalty =
        _sharpness > 0 ? (1 - _sharpness / 100).clamp(0.0, 1.0) : 0.0;

    final weakness = 0.45 * (1 - meanConf) +
        0.25 * lowConfFrac +
        0.15 * (1 - coverageScore) +
        0.15 * blurPenalty;
    return weakness.clamp(0.0, 1.0);
  }

  /// True when [sourceLang] is a concrete (non-auto) language whose script
  /// ML Kit can't OCR — caller should route the capture to vision instead.
  bool _sourceNeedsVision(String? sourceLang) {
    if (sourceLang == null) return false;
    final code = sourceLang.toLowerCase().split('-').first;
    if (code.isEmpty || code == 'auto') return false;
    return _visionOnlyLangs.contains(code);
  }

  /// Recover to the live-preview state after a failed capture / pick so the
  /// user isn't stuck on the spinner.
  void _recoverToPreview() {
    if (mounted) setState(() => _step = _CameraStep.preview);
    _startStream();
  }

  /// Hybrid OCR tier 2: Google Cloud Vision (via backend). Tried BEFORE
  /// the pricier vision-LLM when on-device ML Kit comes back weak. Vision
  /// has far higher recall on dense / small / mixed-script captures and
  /// returns per-block boxes the overlay positions exactly.
  ///
  /// Returns true when it populated a result (caller stops); false when
  /// the caller should fall through to [_captureWithVision] - either
  /// Vision isn't configured on the server (no key) or it found no text.
  Future<bool> _captureWithGoogleVision(
    String path,
    Uint8List bytes,
    ui.Size size, {
    required String scene,
  }) async {
    try {
      final langSettings = ref.read(languageSettingsProvider).valueOrNull;
      final targetLang = langSettings?.targetLang ?? 'en';
      final sourceLang = langSettings?.sourceLang;
      final api = ref.read(apiClientProvider);
      final compressed =
          await _cameraService.compressForVision(bytes, scene: scene);
      final imageBase64 = base64Encode(compressed);

      final response = await api.dio.post('/translate-image-ocr', data: {
        'imageBase64': imageBase64,
        'targetLang': targetLang,
        'scene': scene,
        if (sourceLang != null && sourceLang.isNotEmpty && sourceLang != 'auto')
          'sourceLang': sourceLang,
        'imageWidth': size.width.round(),
        'imageHeight': size.height.round(),
      });
      if (!mounted) return false;
      final data = response.data as Map?;
      final rawBlocks = data?['blocks'];
      if (rawBlocks is! List || rawBlocks.isEmpty) {
        // Vision unconfigured or found nothing → let the LLM tier try.
        return false;
      }

      // Box convention matches /translate-image: [ymin, xmin, ymax, xmax]
      // in the same pixel space as `size`.
      final blocks = <OcrBlock>[];
      final translations = <String>[];
      for (final b in rawBlocks) {
        if (b is! Map) continue;
        final original = (b['original'] as String?)?.trim() ?? '';
        final translation = (b['translation'] as String?)?.trim() ?? '';
        if (original.isEmpty && translation.isEmpty) continue;
        final box = b['box'];
        if (box is! List || box.length != 4) continue;
        double n(int i) => (box[i] is num) ? (box[i] as num).toDouble() : 0.0;
        final ymin = n(0), xmin = n(1), ymax = n(2), xmax = n(3);
        if (xmax <= xmin || ymax <= ymin) continue;
        blocks.add(OcrBlock(
          text: original,
          boundingBox: Rect.fromLTRB(xmin, ymin, xmax, ymax),
        ));
        translations.add(translation);
      }
      if (blocks.isEmpty) return false;

      final rawSrc = (data?['sourceLang'] as String?)?.toLowerCase();
      _captureSourceLang =
          (rawSrc != null && RegExp(r'^[a-z]{2}$').hasMatch(rawSrc))
              ? rawSrc
              : null;

      setState(() {
        _capturedPath = path;
        _capturedImageSize = size;
        _blocks = blocks;
        _translations = translations;
        _error = null;
        _step = _resultStepRespectingBatch();
      });
      ref.read(trackingServiceProvider).event('camera_capture', properties: {
        'scene':       scene,
        'source_lang': sourceLang ?? 'auto',
        'target_lang': targetLang,
        'block_count': blocks.length,
        'path':        'google_vision',
      });
      return true;
    } catch (e) {
      debugPrint('[Camera] Google Vision OCR failed: $e');
      // Network / server error → fall through to the LLM tier.
      return false;
    }
  }

  /// Vision-LLM pipeline: bypasses ML Kit OCR entirely and sends the raw
  /// image to the server. Used for scene=sign (stylized/cursive fonts that
  /// on-device OCR can't read) AND as a fallback when ML Kit returns nothing
  /// (handwriting, low-contrast). Server returns transcription + translation
  /// with `\n`-separated lines matching the visual structure.
  ///
  /// Rendering depends on the scene:
  ///   - sign / document / auto: ONE block covering the whole image (the
  ///     user reads it as one message — same aggregate semantics the OCR
  ///     path produces for those scenes).
  ///   - menu / screenshot: SPLIT the response by `\n` into N blocks, each
  ///     a vertical strip of the image. The user expects per-row cards
  ///     (one dish per card) — the chalkboard / handwritten menu fallback
  ///     path otherwise produces a giant single card that hides the layout.
  Future<void> _captureWithVision(
    String path,
    Uint8List bytes,
    Size size, {
    required String scene,
    bool isRetry = false,
  }) async {
    try {
      final langSettings = ref.read(languageSettingsProvider).valueOrNull;
      final targetLang = langSettings?.targetLang ?? 'en';
      // User-pinned source language. When concrete (non-'auto') the server
      // injects ONLY that language's food-translation traps + few-shot,
      // keeping the vision prompt lean instead of shipping every language's
      // block on every request. Omitted when 'auto' so the server stays on
      // its compact base prompt.
      final sourceLang = langSettings?.sourceLang;
      final api = ref.read(apiClientProvider);
      // Downscale + recompress before upload: a full-res capture costs more
      // vision tokens and uploads slower without reading the sign any better.
      final compressed =
          await _cameraService.compressForVision(bytes, scene: scene);
      final imageBase64 = base64Encode(compressed);

      final response = await api.dio.post('/translate-image', data: {
        'imageBase64': imageBase64,
        'targetLang': targetLang,
        'scene': scene,
        if (sourceLang != null && sourceLang.isNotEmpty && sourceLang != 'auto')
          'sourceLang': sourceLang,
        // Ask the server (Gemini-routed) for per-block bounding boxes so
        // the result overlay can position each translation chip OVER the
        // matching source region — instead of the strip-distribution
        // fallback below that fakes evenly-spaced rows. Pass the
        // ORIGINAL capture dimensions: boxes come back normalized 0-1000
        // and the server scales them to whatever `imageWidth/Height` we
        // send, so we hand it the same coord space the overlay later
        // renders chips in (`_capturedImageSize`).
        'withBoxes': true,
        'imageWidth': size.width.round(),
        'imageHeight': size.height.round(),
      });
      if (!mounted) return;
      final data = response.data as Map?;
      final transcription = (data?['transcription'] as String?) ?? '';
      final translation = (data?['translation'] as String?) ?? '';
      // Server self-assesses confidence per image ("high" | "medium" | "low").
      // We map this onto the same numeric scale ML Kit blocks use so the
      // existing low-confidence UI (amber tint + warning badge) fires
      // automatically — see OcrBlock.isLowConfidence. The user MUST be able
      // to tell when a vision read is shaky: low-confidence sign translations
      // can be actively dangerous (a "STOP" misread as "SLOP", a "No entry"
      // dropped entirely), so silently rendering them with full trust — as
      // the previous `confidence: 1.0` did — is the bug we're fixing here.
      final visionConfidence = (data?['confidence'] as String?)?.toLowerCase();
      final mappedConfidence =
          _mapVisionConfidenceToScore(visionConfidence, scene);
      // Stash for the result screen's chip — null when the server didn't
      // include the field so the chip stays hidden on legacy responses
      // rather than misleading the user with a fabricated rating.
      _visionConfidence = (visionConfidence == 'high' ||
              visionConfidence == 'medium' ||
              visionConfidence == 'low')
          ? visionConfidence
          : null;
      // Server's content-type guess. Whitelist to the values our prompt
      // tells the model to use; anything else (legacy server, model
      // hallucination) becomes null so the chip stays hidden.
      final rawDetected = (data?['detectedScene'] as String?)?.toLowerCase();
      _detectedScene = const {'menu', 'sign', 'document', 'screenshot', 'other'}
              .contains(rawDetected)
          ? rawDetected
          : null;
      // Server's detected source language (lowercase 2-letter ISO 639-1).
      // Strict regex check — the model occasionally hands back full names
      // or locale-tagged codes, those would confuse the TTS voice pick.
      final rawSrcLang = (data?['sourceLang'] as String?)?.toLowerCase();
      _captureSourceLang =
          (rawSrcLang != null && RegExp(r'^[a-z]{2}$').hasMatch(rawSrcLang))
              ? rawSrcLang
              : null;
      // Surface low/medium confidence in telemetry for monitoring — separate
      // from `camera_capture` so we can chart it without scene-filtering.
      if (visionConfidence == 'low' || visionConfidence == 'medium') {
        ref.read(trackingServiceProvider).event('vision_confidence_warn',
            properties: {
              'confidence': visionConfidence,
              'scene':      scene,
            });
      }
      final l = AppLocalizations.of(context)!;

      if (transcription.trim().isEmpty && translation.trim().isEmpty) {
        // Auto-retry once with scene=auto — auto is the most permissive
        // framing (no menu/sign/document constraints), so a strict-scene
        // miss often becomes a hit when re-routed. Previously we retried
        // with scene=sign, but that forced PLACE IDENTIFICATION on
        // anything (menus, documents, screenshots), and the model would
        // correctly refuse to identify a "place" when the image isn't a
        // sign — leading to a second empty result and a wrong "No text
        // found" error on otherwise-readable content. Skip the retry when
        // already-auto (would just be a duplicate call) or when this IS
        // the retry (prevent infinite loop). The retry shares the same
        // captured JPEG — no second shutter sound, no perceptible extra
        // latency beyond the second LLM round-trip.
        if (!isRetry && scene != 'auto') {
          ref.read(trackingServiceProvider).event('vision_retry_auto',
              properties: {
                'original_scene': scene,
              });
          // Make sure the spinner stays visible while we hit the
          // server again — _step might already be `result`-bound
          // from a state we set above (it isn't right now, but
          // being explicit keeps this safe to refactor).
          if (mounted && _step != _CameraStep.translating) {
            setState(() => _step = _CameraStep.translating);
          }
          await _captureWithVision(path, bytes, size,
              scene: 'auto', isRetry: true);
          return;
        }
        setState(() {
          _capturedPath = path;
          _capturedImageSize = size;
          _blocks = [];
          _translations = [];
          _error = l.cameraNoText;
          _step = _resultStepRespectingBatch();
        });
        return;
      }

      // Per-block AR overlay path. Server returns `blocks[]` when we
      // pass withBoxes=true; each block already has its bounding box
      // scaled to the original capture's pixel coords (we sent `size`),
      // so we can build OcrBlocks directly and the result overlay will
      // position each chip over the actual text region — replacing the
      // strip-distribution hack below for every vision capture that the
      // server's box pipeline can serve (currently any image when the
      // Gemini-first box route succeeds). Falls through to the strip
      // / single-block code if blocks come back empty (e.g. an outage
      // where only Llama-4 served, returning no usable boxes).
      final rawBlocks = data?['blocks'];
      if (rawBlocks is List && rawBlocks.isNotEmpty) {
        final visionBlocks = <OcrBlock>[];
        final visionTranslations = <String>[];
        for (final b in rawBlocks) {
          if (b is! Map) continue;
          final original = (b['original'] as String?)?.trim() ?? '';
          final trVi = (b['translation'] as String?)?.trim() ?? '';
          if (original.isEmpty && trVi.isEmpty) continue;
          final box = b['box'];
          if (box is! List || box.length != 4) continue;
          // Server convention: [ymin, xmin, ymax, xmax] in pixels of the
          // dimensions we POSTed (matches `size` for camera captures).
          double n(int i) => (box[i] is num) ? (box[i] as num).toDouble() : 0.0;
          final ymin = n(0), xmin = n(1), ymax = n(2), xmax = n(3);
          if (xmax <= xmin || ymax <= ymin) continue;
          // Optional sub-items array: present only when this block holds
          // multiple distinct items (typical for menu rows with several
          // dish-name + price pairs on one line). Drives the explain
          // picker chips - server already paired each original with its
          // translation so the user sees readable labels instead of
          // having to drag-select source-language text.
          final rawItems = b['items'];
          List<OcrBlockItem>? items;
          if (rawItems is List && rawItems.isNotEmpty) {
            final parsed = <OcrBlockItem>[];
            for (final it in rawItems) {
              if (it is! Map) continue;
              final origIt = (it['original'] as String?)?.trim() ?? '';
              final trIt = (it['translation'] as String?)?.trim() ?? '';
              if (origIt.isEmpty && trIt.isEmpty) continue;
              parsed.add(OcrBlockItem(original: origIt, translation: trIt));
            }
            if (parsed.length >= 2) items = parsed;
          }
          visionBlocks.add(OcrBlock(
            text: original,
            boundingBox: Rect.fromLTRB(xmin, ymin, xmax, ymax),
            confidence: mappedConfidence,
            items: items,
          ));
          visionTranslations.add(trVi);
        }
        if (visionBlocks.isNotEmpty) {
          setState(() {
            _capturedPath = path;
            _capturedImageSize = size;
            _blocks = visionBlocks;
            _translations = visionTranslations;
            _error = null;
            _step = _resultStepRespectingBatch();
          });
          ref.read(trackingServiceProvider).event('camera_capture', properties: {
            'scene':             scene,
            'source_lang':
                ref.read(languageSettingsProvider).valueOrNull?.sourceLang ?? 'auto',
            'target_lang':       targetLang,
            'block_count':       visionBlocks.length,
            'total_chars':       transcription.length,
            'path':              'vision_boxes',
            'vision_confidence': visionConfidence ?? 'unknown',
          });
          return;
        }
      }

      // Per-line split for menu / screenshot — match what the user expects
      // when those scenes are picked. Both fields share \n line structure
      // (server prompt enforces `preserve_structure`), so a 1:1 alignment
      // is usually clean. If line counts diverge (LLM occasionally drops a
      // blank line), fall back to single-block to avoid stacking mismatched
      // pairs.
      final perLineScenes = scene == 'menu' || scene == 'screenshot';
      final srcLines = transcription
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final dstLines = translation
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (perLineScenes &&
          srcLines.length >= 2 &&
          srcLines.length == dstLines.length) {
        // Distribute vertical strips evenly across the image height. Bboxes
        // aren't precise (vision doesn't return per-line geometry), but
        // matching the visual order is enough for the result overlay to
        // stack cards top-to-bottom in reading order.
        final stripHeight = size.height / srcLines.length;
        final blocks = <OcrBlock>[];
        for (var i = 0; i < srcLines.length; i++) {
          blocks.add(OcrBlock(
            text: srcLines[i],
            boundingBox: Rect.fromLTWH(
              0,
              i * stripHeight,
              size.width,
              stripHeight,
            ),
            // Vision returns one confidence per image — each line shares it.
            confidence: mappedConfidence,
          ));
        }
        setState(() {
          _capturedPath = path;
          _capturedImageSize = size;
          _blocks = blocks;
          _translations = dstLines;
          _error = null;
          _step = _resultStepRespectingBatch();
        });
        ref.read(trackingServiceProvider).event('camera_capture', properties: {
          'scene':           scene,
          'source_lang':
              ref.read(languageSettingsProvider).valueOrNull?.sourceLang ?? 'auto',
          'target_lang':     targetLang,
          'block_count':     blocks.length,
          'total_chars':     transcription.length,
          'path':            'vision_per_line',
          'vision_confidence': visionConfidence ?? 'unknown',
        });
        return;
      }

      // Single block covering the whole image — sign / document / auto
      // semantics, OR a menu/screenshot whose line counts diverged.
      final block = OcrBlock(
        text: transcription.isNotEmpty ? transcription : translation,
        boundingBox: Rect.fromLTWH(0, 0, size.width, size.height),
        confidence: mappedConfidence,
      );
      setState(() {
        _capturedPath = path;
        _capturedImageSize = size;
        _blocks = [block];
        _translations = [translation];
        _error = null;
        _step = _resultStepRespectingBatch();
      });
      ref.read(trackingServiceProvider).event('camera_capture', properties: {
        'scene':           scene,
        'source_lang':
            ref.read(languageSettingsProvider).valueOrNull?.sourceLang ?? 'auto',
        'target_lang':     targetLang,
        'block_count':     1,
        'total_chars':     transcription.length,
        'path':            'vision',
        'vision_confidence': visionConfidence ?? 'unknown',
      });
    } catch (error) {
      debugPrint('[Camera] Vision capture failed: $error');
      ref.read(trackingServiceProvider).event('error_shown', properties: {
        'kind':  'vision_capture_failed',
        'scene': scene,
      });
      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      setState(() {
        _capturedPath = path;
        _capturedImageSize = size;
        _blocks = [];
        _translations = [];
        _error = l.cameraExplainError;
        _step = _resultStepRespectingBatch();
      });
    }
  }

  Future<void> _translateAndShow() async {
    final sw = Stopwatch()..start();
    try {
      final texts = _blocks.map((b) => b.text).toList();
      if (texts.isEmpty) {
        if (!mounted) return;
        setState(() {
          _translations = [];
          _pendingIndices = {};
          _step = _resultStepRespectingBatch();
        });
        return;
      }

      // Phase 1: probe cache synchronously and show overlay immediately
      // with cache hits + original text as placeholder for misses.
      final cache = _probeTranslationCache(texts);
      final initialTranslations = List<String>.generate(
        texts.length,
        (i) => cache.results[i] ?? texts[i],
      );
      final missSet = Set<int>.from(cache.missIndices);

      if (!mounted) return;
      setState(() {
        _translations = initialTranslations;
        _pendingIndices = missSet;
        _step = _resultStepRespectingBatch();
      });
      debugPrint('[Camera] Latency: cache probe ${sw.elapsedMilliseconds}ms '
          '(${cache.cacheHits}/${texts.length} hits)');

      // All cache hits → no network needed.
      if (cache.missIndices.isEmpty) return;

      // Phase 2: progressive chunk translation for cache misses.
      final chunkSw = Stopwatch()..start();
      await _translateBatch(
        texts,
        forceRefresh: false,
        onChunkDone: (partialTranslations, updatedIndices) {
          if (!mounted) return;
          setState(() {
            final updated = List<String>.from(_translations);
            for (var j = 0; j < updatedIndices.length; j++) {
              updated[updatedIndices[j]] = partialTranslations[j];
            }
            _translations = updated;
            _pendingIndices = _pendingIndices.difference(updatedIndices.toSet());
          });
          debugPrint('[Camera] Latency: chunk done +${chunkSw.elapsedMilliseconds}ms '
              '(${updatedIndices.length} blocks)');
        },
      );
      debugPrint('[Camera] Latency: TOTAL ${sw.elapsedMilliseconds}ms '
          '(${texts.length} blocks, ${cache.missIndices.length} network)');
    } catch (e) {
      debugPrint('[Camera] Translate failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _pendingIndices = {};
        _step = _resultStepRespectingBatch();
      });
    }
  }

  /// Probes the per-session translation cache for [texts]. Returns a record
  /// with partial results (null for misses), miss indices/texts, and hit count.
  /// Shared between [_translateAndShow] (immediate overlay) and
  /// [_translateBatch] (network fallback).
  ({
    List<String?> results,
    List<int> missIndices,
    List<String> missTexts,
    int cacheHits,
  }) _probeTranslationCache(
    List<String> texts, {
    bool forceRefresh = false,
  }) {
    final langSettings = ref.read(languageSettingsProvider).valueOrNull;
    final targetLang = langSettings?.targetLang ?? 'en';
    final sourceLang = langSettings?.sourceLang ?? 'auto';
    final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
        CameraScene.auto;

    final results = List<String?>.filled(texts.length, null);
    final missIndices = <int>[];
    final missTexts = <String>[];
    var cacheHits = 0;
    for (var i = 0; i < texts.length; i++) {
      final cached = forceRefresh
          ? null
          : TranslationCache.instance.lookup(
              text: texts[i],
              sourceLang: sourceLang,
              targetLang: targetLang,
              scene: scene.id,
            );
      if (cached != null) {
        results[i] = cached;
        cacheHits++;
      } else {
        missIndices.add(i);
        missTexts.add(texts[i]);
      }
    }
    return (
      results: results,
      missIndices: missIndices,
      missTexts: missTexts,
      cacheHits: cacheHits,
    );
  }

  Future<List<String>> _translateBatch(
    List<String> texts, {
    bool forceRefresh = false,
    void Function(List<String> partialTranslations, List<int> updatedIndices)?
        onChunkDone,
  }) async {
    final langSettings = ref.read(languageSettingsProvider).valueOrNull;
    final targetLang = langSettings?.targetLang ?? 'en';
    final sourceLang = langSettings?.sourceLang ?? 'auto';
    final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
        CameraScene.auto;

    // Probe the per-session cache before hitting the network.
    final probe = _probeTranslationCache(texts, forceRefresh: forceRefresh);
    final results = probe.results;
    final missIndices = probe.missIndices;
    final missTexts = probe.missTexts;

    if (texts.isNotEmpty) {
      ref.read(trackingServiceProvider).event('translate_cache', properties: {
        'hits': probe.cacheHits,
        'total': texts.length,
        'scene': scene.id,
      });
    }

    // All-hit fast path: skip the API entirely.
    if (missTexts.isEmpty) {
      return results.cast<String>();
    }

    try {
      final session = await SessionStore().load();
      if (session == null) {
        for (final idx in missIndices) {
          results[idx] = texts[idx];
        }
        return results.cast<String>();
      }

      final api = ref.read(apiClientProvider);

      final chunkRanges = <(int start, int end)>[];
      for (var i = 0; i < missTexts.length; i += _batchChunkSize) {
        chunkRanges.add(
          (i, math.min(i + _batchChunkSize, missTexts.length)),
        );
      }

      // Progressive path: fire all chunks in parallel, deliver each
      // result via onChunkDone as soon as it completes (completion-order,
      // not submission-order). This gives the speed of Future.wait while
      // still updating the overlay incrementally.
      if (onChunkDone != null) {
        await Future.wait(chunkRanges.map((range) async {
          final (start, end) = range;
          final partialTranslations = <String>[];
          final partialIndices = <int>[];
          try {
            final response = await api.dio
                .post('/translate-batch', data: {
                  'texts': missTexts.sublist(start, end),
                  'targetLang': targetLang,
                  'appHint': 'camera',
                  'scene': scene.id,
                })
                .timeout(const Duration(seconds: 60));
            final data = response.data as Map?;
            if (_captureSourceLang == null) {
              final rawSrc =
                  (data?['detectedSourceLang'] as String?)?.toLowerCase();
              if (rawSrc != null &&
                  RegExp(r'^[a-z]{2}$').hasMatch(rawSrc)) {
                _captureSourceLang = rawSrc;
              }
            }
            final raw = data?['translations'] as List?;
            for (var k = 0; k < end - start; k++) {
              final missIdx = start + k;
              final origIdx = missIndices[missIdx];
              final originalText = texts[origIdx];
              final value =
                  (raw != null && k < raw.length) ? raw[k] : null;
              final translation =
                  value is String && value.trim().isNotEmpty
                      ? value
                      : originalText;
              results[origIdx] = translation;
              partialIndices.add(origIdx);
              partialTranslations.add(translation);
              if (translation != originalText) {
                TranslationCache.instance.store(
                  text: originalText,
                  sourceLang: sourceLang,
                  targetLang: targetLang,
                  scene: scene.id,
                  translation: translation,
                );
              }
            }
          } catch (e) {
            debugPrint(
                '[Camera] Translate chunk failed ($start-$end): $e');
            for (var k = 0; k < end - start; k++) {
              final missIdx = start + k;
              final origIdx = missIndices[missIdx];
              results[origIdx] = texts[origIdx];
              partialIndices.add(origIdx);
              partialTranslations.add(texts[origIdx]);
            }
          }
          onChunkDone(partialTranslations, partialIndices);
        }));
        return results.cast<String>();
      }

      // Batch path: run all chunks in parallel, return when all done.
      final chunkResults = await Future.wait(chunkRanges.map((range) async {
        final (start, end) = range;
        try {
          final response = await api.dio
              .post('/translate-batch', data: {
                'texts': missTexts.sublist(start, end),
                'targetLang': targetLang,
                'appHint': 'camera',
                'scene': scene.id,
              })
              .timeout(const Duration(seconds: 60));
          final data = response.data as Map?;
          if (_captureSourceLang == null) {
            final rawSrc =
                (data?['detectedSourceLang'] as String?)?.toLowerCase();
            if (rawSrc != null && RegExp(r'^[a-z]{2}$').hasMatch(rawSrc)) {
              _captureSourceLang = rawSrc;
            }
          }
          return data?['translations'] as List?;
        } catch (e) {
          debugPrint('[Camera] Translate chunk failed ($start-$end): $e');
          return null;
        }
      }));

      for (var c = 0; c < chunkRanges.length; c++) {
        final (start, end) = chunkRanges[c];
        final raw = chunkResults[c];
        for (var k = 0; k < end - start; k++) {
          final missIdx = start + k;
          final origIdx = missIndices[missIdx];
          final originalText = texts[origIdx];
          final value = (raw != null && k < raw.length) ? raw[k] : null;
          final translation = value is String && value.trim().isNotEmpty
              ? value
              : originalText;
          results[origIdx] = translation;
          if (translation != originalText) {
            TranslationCache.instance.store(
              text: originalText,
              sourceLang: sourceLang,
              targetLang: targetLang,
              scene: scene.id,
              translation: translation,
            );
          }
        }
      }
      return results.cast<String>();
    } catch (e) {
      debugPrint('[Camera] Translate failed: $e');
      for (final idx in missIndices) {
        results[idx] = texts[idx];
      }
      return results.cast<String>();
    }
  }

  /// Max texts per `/translate-batch` request. Mirrors the server DTO's
  /// `ArrayMaxSize(60)` exactly — we cap at the limit, not below, so a
  /// dense capture with N blocks costs `ceil(N / 60)` quota counts
  /// rather than `ceil(N / 50)`. Server failing at the exact boundary
  /// would mean an off-by-one in class-validator, which we'd want to
  /// catch in dev anyway.
  /// Per-/translate-batch chunk cap. Empirically the server LLM takes
  /// ~0.5-0.8 s per Japanese-to-Vietnamese block; at 60 blocks the chunk
  /// would hit Dio's 30 s receive timeout on dense menu captures. 15 keeps
  /// each chunk's worst case around 12 s while parallelising 3-4 chunks
  /// for a 50-block capture - faster total than 60-per-chunk anyway.
  static const int _batchChunkSize = 15;

  void _retake() {
    setState(() {
      _step = _CameraStep.preview;
      _capturedPath = null;
      _capturedImageSize = null;
      _blocks = [];
      _translations = [];
      _liveBlocks = [];
      _error = null;
      _visionConfidence = null;
      _detectedScene = null;
      _captureSourceLang = null;
      // Drop the multi-pick batch on retake — going back to live
      // preview implies the user is starting over, not continuing to
      // edit the previous result set.
      _batchQueue.clear();
      _activeBatchIndex = 0;
      _isBatchProcessing = false;
      _batchTotal = 0;
      _batchDone = 0;
    });
    _startStream();
  }

  /// Rasterise the shareable subtree (captured image + translation
  /// overlay + chips) to a PNG and hand it to the OS share sheet. The
  /// shared file lives in the app's temp directory under a millis-
  /// suffixed name so back-to-back shares don't clobber each other
  /// (the system share sheet hangs on to the path past the dialog
  /// dismissal).
  ///
  /// Currently unreferenced: the Share action chip was pulled from the
  /// result bar until the export quality is reworked. Kept (with the
  /// RepaintBoundary it reads) so re-enabling is a one-line button add.
  // ignore: unused_element
  Future<void> _shareResult() async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary = _resultRepaintKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('[Camera] Share: no render boundary');
        return;
      }
      // pixelRatio=3.0: matches a typical phone's logical→physical
      // ratio so the exported PNG is sharp on every receiving device,
      // not "screen-resolution" tiny.
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        debugPrint('[Camera] Share: toByteData returned null');
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final filename =
          'transkey_share_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);
      ref.read(trackingServiceProvider).event('camera_share');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: l.cameraShareSubject,
        ),
      );
    } catch (e) {
      debugPrint('[Camera] Share failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.cameraShareFailed),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _copyAll() {
    final all = <String>[];
    for (var i = 0; i < _blocks.length; i++) {
      final original = _blocks[i].text;
      final translated = i < _translations.length ? _translations[i] : '';
      if (translated.isNotEmpty && translated != original) {
        all.add('$original → $translated');
      } else {
        all.add(original);
      }
    }
    Clipboard.setData(ClipboardData(text: all.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.copied)),
    );
  }

  Future<void> _toggleFlash() async {
    _flashOn = !_flashOn;
    await _cameraService.setFlash(_flashOn);
    setState(() {});
  }

  /// Open the language picker to change the target translation language
  /// without leaving the camera. Pauses the OCR stream while the sheet is
  /// open (same pattern as [_explainBlock]) so the live overlay doesn't
  /// thrash under the modal. The new lang takes effect on the NEXT capture
  /// — already-captured results aren't re-translated automatically; the
  /// user can tap retake.
  Future<void> _changeTargetLang() async {
    final current =
        ref.read(languageSettingsProvider).valueOrNull?.targetLang ?? 'en';
    final streaming = _step == _CameraStep.preview;
    if (streaming) await _cameraService.stopTextStream();
    if (!mounted) return;
    final picked = await LanguagePickerSheet.show(
      context,
      selectedCode: current,
      field: LanguagePickerField.target,
      // Target language can't be "auto" — only source can.
      showAuto: false,
    );
    if (picked != null && picked != current) {
      await ref
          .read(languageSettingsProvider.notifier)
          .setTargetLang(picked);
      ref.read(trackingServiceProvider).event('target_lang_change', properties: {
        'from':   current,
        'to':     picked,
        'source': 'camera',
      });
    }
    if (!mounted) return;
    if (streaming && _step == _CameraStep.preview) _startStream();
  }

  /// Label for the source pill — "Auto" when undetected, else the code.
  String _sourceLabel(AppLocalizations l) {
    final src =
        ref.watch(languageSettingsProvider).valueOrNull?.sourceLang ?? 'auto';
    return src.toLowerCase() == 'auto' ? l.autoDetect : src.toUpperCase();
  }

  /// Open the source-language picker. Setting a concrete source (esp. a
  /// non-Latin script ML Kit can't read) routes captures to the vision LLM
  /// for accuracy. "Auto" keeps on-device-first behaviour. Same stream
  /// pause/resume dance as [_changeTargetLang].
  Future<void> _changeSourceLang() async {
    final current =
        ref.read(languageSettingsProvider).valueOrNull?.sourceLang ?? 'auto';
    final streaming = _step == _CameraStep.preview;
    if (streaming) await _cameraService.stopTextStream();
    if (!mounted) return;
    final picked = await LanguagePickerSheet.show(
      context,
      selectedCode: current,
      field: LanguagePickerField.source,
      // Source CAN be auto-detect.
      showAuto: true,
    );
    if (picked != null && picked != current) {
      await ref
          .read(languageSettingsProvider.notifier)
          .setSourceLang(picked);
      ref.read(trackingServiceProvider).event('source_lang_change', properties: {
        'from':   current,
        'to':     picked,
        'source': 'camera',
      });
    }
    if (!mounted) return;
    if (streaming && _step == _CameraStep.preview) _startStream();
  }

  String _langDisplay(String code) {
    const names = {
      'en': 'English', 'vi': 'Tiếng Việt', 'ja': '日本語',
      'zh': '中文', 'ko': '한국어', 'fr': 'Français',
      'de': 'Deutsch', 'es': 'Español', 'pt': 'Português',
      'ru': 'Русский', 'ar': 'العربية', 'it': 'Italiano',
      'id': 'Bahasa', 'th': 'ไทย',
    };
    return names[code] ?? code.toUpperCase();
  }
}

/// Pill used in the camera bottom bar. Tap to snap zoom to a preset.
/// Active state (within 0.15× of preset) gets a filled white background
/// to mimic the iOS camera "1× / 2× / max" toggle look.
class _ZoomPresetPill extends StatelessWidget {
  const _ZoomPresetPill({
    required this.label,
    required this.zoom,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final double zoom;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.black87 : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact pill that surfaces the server's self-assessed confidence on
/// a vision capture. Sits at top-left of the result screen.
///
/// Color signals the level at a glance — even before the user reads
/// the label:
///   - high   → green : the AI is confident, trust the translation
///   - medium → amber : double-check before acting on it
///   - low    → red   : likely wrong, prefer retake
///
/// Each level has its own icon as a redundant cue for accessibility
/// (color-blind users) and for languages whose label sits at the edge
/// of single-word fit.
/// Compact prev / next pager shown at the top of the result screen
/// during a multi-pick gallery batch (2+ images). Tap arrows to walk
/// through the processed pages without re-shooting; current position
/// rendered as "2 / 4" between them. Disabled state at the ends so
/// users don't have to learn an invisible boundary.
class _BatchPageNav extends StatelessWidget {
  const _BatchPageNav({
    required this.currentIndex,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });
  final int currentIndex;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final canPrev = currentIndex > 0;
    final canNext = currentIndex < total - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 22),
            color: canPrev ? Colors.white : Colors.white38,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: canPrev ? onPrev : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${currentIndex + 1} / $total',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 22),
            color: canNext ? Colors.white : Colors.white38,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: canNext ? onNext : null,
          ),
        ],
      ),
    );
  }
}

/// Frozen state of one processed capture, used to swap between pages
/// in a multi-pick gallery batch without re-running OCR / vision. The
/// fields mirror the per-capture singletons on [_CameraScreenState];
/// see [_snapshotActive] / [_restoreFromSnapshot] for the round-trip.
/// Per-image OCR result carried between the parallel-OCR phase and the
/// sequential translate phase of the gallery batch flow. Holds only the
/// data needed to seed [_translateAndShow] for one image - no shared
/// state, no translations yet.
class _BatchOcrResult {
  _BatchOcrResult({
    required this.path,
    required this.size,
    required this.blocks,
  });
  final String path;
  final ui.Size size;
  final List<OcrBlock> blocks;
}

class _BatchSnapshot {
  _BatchSnapshot({
    required this.path,
    required this.imageSize,
    required this.blocks,
    required this.translations,
    this.visionConfidence,
    this.detectedScene,
    this.sourceLang,
    this.error,
  });
  final String path;
  final ui.Size imageSize;
  List<OcrBlock> blocks;
  List<String> translations;
  String? visionConfidence;
  String? detectedScene;
  String? sourceLang;
  String? error;
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.level});
  final String level;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final String label;
    final Color bg;
    final IconData icon;
    switch (level) {
      case 'high':
        label = l.cameraConfidenceReliable;
        // Tailwind green-700 — readable on bright photo backgrounds.
        bg = const Color(0xFF15803D);
        icon = Icons.verified_outlined;
        break;
      case 'medium':
        label = l.cameraConfidenceCaution;
        bg = const Color(0xFFB45309); // amber-700
        icon = Icons.warning_amber_rounded;
        break;
      case 'low':
        label = l.cameraConfidenceUnreliable;
        bg = const Color(0xFFB91C1C); // red-700
        icon = Icons.error_outline;
        break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        // Slight transparency so the chip reads as an overlay, not a
        // solid UI element competing with the photo behind it.
        color: bg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Detected: <scene>" chip surfacing the server's content-type guess.
/// Rendered below the confidence chip when the user's selected scene
/// is `auto`. The chip is a soft confirmation — same dark-pill style as
/// the explain hint, NOT colour-coded like the confidence chip, so it
/// reads as informational metadata rather than another warning level.
class _DetectedSceneChip extends StatelessWidget {
  const _DetectedSceneChip({required this.scene});
  final String scene;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final String sceneLabel;
    final IconData icon;
    switch (scene) {
      case 'menu':
        sceneLabel = l.cameraSceneMenu;
        icon = Icons.restaurant_menu_outlined;
        break;
      case 'sign':
        sceneLabel = l.cameraSceneSign;
        icon = Icons.storefront_outlined;
        break;
      case 'document':
        sceneLabel = l.cameraSceneDocument;
        icon = Icons.description_outlined;
        break;
      case 'screenshot':
        sceneLabel = l.cameraSceneScreenshot;
        icon = Icons.phone_iphone_outlined;
        break;
      default:
        sceneLabel = l.cameraSceneOther;
        icon = Icons.help_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 12),
          const SizedBox(width: 5),
          Text(
            l.cameraDetected(sceneLabel),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Language-neutral "scanning" indicator shown on the live preview
/// before the first text box appears, so the camera doesn't look dead
/// during the camera-init + first-OCR window. Pure icon + spinner — no
/// i18n needed.
class _ScanningPill extends StatelessWidget {
  const _ScanningPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          SizedBox(width: 8),
          Icon(Icons.document_scanner_outlined,
              size: 15, color: Colors.white70),
        ],
      ),
    );
  }
}

/// Circular icon-only button for the result action bar's view-control
/// cluster (eye / help / reset). Visually lighter than [_ActionChip] so
/// the labelled Retake / Copy actions stay the primary affordances.
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact pill in the camera top bar for a language slot (source or
/// target). Shows the language label + a dropdown caret; tapping opens the
/// relevant picker. [label] is already display-ready ("Auto", "VI", "JA"…).
class _LangPill extends StatelessWidget {
  const _LangPill({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Icon(Icons.arrow_drop_down,
                  color: Colors.white70, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gallery shortcut next to the capture circle — opens the system image
/// picker; the chosen photo runs through the same OCR + scene pipeline as
/// a live capture. Sized + styled to read as a secondary action (not the
/// primary one — that's the white capture button).
class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Icon(
            Icons.photo_library_outlined,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// Tap-to-focus feedback ring. A fresh instance (keyed by tap position)
/// plays a quick shrink-in animation each time the user taps, so the ring
/// reads as "focusing here now" rather than a static marker.
class _FocusRing extends StatelessWidget {
  const _FocusRing({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.4, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.amberAccent, width: 2),
        ),
      ),
    );
  }
}
