import 'dart:math';
import 'package:flutter/material.dart';

import '../core/app_colors.dart';

class NeuralForgePainter extends CustomPainter {
  NeuralForgePainter({required this.progress, required this.nodes});

  final double progress;
  final List<Offset> nodes;

  double phase(double start, double end) {
    return ((progress - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 30);

    final networkProgress = phase(0.02, 0.35);
    final pulseProgress = phase(0.27, 0.58);
    final collapseProgress = phase(0.55, 0.82);
    final exitProgress = phase(0.87, 1.0);

    final absoluteNodes = nodes.map((point) {
      final brainWidth = min(size.width * 0.55, 720.0);
      final brainHeight = min(size.height * 0.55, 420.0);

      final original = Offset(
        center.dx + point.dx * brainWidth,
        center.dy + point.dy * brainHeight,
      );

      final collapse = Curves.easeInOutCubic.transform(collapseProgress);

      return Offset.lerp(original, center, collapse * 0.82)!;
    }).toList();

    final backgroundPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              AppColors.gold.withValues(alpha: 0.10 * networkProgress),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: size.shortestSide * 0.55),
          );

    canvas.drawCircle(center, size.shortestSide * 0.55, backgroundPaint);

    _drawConnections(
      canvas,
      absoluteNodes,
      networkProgress,
      pulseProgress,
      exitProgress,
    );

    _drawNodes(
      canvas,
      absoluteNodes,
      networkProgress,
      pulseProgress,
      exitProgress,
    );

    _drawEnergyWave(canvas, size, center, pulseProgress, exitProgress);

    _drawOrbitingParticles(
      canvas,
      center,
      size,
      pulseProgress,
      collapseProgress,
      exitProgress,
    );
  }

  void _drawConnections(
    Canvas canvas,
    List<Offset> points,
    double networkProgress,
    double pulseProgress,
    double exitProgress,
  ) {
    final visibleCount = (points.length * networkProgress).round();

    for (var i = 0; i < visibleCount; i++) {
      for (var j = i + 1; j < visibleCount; j++) {
        final distance = (points[i] - points[j]).distance;

        if (distance > 145) continue;

        final opacity = ((1 - distance / 145) * 0.42 * (1 - exitProgress))
            .clamp(0.0, 1.0);

        final linePaint = Paint()
          ..color = AppColors.gold.withValues(alpha: opacity)
          ..strokeWidth = 1.1
          ..style = PaintingStyle.stroke;

        canvas.drawLine(points[i], points[j], linePaint);

        if (pulseProgress > 0.05) {
          final pulsePosition =
              (pulseProgress * 1.8 + i * 0.07 + j * 0.03) % 1.0;

          final travelingPoint = Offset.lerp(
            points[i],
            points[j],
            pulsePosition,
          )!;

          final pulsePaint = Paint()
            ..color = AppColors.brightGold.withValues(
              alpha: (1 - exitProgress) * 0.9,
            )
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

          canvas.drawCircle(travelingPoint, 2.5, pulsePaint);
        }
      }
    }
  }

  void _drawNodes(
    Canvas canvas,
    List<Offset> points,
    double networkProgress,
    double pulseProgress,
    double exitProgress,
  ) {
    final visibleCount = (points.length * networkProgress).round();

    for (var i = 0; i < visibleCount; i++) {
      final pulse = sin((pulseProgress * pi * 7) + i) * 0.5 + 0.5;
      final radius = 2.2 + pulse * 2.4;

      final glowPaint = Paint()
        ..color = AppColors.gold.withValues(
          alpha: (0.22 + pulse * 0.3) * (1 - exitProgress),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

      final corePaint = Paint()
        ..color = Color.lerp(
          AppColors.gold,
          AppColors.brightGold,
          pulse,
        )!.withValues(alpha: 1 - exitProgress);

      canvas.drawCircle(points[i], radius * 2.6, glowPaint);
      canvas.drawCircle(points[i], radius, corePaint);
    }
  }

  void _drawEnergyWave(
    Canvas canvas,
    Size size,
    Offset center,
    double pulseProgress,
    double exitProgress,
  ) {
    if (pulseProgress <= 0.02 || pulseProgress >= 0.88) {
      return;
    }

    final waveProgress = ((pulseProgress - 0.02) / 0.86).clamp(0.0, 1.0);

    final easedProgress = Curves.easeOutCubic.transform(waveProgress);

    final fade = (1 - waveProgress).clamp(0.0, 1.0) * (1 - exitProgress);

    final maxRadius = min(size.width, size.height) * 0.48;
    final radius = 35 + maxRadius * easedProgress;

    final waveRect = Rect.fromCenter(
      center: center,
      width: radius * 2.15,
      height: radius * 1.08,
    );

    final outerGlowPaint = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.38 * fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);

    final brightRingPaint = Paint()
      ..color = AppColors.brightGold.withValues(alpha: 0.95 * fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawOval(waveRect, outerGlowPaint);
    canvas.drawOval(waveRect, brightRingPaint);

    final secondProgress = ((waveProgress - 0.17) / 0.83).clamp(0.0, 1.0);

    if (secondProgress > 0) {
      final secondRadius =
          25 + maxRadius * Curves.easeOutCubic.transform(secondProgress);

      final secondFade =
          (1 - secondProgress).clamp(0.0, 1.0) * (1 - exitProgress);

      final secondRect = Rect.fromCenter(
        center: center,
        width: secondRadius * 2.05,
        height: secondRadius,
      );

      final secondRingPaint = Paint()
        ..color = AppColors.gold.withValues(alpha: 0.55 * secondFade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);

      canvas.drawOval(secondRect, secondRingPaint);
    }

    final flashProgress = (1 - waveProgress / 0.28).clamp(0.0, 1.0);

    if (flashProgress > 0) {
      final flashRadius = 45 + 90 * (1 - flashProgress);

      final flashPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.75 * flashProgress),
            AppColors.brightGold.withValues(alpha: 0.48 * flashProgress),
            AppColors.gold.withValues(alpha: 0.16 * flashProgress),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: flashRadius));

      canvas.drawCircle(center, flashRadius, flashPaint);
    }
  }

  void _drawOrbitingParticles(
    Canvas canvas,
    Offset center,
    Size size,
    double pulseProgress,
    double collapseProgress,
    double exitProgress,
  ) {
    if (pulseProgress <= 0.05) return;

    final maxRadius = min(size.width, size.height) * 0.34;

    for (var i = 0; i < 48; i++) {
      final angle = i * 0.72 + progress * pi * 4.5;
      final layer = 0.45 + (i % 9) / 15;
      final collapsingRadius =
          maxRadius * layer * (1 - collapseProgress * 0.88);

      final point = Offset(
        center.dx + cos(angle) * collapsingRadius,
        center.dy + sin(angle * 1.25) * collapsingRadius * 0.53,
      );

      final opacity =
          (0.25 + (i % 5) * 0.1) * (1 - exitProgress) * pulseProgress;

      final particlePaint = Paint()
        ..color = (i % 4 == 0 ? AppColors.brightGold : AppColors.gold)
            .withValues(alpha: opacity.clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      canvas.drawCircle(point, 1.3 + (i % 3), particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant NeuralForgePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
