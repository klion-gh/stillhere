import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Inline error surface used by the auth/connect forms.
class ErrorBanner extends StatelessWidget {
  final String message;

  const ErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's logo mark — gradient rounded square with a glow.
class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 84});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(size * 0.31),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: size * 0.38,
              spreadRadius: 2,
              offset: Offset(0, size * 0.1),
            ),
          ],
        ),
        child: Icon(Icons.bolt_rounded, color: Colors.white, size: size * 0.52),
      ),
    );
  }
}
