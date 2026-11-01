import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/internet_connection_service.dart';
import 'package:goldbrain/core/live_market_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reuses only a fresh shared market batch', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      final category = request.url.queryParameters['category'];
      final items = switch (category) {
        'currencies' => [_item('USD', 185400, 'تومان')],
        'gold' => [
          _item('XAU18', 18809300, 'تومان / گرم'),
          _item('XAUUSD', 4361.2, 'دلار'),
          _item('XAGUSD', 65.19, 'دلار'),
        ],
        'crypto' => [
          _item('BTC', 63878, 'USDT'),
          _item('ETH', 1871.76, 'USDT'),
        ],
        _ => const <Map<String, Object>>[],
      };
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {'items': items},
        }),
        200,
      );
    });
    final service = GlobalPriceService(
      client: client,
      navasanApiKey: '',
      cacheDuration: Duration.zero,
    );
    final store = LiveMarketStore(
      service: service,
      refreshAfter: const Duration(days: 1),
      symbols: const {'BTC', 'ETH'},
    );

    final first = await store.load();
    final second = await store.load();

    expect(first.quotes, hasLength(2), reason: first.errors.toString());
    expect(second, same(first));
    expect(requests, 1);
    expect(store.loadedAt, isNotNull);
    store.dispose();
  });

  testWidgets('auto refresh bypasses caches and stops with its UI owner', (
    tester,
  ) async {
    final priceService = _CountingPriceService();
    final internetService = InternetConnectionService(
      client: MockClient((_) async => http.Response('{"ok":true}', 200)),
      probeUris: [Uri.parse('https://probe.example/status')],
    );
    final store = LiveMarketStore(
      service: priceService,
      internetService: internetService,
      autoRefreshInterval: const Duration(milliseconds: 20),
      offlineRetryInterval: const Duration(milliseconds: 10),
      symbols: const {'BTC'},
    );

    store.startAutoRefresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();
    store.stopAutoRefresh();
    final stoppedAt = priceService.requests;
    await tester.pump(const Duration(milliseconds: 60));

    expect(stoppedAt, greaterThanOrEqualTo(2));
    expect(priceService.requests, stoppedAt);
    expect(priceService.forceRefreshValues, everyElement(isTrue));
    expect(store.connectionStatus, InternetConnectionStatus.online);
    store.dispose();
  });
}

class _CountingPriceService extends GlobalPriceService {
  int requests = 0;
  final List<bool> forceRefreshValues = [];

  @override
  Future<GlobalPriceBatch> fetchQuotes(
    Iterable<String> symbols, {
    bool forceRefresh = false,
  }) async {
    requests++;
    forceRefreshValues.add(forceRefresh);
    final now = DateTime.now();
    return GlobalPriceBatch(
      requestedSymbols: symbols.toSet(),
      quotes: {
        'BTC': GlobalPriceQuote(
          symbol: 'BTC',
          name: 'Bitcoin',
          currency: 'USDT',
          price: 62000 + requests.toDouble(),
          updatedAt: now,
          provider: GlobalPriceProvider.zarix,
        ),
      },
      errors: const {},
    );
  }
}

Map<String, Object> _item(String symbol, num price, String unit) {
  return {
    'symbol': symbol,
    'title': symbol,
    'price': price,
    'changePercent': 0.1,
    'unit': unit,
    'updatedAt': '2026-08-10T17:25:47Z',
    'source': 'test-source',
  };
}
