import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../providers/camera_settings_provider.dart';

/// Horizontally scrollable chip row exposing the [CameraScene] choices to
/// the user, sitting above the language pill in the camera bottom bar.
///
/// Why a chip row rather than burying this in the settings sheet: the
/// user picks this BEFORE pressing capture, so it lives next to capture.
/// One tap to switch, no modal in the way.
class ScenePickerRow extends ConsumerWidget {
  const ScenePickerRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final settings =
        ref.watch(cameraSettingsProvider).valueOrNull ?? CameraSettings.defaults;
    final notifier = ref.read(cameraSettingsProvider.notifier);

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final scene in CameraScene.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _SceneChip(
                label: _sceneLabel(l, scene),
                icon: _sceneIcon(scene),
                isActive: settings.scene == scene,
                onTap: () => notifier.setScene(scene),
              ),
            ),
        ],
      ),
    );
  }

  String _sceneLabel(AppLocalizations l, CameraScene scene) {
    switch (scene) {
      case CameraScene.auto:
        return l.cameraSceneAuto;
      case CameraScene.document:
        return l.cameraSceneDocument;
      case CameraScene.menu:
        return l.cameraSceneMenu;
      case CameraScene.sign:
        return l.cameraSceneSign;
      case CameraScene.screenshot:
        return l.cameraSceneScreenshot;
    }
  }

  IconData _sceneIcon(CameraScene scene) {
    switch (scene) {
      case CameraScene.auto:
        return Icons.auto_awesome;
      case CameraScene.document:
        return Icons.description_outlined;
      case CameraScene.menu:
        return Icons.restaurant_menu;
      case CameraScene.sign:
        return Icons.signpost_outlined;
      case CameraScene.screenshot:
        return Icons.phone_android;
    }
  }
}

class _SceneChip extends StatelessWidget {
  const _SceneChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.black54,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? Colors.black87 : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.black87 : Colors.white,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
