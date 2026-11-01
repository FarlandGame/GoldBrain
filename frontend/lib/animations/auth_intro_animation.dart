import 'dart:math' as math;

import 'package:flutter/material.dart';

class AuthIntroAnimation extends StatefulWidget {
  const AuthIntroAnimation({
    super.key,
    required this.accentColor,
    required this.onCompleted,
  });

  final Color accentColor;
  final VoidCallback onCompleted;

  @override
  State<AuthIntroAnimation> createState() => _AuthIntroAnimationState();
}

class _AuthIntroAnimationState extends State<AuthIntroAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_AuthParticle> _particles;

  @override
  void initState() {
    super.initState();

    _particles = _createParticles();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted();
      }
    });

    _controller.forward();
  }

  List<_AuthParticle> _createParticles() {
    final random = math.Random(2026);

    return List.generate(95, (index) {
      final angle = random.nextDouble() * math.pi * 2;
      final distance = 90 + random.nextDouble() * 360;

      return _AuthParticle(
        angle: angle,
        distance: distance,
        radius: 1.2 + random.nextDouble() * 3.2,
        delay: random.nextDouble() * 0.18,
        targetX: -0.42 + random.nextDouble() * 0.84,
        targetY: -0.27 + random.nextDouble() * 0.54,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _AuthIntroPainter(
              progress: _controller.value,
              accentColor: widget.accentColor,
              particles: _particles,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _AuthIntroPainter extends CustomPainter {
  const _AuthIntroPainter({
    required this.progress,
    required this.accentColor,
    required this.particles,
  });

  final double progress;
  final Color accentColor;
  final List<_AuthParticle> particles;

  double phase(double start, double end) {
    return ((progress - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final orbEntry = Curves.easeOutBack.transform(phase(0.00, 0.20));

    final impact = Curves.easeOutExpo.transform(phase(0.18, 0.34));

    final explosion = Curves.easeOutCubic.transform(phase(0.27, 0.56));

    final morph = Curves.easeInOutCubic.transform(phase(0.52, 0.84));

    final fadeOut = Curves.easeInCubic.transform(phase(0.84, 1.00));

    final opacity = 1 - fadeOut;

    _drawBackgroundGlow(canvas, size, center, impact, opacity);

    _drawIncomingProjectile(canvas, size, center, impact, opacity);

    _drawOrb(canvas, center, orbEntry, impact, opacity);

    _drawShockwave(canvas, center, impact, opacity);

    _drawParticles(canvas, size, center, explosion, morph, opacity);

    _drawPanelBlueprint(canvas, size, center, morph, opacity);
  }

  void _drawBackgroundGlow(
    Canvas canvas,
    Size size,
    Offset center,
    double impact,
    double opacity,
  ) {
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accentColor.withValues(alpha: 0.18 * impact * opacity),
              accentColor.withValues(alpha: 0.05 * impact * opacity),
              Colors.transparent,
            ],
            stops: const [0, 0.38, 1],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.shortestSide * 0.55),
          );

    canvas.drawCircle(center, size.shortestSide * 0.55, glowPaint);
  }

  void _drawIncomingProjectile(
    Canvas canvas,
    Size size,
    Offset center,
    double impact,
    double opacity,
  ) {
    if (impact >= 1) return;

    final projectileProgress = Curves.easeInExpo.transform(phase(0.08, 0.29));

    final start = Offset(-100, center.dy - size.height * 0.16);

    final position = Offset.lerp(start, center, projectileProgress)!;

    final direction = center - position;
    final normalized = direction.distance == 0
        ? Offset.zero
        : direction / direction.distance;

    final trailStart = position - normalized * 170;

    final trailPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          accentColor.withValues(alpha: 0.15 * opacity),
          accentColor.withValues(alpha: 0.85 * opacity),
        ],
      ).createShader(Rect.fromPoints(trailStart, position))
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawLine(trailStart, position, trailPaint);

    final corePaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.drawCircle(position, 5, corePaint);
  }

  void _drawOrb(
    Canvas canvas,
    Offset center,
    double orbEntry,
    double impact,
    double opacity,
  ) {
    final compressedScale = 1 - impact * 0.55;
    final radius = 58 * orbEntry * compressedScale;

    if (radius <= 0) return;

    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.34 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32);

    final orbPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        colors: [
          Colors.white.withValues(alpha: opacity),
          accentColor.withValues(alpha: opacity),
          accentColor.withValues(alpha: 0.35 * opacity),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius * 1.7, glowPaint);

    canvas.drawCircle(center, radius, orbPaint);

    final ringPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.75 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawCircle(center, radius * 1.22, ringPaint);
  }

  void _drawShockwave(
    Canvas canvas,
    Offset center,
    double impact,
    double opacity,
  ) {
    if (impact <= 0) return;

    final shockRadius = 40 + impact * 330;

    final shockPaint = Paint()
      ..color = accentColor.withValues(alpha: (1 - impact) * 0.65 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawCircle(center, shockRadius, shockPaint);
  }

  void _drawParticles(
    Canvas canvas,
    Size size,
    Offset center,
    double explosion,
    double morph,
    double opacity,
  ) {
    final panelWidth = math.min(size.width * 0.75, 940.0);
    final panelHeight = math.min(size.height * 0.62, 560.0);

    for (var index = 0; index < particles.length; index++) {
      final particle = particles[index];

      final localExplosion = Curves.easeOutCubic.transform(
        ((explosion - particle.delay) / (1 - particle.delay)).clamp(0.0, 1.0),
      );

      final explodedPosition = Offset(
        center.dx +
            math.cos(particle.angle) * particle.distance * localExplosion,
        center.dy +
            math.sin(particle.angle) * particle.distance * localExplosion,
      );

      final targetPosition = Offset(
        center.dx + particle.targetX * panelWidth,
        center.dy + particle.targetY * panelHeight,
      );

      final position = Offset.lerp(explodedPosition, targetPosition, morph)!;

      final pulse = math.sin(progress * math.pi * 12 + index * 0.7) * 0.5 + 0.5;

      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: (0.12 + pulse * 0.2) * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      final corePaint = Paint()
        ..color = Color.lerp(
          accentColor,
          Colors.white,
          pulse * 0.55,
        )!.withValues(alpha: opacity);

      canvas.drawCircle(position, particle.radius * 2.8, glowPaint);

      canvas.drawCircle(position, particle.radius, corePaint);

      if (index % 4 == 0 && morph > 0.15) {
        final nextParticle = particles[(index + 7) % particles.length];

        final nextTarget = Offset(
          center.dx + nextParticle.targetX * panelWidth,
          center.dy + nextParticle.targetY * panelHeight,
        );

        final linePaint = Paint()
          ..color = accentColor.withValues(alpha: 0.10 * morph * opacity)
          ..strokeWidth = 0.8;

        canvas.drawLine(position, nextTarget, linePaint);
      }
    }
  }

  void _drawPanelBlueprint(
    Canvas canvas,
    Size size,
    Offset center,
    double morph,
    double opacity,
  ) {
    if (morph <= 0.05) return;

    final panelWidth = math.min(size.width * 0.76, 950.0);
    final panelHeight = math.min(size.height * 0.64, 570.0);

    final rect = Rect.fromCenter(
      center: center,
      width: panelWidth,
      height: panelHeight,
    );

    final borderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.42 * morph * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(34)),
      borderPaint,
    );

    final dividerPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.18 * morph * opacity)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(center.dx, rect.top + 45),
      Offset(center.dx, rect.bottom - 45),
      dividerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AuthIntroPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accentColor != accentColor;
  }
}

class _AuthParticle {
  const _AuthParticle({
    required this.angle,
    required this.distance,
    required this.radius,
    required this.delay,
    required this.targetX,
    required this.targetY,
  });

  final double angle;
  final double distance;
  final double radius;
  final double delay;
  final double targetX;
  final double targetY;
}
