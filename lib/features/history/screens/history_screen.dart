import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/empty_states.dart';
import '../providers/history_provider.dart';
import '../widgets/history_card.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    // Avoid re-filtering 500+ entries on every keystroke; wait for a pause.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      ref.read(historyProvider.notifier).setSearchQuery(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final historyState = ref.watch(historyProvider);
    final filtered = historyState.filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.historyTitle),
        actions: [
          if (historyState.entries.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (action) {
                switch (action) {
                  case 'clear':
                    _confirmClear(context, ref);
                  case 'clear_non_fav':
                    _confirmClearNonFavorites(context, ref);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'clear',
                  child: Text(l.historyMenuClearAll),
                ),
                PopupMenuItem(
                  value: 'clear_non_fav',
                  child: Text(l.historyMenuKeepFavorites),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: l.historySearchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _searchDebounce?.cancel();
                          ref
                              .read(historyProvider.notifier)
                              .setSearchQuery('');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                _filterChip(
                  label: l.historyFilterAll,
                  selected: historyState.filter == HistoryFilter.all,
                  onSelected: () => ref
                      .read(historyProvider.notifier)
                      .setFilter(HistoryFilter.all),
                ),
                const SizedBox(width: AppSpacing.sm),
                _filterChip(
                  label: l.historyFilterFavorites,
                  selected: historyState.filter == HistoryFilter.favorites,
                  onSelected: () => ref
                      .read(historyProvider.notifier)
                      .setFilter(HistoryFilter.favorites),
                ),
                const SizedBox(width: AppSpacing.sm),
                _filterChip(
                  label: l.historyFilterLocked,
                  selected: historyState.filter == HistoryFilter.locked,
                  onSelected: () => ref
                      .read(historyProvider.notifier)
                      .setFilter(HistoryFilter.locked),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // List
          Expanded(
            child: filtered.isEmpty
                ? const HistoryEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      return HistoryCard(
                        entry: entry,
                        onToggleFavorite: () => ref
                            .read(historyProvider.notifier)
                            .toggleFavorite(entry.id),
                        onDelete: () => ref
                            .read(historyProvider.notifier)
                            .delete(entry.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.historyClearDialogTitle),
        content: Text(l.historyClearDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(historyProvider.notifier).clearAll();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: Text(l.clear),
          ),
        ],
      ),
    );
  }

  void _confirmClearNonFavorites(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.historyMenuKeepFavorites),
        content: Text(l.historyKeepFavDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(historyProvider.notifier).clearNonFavorites();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: Text(l.clear),
          ),
        ],
      ),
    );
  }
}
