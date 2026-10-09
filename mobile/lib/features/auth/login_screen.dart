import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/config.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets.dart';
import 'auth_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
      await ref.read(authServiceProvider).signIn(_email.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            GradientHeader(
              bottomRadius: 32,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandLogo(size: 60),
                  const SizedBox(height: 22),
                  Text(
                    AppConfig.collegeName.toUpperCase(),
                    style: AppText.overline.copyWith(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(AppConfig.appName, style: AppText.display.copyWith(color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(
                    'Mark your attendance from your phone once you are on campus — no queue at the gate.',
                    style: AppText.body.copyWith(color: Colors.white.withValues(alpha: 0.78)),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                      child: Form(
                        key: _form,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Sign in', style: AppText.h1),
                              const SizedBox(height: 4),
                              const Text('Use your official college email.', style: AppText.body),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                ),
                                validator: (v) =>
                                    (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _password,
                                obscureText: _obscure,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure ? 'Show password' : 'Hide password',
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty) ? 'Enter your password' : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => context.push('/forgot'),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                              if (_error != null) ...[
                                MessageBanner(message: _error!, tone: BannerTone.error),
                                const SizedBox(height: 14),
                              ],
                              PrimaryButton(
                                label: 'Sign in',
                                icon: Icons.login_rounded,
                                busy: _busy,
                                onPressed: _submit,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('New staff member?', style: AppText.body),
                        TextButton(
                          onPressed: () => context.push('/signup'),
                          child: const Text('Create an account'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const _TrustRow(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label) => Expanded(
      child: Column(
        children: [
          IconBadge(icon, color: AppColors.navy, size: 40),
          const SizedBox(height: 8),
          Text(label, style: AppText.caption, textAlign: TextAlign.center),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(Icons.bluetooth_rounded, 'Campus beacon\nverified'),
        item(Icons.face_retouching_natural, 'Live face\ncheck'),
        item(Icons.lock_outline_rounded, 'Photos never\nstored'),
      ],
    );
  }
}
