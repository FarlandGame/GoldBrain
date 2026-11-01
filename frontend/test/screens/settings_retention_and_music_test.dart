import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('finite retention is unchanged when confirmation is cancelled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.sound_enabled': false,
      'settings.language_code': 'persian',
    });
    tester.view.physicalSize = const Size(1600, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsScreen(
              selectedTheme: GoldBrainTheme.gold,
              selectedLanguage: GoldBrainLanguage.persian,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ذخیره خودکار تغییرات محلی'), findsOneWidget);
    expect(find.text('همیشه'), findsOneWidget);

    await tester.tap(find.text('۳۰ روز'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('retention-confirmation-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retention-cancel-button')));
    await tester.pumpAndSettle();
    expect(SettingsStore.instance.dataRetention, 'forever');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings.data_retention'), 'forever');
  });

  for (final direction in TextDirection.values) {
    testWidgets(
      'playlist controls keep previous left and next right in $direction',
      (tester) async {
        var previous = 0;
        var next = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: Center(
                  child: PlaylistTransportControls(
                    previousTooltip: 'Previous track',
                    nextTooltip: 'Next track',
                    onPrevious: () => previous++,
                    onNext: () => next++,
                  ),
                ),
              ),
            ),
          ),
        );

        final previousFinder = find.byKey(
          const ValueKey('playlist-previous-button'),
        );
        final nextFinder = find.byKey(const ValueKey('playlist-next-button'));
        expect(
          tester.getCenter(previousFinder).dx,
          lessThan(tester.getCenter(nextFinder).dx),
        );
        expect(
          find.descendant(
            of: previousFinder,
            matching: find.byIcon(Icons.skip_previous_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: nextFinder,
            matching: find.byIcon(Icons.skip_next_rounded),
          ),
          findsOneWidget,
        );

        await tester.tap(previousFinder);
        await tester.tap(nextFinder);
        expect(previous, 1);
        expect(next, 1);
      },
    );
  }
}
