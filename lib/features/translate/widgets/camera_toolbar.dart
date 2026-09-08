import 'package:flutter/material.dart';

/// Keeps primary camera controls reachable on narrow and large-text displays.
class CameraToolbar extends StatelessWidget {
  const CameraToolbar({
    super.key,
    required this.sourceLabel,
    required this.targetLabel,
    required this.onClose,
    required this.onSource,
    required this.onTarget,
    required this.onSettings,
    required this.settingsTooltip,
    required this.helpTooltip,
    this.onFlash,
    this.onHelp,
    this.flashOn = false,
  });

  final String sourceLabel, targetLabel, settingsTooltip, helpTooltip;
  final VoidCallback onClose, onSource, onTarget, onSettings;
  final VoidCallback? onFlash, onHelp;
  final bool flashOn;

  static bool needsSecondRow({
    required double width,
    required TextScaler textScaler,
    required int secondaryActionCount,
  }) =>
      secondaryActionCount > 0 &&
      (width < 240 + 48 * (2 + secondaryActionCount) ||
          textScaler.scale(13) > 17);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final secondary = <Widget>[
            if (onFlash != null)
              IconButton(
                key: const ValueKey('camera-flash'),
                icon: Icon(flashOn ? Icons.flash_on : Icons.flash_off),
                onPressed: onFlash,
              ),
            if (onHelp != null)
              IconButton(
                key: const ValueKey('camera-help'),
                icon: const Icon(Icons.help_outline),
                tooltip: helpTooltip,
                onPressed: onHelp,
              ),
          ];
          final split = needsSecondRow(
            width: constraints.maxWidth,
            textScaler: MediaQuery.textScalerOf(context),
            secondaryActionCount: secondary.length,
          );
          return IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('camera-close'),
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            flex: 2,
                            child: _LanguagePill(
                              key: const ValueKey('camera-source'),
                              label: sourceLabel,
                              onTap: onSource,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 1),
                            child: Icon(Icons.arrow_right_alt,
                                color: Colors.white70, size: 18),
                          ),
                          Flexible(
                            child: _LanguagePill(
                              key: const ValueKey('camera-target'),
                              label: targetLabel,
                              onTap: onTarget,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!split) ...secondary,
                    IconButton(
                      key: const ValueKey('camera-settings'),
                      icon: const Icon(Icons.tune),
                      tooltip: settingsTooltip,
                      onPressed: onSettings,
                    ),
                  ],
                ),
                if (split)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: secondary,
                  ),
              ],
            ),
          );
        },
      );
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: Material(
          color: Colors.white.withValues(alpha: 0.15),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down,
                        color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
