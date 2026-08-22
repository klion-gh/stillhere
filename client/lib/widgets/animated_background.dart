/// The animated backdrop behind the full-screen flows.
///
/// Eight styles, all painted by one painter driven by one controller. Every term
/// completes a whole number of cycles across the loop, so the frame at the end
/// matches the frame at the start — a fractional rate anywhere makes the restart
/// visible.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../core/appearance.dart';
import '../core/theme.dart';

/// The app's backdrop: a palette gradient with an optional slow animation on
/// top. Everything is painted by a single CustomPainter driven by one
/// controller — cheap enough to sit behind every screen without costing
/// battery on a phone.
///
/// Every animation is built to be seamless: `t` runs 0→1 and each term
/// completes a whole number of cycles across that range, so the frame at
/// t=1 matches the frame at t=0 and the restart is invisible. Anything with
/// a fractional rate (0.7, 1.3, …) jumps at the loop point.
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

  static const _tau = 2 * pi;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case AppBackgroundId.orbs:
        _paintOrbs(canvas, size);
      case AppBackgroundId.aurora:
        _paintAurora(canvas, size);
      case AppBackgroundId.stars:
        _paintStars(canvas, size);
      case AppBackgroundId.mesh:
        _paintMesh(canvas, size);
      case AppBackgroundId.meteors:
        _paintMeteors(canvas, size);
      case AppBackgroundId.waves:
        _paintWaves(canvas, size);
      case AppBackgroundId.embers:
        _paintEmbers(canvas, size);
      case AppBackgroundId.plain:
        break;
    }
  }

  /// Large soft blobs drifting along closed Lissajous paths. Both frequencies
  /// are whole numbers, so each orb returns exactly to its starting point.
  void _paintOrbs(Canvas canvas, Size size) {
    const orbs = [
      (radius: 0.55, fx: 1, fy: 1, phase: 0.0, useAccent: false),
      (radius: 0.45, fx: 1, fy: 2, phase: 0.35, useAccent: true),
      (radius: 0.35, fx: 2, fy: 1, phase: 0.68, useAccent: false),
    ];

    for (final orb in orbs) {
      final angle = (t + orb.phase) * _tau;
      final cx = size.width * (0.5 + 0.38 * sin(angle * orb.fx));
      final cy = size.height * (0.45 + 0.34 * cos(angle * orb.fy));
      final radius = size.shortestSide * orb.radius;
      final color = orb.useAccent ? accent : primary;

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  /// Ribbons of light that undulate horizontally. The travelling phase
  /// advances by exactly one full turn over the loop.
  void _paintAurora(Canvas canvas, Size size) {
    for (var band = 0; band < 3; band++) {
      final phase = t * _tau + band * 1.7;
      final baseY = size.height * (0.28 + band * 0.22);
      final color = band.isEven ? primary : accent;

      final path = Path()..moveTo(0, baseY);
      for (double x = 0; x <= size.width; x += size.width / 24) {
        final u = x / size.width;
        final y = baseY +
            sin(u * 3 * pi + phase) * size.height * 0.06 +
            // Whole-number multiple of the phase: 2 turns per loop, so this
            // term also lands back where it started.
            cos(u * _tau - phase * 2) * size.height * 0.03;
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
  /// they're stable across frames without being stored.
  void _paintStars(Canvas canvas, Size size) {
    final rng = Random(42);
    final paint = Paint();
    for (var i = 0; i < 90; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final baseRadius = rng.nextDouble() * 1.4 + 0.4;
      final twinklePhase = rng.nextDouble() * _tau;
      final twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * _tau * 2 + twinklePhase));

      paint.color = (i % 5 == 0 ? accent : Colors.white).withValues(alpha: 0.55 * twinkle);
      canvas.drawCircle(Offset(x, y), baseRadius * twinkle, paint);
    }
  }

  /// Drifting nodes joined by lines when they come close — the "plexus" look.
  void _paintMesh(Canvas canvas, Size size) {
    const count = 26;
    final rng = Random(7);
    final points = <Offset>[];

    for (var i = 0; i < count; i++) {
      final baseX = rng.nextDouble();
      final baseY = rng.nextDouble();
      final ampX = 0.04 + rng.nextDouble() * 0.05;
      final ampY = 0.04 + rng.nextDouble() * 0.05;
      final phase = rng.nextDouble() * _tau;
      // Integer harmonics keep each node on a closed loop.
      final fx = 1 + rng.nextInt(2);
      final fy = 1 + rng.nextInt(2);
      points.add(Offset(
        (baseX + ampX * sin(t * _tau * fx + phase)) * size.width,
        (baseY + ampY * cos(t * _tau * fy + phase)) * size.height,
      ));
    }

    final linkDistance = size.shortestSide * 0.22;
    final linePaint = Paint()..strokeWidth = 1;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final d = (points[i] - points[j]).distance;
        if (d > linkDistance) continue;
        final strength = 1 - d / linkDistance;
        linePaint.color = primary.withValues(alpha: 0.16 * strength);
        canvas.drawLine(points[i], points[j], linePaint);
      }
    }

    final dotPaint = Paint()..color = accent.withValues(alpha: 0.5);
    for (final p in points) {
      canvas.drawCircle(p, 1.6, dotPaint);
    }
  }

  /// Streaks falling diagonally. Each one wraps on its own fractional
  /// progress, so there's no shared restart to notice.
  void _paintMeteors(Canvas canvas, Size size) {
    const count = 14;
    final rng = Random(19);
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      final lane = rng.nextDouble();
      final speed = 1 + rng.nextInt(3); // whole trips per loop
      final offset = rng.nextDouble();
      final length = size.shortestSide * (0.08 + rng.nextDouble() * 0.12);

      // Fractional part wraps continuously — the position at t=1 equals t=0.
      final progress = (t * speed + offset) % 1.0;
      // Travel diagonally across a box larger than the screen so streaks
      // enter and leave off-canvas instead of popping in.
      final x = (lane * 1.4 - 0.2) * size.width + progress * size.width * 0.5;
      final y = -0.2 * size.height + progress * size.height * 1.4;

      final dir = const Offset(-0.35, 1).normalized();
      final tail = Offset(x, y) - dir * length;

      paint.shader = LinearGradient(
        colors: [accent.withValues(alpha: 0.0), accent.withValues(alpha: 0.45)],
      ).createShader(Rect.fromPoints(tail, Offset(x, y)));
      paint.strokeWidth = 1.6;
      canvas.drawLine(tail, Offset(x, y), paint);
    }
  }

  /// Broad overlapping swells, like light on water.
  void _paintWaves(Canvas canvas, Size size) {
    for (var layer = 0; layer < 4; layer++) {
      final color = layer.isEven ? primary : accent;
      final baseY = size.height * (0.55 + layer * 0.11);
      final amplitude = size.height * (0.05 - layer * 0.008);
      final speed = layer + 1; // whole turns per loop

      final path = Path()..moveTo(0, size.height);
      path.lineTo(0, baseY);
      for (double x = 0; x <= size.width; x += size.width / 40) {
        final u = x / size.width;
        final y = baseY + sin(u * _tau * (layer + 2) + t * _tau * speed) * amplitude;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, baseY - amplitude, size.width, size.height - baseY)),
      );
    }
  }

  /// Slow sparks rising, like embers over a fire.
  void _paintEmbers(Canvas canvas, Size size) {
    const count = 40;
    final rng = Random(101);
    final paint = Paint();

    for (var i = 0; i < count; i++) {
      final lane = rng.nextDouble();
      final speed = 1 + rng.nextInt(2);
      final offset = rng.nextDouble();
      final sway = 0.02 + rng.nextDouble() * 0.04;
      final swayFreq = 1 + rng.nextInt(3);
      final radius = 0.8 + rng.nextDouble() * 1.8;

      final progress = (t * speed + offset) % 1.0;
      // Rises from just below the screen to just above it.
      final y = (1.1 - progress * 1.2) * size.height;
      final x = (lane + sway * sin(progress * _tau * swayFreq)) * size.width;

      // Fade in at the bottom and out at the top so nothing blinks out of
      // existence mid-screen when it wraps.
      final fade = sin(progress * pi).clamp(0.0, 1.0);
      paint.color = (i % 3 == 0 ? accent : primary).withValues(alpha: 0.5 * fade);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.style != style ||
      oldDelegate.primary != primary ||
      oldDelegate.accent != accent;
}

extension _Normalize on Offset {
  Offset normalized() {
    final d = distance;
    return d == 0 ? this : this / d;
  }
}
