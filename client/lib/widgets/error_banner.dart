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

/// The app's logo mark — the cyber dove over a soft glow.
class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 84});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The logo is a cut-out rather than a filled tile, so a box shadow
            // would trace its bounding square. A radial glow sits behind it
            // instead and picks up the palette.
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.34),
                    AppColors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
              child: SizedBox(width: size, height: size),
            ),
            Image.asset(
              'assets/icons/logo.png',
              width: size * 0.94,
              height: size * 0.94,
              filterQuality: FilterQuality.medium,
            ),
          ],
        ),
      ),
    );
  }
}
