import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('currency selection applies and persists without pressing Save', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.sound_enabled': false,
      'settings.currency_code': 'auto',
      'settings.language_code': 'english',
    });
    tester.view.physicalSize = const Size(1600, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var changeCallbacks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsScreen(
              selectedTheme: GoldBrainTheme.gold,
              selectedLanguage: GoldBrainLanguage.english,
              onSettingsChanged: () => changeCallbacks++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('US Dollar').first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(SettingsStore.instance.currencyCode, 'USD');
    expect(changeCallbacks, 1);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings.currency_code'), 'USD');
  });
}
