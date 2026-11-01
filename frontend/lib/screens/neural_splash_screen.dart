import 'dart:math';

import 'package:flutter/material.dart';

import '../animations/neural_forge_painter.dart';
import '../core/app_colors.dart';
import '../core/app_sound_service.dart';
import '../core/settings_store.dart';
import 'selection_screen.dart';

class NeuralSplashScreen extends StatefulWidget {
  const NeuralSplashScreen({super.key});

  @override
  State<NeuralSplashScreen> createState() => _NeuralSplashScreenState();
}

class _NeuralSplashScreenState extends State<NeuralSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Offset> _nodes;

  @override
  void initState() {
    super.initState();

    _nodes = _generateBrainNodes();
    _playStartupSound();

    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 7600),
          )
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  transitionDuration: const Duration(milliseconds: 1000),
                  pageBuilder: (_, animation, secondaryAnimation) {
                    return const SelectionScreen();
                  },
                  transitionsBuilder:
                      (_, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 1.04,
                              end: 1,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                ),
              );
            }
          })
          ..forward();
  }

  Future<void> _playStartupSound() async {
    final settings = SettingsStore.instance;
    await settings.load();

    if (!mounted) return;

    await AppSoundService.instance.playStartup(
      enabled: settings.soundEnabled && settings.interfaceSoundsEnabled,
      volume: settings.interfaceVolume,
    );
  }

  List<Offset> _generateBrainNodes() {
    final random = Random(9876);
    final points = <Offset>[];

    while (points.length < 54) {
      final x = random.nextDouble() * 2 - 1;
      final y = random.nextDouble() * 2 - 1;

      final ellipse = (x * x) / 1.0 + (y * y) / 0.72;

      if (ellipse <= 1) {
        points.add(Offset(x * 0.5, y * 0.5));
      }
    }

    return points;
  }

  double section(double value, double start, double end) {
    return ((value - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final value = _controller.value;

          final titleProgress = Curves.easeOutCubic.transform(
            section(value, 0.55, 0.78),
          );

          final subtitleProgress = Curves.easeOut.transform(
            section(value, 0.70, 0.88),
          );

          final exitProgress = Curves.easeInCubic.transform(
            section(value, 0.90, 1),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: NeuralForgePainter(progress: value, nodes: _nodes),
              ),

              Center(
                child: Transform.scale(
                  scale: 0.82 + titleProgress * 0.18,
                  child: Opacity(
                    opacity: titleProgress * (1 - exitProgress),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            final movement = value * 2.3 - 0.8;

                            return LinearGradient(
                              begin: Alignment(-1 + movement, 0),
                              end: Alignment(1 + movement, 0),
                              colors: const [
                                AppColors.deepGold,
                                AppColors.brightGold,
                                Colors.white,
                                AppColors.gold,
                                AppColors.deepGold,
                              ],
                              stops: const [0, 0.32, 0.50, 0.68, 1],
                            ).createShader(bounds);
                          },
                          child: const Text(
                            'GOLDBRAIN',
                            style: TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 10,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        Opacity(
                          opacity: subtitleProgress,
                          child: Transform.translate(
                            offset: Offset(0, 15 * (1 - subtitleProgress)),
                            child: const Text(
                              'CREATED BY BARDIA & ARMIYA ALIZADEH (KABIR)',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 15,
                                letterSpacing: 2.2,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        Opacity(
                          opacity: subtitleProgress,
                          child: const Text(
                            'NEURAL MARKET INTELLIGENCE',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 11,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 32,
                right: 32,
                bottom: 28,
                child: Opacity(
                  opacity: section(value, 0.08, 0.32) * (1 - exitProgress),
                  child: Row(
                    children: [
                      const Text(
                        'INITIALIZING NEURAL FORGE',
                        style: TextStyle(
                          color: AppColors.mutedText,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 2,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.gold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${(value * 100).round().toString().padLeft(2, '0')}%',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
