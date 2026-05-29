import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/camera/camera_service.dart';
import '../../../core/tracking/tracking_provider.dart';

const _kConfidenceKey = 'tk_cam_confidence_threshold';
const _kHideLowKey = 'tk_cam_hide_low';
const _kShowOriginalAlwaysKey = 'tk_cam_show_original';
const _kOverlayOpacityKey = 'tk_cam_overlay_opacity';
const _kSceneKey = 'tk_cam_scene';
const _kPrimaryColorKey = 'tk_cam_primary_color';
const _kOverlayFontScaleKey = 'tk_cam_overlay_font_scale_v2';

// User-tunable multiplier on the overlay font. Unlike the earlier
// attempt this version DOES NOT shrink the rendered text back to fit
// the bbox - at >1.0 the text grows past the bubble bounds and paints
// over the surrounding art. The card background stays anchored to the
// bbox so only the text glyphs spill out. Reset button in the settings
// sheet snaps back to 1.0.
const double kOverlayFontScaleMin = 1.0;
const double kOverlayFontScaleMax = 3.0;
const double kOverlayFontScaleDefault = 1.0;

/// Capture scene the user picks before / during capture. The value flows
/// to the server's translate-batch prompt as a "scene" hint and also
/// tunes the OCR pipeline's block-merge behaviour on the client.
///
/// Adding a new value: extend [CameraScene], update [cameraSceneFromId],
/// add an i18n label, add a hint block in the server prompt's
/// SCENE_HINTS map.
enum CameraScene {
  auto('auto'),
  document('document'),
  menu('menu'),
  sign('sign'),
  screenshot('screenshot'),
  manga('manga');

  const CameraScene(this.id);
  final String id;
}

CameraScene cameraSceneFromId(String? id) {
  for (final s in CameraScene.values) {
    if (s.id == id) return s;
  }
  return CameraScene.auto;
}

/// Persisted user-tunable parameters for the Lens / camera-translate flow.
/// Values surface in the settings sheet (gear icon in the camera top bar)
/// and are picked up by the OCR pipeline + overlay renderer immediately.
class CameraSettings {
  const CameraSettings({
    required this.confidenceThreshold,
    required this.hideLowConfidence,
    required this.showOriginalAlways,
    required this.overlayOpacity,
    required this.usePrimaryOverlayColor,
    required this.scene,
    required this.overlayFontScale,
  });

  /// OCR blocks with confidence below this are dropped before translation.
  /// Range: 0.0 (keep everything) — 0.7 (very strict, may drop real text).
  /// Default 0.30 matches the [kOcrConfidenceFloor] hard-coded floor;
  /// users can relax or tighten as needed. iOS doesn't report confidence
  /// so this only affects Android.
  final double confidenceThreshold;

  /// When true, blocks above the floor but below the "badge" threshold
  /// (0.30–0.50) are also dropped instead of rendered with a warning.
  /// Use this for clean documents where any low-confidence block is noise.
  final bool hideLowConfidence;

  /// When true, the original text always renders under the translation
  /// (small, italic). Off by default — user can tap a card to expand.
  final bool showOriginalAlways;

  /// Background opacity of translation cards. Range 0.4–1.0. Low values
  /// let the source photo show through (good for verification); high
  /// values prioritise readability.
  final double overlayOpacity;

  /// When true, all translation cards use a single primary color instead of
  /// per-block background sampling. Cleaner look, avoids color mismatches.
  final bool usePrimaryOverlayColor;

  /// Active capture scene. Tuned independently by the chip row in the
  /// camera bottom bar — the settings sheet doesn't expose this knob
  /// (it'd be one extra tap away from the live preview where users
  /// actually make this decision).
  final CameraScene scene;

  /// Multiplier applied to the rendered overlay font. At 1.0 the auto
  /// fitter picks a size that fits the bbox; above 1.0 the user has
  /// chosen "I want bigger text even if it spills out of the bubble" -
  /// the renderer honours the chosen size without shrinking it back and
  /// without clipping the overflowing glyphs (only the card background
  /// stays bbox-anchored). Reset button in the settings sheet returns
  /// to 1.0.
  final double overlayFontScale;

  static const defaults = CameraSettings(
    confidenceThreshold: kOcrConfidenceFloor,
    hideLowConfidence: false,
    showOriginalAlways: false,
    overlayOpacity: 0.80,
    usePrimaryOverlayColor: false,
    scene: CameraScene.auto,
    overlayFontScale: kOverlayFontScaleDefault,
  );

  CameraSettings copyWith({
    double? confidenceThreshold,
    bool? hideLowConfidence,
    bool? showOriginalAlways,
    double? overlayOpacity,
    bool? usePrimaryOverlayColor,
    CameraScene? scene,
    double? overlayFontScale,
  }) =>
      CameraSettings(
        confidenceThreshold:
            confidenceThreshold ?? this.confidenceThreshold,
        hideLowConfidence: hideLowConfidence ?? this.hideLowConfidence,
        showOriginalAlways:
            showOriginalAlways ?? this.showOriginalAlways,
        overlayOpacity: overlayOpacity ?? this.overlayOpacity,
        usePrimaryOverlayColor:
            usePrimaryOverlayColor ?? this.usePrimaryOverlayColor,
        scene: scene ?? this.scene,
        overlayFontScale: overlayFontScale ?? this.overlayFontScale,
      );
}

class CameraSettingsNotifier extends AsyncNotifier<CameraSettings> {
  @override
  Future<CameraSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return CameraSettings(
      confidenceThreshold:
          prefs.getDouble(_kConfidenceKey) ?? CameraSettings.defaults.confidenceThreshold,
      hideLowConfidence:
          prefs.getBool(_kHideLowKey) ?? CameraSettings.defaults.hideLowConfidence,
      showOriginalAlways: prefs.getBool(_kShowOriginalAlwaysKey) ??
          CameraSettings.defaults.showOriginalAlways,
      overlayOpacity: prefs.getDouble(_kOverlayOpacityKey) ??
          CameraSettings.defaults.overlayOpacity,
      usePrimaryOverlayColor: prefs.getBool(_kPrimaryColorKey) ??
          CameraSettings.defaults.usePrimaryOverlayColor,
      scene: cameraSceneFromId(prefs.getString(_kSceneKey)),
      overlayFontScale: (prefs.getDouble(_kOverlayFontScaleKey) ??
              kOverlayFontScaleDefault)
          .clamp(kOverlayFontScaleMin, kOverlayFontScaleMax),
    );
  }

  Future<void> setScene(CameraScene scene) async {
    final current = state.valueOrNull;
    if (current == null || current.scene == scene) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSceneKey, scene.id);
    state = AsyncData(current.copyWith(scene: scene));
    ref.read(trackingServiceProvider).event('camera_scene_change',
        properties: {'from': current.scene.id, 'to': scene.id});
  }

  Future<void> setConfidenceThreshold(double value) async {
    final clamped = value.clamp(0.0, 0.7);
    final current = state.valueOrNull;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kConfidenceKey, clamped);
    state = AsyncData(current.copyWith(confidenceThreshold: clamped));
  }

  Future<void> setHideLowConfidence(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideLowKey, value);
    state = AsyncData(current.copyWith(hideLowConfidence: value));
  }

  Future<void> setShowOriginalAlways(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowOriginalAlwaysKey, value);
    state = AsyncData(current.copyWith(showOriginalAlways: value));
  }

  Future<void> setOverlayOpacity(double value) async {
    final clamped = value.clamp(0.4, 1.0);
    final current = state.valueOrNull;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kOverlayOpacityKey, clamped);
    state = AsyncData(current.copyWith(overlayOpacity: clamped));
  }

  Future<void> setUsePrimaryOverlayColor(bool value) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPrimaryColorKey, value);
    state = AsyncData(current.copyWith(usePrimaryOverlayColor: value));
  }

  Future<void> setOverlayFontScale(double value) async {
    final clamped = value.clamp(kOverlayFontScaleMin, kOverlayFontScaleMax);
    final current = state.valueOrNull;
    if (current == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kOverlayFontScaleKey, clamped);
    state = AsyncData(current.copyWith(overlayFontScale: clamped));
  }

  Future<void> resetOverlayFontScale() =>
      setOverlayFontScale(kOverlayFontScaleDefault);

  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kConfidenceKey);
    await prefs.remove(_kHideLowKey);
    await prefs.remove(_kShowOriginalAlwaysKey);
    await prefs.remove(_kOverlayOpacityKey);
    await prefs.remove(_kPrimaryColorKey);
    await prefs.remove(_kSceneKey);
    await prefs.remove(_kOverlayFontScaleKey);
    state = const AsyncData(CameraSettings.defaults);
  }
}

final cameraSettingsProvider =
    AsyncNotifierProvider<CameraSettingsNotifier, CameraSettings>(
  CameraSettingsNotifier.new,
);
