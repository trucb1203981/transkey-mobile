import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../providers/camera_settings_provider.dart';

/// Modal bottom sheet exposing the user-tunable parameters for the
/// camera-translate flow. Triggered by the gear icon in the camera top bar.
///
/// Why a sheet rather than the global settings screen: these knobs only
/// make sense in the context of an active capture, so wedge them next to
/// the camera rather than buried two taps away.
class CameraSettingsSheet extends ConsumerWidget {
  const CameraSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const CameraSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final settingsAsync = ref.watch(cameraSettingsProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1F2937), // slate-800 — dark enough for camera UX
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: settingsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e', style: const TextStyle(color: Colors.white)),
          ),
          data: (settings) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.cameraSettingsTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(cameraSettingsProvider.notifier)
                          .resetToDefaults(),
                      child: Text(
                        l.cameraSettingsReset,
                        style: const TextStyle(color: Colors.lightBlueAccent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _SliderRow(
                  label: l.cameraSettingsConfidence,
                  hint: l.cameraSettingsConfidenceHint,
                  value: settings.confidenceThreshold,
                  min: 0.0,
                  max: 0.7,
                  divisions: 14,
                  valueLabel: _percentLabel(settings.confidenceThreshold),
                  onChanged: (v) => ref
                      .read(cameraSettingsProvider.notifier)
                      .setConfidenceThreshold(v),
                ),
                const SizedBox(height: 16),
                _SwitchRow(
                  label: l.cameraSettingsHideLow,
                  hint: l.cameraSettingsHideLowHint,
                  value: settings.hideLowConfidence,
                  onChanged: (v) => ref
                      .read(cameraSettingsProvider.notifier)
                      .setHideLowConfidence(v),
                ),
                const SizedBox(height: 16),
                _SwitchRow(
                  label: l.cameraSettingsShowOriginal,
                  hint: l.cameraSettingsShowOriginalHint,
                  value: settings.showOriginalAlways,
                  onChanged: (v) => ref
                      .read(cameraSettingsProvider.notifier)
                      .setShowOriginalAlways(v),
                ),
                const SizedBox(height: 16),
                _SliderRow(
                  label: l.cameraSettingsOpacity,
                  hint: l.cameraSettingsOpacityHint,
                  value: settings.overlayOpacity,
                  min: 0.4,
                  max: 1.0,
                  divisions: 6,
                  valueLabel: _percentLabel(settings.overlayOpacity),
                  onChanged: (v) => ref
                      .read(cameraSettingsProvider.notifier)
                      .setOverlayOpacity(v),
                ),
                const SizedBox(height: 16),
                _SliderRow(
                  label: l.cameraSettingsFontScale,
                  hint: l.cameraSettingsFontScaleHint,
                  value: settings.overlayFontScale,
                  min: kOverlayFontScaleMin,
                  max: kOverlayFontScaleMax,
                  divisions: 20,
                  valueLabel:
                      '${settings.overlayFontScale.toStringAsFixed(1)}×',
                  onChanged: (v) => ref
                      .read(cameraSettingsProvider.notifier)
                      .setOverlayFontScale(v),
                  trailing: settings.overlayFontScale != kOverlayFontScaleDefault
                      ? TextButton(
                          onPressed: () => ref
                              .read(cameraSettingsProvider.notifier)
                              .resetOverlayFontScale(),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            foregroundColor: Colors.lightBlueAccent,
                          ),
                          child: Text(l.cameraSettingsReset),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                _SwitchRow(
                  label: l.cameraSettingsPrimaryColor,
                  hint: l.cameraSettingsPrimaryColorHint,
                  value: settings.usePrimaryOverlayColor,
                  onChanged: (v) => ref
                      .read(cameraSettingsProvider.notifier)
                      .setUsePrimaryOverlayColor(v),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _percentLabel(double v) => '${(v * 100).round()}%';
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    this.trailing,
  });

  final String label;
  final String hint;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  // Optional widget shown on the right of the value label - used for a
  // per-row Reset button (e.g. font scale) so the user can snap back to
  // the default without hunting the global Reset at the top.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: const TextStyle(
                color: Colors.lightBlueAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
        Text(
          hint,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.lightBlueAccent,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.lightBlueAccent,
            overlayColor: Colors.lightBlueAccent.withValues(alpha: 0.2),
            trackHeight: 3,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: Colors.lightBlueAccent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
