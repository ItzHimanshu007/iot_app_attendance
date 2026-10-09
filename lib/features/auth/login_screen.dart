import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../routes/app_router.dart';
import '../auth/controllers/auth_controller.dart';
import '../../shared/widgets/loading_widgets.dart';

/// Login screen — connected to AuthController.
///
/// No business logic here — all auth handling in AuthController.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _fadeController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Clear previous error
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    final error = await ref.read(authControllerProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    // The login() call never throws — errors are returned as strings.
    // We set the error here regardless of mount status because GoRouter
    // will NOT navigate away on failure (isInitializing=false, so no splash
    // redirect happens). The widget stays mounted.
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state errorMessage as a fallback —
    // in case the widget was rebuilt and local _errorMessage was lost.
    ref.listen<AuthSessionState>(authControllerProvider, (previous, next) {
      if (next.isUnauthenticated &&
          next.errorMessage != null &&
          mounted &&
          !_isLoading) {
        setState(() => _errorMessage = next.errorMessage);
      }
    });

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),

                // ── Logo + Header ──────────────────────────────────────
                _buildHeader(context),

                const SizedBox(height: 48),

                // ── Error Banner ───────────────────────────────────────
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 20),
                ],

                // ── Form ───────────────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Email
                      Text('Email address',
                          style: AppTypography.labelLarge),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        enabled: !_isLoading,
                        decoration: const InputDecoration(
                          hintText: 'student@campus.edu',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!v.contains('@') || !v.contains('.')) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Password
                      Text('Password', style: AppTypography.labelLarge),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        enabled: !_isLoading,
                        onFieldSubmitted: (_) => _handleLogin(),
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Password is required';
                          }
                          if (v.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : () {
                            context.push(RoutePaths.forgotPassword);
                          },
                          child: const Text('Forgot password?'),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Submit button
                      AppLoadingButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        label: 'Sign In',
                        isLoading: _isLoading,
                        icon: Icons.login_rounded,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                _buildFooter(context),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.school_rounded,
              size: 44,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text('Welcome Back', style: AppTypography.displaySmall),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Sign in to your campus account',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Column(
      children: [
        // ── Create Account ────────────────────────────────────────────────
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                "Don't have an account?",
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () => context.push(RoutePaths.signUp),
            icon: const Icon(Icons.person_add_outlined, size: 20),
            label: const Text('Create Account'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: AppTypography.labelLarge,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Smart Campus Attendance v${_appVersion()}',
          style: AppTypography.labelSmall
              .copyWith(color: AppColors.textTertiary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Admin accounts are created by IT administrators',
          style: AppTypography.labelSmall
              .copyWith(color: AppColors.textTertiary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _showForgotPassword() {
    // Now navigates to dedicated forgot-password screen
    // (kept for API compatibility)
    context.push(RoutePaths.forgotPassword);
  }

  String _appVersion() => '0.1.0';
}

/// Animated error banner shown below the header.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
