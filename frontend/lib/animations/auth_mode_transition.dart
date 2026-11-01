import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum AuthTransitionType { bullet, pencil }

class AuthModeTransition extends StatefulWidget {
  const AuthModeTransition({
    super.key,
    required this.type,
    required this.accentColor,
    required this.snapshot,
    required this.snapshotRect,
    required this.onMidpoint,
    required this.onCompleted,
  });

  final AuthTransitionType type;
  final Color accentColor;
  final ui.Image snapshot;
  final Rect snapshotRect;
  final VoidCallback onMidpoint;
  final VoidCallback onCompleted;

  @override
  State<AuthModeTransition> createState() => _AuthModeTransitionState();
}

class _AuthModeTransitionState extends State<AuthModeTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Shard> _shards;
  bool _midpointCalled = false;

  @override
  void initState() {
    super.initState();

    _shards = _buildShards(widget.snapshotRect.size);

    _controller =
        AnimationController(
            vsync: this,
            duration: Duration(
              milliseconds: widget.type == AuthTransitionType.bullet
                  ? 3200
                  : 3500,
            ),
          )
          ..addListener(_checkMidpoint)
          ..forward().whenComplete(() {
            if (mounted) widget.onCompleted();
          });
  }

  void _checkMidpoint() {
    final midpoint = widget.type == AuthTransitionType.bullet ? 0.64 : 0.61;

    if (!_midpointCalled && _controller.value >= midpoint) {
      _midpointCalled = true;
      widget.onMidpoint();
    }
  }

  List<_Shard> _buildShards(Size size) {
    final random = math.Random(7301);
    const columns = 9;
    const rows = 6;

    final cellW = size.width / columns;
    final cellH = size.height / rows;
    final shards = <_Shard>[];

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final left = col * cellW;
        final top = row * cellH;
        final rect = Rect.fromLTWH(left, top, cellW, cellH);

        final diagonalForward = random.nextBool();
        final delay = random.nextDouble() * 0.18;
        final drift = (random.nextDouble() - 0.5) * 220;
        final rotation = (random.nextDouble() - 0.5) * 2.8;
        final depth = 0.78 + random.nextDouble() * 0.42;

        shards.add(
          _Shard(
            rect: rect,
            triangleIndex: 0,
            diagonalForward: diagonalForward,
            delay: delay,
            drift: drift,
            rotation: rotation,
            depth: depth,
          ),
        );

        shards.add(
          _Shard(
            rect: rect,
            triangleIndex: 1,
            diagonalForward: diagonalForward,
            delay: math.min(0.24, delay + random.nextDouble() * 0.05),
            drift: drift + (random.nextDouble() - 0.5) * 90,
            rotation: -rotation * 0.85,
            depth: depth,
          ),
        );
      }
    }

    return shards;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_checkMidpoint)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size.infinite,
            painter: _CinematicAuthPainter(
              progress: _controller.value,
              type: widget.type,
              accentColor: widget.accentColor,
              snapshot: widget.snapshot,
              snapshotRect: widget.snapshotRect,
              shards: _shards,
            ),
          );
        },
      ),
    );
  }
}

class _Shard {
  const _Shard({
    required this.rect,
    required this.triangleIndex,
    required this.diagonalForward,
    required this.delay,
    required this.drift,
    required this.rotation,
    required this.depth,
  });

  final Rect rect;
  final int triangleIndex;
  final bool diagonalForward;
  final double delay;
  final double drift;
  final double rotation;
  final double depth;

  Path clipPath() {
    final path = Path();

    if (diagonalForward) {
      if (triangleIndex == 0) {
        path
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.right, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..close();
      } else {
        path
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
      }
    } else {
      if (triangleIndex == 0) {
        path
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.right, rect.top)
          ..lineTo(rect.left, rect.bottom)
          ..close();
      } else {
        path
          ..moveTo(rect.right, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close();
      }
    }

    return path;
  }
}

class _CinematicAuthPainter extends CustomPainter {
  const _CinematicAuthPainter({
    required this.progress,
    required this.type,
    required this.accentColor,
    required this.snapshot,
    required this.snapshotRect,
    required this.shards,
  });

  final double progress;
  final AuthTransitionType type;
  final Color accentColor;
  final ui.Image snapshot;
  final Rect snapshotRect;
  final List<_Shard> shards;

  double phase(double start, double end) {
    return ((progress - start) / (end - start)).clamp(0.0, 1.0);
  }

  double pulse(double t) => math.sin(t * math.pi).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    if (type == AuthTransitionType.bullet) {
      _paintBulletSequence(canvas, size);
    } else {
      _paintPencilSequence(canvas, size);
    }
  }

  void _paintBulletSequence(Canvas canvas, Size size) {
    final flash = pulse(phase(0.00, 0.075));
    final crack = Curves.easeOutExpo.transform(phase(0.025, 0.22));
    final shatter = Curves.easeInCubic.transform(phase(0.15, 0.48));
    final launcher = Curves.easeOutBack.transform(phase(0.30, 0.43));
    final bullet = Curves.easeInQuart.transform(phase(0.40, 0.68));
    final zoom = Curves.easeInOutCubic.transform(phase(0.52, 0.70));
    final reveal = Curves.easeOutExpo.transform(phase(0.62, 0.91));
    final fade = Curves.easeInCubic.transform(phase(0.90, 1.0));

    _drawRedFlash(canvas, size, flash * (1 - fade));
    _drawSnapshotShatter(canvas, crack, shatter, 1 - fade);
    _drawCracks(canvas, crack, 1 - fade);
    _drawLauncher(canvas, size, launcher, 1 - fade);
    _drawBullet(canvas, size, bullet, zoom, reveal, 1 - fade);
  }

  void _paintPencilSequence(Canvas canvas, Size size) {
    final flash = pulse(phase(0.00, 0.075));
    final crack = Curves.easeOutExpo.transform(phase(0.025, 0.21));
    final shatter = Curves.easeInCubic.transform(phase(0.14, 0.45));
    final pencilEntry = Curves.easeOutBack.transform(phase(0.38, 0.52));
    final draw = Curves.easeInOutCubic.transform(phase(0.49, 0.84));
    final build = Curves.easeOutCubic.transform(phase(0.61, 0.93));
    final fade = Curves.easeInCubic.transform(phase(0.92, 1.0));

    _drawRedFlash(canvas, size, flash * (1 - fade));
    _drawSnapshotShatter(canvas, crack, shatter, 1 - fade);
    _drawCracks(canvas, crack, 1 - fade);
    _drawPencilConstruction(canvas, size, pencilEntry, draw, build, 1 - fade);
  }

  void _drawRedFlash(Canvas canvas, Size size, double opacity) {
    if (opacity <= 0) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.92,
          colors: [
            const Color(0xFFFF3048).withValues(alpha: 0.76 * opacity),
            const Color(0xFF8F001B).withValues(alpha: 0.42 * opacity),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
  }

  void _drawSnapshotShatter(
    Canvas canvas,
    double crack,
    double fall,
    double opacity,
  ) {
    if (crack <= 0) return;

    final src = Rect.fromLTWH(
      0,
      0,
      snapshot.width.toDouble(),
      snapshot.height.toDouble(),
    );

    if (fall <= 0.001) {
      canvas.drawImageRect(
        snapshot,
        src,
        snapshotRect,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      return;
    }

    for (final shard in shards) {
      final local = ((fall - shard.delay) / (1 - shard.delay)).clamp(0.0, 1.0);
      final eased = Curves.easeInCubic.transform(local);

      final center = shard.rect.center;
      final drop = eased * eased * 680 * shard.depth;
      final drift = shard.drift * eased;
      final rotation = shard.rotation * eased;
      final scale = 1 - eased * 0.10;

      canvas.save();
      canvas.translate(snapshotRect.left, snapshotRect.top);
      canvas.translate(center.dx + drift, center.dy + drop);
      canvas.rotate(rotation);
      canvas.scale(scale);
      canvas.translate(-center.dx, -center.dy);

      final clip = shard.clipPath();
      canvas.clipPath(clip);

      final shardSrc = Rect.fromLTWH(
        shard.rect.left / snapshotRect.width * snapshot.width,
        shard.rect.top / snapshotRect.height * snapshot.height,
        shard.rect.width / snapshotRect.width * snapshot.width,
        shard.rect.height / snapshotRect.height * snapshot.height,
      );

      canvas.drawImageRect(
        snapshot,
        shardSrc,
        shard.rect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withValues(
            alpha: opacity * (1 - eased * 0.22),
          ),
      );

      canvas.drawPath(
        clip,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = Colors.white.withValues(alpha: 0.48 * opacity),
      );

      canvas.restore();
    }
  }

  void _drawCracks(Canvas canvas, double crack, double opacity) {
    if (crack <= 0 || crack >= 0.98) return;

    final center = snapshotRect.center;
    final random = math.Random(77);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = accentColor.withValues(alpha: 0.23 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.88 * opacity);

    for (var i = 0; i < 30; i++) {
      final angle = i * math.pi * 2 / 30 + (random.nextDouble() - 0.5) * 0.12;
      final length = (110 + random.nextDouble() * 420) * crack;
      final segments = 4 + random.nextInt(4);
      final path = Path()..moveTo(center.dx, center.dy);

      for (var j = 1; j <= segments; j++) {
        final t = j / segments;
        final p = Offset(
          center.dx + math.cos(angle) * length * t,
          center.dy + math.sin(angle) * length * t,
        );
        path.lineTo(
          p.dx + (random.nextDouble() - 0.5) * 17,
          p.dy + (random.nextDouble() - 0.5) * 17,
        );
      }

      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
    }
  }

  void _drawLauncher(Canvas canvas, Size size, double entry, double opacity) {
    if (entry <= 0) return;

    final x = -245 + 215 * entry;
    final y = size.height * 0.53;

    canvas.save();
    canvas.translate(x, y);

    final glow = Paint()
      ..color = accentColor.withValues(alpha: 0.34 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);

    final bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, -44, 255, 88),
      const Radius.circular(25),
    );

    canvas.drawRRect(bodyRect.inflate(12), glow);
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF080B11),
            const Color(0xFF202A39),
            accentColor.withValues(alpha: 0.72),
          ],
        ).createShader(const Rect.fromLTWH(0, -44, 255, 88)),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(115, -19, 185, 38),
        const Radius.circular(12),
      ),
      Paint()..color = const Color(0xFF07090E),
    );

    canvas.drawCircle(
      const Offset(300, 0),
      23,
      Paint()
        ..color = accentColor.withValues(alpha: 0.82 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    canvas.drawCircle(
      const Offset(300, 0),
      9,
      Paint()..color = Colors.white.withValues(alpha: 0.95 * opacity),
    );

    canvas.restore();
  }

  void _drawBullet(
    Canvas canvas,
    Size size,
    double travel,
    double zoom,
    double reveal,
    double opacity,
  ) {
    if (travel <= 0) return;

    final rawX = -20 + (size.width + 90) * travel;
    final rawY = size.height * 0.53;

    final center = Offset(
      ui.lerpDouble(rawX, size.width * 0.53, zoom * 0.88)!,
      ui.lerpDouble(rawY, size.height * 0.50, zoom * 0.88)!,
    );

    final scale = 1 + zoom * 4.7;

    if (reveal > 0) {
      final wipeWidth = size.width * reveal;
      final rect = Rect.fromLTWH(0, 0, wipeWidth, size.height);

      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              accentColor.withValues(alpha: 0.92 * opacity),
              accentColor.withValues(alpha: 0.56 * opacity),
              Colors.white.withValues(alpha: 0.22 * opacity),
              Colors.transparent,
            ],
            stops: const [0.0, 0.52, 0.84, 1.0],
          ).createShader(rect),
      );
    }

    final trail = Rect.fromLTWH(
      center.dx - 320 * scale,
      center.dy - 24 * scale,
      320 * scale,
      48 * scale,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(trail, Radius.circular(28 * scale)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            accentColor.withValues(alpha: 0.10 * opacity),
            accentColor.withValues(alpha: 0.72 * opacity),
            Colors.white.withValues(alpha: 0.95 * opacity),
          ],
        ).createShader(trail)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    final bulletRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-28, -8, 56, 16),
      const Radius.circular(8),
    );

    canvas.drawRRect(
      bulletRect.inflate(9),
      Paint()
        ..color = accentColor.withValues(alpha: 0.55 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.drawRRect(
      bulletRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFF8D1), Color(0xFFFFD455), Color(0xFF8E5B00)],
        ).createShader(const Rect.fromLTWH(-28, -8, 56, 16)),
    );

    canvas.restore();

    if (zoom > 0.20) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.70 * zoom * opacity),
            ],
            stops: const [0.42, 1.0],
          ).createShader(Offset.zero & size),
      );
    }
  }

  void _drawPencilConstruction(
    Canvas canvas,
    Size size,
    double entry,
    double draw,
    double build,
    double opacity,
  ) {
    if (entry <= 0) return;

    final panel = snapshotRect;
    final route = Path()
      ..moveTo(panel.right + 130, panel.top + 35)
      ..cubicTo(
        panel.right - 60,
        panel.top - 90,
        panel.left + 120,
        panel.top + 10,
        panel.left + 65,
        panel.top + 95,
      )
      ..cubicTo(
        panel.left + 10,
        panel.top + 210,
        panel.right - 180,
        panel.bottom - 80,
        panel.right - 80,
        panel.bottom - 45,
      );

    final metric = route.computeMetrics().first;
    final length = metric.length * draw;
    final partial = metric.extractPath(0, length);

    canvas.drawPath(
      partial,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round
        ..color = accentColor.withValues(alpha: 0.38 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    canvas.drawPath(
      partial,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.88 * opacity),
    );

    final tangent = metric.getTangentForOffset(length.clamp(0, metric.length));
    final pencilPos =
        tangent?.position ?? Offset(panel.right + 160, panel.top + 40);

    _drawLuminousPencil(
      canvas,
      Offset.lerp(Offset(size.width + 210, panel.top + 40), pencilPos, entry)!,
      tangent?.angle ?? math.pi,
      opacity,
    );

    final random = math.Random(190);
    for (var i = 0; i < 54; i++) {
      final local = ((build * 1.28) - i / 72).clamp(0.0, 1.0);
      if (local <= 0) continue;

      final col = i % 3;
      final row = i ~/ 3;
      final target = Offset(
        panel.left + panel.width * (0.20 + col * 0.28),
        panel.top + 75 + (row % 13) * 33,
      );

      final start = Offset(
        panel.right + 160 + random.nextDouble() * 220,
        panel.top - 80 + random.nextDouble() * (panel.height + 160),
      );

      final p = Offset.lerp(
        start,
        target,
        Curves.easeOutBack.transform(local),
      )!;

      canvas.drawCircle(
        p,
        1.8 + (i % 4) * 0.7,
        Paint()
          ..color = (i % 5 == 0 ? Colors.white : accentColor).withValues(
            alpha: 0.85 * opacity,
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    final guideRects = <Rect>[
      Rect.fromLTWH(
        panel.left + panel.width * 0.08,
        panel.top + panel.height * 0.16,
        panel.width * 0.35,
        4,
      ),
      Rect.fromLTWH(
        panel.left + panel.width * 0.08,
        panel.top + panel.height * 0.30,
        panel.width * 0.35,
        4,
      ),
      Rect.fromLTWH(
        panel.left + panel.width * 0.08,
        panel.top + panel.height * 0.47,
        panel.width * 0.35,
        4,
      ),
      Rect.fromLTWH(
        panel.left + panel.width * 0.08,
        panel.top + panel.height * 0.61,
        panel.width * 0.35,
        4,
      ),
      Rect.fromLTWH(
        panel.left + panel.width * 0.08,
        panel.top + panel.height * 0.76,
        panel.width * 0.35,
        4,
      ),
    ];

    for (var i = 0; i < guideRects.length; i++) {
      final local = ((build - 0.20 - i * 0.08) / 0.52).clamp(0.0, 1.0);
      if (local <= 0) continue;

      final rect = guideRects[i];

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top, rect.width * local, rect.height),
          const Radius.circular(3),
        ),
        Paint()
          ..color = accentColor.withValues(alpha: 0.78 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  void _drawLuminousPencil(
    Canvas canvas,
    Offset position,
    double angle,
    double opacity,
  ) {
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(angle);

    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-112, -12, 145, 24),
      const Radius.circular(7),
    );

    canvas.drawRRect(
      body.inflate(12),
      Paint()
        ..color = accentColor.withValues(alpha: 0.48 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );

    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [accentColor, Colors.white, accentColor],
        ).createShader(const Rect.fromLTWH(-112, -12, 145, 24)),
    );

    final tip = Path()
      ..moveTo(33, -12)
      ..lineTo(71, 0)
      ..lineTo(33, 12)
      ..close();

    canvas.drawPath(
      tip,
      Paint()..color = const Color(0xFFFFE9B7).withValues(alpha: opacity),
    );

    canvas.drawPath(
      Path()
        ..moveTo(63, -3)
        ..lineTo(80, 0)
        ..lineTo(63, 3)
        ..close(),
      Paint()..color = Colors.black.withValues(alpha: 0.90 * opacity),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CinematicAuthPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.type != type ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.snapshot != snapshot ||
        oldDelegate.snapshotRect != snapshotRect;
  }
}
