import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
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
      final l = AppLocalizations.of(context)!;
      final msg = authError == 'pro_device_limit'
          ? l.proDeviceLimitError
          : authError == 'device_limit'
              ? l.deviceLimitError
              : l.googleSignInFailed(authError);
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

    final l = AppLocalizations.of(context)!;
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
          setState(() => _errorMessage = _messageFor(ApiException.fromDio(err), l));
        } else {
          setState(() => _errorMessage = err.toString());
        }
        return;
      }

      // Register that requires email verification: account created but no
      // session yet. Stay on this screen and prompt the user to check their
      // inbox instead of navigating into the app.
      if (authState.valueOrNull?.needsEmailVerification == true) {
        setState(() => _errorMessage = l.errorEmailNotVerified);
        return;
      }

      if (mounted) context.go('/');
    } on DioException catch (e) {
      setState(() => _errorMessage = _messageFor(ApiException.fromDio(e), l));
    } catch (e) {
      setState(() => _errorMessage = l.errorGeneric);
    }
  }

  /// Pick the user-facing message for an ApiException. Mapped codes use
  /// their localized string; an `unknown` code with a server-provided
  /// message shows that message verbatim (so new server error codes
  /// surface their real cause to the user instead of "Something went
  /// wrong"). Pure unknowns fall back to the generic copy.
  String _messageFor(ApiException ex, AppLocalizations l) {
    if (ex.code == ApiErrorCode.unknown && ex.message.isNotEmpty) {
      return ex.message;
    }
    return ex.code.localize(l);
  }

  Future<void> _googleOAuth() async {
    // Native Google Sign-In: the OS shows its built-in account picker, returns
    // an idToken signed for our server, and we exchange it server-side. No
    // browser redirect / deep-link gymnastics — far more reliable than the
    // previous /auth/google?state=mobile flow.
    //
    // `serverClientId` must be the WEB OAuth client ID (the one already used
    // by passport-google on the server), so the idToken's `aud` matches what
    // the server's verifyIdToken expects. The OS-specific iOS / Android
    // client IDs are configured via Info.plist URL scheme and Android OAuth
    // client (SHA-1 + package name) in Google Cloud Console — they identify
    // the *app* to Google but don't appear in the token audience.
    final serverClientId = dotenv.env['GOOGLE_SERVER_CLIENT_ID'];
    final l = AppLocalizations.of(context)!;
    if (serverClientId == null || serverClientId.isEmpty) {
      setState(() => _errorMessage = l.googleNotConfigured);
      return;
    }

    final googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId: serverClientId,
    );

    try {
      // signOut first so the account picker always shows — otherwise the SDK
      // silently re-uses the previous account on subsequent attempts, which is
      // confusing when the user is trying to switch accounts after an error.
      await googleSignIn.signOut();

      final account = await googleSignIn.signIn();
      if (account == null) return; // user cancelled the picker

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        if (mounted) {
          setState(() => _errorMessage = l.googleSignInNoIdToken);
        }
        return;
      }

      await ref.read(authStateProvider.notifier).signInWithGoogleIdToken(idToken);

      final state = ref.read(authStateProvider);
      if (state.hasError) {
        final err = state.error;
        if (err is DioException) {
          setState(() => _errorMessage = ApiException.fromDio(err).code.localize(l));
        } else {
          setState(() => _errorMessage = err.toString());
        }
        return;
      }
      if (mounted) context.go('/');
    } on DioException catch (e) {
      setState(() => _errorMessage = ApiException.fromDio(e).message);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = l.googleSignInFailed(e.toString()));
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
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                ).createShader(bounds),
                child: Text(
                  'TransKey',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)!.homeTagline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
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
                    tabs: [
                      Tab(text: AppLocalizations.of(context)!.login),
                      Tab(text: AppLocalizations.of(context)!.signUp),
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
    final l = AppLocalizations.of(context)!;

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
                  return l.nameRequired;
                }
                return null;
              },
              decoration: InputDecoration(
                hintText: l.nameHint,
                prefixIcon: const Icon(Icons.person_outline),
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
              if (v == null || v.trim().isEmpty) return l.emailRequired;
              if (!v.contains('@')) return l.emailInvalid;
              return null;
            },
            decoration: InputDecoration(
              hintText: l.emailHint,
              prefixIcon: const Icon(Icons.email_outlined),
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
              if (v == null || v.isEmpty) return l.passwordRequired;
              if (v.length < 6) return l.passwordMinSix;
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: l.passwordHint,
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
                  : Text(_isRegister ? l.createAccount : l.logIn),
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
                  l.orDivider,
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
              label: Text(l.continueWithGoogle),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
