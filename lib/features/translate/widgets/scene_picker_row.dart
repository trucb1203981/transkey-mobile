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
      case CameraScene.manga:
        return l.cameraSceneManga;
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
      case CameraScene.manga:
        return Icons.auto_stories;
    }
  }
}

/// Modal bottom sheet shown when entering the camera screen. The user
/// picks the scene UP FRONT — picking "Comic" routes manga pages through
/// the vision LLM (per-bubble blocks, no ML Kit fragmentation), picking
/// "Auto" keeps the existing detect-from-content path. The same chips
/// stay in the camera bottom bar so a wrong pick can be corrected
/// without re-entering the camera screen.
class SceneEntrySheet extends ConsumerWidget {
  const SceneEntrySheet({super.key});

  static Future<void> show(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const SceneEntrySheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final notifier = ref.read(cameraSettingsProvider.notifier);

    final entries = <(_SceneEntry, CameraScene)>[
      (_SceneEntry(l.cameraSceneAuto,       l.cameraSceneAutoDesc, Icons.auto_awesome),         CameraScene.auto),
      (_SceneEntry(l.cameraSceneManga,      l.cameraSceneMangaDesc, Icons.auto_stories), CameraScene.manga),
      (_SceneEntry(l.cameraSceneMenu,       l.cameraSceneMenuDesc,                Icons.restaurant_menu),  CameraScene.menu),
      (_SceneEntry(l.cameraSceneSign,       l.cameraSceneSignDesc,                            Icons.signpost_outlined), CameraScene.sign),
      (_SceneEntry(l.cameraSceneDocument,   l.cameraSceneDocumentDesc,                    Icons.description_outlined), CameraScene.document),
      (_SceneEntry(l.cameraSceneScreenshot, l.cameraSceneScreenshotDesc,                       Icons.phone_android),    CameraScene.screenshot),
    ];

    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.cameraScenePickerTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.cameraScenePickerHint,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (ctx, i) {
                  final (e, scene) = entries[i];
                  return ListTile(
                    leading: Icon(e.icon, color: theme.colorScheme.primary),
                    title: Text(e.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(e.desc,
                        style: const TextStyle(fontSize: 12)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () async {
                      await notifier.setScene(scene);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneEntry {
  const _SceneEntry(this.label, this.desc, this.icon);
  final String label;
  final String desc;
  final IconData icon;
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
