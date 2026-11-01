import 'settings_store.dart';

class MotionPreferences {
  MotionPreferences._();

  static final SettingsStore _settings = SettingsStore.instance;

  static bool get enabled =>
      _settings.motionEnabled && !_settings.reducedMotion;

  static double get intensity => _settings.animationIntensity.clamp(0.0, 1.0);

  static Duration duration(int milliseconds) {
    if (!enabled) return Duration.zero;
    // Intensity is mainly visual strength, not a wildly different speed.
    final factor = 0.72 + intensity * 0.42;
    return Duration(milliseconds: (milliseconds * factor).round());
  }

  static Duration controllerDuration(int milliseconds) {
    if (!enabled) return const Duration(milliseconds: 1);
    final factor = 0.82 + intensity * 0.36;
    return Duration(milliseconds: (milliseconds * factor).round());
  }
}
