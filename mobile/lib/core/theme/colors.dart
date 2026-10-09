import 'package:flutter/material.dart';

/// Institutional palette: deep navy + academic gold, slate neutrals.
class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────────────────────────
  static const Color navy = Color(0xFF0B2A5B); // headers
  static const Color navyDark = Color(0xFF071D40);
  static const Color primary = Color(0xFF1D4ED8); // actions
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color primarySoft = Color(0xFFE8EEFC);
  static const Color gold = Color(0xFFF5B301); // sparing highlights
  static const Color goldSoft = Color(0xFFFFF6DB);

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF15803D);
  static const Color successSoft = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFB45309);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFB91C1C);
  static const Color errorSoft = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF0369A1);
  static const Color infoSoft = Color(0xFFE0F2FE);

  // ── Neutrals (slate) ───────────────────────────────────────────────────────
  static const Color text = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color background = Color(0xFFF3F5F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFEDF1F6);

  // ── Attendance status ──────────────────────────────────────────────────────
  static const Color present = success;
  static const Color late = warning;
  static const Color absent = error;
  static const Color onLeave = info;
  static const Color notMarked = Color(0xFF64748B);

  static const LinearGradient headerGradient = LinearGradient(
    colors: [navyDark, navy, Color(0xFF15408A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient actionGradient = LinearGradient(
    colors: [Color(0xFF1E40AF), primary],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}
