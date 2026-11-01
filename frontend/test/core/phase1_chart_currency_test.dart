import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/backend_api_client.dart';
import 'package:goldbrain/core/backend_types.dart';
import 'package:goldbrain/core/currency_service.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('one sourced rate converts every chart price and preserves source', () {
    CurrencyService.updateIranianTomanPerUsd(
      200000,
      observedAt: DateTime.now(),
    );
    final series = MarketHistorySeries(
      symbol: 'XAU',
      currency: 'USD',
      range: MarketHistoryRange.oneDay,
      candles: [
        MarketCandle(
          time: DateTime.now(),
          open: 2,
          high: 3,
          low: 1,
          close: 2.5,
        ),
      ],
      provider: MarketHistoryProvider.backend,
      providerLabel: 'GoldBrain · test',
      fetchedAt: DateTime.now(),
    );
    final converted = series.forDisplay(
      selectedCode: 'IRT',
      language: GoldBrainLanguage.persian,
    );
    expect(converted.conversionUnavailable, isFalse);
    expect(converted.conversionStale, isFalse);
    expect(converted.series.currency, 'IRT');
    expect(converted.series.candles.single.open, 400000);
    expect(converted.series.candles.single.high, 600000);
    expect(converted.series.candles.single.low, 200000);
    expect(converted.series.candles.single.close, 500000);
    expect(series.currency, 'USD');
    expect(series.candles.single.close, 2.5);
  });

  test('unknown FX rate retains the source currency on a chart', () {
    final series = MarketHistorySeries(
      symbol: 'TEST',
      currency: 'XYZ',
      range: MarketHistoryRange.oneDay,
      candles: [
        MarketCandle(time: DateTime.now(), open: 1, high: 1, low: 1, close: 1),
      ],
      provider: MarketHistoryProvider.backend,
      providerLabel: 'GoldBrain · test',
      fetchedAt: DateTime.now(),
    );
    final converted = series.forDisplay(
      selectedCode: 'IRT',
      language: GoldBrainLanguage.persian,
    );
    expect(converted.conversionUnavailable, isTrue);
    expect(converted.series.currency, 'XYZ');
    expect(converted.series.candles.single.close, 1);
  });

  test('Backend candle preserves the price-sample disclosure', () {
    final now = DateTime.now().toUtc();
    final candle = BackendCandle.fromJson({
      'symbol': 'LEO',
      'timeframe': '1h',
      'currency': 'USD',
      'provider': 'coingecko',
      'opened_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'closed_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'open': 9.1,
      'high': 9.1,
      'low': 9.1,
      'close': 9.1,
      'quality_flags': ['price_sample_not_ohlc'],
    });
    expect(candle.qualityFlags, contains('price_sample_not_ohlc'));
  });

  test('30-day chart bypasses a short quote-collector series', () async {
    final now = DateTime.now().toUtc();
    final hour = DateTime.utc(now.year, now.month, now.day, now.hour);
    final providers = <String?>[];
    List<Map<String, Object?>> candles(String provider, int count) => [
      for (var i = count; i > 0; i--)
        {
          'symbol': 'BTC',
          'timeframe': '1h',
          'currency': 'USDT',
          'provider': provider,
          'opened_at': hour.subtract(Duration(hours: i)).toIso8601String(),
          'closed_at': hour.subtract(Duration(hours: i - 1)).toIso8601String(),
          'open': 70000,
          'high': 70100,
          'low': 69900,
          'close': 70050,
        },
    ];
    final api = GoldBrainBackendClient(
      config: GoldBrainBackendConfig(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        apiKey: '',
      ),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/market/quotes')) {
          return http.Response(
            jsonEncode({
              'quotes': [
                {
                  'symbol': 'BTC',
                  'name': 'Bitcoin',
                  'currency': 'USDT',
                  'price': 70050,
                  'updated_at': now.toIso8601String(),
                  'provider': 'wallex',
                },
              ],
              'issues': [],
            }),
            200,
          );
        }
        providers.add(request.url.queryParameters['provider']);
        final provider = request.url.queryParameters['provider'];
        return http.Response(
          jsonEncode({
            'candles': candles(
              provider == 'quote-collector' ? 'quote-collector' : 'wallex',
              provider == 'quote-collector' ? 2 : 720,
            ),
          }),
          200,
        );
      }),
    )..setAccessToken('chart-test');
    final history = MarketHistoryService(backend: api);
    final result = await history.fetchHistory(
      'BTC',
      range: MarketHistoryRange.oneMonth,
    );
    expect(providers, ['quote-collector', 'wallex']);
    expect(result.candles.length, 719);
    expect(result.providerLabel, 'GoldBrain · wallex');
    history.close();
    api.close();
  });
}
