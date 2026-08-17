import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/appearance.dart';
import '../core/avatar_cache.dart';
import '../core/theme.dart';
import '../models/user.dart';
import 'animated_background.dart';

/// Circular avatar: the user's picture if they have one, otherwise a
/// per-user gradient derived from the tag so the same person is always the
/// same colour across devices.
class GradientAvatar extends ConsumerWidget {
  final String username;
  final double size;
  final bool showPulse;

  /// Needed to build the picture URL; without it the gradient is used.
  final String? userId;
  final bool hasAvatar;
  final DateTime? avatarUpdatedAt;

  const GradientAvatar({
    super.key,
    required this.username,
    this.size = 48,
    this.showPulse = false,
    this.userId,
    this.hasAvatar = false,
    this.avatarUpdatedAt,
  });

  /// For the common case where the whole user is on hand. [fallbackUsername]
  /// covers the moment before the conversation list has loaded, when all a
  /// screen has is the tag from its route.
  factory GradientAvatar.of(
    AppUser? user, {
    Key? key,
    required String fallbackUsername,
    double size = 48,
    bool showPulse = false,
  }) {
    return GradientAvatar(
      key: key,
      username: user?.username ?? fallbackUsername,
      size: size,
      showPulse: showPulse,
      userId: user?.id,
      hasAvatar: user?.hasAvatar ?? false,
      avatarUpdatedAt: user?.avatarUpdatedAt,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradient = AppColors.avatarGradient(username);
    final letter = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final fallback = _GradientLetter(gradient: gradient, letter: letter, size: size);

    Widget content = fallback;
    if (hasAvatar && userId != null) {
      final avatar = ref.watch(
        avatarBytesProvider(AvatarRef(userId!, avatarUpdatedAt?.millisecondsSinceEpoch ?? 0)),
      );
      // Anything other than a loaded image — still loading, no picture, or a
      // failure — falls back to the gradient rather than a gap or a broken
      // image box.
      content = avatar.maybeWhen(
        data: (bytes) => bytes == null
            ? fallback
            : Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
        orElse: () => fallback,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
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
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: content,
    );
  }
}

class _GradientLetter extends StatelessWidget {
  final LinearGradient gradient;
  final String letter;
  final double size;

  const _GradientLetter({required this.gradient, required this.letter, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
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
