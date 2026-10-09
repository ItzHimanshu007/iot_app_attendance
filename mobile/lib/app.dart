import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/api_client.dart';
import 'core/api_exception.dart';
import 'core/config.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/colors.dart';
import 'features/admin/admin_screen.dart';
import 'features/attendance/history_screen.dart';
import 'features/attendance/home_screen.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/session.dart';
import 'features/auth/signup_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_screen.dart';
import 'shared/widgets.dart';

const _publicRoutes = {'/', '/signup', '/forgot'};

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    redirect: (context, state) {
      if (!AppConfig.isConfigured) return state.matchedLocation == '/' ? null : '/';
      final signedIn = Supabase.instance.client.auth.currentUser != null;
      if (!signedIn && !_publicRoutes.contains(state.matchedLocation)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const AppGate()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
    ],
  );
});

class StaffAttendanceApp extends ConsumerWidget {
  const StaffAttendanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Staff Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Decides what the signed-in (or signed-out) user sees.
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> {
  @override
  void initState() {
    super.initState();
    if (AppConfig.isConfigured) ref.read(apiClientProvider).warmUp();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) return const _ConfigMissingScreen();
    final userId = ref.watch(userIdProvider);
    if (userId == null) return const LoginScreen();

    return ref
        .watch(meProvider)
        .when(
          loading: () => const _Splash(),
          error: (e, _) => Scaffold(
            body: SafeArea(
              child: ErrorView(message: errorMessage(e), onRetry: () => ref.invalidate(meProvider)),
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                child: const Text('Sign out'),
              ),
            ),
          ),
          data: (me) {
            if (me == null) return const _Splash();
            if (!me.onboarding.isReady) return OnboardingScreen(me: me);
            return HomeScreen(me: me);
          },
        );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: 56, color: AppColors.primary),
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting… (the server may take a few seconds to wake up)'),
          ],
        ),
      ),
    );
  }
}

class _ConfigMissingScreen extends StatelessWidget {
  const _ConfigMissingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: EmptyState(
          icon: Icons.settings_suggest_outlined,
          color: AppColors.warning,
          title: 'App is not configured',
          subtitle:
              'Missing: ${AppConfig.missing.join(', ')}\n\n'
              'Copy mobile/config/example.json to mobile/config/dev.json, fill it in, and run:\n'
              'flutter run --dart-define-from-file=config/dev.json',
        ),
      ),
    );
  }
}
