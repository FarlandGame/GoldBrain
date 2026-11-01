import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/app_sound_service.dart';
import 'package:goldbrain/screens/dashboard_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/widgets/deep_market_analysis_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('deep analyst panel fits without RenderFlex overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.sound_enabled': false,
      'settings.interface_sounds_enabled': false,
      'settings.music_enabled': false,
      'settings.motion_enabled': false,
      'settings.reduced_motion': true,
      'settings.density': 'compact',
    });
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: DashboardScreen(
          selectedTheme: GoldBrainTheme.blue,
          selectedLanguage: GoldBrainLanguage.persian,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DeepMarketAnalysisCard), findsOneWidget);
    expect(find.byKey(const ValueKey('start-deep-analysis')), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await AppSoundService.instance.dispose();
  });
}
