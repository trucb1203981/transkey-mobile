import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/auth/session_store.dart';
import '../../../core/camera/camera_service.dart';
import '../../../core/tracking/tracking_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/upgrade_nudge_sheet.dart';
import '../../translate/providers/camera_settings_provider.dart';
import '../../translate/providers/features_provider.dart';
import '../../translate/providers/language_settings_provider.dart';
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

class _CameraScreenState extends ConsumerState<CameraScreen> {
  final _cameraService = CameraService();
  _CameraStep _step = _CameraStep.preview;
  bool _flashOn = false;

  String? _capturedPath;
  ui.Size? _capturedImageSize;
  List<OcrBlock> _liveBlocks = [];
  List<OcrBlock> _blocks = [];
  List<String> _translations = [];
  String? _error;

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

  @override
  void initState() {
    super.initState();
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

  void _startStream() {
    _cameraService.startTextStream((blocks) {
      if (mounted && _step == _CameraStep.preview) {
        setState(() => _liveBlocks = blocks);
      }
    });
  }

  @override
  void dispose() {
    _focusResetTimer?.cancel();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBody(l),
          _buildTopBar(l),
          if (_step == _CameraStep.preview) _buildBottomControls(l),
        ],
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

  /// Open the "What is this?" sheet for a single live-preview block.
  /// Pauses the OCR stream while the sheet is open so the box overlay
  /// doesn't shift around under the modal; resumes on close.
  Future<void> _explainBlock(OcrBlock block) async {
    ref.read(trackingServiceProvider).event('region_explain', properties: {
      'length': block.text.length,
      'step':   _step.name,
    });
    await _cameraService.stopTextStream();
    if (!mounted) return;
    await WhatIsThisSheet.show(context, block.text);
    if (!mounted) return;
    if (_step == _CameraStep.preview) _startStream();
  }

  Widget _buildTranslating(AppLocalizations l) {
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
                  l.cameraTranslating,
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
        Center(
          child: Image.file(File(_capturedPath!), fit: BoxFit.contain),
        ),
        if (_blocks.isNotEmpty && _translations.isNotEmpty)
          CameraResultOverlay(
            // Per-capture Key forces a FRESH State instance every time
            // the captured file changes. Without this, internal state
            // (_expanded set, _dragOffsets map, _overlayVisible toggle)
            // bleeds across captures: a block expanded by index in
            // capture N would auto-expand the block at the same index
            // in capture N+1, and drag offsets from previous scene
            // would apply to the new translations. Mode-switch bug
            // surfaced when user changed scene → captured again →
            // unrelated card was pre-expanded / pre-dragged.
            key: ValueKey(_capturedPath),
            blocks: _blocks,
            translations: _translations,
            imageSize: _capturedImageSize!,
            hideLowConfidence: settings.hideLowConfidence,
            showOriginalAlways: settings.showOriginalAlways,
            overlayOpacity: settings.overlayOpacity,
            // "What is this?" per-card: same handler the live preview
            // uses (stop stream, show sheet, restart on close). The
            // stream-stop is a no-op here because we're already in
            // result mode, and the restart guard checks _step.
            onExplain: _explainBlock,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionChip(
                icon: Icons.refresh,
                label: AppLocalizations.of(context)!.cameraRetake,
                onTap: _retake,
              ),
              const SizedBox(width: 16),
              _ActionChip(
                icon: Icons.copy,
                label: AppLocalizations.of(context)!.cameraCopyAll,
                onTap: _copyAll,
              ),
            ],
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
                  IconButton(
                    icon: const Icon(Icons.help_outline, color: Colors.white),
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
                      border: Border.all(color: Colors.white, width: 4),
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

  Future<void> _capture() async {
    // Instant UI feedback: switch to the translating screen IMMEDIATELY
    // when the user taps. The 2 s OCR pipeline otherwise leaves the user
    // staring at the live preview wondering whether the tap registered.
    // [_capturedPath] is still null at this point so [_buildTranslating]
    // falls back to the spinner-over-black layout until the picture is
    // ready, then the captured frame is drawn behind the spinner.
    setState(() => _step = _CameraStep.translating);

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

  /// Pick an existing photo from the gallery and run it through the same
  /// OCR + scene pipeline as a live capture. Useful when the user already
  /// has a photo of the menu/sign/document and doesn't need a fresh shot —
  /// or when the lighting at the moment is bad and they'd rather use a
  /// clearer photo from before.
  Future<void> _pickFromGallery() async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
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
    if (picked == null) return; // user cancelled
    if (!mounted) return;
    ref.read(trackingServiceProvider).event('gallery_pick');
    setState(() => _step = _CameraStep.translating);
    await _cameraService.stopTextStream();
    try {
      // Fast OCR for gallery: single pass instead of the 3-pass live-
      // capture pipeline. User picked the photo themselves — it's almost
      // always clear enough that contrast/binarize variants add latency
      // (4-6 s on a 1600 px image) without finding more text. The empty-
      // result vision fallback in _processImage still catches truly
      // hard cases (handwriting, stylized) so we don't lose quality.
      await _processImage(picked.path, aggressivePasses: false);
    } catch (e) {
      debugPrint('[Camera] Gallery process failed: $e');
      _recoverToPreview();
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
    // East / Russia / Greece etc. scans a script ML Kit literally cannot
    // read (Thai, Arabic, Cyrillic, Greek, Hebrew, Khmer, …). If the user
    // pinned such a source language, skip ML Kit entirely and go straight
    // to the vision LLM — it reads any script. (When source is "auto" we
    // still try ML Kit first and lean on the weak-result fallback below.)
    final sourceLang =
        ref.read(languageSettingsProvider).valueOrNull?.sourceLang;
    if (_sourceNeedsVision(sourceLang)) {
      debugPrint('[Camera] source=$sourceLang not ML-Kit-readable — vision');
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
    // human. 12 chars is comfortably below any real menu/document capture
    // but above a single short word the OCR genuinely nailed.
    final totalChars = blocks.fold<int>(
      0,
      (sum, b) => sum + b.text.replaceAll(RegExp(r'\s'), '').length,
    );

    if (blocks.isEmpty || totalChars < 12) {
      debugPrint('[Camera] OCR weak ($totalChars chars) — vision fallback');
      ref.read(trackingServiceProvider).event('vision_fallback', properties: {
        'reason':      'weak_ocr',
        'scene':       scene.id,
        'total_chars': totalChars,
      });
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

    ref.read(trackingServiceProvider).event('camera_capture', properties: {
      'scene':        scene.id,
      'source_lang':  sourceLang ?? 'auto',
      'target_lang':
          ref.read(languageSettingsProvider).valueOrNull?.targetLang ?? 'en',
      'block_count':  blocks.length,
      'total_chars':  totalChars,
      'path':         'mlkit',
    });

    _translateAndShow();
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
  }) async {
    try {
      final langSettings = ref.read(languageSettingsProvider).valueOrNull;
      final targetLang = langSettings?.targetLang ?? 'en';
      final api = ref.read(apiClientProvider);
      // Downscale + recompress before upload: a full-res capture costs more
      // vision tokens and uploads slower without reading the sign any better.
      final compressed = await _cameraService.compressForVision(bytes);
      final imageBase64 = base64Encode(compressed);

      final response = await api.dio.post('/translate-image', data: {
        'imageBase64': imageBase64,
        'targetLang': targetLang,
        'scene': scene,
      });
      if (!mounted) return;
      final data = response.data as Map?;
      final transcription = (data?['transcription'] as String?) ?? '';
      final translation = (data?['translation'] as String?) ?? '';
      final l = AppLocalizations.of(context)!;

      if (transcription.trim().isEmpty && translation.trim().isEmpty) {
        setState(() {
          _capturedPath = path;
          _capturedImageSize = size;
          _blocks = [];
          _translations = [];
          _error = l.cameraNoText;
          _step = _CameraStep.result;
        });
        return;
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
            confidence: 1.0,
          ));
        }
        setState(() {
          _capturedPath = path;
          _capturedImageSize = size;
          _blocks = blocks;
          _translations = dstLines;
          _error = null;
          _step = _CameraStep.result;
        });
        ref.read(trackingServiceProvider).event('camera_capture', properties: {
          'scene':        scene,
          'source_lang':
              ref.read(languageSettingsProvider).valueOrNull?.sourceLang ?? 'auto',
          'target_lang':  targetLang,
          'block_count':  blocks.length,
          'total_chars':  transcription.length,
          'path':         'vision_per_line',
        });
        return;
      }

      // Single block covering the whole image — sign / document / auto
      // semantics, OR a menu/screenshot whose line counts diverged.
      final block = OcrBlock(
        text: transcription.isNotEmpty ? transcription : translation,
        boundingBox: Rect.fromLTWH(0, 0, size.width, size.height),
        confidence: 1.0,
      );
      setState(() {
        _capturedPath = path;
        _capturedImageSize = size;
        _blocks = [block];
        _translations = [translation];
        _error = null;
        _step = _CameraStep.result;
      });
      ref.read(trackingServiceProvider).event('camera_capture', properties: {
        'scene':        scene,
        'source_lang':
            ref.read(languageSettingsProvider).valueOrNull?.sourceLang ?? 'auto',
        'target_lang':  targetLang,
        'block_count':  1,
        'total_chars':  transcription.length,
        'path':         'vision',
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
        _step = _CameraStep.result;
      });
    }
  }

  Future<void> _translateAndShow() async {
    try {
      final texts = _blocks.map((b) => b.text).toList();
      final translations = await _translateBatch(texts);
      if (!mounted) return;
      setState(() {
        _translations = translations;
        _step = _CameraStep.result;
      });
    } catch (e) {
      debugPrint('[Camera] Translate failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _step = _CameraStep.result;
      });
    }
  }

  Future<List<String>> _translateBatch(List<String> texts) async {
    try {
      final session = await SessionStore().load();
      if (session == null) return texts;

      final langSettings = ref.read(languageSettingsProvider).valueOrNull;
      final targetLang = langSettings?.targetLang ?? 'en';
      final scene = ref.read(cameraSettingsProvider).valueOrNull?.scene ??
          CameraScene.auto;

      final api = ref.read(apiClientProvider);
      final response = await api.dio.post('/translate-batch', data: {
        'texts': texts,
        'targetLang': targetLang,
        'appHint': 'camera',
        // Server uses this to inject scene-specific guidance into the
        // batch prompt (menu-vs-document priorities differ a lot).
        'scene': scene.id,
      });

      final data = response.data as Map?;
      final raw = data?['translations'] as List?;
      if (raw == null) return texts;

      final out = <String>[];
      for (var i = 0; i < texts.length; i++) {
        final value = i < raw.length ? raw[i] : null;
        out.add(
          value is String && value.trim().isNotEmpty ? value : texts[i],
        );
      }
      return out;
    } catch (e) {
      debugPrint('[Camera] Translate failed: $e');
      return texts;
    }
  }

  void _retake() {
    setState(() {
      _step = _CameraStep.preview;
      _capturedPath = null;
      _capturedImageSize = null;
      _blocks = [];
      _translations = [];
      _liveBlocks = [];
      _error = null;
    });
    _startStream();
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
