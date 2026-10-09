import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme/colors.dart';
import '../core/theme/typography.dart';

// ── Status colours ──────────────────────────────────────────────────────────

Color statusColor(String status) => switch (status) {
  'present' => AppColors.present,
  'late' => AppColors.late,
  'absent' => AppColors.absent,
  'on_leave' => AppColors.onLeave,
  _ => AppColors.notMarked,
};

Color statusSoftColor(String status) => switch (status) {
  'present' => AppColors.successSoft,
  'late' => AppColors.warningSoft,
  'absent' => AppColors.errorSoft,
  'on_leave' => AppColors.infoSoft,
  _ => AppColors.surfaceMuted,
};

/// Pill with a coloured dot, e.g. "● Present".
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
    this.dense = false,
  });

  factory StatusChip.attendance(String status, {bool dense = false}) => StatusChip(
    label: Fmt.statusLabel(status),
    color: statusColor(status),
    background: statusSoftColor(status),
    dense: dense,
  );

  factory StatusChip.tone(String label, Color color, {IconData? icon, bool dense = false}) =>
      StatusChip(
        label: label,
        color: color,
        background: color.withValues(alpha: 0.1),
        icon: icon,
        dense: dense,
      );

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: dense ? 12 : 14, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          SizedBox(width: dense ? 4 : 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppText.heading,
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Surfaces ────────────────────────────────────────────────────────────────

/// White rounded card with a hairline border and soft shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 18,
            offset: Offset(0, 6),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Navy gradient block used at the top of main screens.
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 28),
    this.bottomRadius = 28,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double bottomRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(bottomRadius)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Small uppercase section title with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(child: Text(title.toUpperCase(), style: AppText.overline)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Icon inside a tinted rounded square.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color = AppColors.primary, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Number + label tile for summaries.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.primary,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, color: color, size: 34),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppText.number),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Circle with initials.
class Avatar extends StatelessWidget {
  const Avatar(this.initials, {super.key, this.size = 44, this.onDark = false});

  final String initials;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onDark ? Colors.white.withValues(alpha: 0.14) : AppColors.primarySoft,
        border: onDark ? Border.all(color: Colors.white.withValues(alpha: 0.35)) : null,
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: AppText.heading,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.36,
          color: onDark ? Colors.white : AppColors.primaryDark,
        ),
      ),
    );
  }
}

/// The app's logo mark.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset('assets/branding/logo.png', width: size, height: size),
    );
  }
}

/// Icon · label · value row used in detail cards.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, this.value, this.trailing});

  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final shown = value == null || value!.isEmpty ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.caption),
                const SizedBox(height: 2),
                Text(shown, style: AppText.bodyStrong),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

enum BannerTone { info, success, warning, error }

/// Inline message box.
class MessageBanner extends StatelessWidget {
  const MessageBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = BannerTone.info,
    this.icon,
    this.action,
  });

  final String message;
  final String? title;
  final BannerTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, defaultIcon) = switch (tone) {
      BannerTone.info => (AppColors.info, AppColors.infoSoft, Icons.info_outline_rounded),
      BannerTone.success => (AppColors.success, AppColors.successSoft, Icons.check_circle_outline),
      BannerTone.warning => (AppColors.warning, AppColors.warningSoft, Icons.warning_amber_rounded),
      BannerTone.error => (AppColors.error, AppColors.errorSoft, Icons.error_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: AppText.h3.copyWith(color: fg, fontSize: 14)),
                  const SizedBox(height: 2),
                ],
                Text(message, style: AppText.caption.copyWith(color: AppColors.text, fontSize: 13)),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Four bars showing BLE signal strength.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.rssi, this.color = AppColors.success});

  final int rssi;
  final Color color;

  int get level => rssi >= -65
      ? 4
      : rssi >= -75
      ? 3
      : rssi >= -85
      ? 2
      : 1;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 5,
            height: 6.0 + i * 4,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: i < level ? color : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

// ── Buttons ─────────────────────────────────────────────────────────────────

/// Large primary action with a busy spinner.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          else if (icon != null)
            Icon(icon, size: 20),
          if (busy || icon != null) const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

// ── States ──────────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.color = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 20),
            Text(title, style: AppText.h2, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: AppText.body, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      color: AppColors.error,
      title: 'Something went wrong',
      subtitle: message,
      action: onRetry == null
          ? null
          : SizedBox(
              width: 180,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ),
    );
  }
}

/// Centered spinner for loading sections.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.height = 160});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Center(child: CircularProgressIndicator()),
  );
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}
