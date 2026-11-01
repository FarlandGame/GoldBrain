import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/screens/ai_assistant_screen.dart';
import 'package:goldbrain/screens/dashboard_screen.dart';
import 'package:goldbrain/screens/markets_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.sound_enabled': false,
      'settings.interface_sounds_enabled': false,
      'settings.music_enabled': false,
      'settings.motion_enabled': false,
      'settings.reduced_motion': true,
      'settings.density': 'compact',
      'settings.language': 'persian',
      'settings.startup_page': 'dashboard',
    });
  });

  Future<void> pumpLandscapeDashboard(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: DashboardScreen(
          selectedTheme: GoldBrainTheme.gold,
          selectedLanguage: GoldBrainLanguage.persian,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('800x360 phone landscape uses the compact usable shell', (
    tester,
  ) async {
    await pumpLandscapeDashboard(tester, const Size(800, 360));

    expect(
      find.byKey(const ValueKey('mobile-landscape-sidebar-brand')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-landscape-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-landscape-market-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-landscape-dashboard-content')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('sidebar-item-1')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(MarketsScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-landscape-market-strip')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('sidebar-item-3')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(AiAssistantScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('915x412 phone landscape has no RenderFlex exception', (
    tester,
  ) async {
    await pumpLandscapeDashboard(tester, const Size(915, 412));

    expect(
      find.byKey(const ValueKey('mobile-landscape-header')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Android activity supports both landscape directions', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    // The repository currently ships the Windows target only. Keep this
    // regression check active for Android checkouts without making the
    // Windows test suite fail when that optional target is absent.
    if (!manifest.existsSync()) return;
    final contents = manifest.readAsStringSync();
    expect(contents, contains('android:screenOrientation="sensorLandscape"'));
  });
}
