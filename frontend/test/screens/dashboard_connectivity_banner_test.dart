import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/internet_connection_service.dart';
import 'package:goldbrain/core/live_market_store.dart';
import 'package:goldbrain/screens/dashboard_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the Persian offline warning and recovers after retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.language_code': 'persian',
      'settings.sound_enabled': false,
      'settings.interface_sounds_enabled': false,
      'settings.music_enabled': false,
      'settings.motion_enabled': false,
      'settings.reduced_motion': true,
    });
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var online = false;
    final priceService = _SwitchablePriceService(() => online);
    final internetService = InternetConnectionService(
      client: MockClient(
        (_) async => online
            ? http.Response('{"ok":true}', 200)
            : http.Response('{}', 503),
      ),
      probeUris: [Uri.parse('https://probe.example/status')],
    );
    final store = LiveMarketStore(
      service: priceService,
      internetService: internetService,
      autoRefreshInterval: const Duration(hours: 1),
      offlineRetryInterval: const Duration(hours: 1),
      symbols: const {'BTC'},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          selectedTheme: GoldBrainTheme.blue,
          selectedLanguage: GoldBrainLanguage.persian,
          marketStore: store,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.text('اتصال اینترنت برقرار نیست؛ برنامه بدون اینترنت کار نمی‌کند.'),
      findsOneWidget,
    );

    online = true;
    await tester.tap(find.text('تلاش دوباره'));
    await store.retryNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      find.text('اتصال اینترنت برقرار نیست؛ برنامه بدون اینترنت کار نمی‌کند.'),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}

class _SwitchablePriceService extends GlobalPriceService {
  _SwitchablePriceService(this.isOnline);

  final bool Function() isOnline;

  @override
  Future<GlobalPriceBatch> fetchQuotes(
    Iterable<String> symbols, {
    bool forceRefresh = false,
  }) async {
    if (!isOnline()) {
      return GlobalPriceBatch(
        requestedSymbols: symbols.toSet(),
        quotes: const {},
        errors: const {'BTC': 'offline'},
      );
    }
    return GlobalPriceBatch(
      requestedSymbols: symbols.toSet(),
      quotes: {
        'BTC': GlobalPriceQuote(
          symbol: 'BTC',
          name: 'Bitcoin',
          currency: 'USDT',
          price: 62000,
          updatedAt: DateTime.now(),
          provider: GlobalPriceProvider.zarix,
        ),
      },
      errors: const {},
    );
  }
}
