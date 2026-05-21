import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/tracking/tracking_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../translate/services/tts_service.dart';
import '../models/phrasebook_entry.dart';
import '../providers/phrasebook_provider.dart';

/// Personal phrasebook list. Reached from the home screen via the
/// "Saved dishes" entry; entries are added from the camera "What is
/// this?" sheet by tapping Save. Optimised for travel: each card shows
/// the dish name large + a single explanation snippet so the user can
/// flash the screen at a waiter when ordering.
///
/// Top of the screen carries a category filter chip row (All / Menu /
/// Place / Document / Other). The selected chip narrows the list; "All"
/// is the default and shows everything. Filter is in-memory — we already
/// have the full list locally so a chip tap is instant (no refetch).
class PhrasebookScreen extends ConsumerStatefulWidget {
  const PhrasebookScreen({super.key});

  @override
  ConsumerState<PhrasebookScreen> createState() => _PhrasebookScreenState();
}

class _PhrasebookScreenState extends ConsumerState<PhrasebookScreen> {
  /// null = "All" chip selected (no filter). Otherwise = one of the
  /// PhrasebookCategory.* slugs.
  String? _filter;

  @override
  void initState() {
    super.initState();
    final entries = ref.read(phrasebookProvider).valueOrNull;
    ref.read(trackingServiceProvider).event('phrasebook_open',
        properties: {'entry_count': entries?.length ?? 0});
  }

  String _categoryLabel(AppLocalizations l, String slug) {
    switch (slug) {
      case PhrasebookCategory.menu:
        return l.phrasebookCategoryMenu;
      case PhrasebookCategory.place:
        return l.phrasebookCategoryPlace;
      case PhrasebookCategory.document:
        return l.phrasebookCategoryDocument;
      default:
        return l.phrasebookCategoryOther;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(phrasebookProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.phrasebookTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.cameraRetake,
            onPressed: () => ref.read(phrasebookProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chip row — horizontally scrollable so adding categories
          // later (e.g. "shopping", "transport") doesn't overflow. Each
          // category chip carries its own accent colour so the selected
          // filter matches the chips on the list rows below.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _FilterChipItem(
                  label: l.phrasebookCategoryAll,
                  selected: _filter == null,
                  category: null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final slug in PhrasebookCategory.all)
                  _FilterChipItem(
                    label: _categoryLabel(l, slug),
                    selected: _filter == slug,
                    category: slug,
                    onTap: () => setState(() => _filter = slug),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (allItems) {
                final items = _filter == null
                    ? allItems
                    : allItems
                        .where((dish) => dish.category == _filter)
                        .toList(growable: false);
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bookmark_border,
                            size: 64, color: Theme.of(context).hintColor),
                        const SizedBox(height: 12),
                        Text(
                          l.phrasebookEmpty,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                  color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(phrasebookProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _DishTile(dish: items[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill-shaped chip used in the category filter row. Plain widget (no
/// FilterChip) so it stays compact in a horizontal scroller. Selected
/// state borrows the category's own accent colour (via [_categoryStyle])
/// so the filter visually matches the chips on the rows below. The "All"
/// chip uses the neutral primary because it isn't tied to a category.
class _FilterChipItem extends StatelessWidget {
  const _FilterChipItem({
    required this.label,
    required this.selected,
    required this.category,
    required this.onTap,
  });

  final String label;
  final bool selected;
  /// Null = the "All" chip; otherwise the category slug whose accent
  /// drives the selected colour.
  final String? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final Color bg;
    final Color fg;
    if (selected) {
      if (category == null) {
        // "All" → neutral primary fill, no category accent.
        bg = scheme.primary;
        fg = scheme.onPrimary;
      } else {
        // Selected category → its accent at slightly stronger alpha so
        // it reads clearly as "active" while still matching the row badges.
        final style = _categoryStyle(category!, brightness);
        bg = style.bg.withValues(alpha: brightness == Brightness.dark ? 0.42 : 0.30);
        fg = style.fg;
      }
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurface.withValues(alpha: 0.82);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DishTile extends ConsumerWidget {
  const _DishTile({required this.dish});
  final PhrasebookEntry dish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      leading: _PhrasebookSpeakButton(dish: dish),
      title: Text(
        dish.recognizedText,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category chip — shows which bucket this entry lives in.
            // Helpful when the user is on the "All" filter so they can
            // visually scan the bucket of each row at a glance, and when
            // they re-categorise an entry they immediately see the chip
            // change.
            _CategoryChip(category: dish.category),
            const SizedBox(height: 6),
            Text(
              dish.explanation,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            if (dish.note != null && dish.note!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                // Tap the inline note preview to open the edit dialog —
                // gives the user one-tap access to the full note text
                // without scrolling through the detail sheet first.
                child: GestureDetector(
                  onTap: () => _editNote(context, ref),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .secondaryContainer
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.sticky_note_2_outlined, size: 12),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dish.note!,
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (action) async {
          if (action == 'copy') {
            await Clipboard.setData(ClipboardData(text: dish.recognizedText));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(l.copied),
                  duration: const Duration(seconds: 1)),
            );
          } else if (action == 'note') {
            _editNote(context, ref);
          } else if (action == 'category') {
            _changeCategory(context, ref);
          } else if (action == 'delete') {
            await _confirmDelete(context, ref);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'copy',
            child: ListTile(
              leading: const Icon(Icons.copy),
              title: Text(l.phrasebookCopy),
              dense: true,
            ),
          ),
          PopupMenuItem(
            value: 'note',
            child: ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(l.phrasebookNote),
              dense: true,
            ),
          ),
          PopupMenuItem(
            value: 'category',
            child: ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(l.phrasebookCategoryChange),
              dense: true,
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(l.phrasebookDelete,
                  style: const TextStyle(color: Colors.red)),
              dense: true,
            ),
          ),
        ],
      ),
      onTap: () => _showFull(context, ref),
    );
  }

  /// Bottom sheet to re-categorise the entry. Optimistic update via the
  /// provider — list/filter chip rows reflect the new bucket immediately.
  Future<void> _changeCategory(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    String? categoryLabel(String slug) {
      switch (slug) {
        case PhrasebookCategory.menu:
          return l.phrasebookCategoryMenu;
        case PhrasebookCategory.place:
          return l.phrasebookCategoryPlace;
        case PhrasebookCategory.document:
          return l.phrasebookCategoryDocument;
        case PhrasebookCategory.other:
          return l.phrasebookCategoryOther;
      }
      return null;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                l.phrasebookCategoryChange,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final slug in PhrasebookCategory.all)
              ListTile(
                leading: Icon(
                  dish.category == slug
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: dish.category == slug
                      ? Theme.of(sheetContext).colorScheme.primary
                      : null,
                ),
                title: Text(categoryLabel(slug) ?? slug),
                onTap: () => Navigator.of(sheetContext).pop(slug),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || picked == dish.category) return;
    await ref.read(phrasebookProvider.notifier).updateCategory(dish.id, picked);
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: dish.note ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.phrasebookNote),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(hintText: l.phrasebookNoteHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l.phrasebookNoteSave),
          ),
        ],
      ),
    );
    if (result == null) return;
    await ref
        .read(phrasebookProvider.notifier)
        .updateNote(dish.id, result.isEmpty ? null : result);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.phrasebookDelete),
        content: Text(l.phrasebookDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l.phrasebookDelete),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ref.read(phrasebookProvider.notifier).delete(dish.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? l.phrasebookDeleted : l.phrasebookSaveFailed),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showFull(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      dish.recognizedText,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PhrasebookSpeakButton(dish: dish, large: true),
                ],
              ),
              const SizedBox(height: 12),
              Text(dish.explanation,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
              // Same disclaimer logic as WhatIsThisSheet: menu / sign /
              // auto scenes can produce wrong-dish or wrong-sign
              // interpretations from OCR garbage; surfacing this here
              // (where the user reads to order at a restaurant abroad)
              // is more important than in the live sheet.
              if (dish.scene == 'menu' ||
                  dish.scene == 'sign' ||
                  dish.scene == 'auto')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 14,
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l.cameraExplainDisclaimer,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (dish.originalText != null &&
                  dish.originalText!.trim().isNotEmpty &&
                  dish.originalText != dish.recognizedText)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${l.cameraOriginalLabel}: ${dish.originalText}',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(sheetContext).hintColor,
                    ),
                  ),
                ),
              // Full-note card — visible only when the user has saved a
              // note. Tap-anywhere or the pencil icon opens the edit
              // dialog. Note text wraps freely (no ellipsis) so the user
              // sees the whole thing here vs the 1-line preview on the list.
              if (dish.note != null && dish.note!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _editNote(context, ref);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .secondaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 16,
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              dish.note!,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .onSecondaryContainer
                                .withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.copy),
                label: Text(l.phrasebookCopy),
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: dish.recognizedText));
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(l.copied),
                        duration: const Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Speaker that plays the saved dish's `recognizedText` in its source language
/// (the column persisted at save time). Travel use case: reopen a saved dish
/// at the restaurant and let the phone pronounce it for the waiter.
///
/// Two sizes: `large=false` (default, leading icon on list rows) and `large`
/// (detail sheet header next to the dish title). Both share play/stop toggle
/// behaviour: tapping while THIS dish is the current TTS utterance stops it,
/// tapping while idle (or speaking some other dish) plays this one.
///
/// Disabled — and shown grey — when the row has no source lang (legacy rows
/// saved before the column existed, or saves that happened before the server
/// `detectedSourceLang` rolled out and the user had no pinned source lang).
/// Distinct accent colours per phrasebook category so chips are visually
/// scannable at a glance — menu/place/document/other each get their own
/// hue. Returned (bg, fg) tuple already accounts for theme brightness:
/// bg is a low-alpha tint of the accent so it never overpowers the row,
/// fg is a shade that reads cleanly on that tint in both light + dark.
({Color bg, Color fg}) _categoryStyle(String category, Brightness brightness) {
  final MaterialColor accent;
  switch (category) {
    case PhrasebookCategory.menu:
      accent = Colors.deepOrange;
      break;
    case PhrasebookCategory.place:
      accent = Colors.green;
      break;
    case PhrasebookCategory.document:
      accent = Colors.blue;
      break;
    default:
      accent = Colors.blueGrey;
      break;
  }
  final isDark = brightness == Brightness.dark;
  return (
    bg: accent.withValues(alpha: isDark ? 0.22 : 0.14),
    fg: isDark ? accent.shade200 : accent.shade700,
  );
}

IconData _categoryIcon(String category) {
  switch (category) {
    case PhrasebookCategory.menu:
      return Icons.restaurant_menu_outlined;
    case PhrasebookCategory.place:
      return Icons.place_outlined;
    case PhrasebookCategory.document:
      return Icons.description_outlined;
    default:
      return Icons.label_outline;
  }
}

String _categoryLabelFor(AppLocalizations l, String category) {
  switch (category) {
    case PhrasebookCategory.menu:
      return l.phrasebookCategoryMenu;
    case PhrasebookCategory.place:
      return l.phrasebookCategoryPlace;
    case PhrasebookCategory.document:
      return l.phrasebookCategoryDocument;
    default:
      return l.phrasebookCategoryOther;
  }
}

/// Compact pill showing an entry's category — icon + localised label.
/// Rendered in each list row's subtitle so the user can see the bucket
/// without opening the entry. Colour comes from [_categoryStyle] so each
/// category is instantly recognisable.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final style = _categoryStyle(category, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_categoryIcon(category), size: 12, color: style.fg),
          const SizedBox(width: 4),
          Text(
            _categoryLabelFor(l, category),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: style.fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhrasebookSpeakButton extends ConsumerWidget {
  const _PhrasebookSpeakButton({required this.dish, this.large = false});

  final PhrasebookEntry dish;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = dish.sourceLang;
    final enabled = lang != null && lang.isNotEmpty;
    final tts = ref.watch(ttsProvider);
    final isPlayingMine =
        tts.isPlaying && tts.currentText == dish.recognizedText.trim();

    final color = enabled
        ? (isPlayingMine
            ? Colors.amber
            : Theme.of(context).colorScheme.primary)
        : Theme.of(context).disabledColor;
    final icon =
        isPlayingMine ? Icons.stop_circle_outlined : Icons.volume_up_outlined;

    return IconButton(
      iconSize: large ? 28 : 22,
      tooltip: enabled ? lang.toUpperCase() : null,
      icon: Icon(icon, color: color),
      onPressed: enabled
          ? () {
              if (isPlayingMine) {
                ref.read(ttsProvider.notifier).stop();
              } else {
                // Respect the user's persisted TTS rate from settings —
                // no per-surface override.
                ref.read(ttsProvider.notifier).speak(
                      dish.recognizedText,
                      lang: lang,
                    );
                ref.read(trackingServiceProvider).event('phrasebook_tts',
                    properties: {'lang': lang, 'category': dish.category});
              }
            }
          : null,
    );
  }
}
