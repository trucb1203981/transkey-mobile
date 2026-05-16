import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../models/glossary_entry.dart';

class AddGlossarySheet extends StatefulWidget {
  const AddGlossarySheet({
    super.key,
    this.entry,
    this.entryIndex,
  });

  /// Non-null when editing an existing entry.
  final GlossaryEntry? entry;
  final int? entryIndex;

  static Future<GlossaryEntry?> show(
    BuildContext context, {
    GlossaryEntry? entry,
    int? entryIndex,
  }) {
    return showModalBottomSheet<GlossaryEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddGlossarySheet(entry: entry, entryIndex: entryIndex),
    );
  }

  @override
  State<AddGlossarySheet> createState() => _AddGlossarySheetState();
}

class _AddGlossarySheetState extends State<AddGlossarySheet> {
  late final _sourceController = TextEditingController(text: widget.entry?.source ?? '');
  late final _targetController = TextEditingController(text: widget.entry?.target ?? '');
  final _formKey = GlobalKey<FormState>();

  bool get _isEditing => widget.entry != null;

  @override
  void dispose() {
    _sourceController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final l = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surface : AppColors.surfaceLight,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.sheetRadius),
          ),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.border : AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Text(
                _isEditing ? l.glossaryEditTitle : l.glossaryAddTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),

              // Source field
              TextFormField(
                controller: _sourceController,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l.glossarySourceLabel,
                  hintText: l.glossarySourceHint,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l.required;
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.sm),

              // Target field
              TextFormField(
                controller: _targetController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l.glossaryTargetLabel,
                  hintText: l.glossaryTargetHint,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l.required;
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l.cancel),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: Text(_isEditing ? l.saveAction : l.addAction),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final entry = GlossaryEntry(
      source: _sourceController.text.trim(),
      target: _targetController.text.trim(),
    );
    Navigator.pop(context, entry);
  }
}
