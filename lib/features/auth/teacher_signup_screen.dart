import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../routes/app_router.dart';
import '../../shared/widgets/loading_widgets.dart';
import '../auth/controllers/auth_controller.dart';

/// Teacher registration form — Phase 4.
///
/// Fields: Full Name, Email, Password, Confirm Password,
///         Employee ID, Department.
class TeacherSignupScreen extends ConsumerStatefulWidget {
  const TeacherSignupScreen({super.key});

  @override
  ConsumerState<TeacherSignupScreen> createState() =>
      _TeacherSignupScreenState();
}

class _TeacherSignupScreenState extends ConsumerState<TeacherSignupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl       = TextEditingController();
  final _emailCtrl      = TextEditingController();
  final _passwordCtrl   = TextEditingController();
  final _confirmCtrl    = TextEditingController();
  final _employeeIdCtrl = TextEditingController();
  final _deptCtrl       = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _isLoading       = false;
  String? _errorMessage;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _employeeIdCtrl.dispose();
    _deptCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final outcome = await ref.read(authControllerProvider.notifier).register(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      fullName: _nameCtrl.text.trim(),
      role: AppConstants.roleTeacher,
      studentIdNumber: _employeeIdCtrl.text.trim(), // stored in student_id_number column
      department: _deptCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (outcome.isSuccess) {
      context.pushReplacement(
        RoutePaths.emailVerification,
        extra: _emailCtrl.text.trim(),
      );
    } else {
      setState(() => _errorMessage = outcome.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),

                // ── Header ─────────────────────────────────────────────────
                _buildHeader(),
                const SizedBox(height: 32),

                // ── Error ──────────────────────────────────────────────────
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 20),
                ],

                // ── Form ───────────────────────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Personal info ──────────────────────────────────
                      _SectionHeader(
                        icon: Icons.person_rounded,
                        label: 'Personal Information',
                        color: AppColors.secondary,
                      ),
                      const SizedBox(height: 16),

                      _FormLabel('Full Name'),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        enabled: !_isLoading,
                        decoration: const InputDecoration(
                          hintText: 'Dr. Priya Kapoor',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Full name is required';
                          }
                          if (v.trim().length < 3) {
                            return 'Name must be at least 3 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FormLabel('Email Address'),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        enabled: !_isLoading,
                        decoration: const InputDecoration(
                          hintText: 'teacher@campus.edu',
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
                      const SizedBox(height: 16),

                      _FormLabel('Password'),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        enabled: !_isLoading,
                        decoration: InputDecoration(
                          hintText: 'Min 8 characters',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Password is required';
                          if (v.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FormLabel('Confirm Password'),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.next,
                        enabled: !_isLoading,
                        decoration: InputDecoration(
                          hintText: 'Re-enter password',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please confirm your password';
                          if (v != _passwordCtrl.text) return 'Passwords do not match';
                          return null;
                        },
                      ),

                      const SizedBox(height: 28),

                      // ── Professional info ──────────────────────────────
                      _SectionHeader(
                        icon: Icons.work_rounded,
                        label: 'Professional Information',
                        color: AppColors.secondary,
                      ),
                      const SizedBox(height: 16),

                      _FormLabel('Employee ID'),
                      TextFormField(
                        controller: _employeeIdCtrl,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        enabled: !_isLoading,
                        decoration: const InputDecoration(
                          hintText: 'e.g. EMP2021001',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Employee ID is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FormLabel('Department'),
                      TextFormField(
                        controller: _deptCtrl,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        enabled: !_isLoading,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          hintText: 'e.g. Computer Science',
                          prefixIcon: Icon(Icons.business_rounded),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Department is required';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 32),

                      // ── Submit button ──────────────────────────────────
                      AppLoadingButton(
                        onPressed: _isLoading ? null : _submit,
                        label: 'Create Teacher Account',
                        isLoading: _isLoading,
                        icon: Icons.assignment_ind_rounded,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D9488), Color(0xFF0891B2)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D9488), Color(0xFF0891B2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.assignment_ind_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text('Teacher Registration', style: AppTypography.displaySmall),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Create your teacher account to manage sessions',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ── Shared Helpers ─────────────────────────────────────────────────────────────

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: AppTypography.labelLarge),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.color = AppColors.primary,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: AppTypography.labelLarge.copyWith(color: color),
        ),
      ],
    );
  }
}

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
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
