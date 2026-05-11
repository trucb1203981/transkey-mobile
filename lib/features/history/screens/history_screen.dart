import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyState = ref.watch(historyProvider);
    final filtered = historyState.filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
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
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear all'),
                ),
                const PopupMenuItem(
                  value: 'clear_non_fav',
                  child: Text('Keep favorites only'),
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
              onChanged: (q) =>
                  ref.read(historyProvider.notifier).setSearchQuery(q),
              decoration: InputDecoration(
                hintText: 'Search history...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
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
                  label: 'All',
                  selected: historyState.filter == HistoryFilter.all,
                  onSelected: () => ref
                      .read(historyProvider.notifier)
                      .setFilter(HistoryFilter.all),
                ),
                const SizedBox(width: AppSpacing.sm),
                _filterChip(
                  label: '★ Favorites',
                  selected: historyState.filter == HistoryFilter.favorites,
                  onSelected: () => ref
                      .read(historyProvider.notifier)
                      .setFilter(HistoryFilter.favorites),
                ),
                const SizedBox(width: AppSpacing.sm),
                _filterChip(
                  label: '🔒 Locked',
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history'),
        content: const Text(
          'Delete all history? Locked entries will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(historyProvider.notifier).clearAll();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _confirmClearNonFavorites(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep favorites only'),
        content: const Text(
          'Delete all non-favorite entries? Locked entries will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(historyProvider.notifier).clearNonFavorites();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
