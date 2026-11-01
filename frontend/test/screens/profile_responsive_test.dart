import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/screens/profile_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('profile remains usable in a narrow Windows viewport', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.motion_enabled': false,
      'settings.sound_enabled': false,
      'settings.language_code': 'english',
      'profile_name': 'Test User',
    });
    await SettingsStore.instance.load();
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ProfileScreen(
              palette: themePalettes[GoldBrainTheme.gold]!,
              selectedLanguage: GoldBrainLanguage.english,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local profile'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
    expect(find.text('user@goldbrain.app'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
