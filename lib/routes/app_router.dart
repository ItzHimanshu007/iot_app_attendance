import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../features/attendance/screens/attendance_history_screen.dart';
import '../features/attendance/screens/attendance_submission_screen.dart';
import '../features/attendance/screens/session_discovery_screen.dart';
import '../features/attendance/models/ble_models.dart';
import '../features/auth/controllers/auth_controller.dart';
import '../features/auth/email_verification_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/student_signup_screen.dart';
import '../features/auth/teacher_signup_screen.dart';
import '../features/debug/presentation/ble_scanner_screen.dart';
import '../features/device/screens/device_registration_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/student/student_dashboard.dart';
import '../features/teacher/screens/active_session_screen.dart';
import '../features/teacher/screens/session_creation_screen.dart';
import '../features/teacher/screens/session_details_screen.dart';
import '../features/teacher/teacher_dashboard.dart';
import '../features/reports/screens/teacher_reports_dashboard.dart';
import '../features/settings/startup_screen.dart';

/// Route path constants.
class RoutePaths {
  RoutePaths._();

  static const String splash          = '/';
  static const String startup         = '/startup';
  static const String login           = '/login';

  // ── Auth / Signup ──────────────────────────────────────────────────────────
  static const String signUp           = '/signup';
  static const String studentSignup    = '/signup/student';
  static const String teacherSignup    = '/signup/teacher';
  static const String emailVerification = '/email-verification';
  static const String forgotPassword   = '/forgot-password';

  // ── Dashboards ─────────────────────────────────────────────────────────────
  static const String studentDashboard = '/student';
  static const String teacherDashboard = '/teacher';

  // ── Shared ─────────────────────────────────────────────────────────────────
  static const String profile         = '/profile';
  static const String settings        = '/settings';

  // ── Student ────────────────────────────────────────────────────────────────
  static const String sessionDiscovery    = '/session-discovery';
  static const String attendanceSubmission = '/attendance';
  static const String attendanceHistory   = '/attendance/history';
  static const String deviceRegistration  = '/device-registration';

  // ── Teacher ────────────────────────────────────────────────────────────────
  static const String sessionCreation = '/session/create';
  static const String activeSession   = '/session/active';
  static const String timetable       = '/timetable';
  static const String reports         = '/reports';
  static const String sessionDetails   = '/session/details';

  // ── Debug / Phase 2 ───────────────────────────────────────────────────────
  static const String bleScanner = '/debug/ble';

  /// Paths accessible without authentication.
  static const Set<String> publicPaths = {
    login,
    signUp,
    studentSignup,
    teacherSignup,
    emailVerification,
    forgotPassword,
  };
}

/// GoRouter with reactive auth state — listens to [authControllerProvider].
///
/// Redirect logic:
///   loading   → splash (always)
///   unauth    → /login
///   auth      → role-based dashboard
///   student   → cannot access /teacher/*
///   teacher   → cannot access /student/*
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final currentPath = state.matchedLocation;

      // ── Loading during app initialization → stay on splash ─────────────
      // isInitializing is only true during initializeSession() on startup.
      // It is intentionally NOT set during login(), so a mid-login loading
      // state does not cause GoRouter to redirect away from /login and blink.
      if (authState.isLoading && authState.isInitializing) {
        dev.log('[NAV] redirect: initializing — currentPath=$currentPath → splash', name: 'GoRouter');
        return currentPath == RoutePaths.splash ? null : RoutePaths.splash;
      }

      // ── Loading but NOT initializing (e.g. logout in progress) → stay ──
      if (authState.isLoading) {
        dev.log('[NAV] redirect: loading (not initializing) — stay at $currentPath', name: 'GoRouter');
        return null;
      }

      // ── Not authenticated → allow public paths, redirect others to login ──────
      if (authState.isUnauthenticated) {
        if (RoutePaths.publicPaths.contains(currentPath)) {
          return null; // allow signup/forgot-password without auth
        }
        dev.log('[NAV] redirect to login — currentPath=$currentPath', name: 'GoRouter');
        return RoutePaths.login;
      }

      // ── Authenticated + on public path → go to role dashboard ───────────────
      if (RoutePaths.publicPaths.contains(currentPath) ||
          currentPath == RoutePaths.splash) {
        final dashboard = _dashboardForRole(authState.role);
        dev.log('[NAV] redirect: authenticated — role=${authState.role} → $dashboard', name: 'GoRouter');
        return dashboard;
      }

      // ── Role isolation — prevent cross-role navigation ──────────────────
      final role = authState.role;
      if (role == AppConstants.roleStudent &&
          currentPath.startsWith(RoutePaths.teacherDashboard)) {
        dev.log('[NAV] redirect: student blocked from teacher route → studentDashboard', name: 'GoRouter');
        return RoutePaths.studentDashboard;
      }
      if ((role == AppConstants.roleTeacher ||
              role == AppConstants.roleAdmin) &&
          currentPath.startsWith(RoutePaths.studentDashboard)) {
        dev.log('[NAV] redirect: teacher/admin blocked from student route → teacherDashboard', name: 'GoRouter');
        return RoutePaths.teacherDashboard;
      }

      return null; // Allow navigation
    },
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.startup,
        name: 'startup',
        builder: (context, state) => const StartupScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      // ── Signup flow ──────────────────────────────────────────────────────────
      GoRoute(
        path: RoutePaths.signUp,
        name: 'signUp',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: RoutePaths.studentSignup,
        name: 'studentSignup',
        builder: (context, state) => const StudentSignupScreen(),
      ),
      GoRoute(
        path: RoutePaths.teacherSignup,
        name: 'teacherSignup',
        builder: (context, state) => const TeacherSignupScreen(),
      ),
      GoRoute(
        path: RoutePaths.emailVerification,
        name: 'emailVerification',
        builder: (context, state) {
          final email = state.extra as String? ?? '';
          return EmailVerificationScreen(email: email);
        },
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        name: 'forgotPassword',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: RoutePaths.studentDashboard,
        name: 'studentDashboard',
        builder: (context, state) => const StudentDashboard(),
      ),
      GoRoute(
        path: RoutePaths.teacherDashboard,
        name: 'teacherDashboard',
        builder: (context, state) => const TeacherDashboard(),
      ),
      GoRoute(
        path: RoutePaths.profile,
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: RoutePaths.settings,
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: RoutePaths.sessionDiscovery,
        name: 'sessionDiscovery',
        builder: (context, state) => const SessionDiscoveryScreen(),
      ),
      GoRoute(
        path: RoutePaths.attendanceSubmission,
        name: 'attendanceSubmission',
        builder: (context, state) {
          // Optional: pre-loaded from SessionDiscoveryScreen via context.push extra
          final advertisement =
              state.extra as AttendanceSessionAdvertisement?;
          return AttendanceSubmissionScreen(
            preloadedAdvertisement: advertisement,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.attendanceHistory,
        name: 'attendanceHistory',
        builder: (context, state) => const AttendanceHistoryScreen(),
      ),
      GoRoute(
        path: RoutePaths.deviceRegistration,
        name: 'deviceRegistration',
        builder: (context, state) => const DeviceRegistrationScreen(),
      ),
      // Teacher routes
      GoRoute(
        path: RoutePaths.sessionCreation,
        name: 'sessionCreation',
        builder: (context, state) => const SessionCreationScreen(),
      ),
      GoRoute(
        path: RoutePaths.activeSession,
        name: 'activeSession',
        builder: (context, state) => const ActiveSessionScreen(),
      ),
      GoRoute(
        path: RoutePaths.timetable,
        name: 'timetable',
        builder: (context, state) => const TimetableScreen(),
      ),
      GoRoute(
        path: RoutePaths.reports,
        name: 'reports',
        builder: (context, state) => const TeacherReportsDashboard(),
      ),
      GoRoute(
        path: RoutePaths.sessionDetails,
        name: 'sessionDetails',
        builder: (context, state) {
          final sessionId = state.extra as String;
          return SessionDetailsScreen(sessionId: sessionId);
        },
      ),
      // ── Debug routes (Phase 2 — remove after validation) ────────────────
      GoRoute(
        path: RoutePaths.bleScanner,
        name: 'bleScanner',
        builder: (context, state) => const BleScannerScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              state.matchedLocation,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(RoutePaths.splash),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});

String _dashboardForRole(String? role) {
  switch (role) {
    case AppConstants.roleTeacher:
    case AppConstants.roleAdmin:
      return RoutePaths.teacherDashboard;
    case AppConstants.roleStudent:
    default:
      return RoutePaths.studentDashboard;
  }
}
