import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/empty_states.dart';
import '../models/glossary_entry.dart';
import '../providers/glossary_provider.dart';
import '../widgets/add_glossary_sheet.dart';

class GlossaryScreen extends ConsumerStatefulWidget {
  const GlossaryScreen({super.key});

  @override
  ConsumerState<GlossaryScreen> createState() => _GlossaryScreenState();
}

class _GlossaryScreenState extends ConsumerState<GlossaryScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Make sure any pending debounced push goes out before the user leaves.
    ref.read(glossaryProvider.notifier).flushPendingPush();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(glossaryProvider.notifier).flushPendingPush();
    }
  }

  @override
  Widget build(BuildContext context) {
    final glossary = ref.watch(glossaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Glossary (${glossary.count}/50)'),
        actions: [
          IconButton(
            icon: glossary.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync',
            onPressed: glossary.isSyncing
                ? null
                : () => ref.read(glossaryProvider.notifier).pull(),
          ),
        ],
      ),
      body: _buildBody(context, ref, glossary),
      floatingActionButton: glossary.isFull
          ? null
          : FloatingActionButton(
              onPressed: () => _addEntry(context, ref),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    GlossaryState glossary,
  ) {
    if (glossary.entries.isEmpty) {
      return const GlossaryEmptyState();
    }

    return Column(
      children: [
        if (glossary.error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            color: AppColors.red.withValues(alpha: 0.1),
            child: Text(
              glossary.error!,
              style: const TextStyle(color: AppColors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            itemCount: glossary.entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, index) {
              final entry = glossary.entries[index];
              return _GlossaryTile(
                entry: entry,
                onEdit: () => _editEntry(context, ref, entry, index),
                onDelete: () => _confirmDelete(context, ref, index),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addEntry(BuildContext context, WidgetRef ref) async {
    final entry = await AddGlossarySheet.show(context);
    if (entry == null || !context.mounted) return;
    ref.read(glossaryProvider.notifier).add(entry);
  }

  Future<void> _editEntry(
    BuildContext context,
    WidgetRef ref,
    GlossaryEntry entry,
    int index,
  ) async {
    final updated = await AddGlossarySheet.show(
      context,
      entry: entry,
      entryIndex: index,
    );
    if (updated == null || !context.mounted) return;
    ref.read(glossaryProvider.notifier).update(index, updated);
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, int index) {
    final source = ref.read(glossaryProvider).entries[index].source;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry'),
        content: Text('Delete "$source"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(glossaryProvider.notifier).delete(index);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _GlossaryTile extends StatelessWidget {
  const _GlossaryTile({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final GlossaryEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.red),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surface : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.borderLight,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.source,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.target,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark ? AppColors.textSecondary : AppColors.textSecondaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
