import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/api/dio_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/theme/app_glass.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/glass/aurora_scaffold.dart';

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
  // When true the message banner reads as a SUCCESS (green) instead of an error
  // (red) - e.g. "account created, verify your email" right after sign-up. The
  // same "verify your email" copy is an error on the login tab (a blocker) but a
  // success on the register tab (the account was just created).
  bool _messageIsSuccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
        _errorMessage = null;
        _messageIsSuccess = false;
      });
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
        setState(() {
          _errorMessage = l.errorEmailNotVerified;
          // On the register tab this means "account created, now verify" - a
          // success. On the login tab it's a blocker - keep it red.
          _messageIsSuccess = _isRegister;
        });
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

  /// "Forgot password?" flow (login tab). Collects the email and POSTs to
  /// /auth/forgot-password, which always returns ok and never reveals whether
  /// the email exists. The server emails a reset link that completes on the
  /// web reset page, so there is no in-app new-password screen to build here.
  Future<void> _showForgotPasswordDialog() async {
    final l = AppLocalizations.of(context)!;
    final emailController =
        TextEditingController(text: _emailController.text.trim());
    final dialogFormKey = GlobalKey<FormState>();
    var sending = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> send() async {
            if (!dialogFormKey.currentState!.validate()) return;
            setDialogState(() {
              sending = true;
              dialogError = null;
            });
            try {
              final api = ref.read(apiClientProvider);
              await api.dio.post('/auth/forgot-password', data: {
                'email': emailController.text.trim(),
              }).timeout(const Duration(seconds: 20));
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l.forgotPasswordSent)),
              );
            } catch (_) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                sending = false;
                dialogError = l.forgotPasswordError;
              });
            }
          }

          return AlertDialog(
            title: Text(l.forgotPasswordTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.forgotPasswordSubtitle),
                const SizedBox(height: AppSpacing.md),
                Form(
                  key: dialogFormKey,
                  child: TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofocus: true,
                    enabled: !sending,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return l.emailRequired;
                      if (!v.contains('@')) return l.emailInvalid;
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: l.emailHint,
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                    onFieldSubmitted: (_) => send(),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    dialogError!,
                    style: const TextStyle(color: AppColors.red, fontSize: 13),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed:
                    sending ? null : () => Navigator.of(dialogContext).pop(),
                child: Text(l.cancel),
              ),
              ElevatedButton(
                onPressed: sending ? null : send,
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l.forgotPasswordSend),
              ),
            ],
          );
        },
      ),
    );
    emailController.dispose();
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

  /// Native Sign in with Apple (App Store Guideline 4.8 — required because
  /// Google sign-in is offered). AuthenticationServices returns an
  /// identityToken JWT; the backend verifies it against Apple's JWKS.
  /// fullName is only exposed on the FIRST authorization — forward it then.
  Future<void> _appleSignIn() async {
    final l = AppLocalizations.of(context)!;
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        setState(() => _errorMessage = l.appleSignInFailed);
        return;
      }
      final name = [credential.givenName, credential.familyName]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(' ');
      await ref.read(authStateProvider.notifier).signInWithAppleIdentityToken(
            identityToken,
            name: name.isEmpty ? null : name,
          );

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
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return; // user cancelled
      setState(() => _errorMessage = e.message);
    } on DioException catch (e) {
      setState(() => _errorMessage = ApiException.fromDio(e).message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);
    final isLoading = authState.isLoading || authState.isRefreshing;

    return AuroraScaffold(
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
                  decoration: AppGlass.card(
                    isDark: isDark,
                    radius: AppSpacing.buttonRadius,
                    shadow: false,
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
            Builder(builder: (context) {
              // Green for a success banner (e.g. account created), red for errors.
              final c = _messageIsSuccess ? AppColors.green : AppColors.red;
              return Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.buttonRadius),
                  border: Border.all(color: c.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                        _messageIsSuccess
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: c,
                        size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: c),
                      ),
                    ),
                  ],
                ),
              );
            }),

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

          // Forgot password — login tab only. Triggers POST /auth/forgot-password
          // (the server emails a reset link; the new password is set on the web
          // reset page, so no in-app new-password screen is needed).
          if (!_isRegister)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: isLoading ? null : _showForgotPasswordDialog,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(l.forgotPassword),
              ),
            ),
          SizedBox(height: _isRegister ? AppSpacing.xl : AppSpacing.md),

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
          // Sign in with Apple — iOS only (Guideline 4.8: must be offered
          // alongside Google, at least as prominently).
          if (Platform.isIOS) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: isLoading ? null : _appleSignIn,
                icon: const Icon(Icons.apple, size: 24),
                label: Text(l.continueWithApple),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
