import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/screens/about_us_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('about shows supplied identity, purpose, risk and roadmap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.motion_enabled': true,
      'settings.reduced_motion': true,
    });
    await SettingsStore.instance.load();
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SingleChildScrollView(
              child: AboutUsScreen(
                palette: themePalettes[GoldBrainTheme.pink]!,
                selectedLanguage: GoldBrainLanguage.persian,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('بردیا علیزاده، ملقب به کبیر'), findsOneWidget);
    expect(find.text('ارمیا علیزاده، ملقب به کبیر'), findsOneWidget);
    expect(find.textContaining('تجمیع قیمت‌های منبع‌دار'), findsOneWidget);
    expect(find.textContaining('تضمین سود ارائه نمی‌کند'), findsOneWidget);
    expect(
      find.textContaining('هنوز هیچ درگاه پرداخت داخلی پیاده‌سازی نشده است'),
      findsOneWidget,
    );
    expect(tester.binding.transientCallbackCount, 0);
  });
}
