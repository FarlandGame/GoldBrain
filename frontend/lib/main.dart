import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_sound_service.dart';
import 'core/backend_connection.dart';
import 'core/currency_rate_store.dart';
import 'core/error_reporter.dart';
import 'core/notification_service.dart';
import 'core/notification_automation_service.dart';
import 'core/settings_store.dart';
import 'core/windows_app_data_migrator.dart';
import 'screens/neural_splash_screen.dart';
import 'screens/selection_screen.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
      await WindowsAppDataMigrator.migrateForCurrentProcess();
      await SettingsStore.instance.load();
      await CurrencyRateStore.instance.loadCached();
      unawaited(CurrencyRateStore.instance.refresh());
      await BackendConnection.instance.restore();
      await NotificationService.instance.load();
      await NotificationAutomationService.instance.start();
      ErrorReporter.instance.install();
      runApp(const GoldBrainApp());
    },
    (error, stack) {
      ErrorReporter.instance.report(error, stack, source: 'Asynchronous zone');
    },
  );
}

class GoldBrainApp extends StatefulWidget {
  const GoldBrainApp({super.key});

  @override
  State<GoldBrainApp> createState() => _GoldBrainAppState();
}

class _GoldBrainAppState extends State<GoldBrainApp>
    with WidgetsBindingObserver {
  bool _audioSuspended = false;
  bool _audioDisposed = false;
  late GoldBrainTheme _activeTheme;

  @override
  void initState() {
    super.initState();
    _activeTheme = _themeFromSettings();
    SettingsStore.instance.addListener(_handleSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsStore.instance.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  GoldBrainTheme _themeFromSettings() {
    return GoldBrainTheme.values.firstWhere(
      (theme) => theme.name == SettingsStore.instance.themeCode,
      orElse: () => GoldBrainTheme.gold,
    );
  }

  void _handleSettingsChanged() {
    final nextTheme = _themeFromSettings();
    if (mounted && nextTheme != _activeTheme) {
      setState(() => _activeTheme = nextTheme);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_audioSuspended && !_audioDisposed) {
          _audioSuspended = false;
          unawaited(AppSoundService.instance.resumeFromLifecycle());
        }
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!_audioSuspended && !_audioDisposed) {
          _audioSuspended = true;
          unawaited(AppSoundService.instance.suspendForLifecycle());
        }
        break;
      case AppLifecycleState.detached:
        if (!_audioDisposed) {
          _audioDisposed = true;
          unawaited(AppSoundService.instance.dispose());
        }
        break;
      case AppLifecycleState.inactive:
        // Losing focus briefly should not restart a desktop music process.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = themePalettes[_activeTheme]!;
    final colorScheme = palette.isLight
        ? ColorScheme.light(
            primary: palette.primary,
            secondary: palette.secondary,
            surface: palette.surface,
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: palette.text,
            outline: palette.primary.withValues(alpha: .38),
          )
        : ColorScheme.dark(
            primary: palette.primary,
            secondary: palette.secondary,
            surface: palette.surface,
            onPrimary: Colors.black,
            onSecondary: Colors.black,
            onSurface: palette.text,
            outline: palette.primary.withValues(alpha: .38),
          );
    return MaterialApp(
      title: 'GoldBrain',
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: const Duration(milliseconds: 260),
      theme: ThemeData(
        brightness: palette.isLight ? Brightness.light : Brightness.dark,
        scaffoldBackgroundColor: palette.background,
        canvasColor: palette.surface,
        colorScheme: colorScheme,
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: palette.primary,
          selectionColor: palette.primary.withValues(alpha: .28),
          selectionHandleColor: palette.primary,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: palette.primary,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: palette.primary,
          thumbColor: palette.primary,
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const NeuralSplashScreen(),
    );
  }
}
