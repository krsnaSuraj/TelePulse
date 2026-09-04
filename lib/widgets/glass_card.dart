import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? backgroundColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 12,
    this.onTap,
    this.borderColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final border = Border.all(
      color: borderColor ?? AppColors.hairline,
      width: 1,
    );

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
      ),
      child: onTap != null
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(borderRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(borderRadius),
                onTap: onTap,
                splashFactory: InkRipple.splashFactory,
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(14),
                  child: child,
                ),
              ),
            )
          : Padding(
              padding: padding ?? const EdgeInsets.all(14),
              child: child,
            ),
    );
  }
}
