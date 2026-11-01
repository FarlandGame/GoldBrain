import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/currency_rate_store.dart';
import 'package:goldbrain/core/currency_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loads sourced USD rates and reuses the persisted snapshot', () async {
    final rates = <String, num>{
      'USD': 1,
      'EUR': 0.91,
      'GBP': 0.78,
      'JPY': 151,
      'RUB': 91,
      'CNY': 7.2,
      'AED': 3.6725,
      'TRY': 40,
      'CAD': 1.36,
      'AUD': 1.51,
      'CHF': 0.88,
      'INR': 86,
      'SAR': 3.75,
    };
    final store = CurrencyRateStore(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'base': 'USD', 'rates': rates}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    addTearDown(store.dispose);

    expect(await store.refresh(force: true), isTrue);
    expect(CurrencyService.unitsPerUsdFor('JPY'), 151);
    expect(CurrencyService.unitsPerUsdFor('SAR'), 3.75);

    CurrencyService.updateInternationalRates(const {'JPY': 100});
    final cachedStore = CurrencyRateStore(
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    addTearDown(cachedStore.dispose);
    await cachedStore.loadCached();

    expect(CurrencyService.unitsPerUsdFor('JPY'), 151);
    expect(cachedStore.fetchedAt, isNotNull);
  });

  test(
    'rejects incomplete provider data instead of corrupting rates',
    () async {
      CurrencyService.updateInternationalRates(const {'JPY': 149});
      final store = CurrencyRateStore(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'base': 'USD',
              'rates': {'USD': 1, 'JPY': 999},
            }),
            200,
          ),
        ),
      );
      addTearDown(store.dispose);

      expect(await store.refresh(force: true), isFalse);
      expect(CurrencyService.unitsPerUsdFor('JPY'), 149);
      expect(store.lastError, isNotNull);
    },
  );
}
