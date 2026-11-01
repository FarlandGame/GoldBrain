import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/screens/auth_screen.dart';
import 'package:goldbrain/screens/neural_splash_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _landscapePhoneSizes = <Size>[Size(800, 360), Size(915, 412)];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{
      'settings.motion_enabled': false,
      'settings.reduced_motion': true,
      'settings.sound_enabled': false,
      'settings.music_enabled': false,
    });
    await SettingsStore.instance.load();
  });

  for (final size in _landscapePhoneSizes) {
    testWidgets('splash fits a ${size.width}x${size.height} phone', (
      tester,
    ) async {
      _setViewport(tester, size);

      await tester.pumpWidget(const MaterialApp(home: NeuralSplashScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('GOLDBRAIN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selection remains scrollable at ${size.width}x${size.height}', (
      tester,
    ) async {
      _setViewport(tester, size);

      await tester.pumpWidget(const MaterialApp(home: SelectionScreen()));
      await tester.pump(const Duration(seconds: 2));

      final enterButton = find.text('ENTER GOLDBRAIN');
      expect(enterButton, findsOneWidget);
      await tester.scrollUntilVisible(
        enterButton,
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(enterButton.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('authentication remains usable at ${size.width}x${size.height}', (
      tester,
    ) async {
      _setViewport(tester, size);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const AuthScreen(
              selectedTheme: GoldBrainTheme.gold,
              selectedLanguage: GoldBrainLanguage.english,
            ),
          ),
        ),
      );
      await tester.pump();

      final guestButton = find.text('Continue as guest (local only)');
      expect(guestButton, findsOneWidget);
      await tester.scrollUntilVisible(
        guestButton,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(guestButton.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
