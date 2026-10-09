import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import 'auth_service.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_email.text.contains('@')) {
      showSnack(context, 'Enter a valid email', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).resetPassword(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: _sent
            ? EmptyState(
                icon: Icons.mark_email_read_outlined,
                color: AppColors.success,
                title: 'Check your inbox',
                subtitle:
                    'If an account exists for ${_email.text.trim()}, '
                    'a password reset link is on its way.',
                action: SizedBox(
                  width: 200,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to sign in'),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: IconBadge(Icons.key_rounded, size: 48),
                        ),
                        const SizedBox(height: 16),
                        const Text('Forgot your password?', style: AppText.h2),
                        const SizedBox(height: 6),
                        const Text(
                          'Enter your official email and we will send you a link to set a new password.',
                          style: AppText.body,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                        const SizedBox(height: 18),
                        PrimaryButton(
                          label: 'Send reset link',
                          icon: Icons.send_rounded,
                          busy: _busy,
                          onPressed: _send,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
