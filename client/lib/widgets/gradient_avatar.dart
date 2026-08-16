import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/appearance.dart';
import '../core/theme.dart';
import 'animated_background.dart';

/// Circular avatar with a per-user gradient derived from the username, so
/// the same person is always the same color across devices.
class GradientAvatar extends StatelessWidget {
  final String username;
  final double size;
  final bool showPulse;

  const GradientAvatar({
    super.key,
    required this.username,
    this.size = 48,
    this.showPulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = AppColors.avatarGradient(username);
    final letter = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        boxShadow: showPulse
            ? [
                BoxShadow(
                  color: gradient.colors.first.withValues(alpha: 0.45),
                  blurRadius: size * 0.5,
                  spreadRadius: size * 0.06,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

/// The backdrop shared by the full-screen flows (connect, auth, chat list,
/// call). Renders the palette gradient plus whichever animated background
/// the user picked in Appearance.
class NightBackdrop extends ConsumerWidget {
  final Widget child;

  const NightBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = ref.watch(appearanceProvider).backgroundId;
    return AnimatedBackdrop(background: background, child: child);
  }
}

/// Soft radial glow used behind hero elements (logo, calling avatar).
class GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const GlowOrb({super.key, required this.color, this.size = 320, this.opacity = 0.16});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
