import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/screens/auth_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('authentication remains usable in a narrow Windows viewport', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.motion_enabled': false,
      'settings.reduced_motion': true,
      'settings.sound_enabled': false,
      'settings.music_enabled': false,
    });
    await SettingsStore.instance.load();
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AuthScreen(
            selectedTheme: GoldBrainTheme.gold,
            selectedLanguage: GoldBrainLanguage.english,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Continue as guest (local only)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
