import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

class CameraReadingEntry {
  const CameraReadingEntry(this.original, this.translated);
  final String original;
  final String translated;
  bool get hasTranslation => translated.isNotEmpty && translated != original;
  String get copyText => hasTranslation ? '$original → $translated' : original;
}

/// Preserve source-only notes, including rows the translation API omitted.
List<CameraReadingEntry> cameraReadingEntries(
        List<String> sources, List<String> translations) =>
    [
      for (var i = 0; i < sources.length; i++)
        if (sources[i].trim().isNotEmpty ||
            (i < translations.length && translations[i].trim().isNotEmpty))
          CameraReadingEntry(sources[i].trim(),
              i < translations.length ? translations[i].trim() : ''),
    ];

class CameraReadingList extends StatelessWidget {
  const CameraReadingList(
      {super.key,
      required this.items,
      required this.onCopyAll,
      required this.onExplain});
  final List<CameraReadingEntry> items;
  final VoidCallback onCopyAll;
  final ValueChanged<String> onExplain;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          // Near-opaque dark-violet glass (matches bottomSheetTheme) so the
          // list stays legible over the camera feed while reading as part
          // of the Liquid Glass world.
          color: Color(0xF216131F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.cameraListView} (${items.length})',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onCopyAll();
                      },
                      icon: const Icon(Icons.copy,
                          size: 16, color: AppColors.primary),
                      label: Text(
                        l.cameraCopyAll,
                        style: const TextStyle(color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 16, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final it = items[i];
                    final hasTranslation = it.hasTranslation;
                    // "What is this?" explains the SOURCE text (the model
                    // handles the original language better than its own
                    // translation); fall back to the translation when the
                    // source is empty.
                    final explainText =
                        it.original.isNotEmpty ? it.original : it.translated;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!hasTranslation)
                                Text(l.cameraOriginalLabel,
                                    style: const TextStyle(
                                        color: AppColors.amber, fontSize: 12)),
                              SelectableText(
                                hasTranslation ? it.translated : it.original,
                                style: TextStyle(
                                  color: hasTranslation
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                              if (hasTranslation && it.original.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  it.original,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (explainText.isNotEmpty)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            tooltip: l.cameraWhatIsThis,
                            icon: const Icon(
                              Icons.help_outline,
                              size: 20,
                              color: AppColors.primary,
                            ),
                            onPressed: () => onExplain(explainText),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
