import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/backend_api_client.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/currency_service.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const requestedWallexAssets = {
  'DOT',
  'PAXG',
  'NOT',
  'AVAX',
  'TON',
  'PEPE',
  'ARB',
};

void main() {
  test(
    'requested assets are discoverable with native USDT units and history',
    () {
      expect(
        GlobalPriceService.supportedSymbols,
        containsAll(requestedWallexAssets),
      );
      final catalog = {
        for (final asset in GlobalPriceService.fallbackAssetCatalog)
          asset.symbol: asset,
      };
      for (final symbol in requestedWallexAssets) {
        expect(catalog[symbol]?.quoteCurrency, 'USDT');
        expect(catalog[symbol]?.forecast, isFalse);
        expect(MarketHistoryService.supportedSymbols, contains(symbol));
      }
      expect(catalog['PAXG']?.assetClass, 'crypto');
      expect(catalog['XAU']?.assetClass, 'metal');
    },
  );

  test(
    'Backend prices preserve tiny tokens and keep PAXG separate from XAU',
    () async {
      final now = DateTime.now().toUtc().toIso8601String();
      final prices = {
        'DOT': 1.128,
        'PAXG': 4102.0,
        'NOT': 0.000396,
        'AVAX': 9.92,
        'PEPE': 0.0000039,
        'ARB': 0.1849,
      };
      final api = _api((request) async {
        expect(request.url.path, '/api/v1/market/quotes');
        expect(request.headers['authorization'], 'Bearer asset-test');
        return http.Response(
          jsonEncode({
            'requested_symbols': [...prices.keys, 'TON'],
            'quotes': [
              for (final entry in prices.entries)
                {
                  'symbol': entry.key,
                  'name': entry.key,
                  'price': entry.value,
                  'currency': 'USDT',
                  'unit': 'coin',
                  'provider': 'wallex',
                  'updated_at': now,
                  'received_at': now,
                  'provider_timestamp': null,
                  'freshness_status': 'DELAYED',
                  'data_quality_status': 'VALID',
                },
            ],
            'issues': [
              {'symbol': 'TON', 'message': 'No valid Wallex price.'},
            ],
            'partial': true,
          }),
          200,
        );
      });
      final service = GlobalPriceService(backend: api);
      final batch = await service.fetchQuotes(requestedWallexAssets);
      for (final entry in prices.entries) {
        expect(batch.quotes[entry.key]?.price, entry.value);
        expect(batch.quotes[entry.key]?.currency, 'USDT');
        expect(batch.quotes[entry.key]?.freshnessStatus, 'DELAYED');
      }
      expect(batch.quotes['PAXG']?.unit, 'coin');
      expect(batch.quotes.containsKey('XAU'), isFalse);
      expect(batch.quotes.containsKey('TON'), isFalse);
      expect(batch.errors['TON'], isNotEmpty);
      service.close();
      api.close();
    },
  );

  test(
    'Backend catalog includes the screenshot assets without enabling prediction',
    () async {
      final api = _api((request) async {
        expect(request.url.path, '/api/v1/market/assets');
        return http.Response(
          jsonEncode({
            'assets': [
              for (final symbol in requestedWallexAssets)
                {
                  'symbol': symbol,
                  'name': symbol,
                  'asset_class': 'crypto',
                  'quote_currency': 'USDT',
                  'live_quote': true,
                  'forecast': false,
                },
            ],
          }),
          200,
        );
      });
      final service = GlobalPriceService(backend: api);
      final catalog = await service.fetchAssetCatalog();
      expect(catalog.isFallback, isFalse);
      expect(
        catalog.assets.map((asset) => asset.symbol).toSet(),
        requestedWallexAssets,
      );
      expect(catalog.assets.every((asset) => !asset.forecast), isTrue);
      service.close();
      api.close();
    },
  );
  test('small token prices stay nonzero in USD and USDT display', () {
    for (final currency in ['USD', 'USDT']) {
      final suffix = currency == 'USD' ? r'$' : 'USDT';
      expect(
        CurrencyService.formatPrice(
          value: 0.0000039,
          sourceCode: currency,
          selectedCode: currency,
          language: GoldBrainLanguage.english,
        ),
        '0.00000390 $suffix',
      );
      expect(
        CurrencyService.formatPrice(
          value: 0.000396,
          sourceCode: currency,
          selectedCode: currency,
          language: GoldBrainLanguage.english,
        ),
        '0.000396 $suffix',
      );
      expect(
        CurrencyService.formatPrice(
          value: 0,
          sourceCode: currency,
          selectedCode: currency,
          language: GoldBrainLanguage.english,
        ),
        '0.00 $suffix',
      );
    }
  });
}

GoldBrainBackendClient _api(
  Future<http.Response> Function(http.Request) handler,
) => GoldBrainBackendClient(
  config: GoldBrainBackendConfig(
    baseUri: Uri.parse('http://127.0.0.1:8000'),
    apiKey: '',
  ),
  client: MockClient(handler),
)..setAccessToken('asset-test');
