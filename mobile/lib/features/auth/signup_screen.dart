import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import 'auth_service.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _employeeId = TextEditingController();
  final _department = TextEditingController();
  final _designation = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _employeeId, _department, _designation, _phone, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final needsConfirmation = await ref
          .read(authServiceProvider)
          .signUp(
            email: _email.text,
            password: _password.text,
            fullName: _name.text,
            employeeId: _employeeId.text,
            department: _department.text,
            designation: _designation.text,
            phone: _phone.text,
          );
      if (!mounted) return;
      if (needsConfirmation) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.mark_email_unread_outlined, size: 40),
            title: const Text('Confirm your email'),
            content: Text(
              'We sent a confirmation link to ${_email.text.trim()}. Open it, then sign in.',
              textAlign: TextAlign.center,
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? '$label is required' : null;

  Widget _gap() => const SizedBox(height: 14);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create staff account')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              const MessageBanner(
                title: 'How activation works',
                message:
                    'After signing up you will register this phone and your face. '
                    'The administrator then approves your account.',
              ),
              const SectionHeader('Personal details'),
              AppCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (v) => _required(v, 'Full name'),
                    ),
                    _gap(),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Mobile number (optional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeader('Work details'),
              AppCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _employeeId,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Employee ID',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) => _required(v, 'Employee ID'),
                    ),
                    _gap(),
                    TextFormField(
                      controller: _department,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        prefixIcon: Icon(Icons.apartment_outlined),
                      ),
                    ),
                    _gap(),
                    TextFormField(
                      controller: _designation,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Designation',
                        prefixIcon: Icon(Icons.work_outline_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeader('Login details'),
              AppCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Official email',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    _gap(),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'At least 8 characters',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                MessageBanner(message: _error!, tone: BannerTone.error),
                const SizedBox(height: 14),
              ],
              PrimaryButton(
                label: 'Create account',
                icon: Icons.person_add_alt_1_rounded,
                busy: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              const Text(
                'By continuing you agree that your face signature (not your photo) is stored '
                'for attendance verification only.',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
