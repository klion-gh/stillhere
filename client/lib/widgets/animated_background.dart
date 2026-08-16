import 'dart:math';

import 'package:flutter/material.dart';

import '../core/appearance.dart';
import '../core/theme.dart';

/// The app's backdrop: a palette gradient with an optional slow animation on
/// top. Everything is painted with a single CustomPainter driven by one
/// controller — cheap enough to sit behind every screen without costing
/// battery on a phone.
class AnimatedBackdrop extends StatefulWidget {
  final AppBackgroundId background;
  final Widget child;

  const AnimatedBackdrop({super.key, required this.background, required this.child});

  @override
  State<AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<AnimatedBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // One long cycle; the painters use fractions of it at different rates so
    // nothing lines up into an obvious loop.
    duration: const Duration(seconds: 60),
  );

  @override
  void initState() {
    super.initState();
    if (widget.background != AppBackgroundId.plain) _controller.repeat();
  }

  @override
  void didUpdateWidget(AnimatedBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.background == AppBackgroundId.plain) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: AppColors.nightGradient),
      child: Stack(
        children: [
          if (widget.background != AppBackgroundId.plain)
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _BackdropPainter(
                      style: widget.background,
                      t: _controller.value,
                      primary: AppColors.primary,
                      accent: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  final AppBackgroundId style;
  final double t;
  final Color primary;
  final Color accent;

  _BackdropPainter({
    required this.style,
    required this.t,
    required this.primary,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case AppBackgroundId.orbs:
        _paintOrbs(canvas, size);
        break;
      case AppBackgroundId.aurora:
        _paintAurora(canvas, size);
        break;
      case AppBackgroundId.stars:
        _paintStars(canvas, size);
        break;
      case AppBackgroundId.plain:
        break;
    }
  }

  /// Large soft blobs drifting along lissajous paths.
  void _paintOrbs(Canvas canvas, Size size) {
    final orbs = [
      (color: primary, radius: 0.55, phase: 0.0, speed: 1.0),
      (color: accent, radius: 0.45, phase: 0.35, speed: 0.7),
      (color: primary, radius: 0.35, phase: 0.68, speed: 1.3),
    ];

    for (final orb in orbs) {
      final angle = (t * orb.speed + orb.phase) * 2 * pi;
      final cx = size.width * (0.5 + 0.38 * sin(angle));
      final cy = size.height * (0.45 + 0.34 * cos(angle * 0.8));
      final radius = size.shortestSide * orb.radius;

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [orb.color.withValues(alpha: 0.20), orb.color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  /// Horizontal ribbons of light that slowly undulate.
  void _paintAurora(Canvas canvas, Size size) {
    for (var band = 0; band < 3; band++) {
      final phase = t * 2 * pi + band * 1.7;
      final baseY = size.height * (0.28 + band * 0.22);
      final color = band.isEven ? primary : accent;

      final path = Path()..moveTo(0, baseY);
      for (double x = 0; x <= size.width; x += size.width / 24) {
        final y = baseY +
            sin((x / size.width) * 3 * pi + phase) * size.height * 0.06 +
            cos((x / size.width) * 2 * pi - phase * 0.6) * size.height * 0.03;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.13), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, baseY - size.height * 0.1, size.width, size.height * 0.5))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
      canvas.drawPath(path, paint);
    }
  }

  /// A fixed star field that twinkles. Positions come from a seeded RNG so
  /// they're stable across frames without storing them.
  void _paintStars(Canvas canvas, Size size) {
    final rng = Random(42);
    final paint = Paint();
    for (var i = 0; i < 90; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final baseRadius = rng.nextDouble() * 1.4 + 0.4;
      final twinklePhase = rng.nextDouble() * 2 * pi;
      final twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 2 * pi * 2 + twinklePhase));

      paint.color = (i % 5 == 0 ? accent : Colors.white).withValues(alpha: 0.55 * twinkle);
      canvas.drawCircle(Offset(x, y), baseRadius * twinkle, paint);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.style != style ||
      oldDelegate.primary != primary ||
      oldDelegate.accent != accent;
}
