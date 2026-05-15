import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _nameFocus = FocusNode();

  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _errorMessage = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Show OAuth error from deep link (e.g. pro_device_limit)
    final authError = ref.read(authStateProvider).valueOrNull?.error;
    if (authError != null && _errorMessage == null) {
      final msg = authError == 'pro_device_limit'
          ? 'Pro account already registered on max devices'
          : authError == 'device_limit'
              ? 'Too many accounts on this device'
              : 'Google sign-in failed: $authError';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _errorMessage = msg);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  bool get _isRegister => _tabController.index == 1;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _errorMessage = null);

    try {
      if (_isRegister) {
        await ref.read(authStateProvider.notifier).register(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              name: _nameController.text.trim(),
            );
      } else {
        await ref.read(authStateProvider.notifier).login(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
      }

      // Check if auth succeeded or failed (AsyncValue.guard stores error in state)
      final authState = ref.read(authStateProvider);
      if (authState.hasError) {
        final err = authState.error;
        if (err is DioException) {
          final apiErr = ApiException.fromDio(err);
          setState(() => _errorMessage = apiErr.message);
        } else {
          setState(() => _errorMessage = err.toString());
        }
        return;
      }

      if (mounted) context.go('/');
    } on DioException catch (e) {
      final apiErr = ApiException.fromDio(e);
      setState(() => _errorMessage = apiErr.message);
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong');
    }
  }

  Future<void> _googleOAuth() async {
    final baseUrl = dotenv.env['TRANSKEY_API_URL'] ?? 'https://api.transkey.app';
    // Server reads "state" param: portPart|deviceId|deviceName|platform
    // "mobile" tells the callback to redirect to transkey:// deep link
    final uri = Uri.parse('$baseUrl/auth/google').replace(queryParameters: {
      'state': 'mobile',
    });
    try {
      // Use the system browser (Chrome) instead of an in-app Custom Tab —
      // Chrome Custom Tab silently blocks auto-navigation to intent:// without
      // a user gesture, which leaves the user stuck on the redirect page after
      // Google sign-in. Regular Chrome handles intent:// → app launch reliably.
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to open Google sign-in: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading || authState.isRefreshing;

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.xl),
              // Logo area
              const Icon(
                Icons.translate_rounded,
                size: 48,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'TransKey',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Tab bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surface : const Color(0xFFF0EDE8),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.buttonRadius),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.buttonRadius),
                    ),
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: isDark
                        ? AppColors.textSecondary
                        : AppColors.textSecondaryLight,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    tabs: const [
                      Tab(text: 'Login'),
                      Tab(text: 'Sign Up'),
                    ],
                  ),
                ),
              ),

              // Form fields
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildForm(isDark: isDark, isLoading: isLoading),
                    _buildForm(isDark: isDark, isLoading: isLoading),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm({
    required bool isDark,
    required bool isLoading,
  }) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(AppSpacing.buttonRadius),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.red, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.red),
                    ),
                  ),
                ],
              ),
            ),

          // Name field (register only)
          if (_isRegister) ...[
            TextFormField(
              controller: _nameController,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (_isRegister && (v == null || v.trim().isEmpty)) {
                  return 'Name is required';
                }
                return null;
              },
              decoration: const InputDecoration(
                hintText: 'Your name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Email
          TextFormField(
            controller: _emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
            decoration: const InputDecoration(
              hintText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Password
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            textInputAction: _isRegister ? TextInputAction.done : TextInputAction.done,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 6) return 'At least 6 characters';
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Submit button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isRegister ? 'Create Account' : 'Log In'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Divider
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  'or',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppColors.textSecondary
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Google OAuth
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : _googleOAuth,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Continue with Google'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
