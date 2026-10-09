import 'package:flutter/material.dart';

import 'colors.dart';

/// Poppins for headings/labels, Roboto (system) for body text.
class AppText {
  AppText._();

  static const String heading = 'Poppins';
  static const String bodyFamily = 'Roboto';

  static const TextStyle display = TextStyle(
    fontFamily: heading,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.4,
    color: AppColors.text,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: heading,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.2,
    color: AppColors.text,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: heading,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.text,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: heading,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.text,
  );

  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 14.5,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 14.5,
    height: 1.45,
    fontWeight: FontWeight.w500,
    color: AppColors.text,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12.5,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle overline = TextStyle(
    fontFamily: heading,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    color: AppColors.textTertiary,
  );

  static const TextStyle number = TextStyle(
    fontFamily: heading,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.1,
    color: AppColors.text,
  );

  static const TextStyle button = TextStyle(
    fontFamily: heading,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
}
