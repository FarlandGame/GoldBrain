import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/market_quote_persistent_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const storageKey = 'goldbrain_last_market_quotes_v1';

  test(
    'does not restore invalid domestic provenance from older caches',
    () async {
      final now = DateTime.now().toUtc().toIso8601String();
      Map<String, Object?> entry(String provider, String source) => {
        'name': 'Market price',
        'currency': 'IRT',
        'price': 100000,
        'updatedAt': now,
        'provider': provider,
        'upstreamSource': source,
      };
      SharedPreferences.setMockInitialValues({
        storageKey: jsonEncode({
          'USD': entry('zarix', 'tgju'),
          'EUR': entry('backend', 'zarix'),
          'GOLD18': entry('backend', 'persian-toolbox'),
          'XAU': {...entry('zarix', 'gold-api'), 'currency': 'USD'},
        }),
      });

      final restored = await MarketQuotePersistentCache().load({
        'USD',
        'EUR',
        'GOLD18',
        'XAU',
      });

      expect(restored.keys, ['XAU']);
      expect(restored['XAU']!.provider, GlobalPriceProvider.zarix);
      expect(restored['XAU']!.wasCached, isTrue);
    },
  );

  test('does not write invalid domestic provenance into a new cache', () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    GlobalPriceQuote quote(
      String symbol,
      GlobalPriceProvider provider,
      String source,
    ) => GlobalPriceQuote(
      symbol: symbol,
      name: symbol,
      currency: symbol == 'XAU' ? 'USD' : 'IRT',
      price: 100000,
      updatedAt: now,
      provider: provider,
      upstreamSource: source,
    );
    final cache = MarketQuotePersistentCache();
    await cache.put({
      'USD': quote('USD', GlobalPriceProvider.zarix, 'tgju'),
      'GOLD18': quote('GOLD18', GlobalPriceProvider.backend, 'persian-toolbox'),
      'XAU': quote('XAU', GlobalPriceProvider.zarix, 'gold-api'),
    });

    final restored = await cache.load({'USD', 'GOLD18', 'XAU'});
    expect(restored.keys, ['XAU']);
  });
}
