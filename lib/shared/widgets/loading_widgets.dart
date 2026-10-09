import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

/// Full-screen loading overlay with animated indicator.
class AppLoadingOverlay extends StatelessWidget {
  const AppLoadingOverlay({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black26,
      child: Center(
        child: Card(
          elevation: 8,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primary,
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Text(message!, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline loading indicator for button states.
///
/// Supports an optional [gradient] to override the theme button colour.
class AppLoadingButton extends StatelessWidget {
  const AppLoadingButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.isLoading = false,
    this.icon,
    this.isExpanded = true,
    this.gradient,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool isLoading;
  final IconData? icon;
  final bool isExpanded;

  /// Optional gradient — overrides the button's background colour.
  final LinearGradient? gradient;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    Widget button;
    if (gradient != null) {
      button = Container(
        height: 54,
        width: isExpanded ? double.infinity : null,
        decoration: BoxDecoration(
          gradient: onPressed == null ? null : gradient,
          color: onPressed == null ? Colors.grey.shade300 : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: child,
        ),
      );
    } else {
      button = SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: child,
        ),
      );
    }

    return isExpanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
