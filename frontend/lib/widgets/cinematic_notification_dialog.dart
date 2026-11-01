import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/selection_screen.dart';

class CinematicNotificationDialog extends StatefulWidget {
  const CinematicNotificationDialog({
    super.key,
    required this.palette,
    required this.motionEnabled,
    required this.reducedMotion,
    required this.intensity,
    required this.child,
  });

  final ThemePalette palette;
  final bool motionEnabled;
  final bool reducedMotion;
  final double intensity;
  final Widget child;

  @override
  State<CinematicNotificationDialog> createState() =>
      _CinematicNotificationDialogState();
}

class _CinematicNotificationDialogState
    extends State<CinematicNotificationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final duration = !widget.motionEnabled
        ? 1
        : widget.reducedMotion
        ? 240
        : (1500 + widget.intensity.clamp(0.0, 1.0) * 500).round();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: duration),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _phase(double start, double end) {
    return ((_controller.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.motionEnabled) return Center(child: widget.child);

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final dialogChild = child ?? const SizedBox.shrink();
        final panelProgress = Curves.easeOutBack.transform(_phase(0.80, 1));
        final panelOpacity = Curves.easeOut.transform(_phase(0.82, 0.96));

        if (widget.reducedMotion) {
          return Center(
            child: Opacity(
              opacity: Curves.easeOut.transform(_controller.value),
              child: Transform.scale(
                scale: 0.96 + _controller.value * 0.04,
                child: dialogChild,
              ),
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _LightToPanelPainter(
                progress: _controller.value,
                color: widget.palette.primary,
                intensity: widget.intensity.clamp(0.0, 1.0),
              ),
            ),
            Center(
              child: Opacity(
                opacity: panelOpacity,
                child: Transform.scale(
                  scale: 0.64 + panelProgress * 0.36,
                  child: Transform.translate(
                    offset: Offset(0, (1 - panelProgress) * 24),
                    child: dialogChild,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LightToPanelPainter extends CustomPainter {
  const _LightToPanelPainter({
    required this.progress,
    required this.color,
    required this.intensity,
  });

  final double progress;
  final Color color;
  final double intensity;

  double phase(double start, double end) {
    return ((progress - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.50);
    final gather = Curves.easeOutCubic.transform(phase(0.00, 0.32));
    final connect = Curves.easeInOutCubic.transform(phase(0.24, 0.50));
    final circle = Curves.easeOutCubic.transform(phase(0.42, 0.64));
    final morph = Curves.easeInOutCubic.transform(phase(0.60, 0.82));
    final fade = phase(0.82, 1.00);
    final radius = math.min(size.width, size.height) * 0.18;
    final nodeCount = 14 + (intensity * 6).round();
    final nodes = <Offset>[];

    final ambientGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.12 * (1 - fade)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 2.1));
    canvas.drawCircle(center, radius * 2.1, ambientGlow);

    for (var i = 0; i < nodeCount; i++) {
      final baseAngle = math.pi * 2 * i / nodeCount;
      final orbitAngle = baseAngle + gather * math.pi * 2.6;
      final startRadius = radius * (1.55 + (i % 3) * 0.16);
      final nodeRadius = startRadius + (radius - startRadius) * gather;
      final point = Offset(
        center.dx + math.cos(orbitAngle) * nodeRadius,
        center.dy + math.sin(orbitAngle) * nodeRadius,
      );
      nodes.add(point);
    }

    final connectionPaint = Paint()
      ..color = color.withValues(alpha: 0.52 * connect * (1 - morph))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35;
    if (connect > 0) {
      final path = Path()..moveTo(nodes.first.dx, nodes.first.dy);
      for (final point in nodes.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, connectionPaint);
    }

    for (var i = 0; i < nodes.length; i++) {
      final pulse = math.sin(progress * math.pi * 7 + i * 0.7) * 0.5 + 0.5;
      final glowPaint = Paint()
        ..color = color.withValues(alpha: (0.25 + pulse * 0.35) * (1 - morph))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      final corePaint = Paint()
        ..color = Color.lerp(
          color,
          Colors.white,
          pulse * 0.45,
        )!.withValues(alpha: 1 - morph);
      canvas.drawCircle(nodes[i], 5 + pulse * 3, glowPaint);
      canvas.drawCircle(nodes[i], 1.9 + pulse, corePaint);
    }

    if (circle > 0) {
      final circlePaint = Paint()
        ..color = color.withValues(alpha: 0.82 * circle * (1 - morph))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4;
      canvas.drawCircle(center, radius, circlePaint);
    }

    if (morph > 0) {
      final panelWidth = size.width * (0.18 + morph * 0.36);
      final panelHeight = size.height * (0.10 + morph * 0.22);
      final frame = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: panelWidth, height: panelHeight),
        Radius.circular(58 * (1 - morph) + 26 * morph),
      );
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.10 * morph * (1 - fade));
      final framePaint = Paint()
        ..color = color.withValues(alpha: 0.78 * morph * (1 - fade))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2;
      canvas.drawRRect(frame, fillPaint);
      canvas.drawRRect(frame, framePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LightToPanelPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.intensity != intensity;
  }
}
