import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/api/dio_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l.changePassword)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _current,
                obscureText: true,
                decoration: InputDecoration(labelText: l.currentPassword),
                validator: (v) =>
                    v == null || v.isEmpty ? l.passwordTooShort : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _next,
                obscureText: true,
                decoration: InputDecoration(labelText: l.newPassword),
                validator: (v) =>
                    v == null || v.length < 8 ? l.passwordTooShort : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration: InputDecoration(labelText: l.confirmPassword),
                validator: (v) =>
                    v != _next.text ? l.passwordMismatch : null,
              ),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.changePassword),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/auth/change-password', data: {
        'currentPassword': _current.text,
        'newPassword': _next.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.changePasswordSuccess)),
      );
      Navigator.of(context).pop();
    } on DioException catch (e) {
      if (!mounted) return;
      // Show the localized copy for known codes (e.g. wrong current
      // password); only fall back to the generic string for true unknowns,
      // so the user never sees a raw server code like "wrong_password".
      final ex = ApiException.fromDio(e);
      final msg = ex.code == ApiErrorCode.unknown
          ? l.changePasswordFailed
          : ex.code.localize(l);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.changePasswordFailed),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
