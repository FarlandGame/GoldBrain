import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/backend_api_client.dart';
import 'package:goldbrain/core/currency_rate_store.dart';
import 'package:goldbrain/core/currency_service.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/internet_connection_service.dart';
import 'package:goldbrain/core/live_market_store.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'domestic 24h chart consumes actual Backend price samples, never hourly candles',
    () async {
      final now = DateTime.now().toUtc();
      for (final symbol in ['USD', 'GOLD18']) {
        final requests = <String>[];
        final unit = symbol == 'USD' ? 'currency_unit' : 'gram_18k';
        final api = _api((request) async {
          requests.add(request.url.path);
          expect(request.url.path, '/api/v1/market/$symbol/samples');
          expect(request.url.queryParameters['range'], '24h');
          return _json({
            'symbol': symbol,
            'range': '24h',
            'samples': [
              for (final hoursAgo in [20, 1])
                {
                  'symbol': symbol,
                  'price': symbol == 'USD' ? 234000 : 23858440,
                  'currency': 'IRT',
                  'unit': unit,
                  'market': 'IRAN',
                  'provider': 'navasan',
                  'provider_timestamp': now
                      .subtract(Duration(hours: hoursAgo))
                      .toIso8601String(),
                  'received_at': now.toIso8601String(),
                  'freshness_status': 'STALE',
                  'data_quality_status': 'VALID',
                  'quality_flags': ['price_sample_not_ohlc'],
                },
            ],
          });
        });
        final history = MarketHistoryService(backend: api);
        final series = await history.fetchHistory(
          symbol,
          range: MarketHistoryRange.oneDay,
        );
        expect(requests, ['/api/v1/market/$symbol/samples']);
        expect(series.isPriceSample, isTrue);
        expect(series.candles.every((point) => point.isPriceSample), isTrue);
        expect(series.providerLabel, contains('not OHLC'));
        expect(
          series.candles.first.time.toUtc(),
          now.subtract(const Duration(hours: 20)),
        );
        expect(series.candles.first.close, symbol == 'USD' ? 234000 : 23858440);
        history.close();
      }
    },
  );

  test(
    'EUR 24h chart waits for at least two persisted source observations',
    () async {
      final now = DateTime.now().toUtc();
      final api = _api((request) async {
        expect(request.url.path, '/api/v1/market/EUR/samples');
        return _json({
          'symbol': 'EUR',
          'range': '24h',
          'samples': [
            {
              'symbol': 'EUR',
              'price': 266540,
              'currency': 'IRT',
              'unit': 'currency_unit',
              'market': 'IRAN',
              'provider': 'navasan',
              'provider_timestamp': now.toIso8601String(),
              'received_at': now.toIso8601String(),
              'freshness_status': 'LIVE',
              'data_quality_status': 'VALID',
              'quality_flags': ['price_sample_not_ohlc'],
            },
          ],
        });
      });
      final history = MarketHistoryService(backend: api);
      await expectLater(
        history.fetchHistory('EUR', range: MarketHistoryRange.oneDay),
        throwsA(isA<MarketHistoryException>()),
      );
      history.close();
    },
  );

  test(
    'original market symbols use authenticated backend quotes and native units',
    () async {
      final api = _api((request) async {
        expect(request.url.path, '/api/v1/market/quotes');
        expect(request.headers['authorization'], 'Bearer adapter-test');
        expect(
          request.url.queryParametersAll['symbols'],
          containsAll(['USD', 'XAG', 'USDT', 'GOLD18', 'BTC']),
        );
        return _json({
          'requested_symbols': ['USD', 'XAG', 'USDT', 'GOLD18', 'BTC'],
          'quotes': [
            _quote('USD', 1000000, 'IRR'),
            _quote('GOLD18', 50000000, 'IRR'),
            _quote('XAG', 30, 'USD'),
            _quote('USDT', 100300, 'IRT'),
            _quote('BTC', 60000, 'USDT'),
          ],
          'issues': [],
          'partial': false,
        });
      });
      final service = GlobalPriceService(backend: api);
      final result = await service.fetchQuotes({
        'USD',
        'XAG',
        'USDT',
        'GOLD18',
        'BTC',
      });
      expect(result.errors, isEmpty);
      expect(result.quotes['GOLD18']!.price, 5000000);
      expect(result.quotes['GOLD18']!.currency, 'IRT');
      expect(result.quotes['USDT']!.price, 100300);
      expect(result.quotes['BTC']!.currency, 'USDT');
      expect(result.quotes['XAG']!.changePercent, isNull);
      expect(
        result.quotes['USD']!.providerLabel,
        'GoldBrain · adapter-fixture',
      );
      expect(
        LiveMarketStore.defaultTrackedSymbols,
        containsAll(['USD', 'XAG', 'USDT', 'BTC']),
      );
      service.close();
    },
  );

  test(
    'old quotes remain explicitly stale and future or missing prices are excluded',
    () async {
      final api = _api(
        (request) async => _json({
          'requested_symbols': ['USD', 'XAG', 'BTC'],
          'quotes': [
            _quote(
              'USD',
              100000,
              'IRT',
              at: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
            ),
            _quote(
              'XAG',
              30,
              'USD',
              at: DateTime.now().toUtc().add(const Duration(hours: 1)),
            ),
          ],
          'issues': [
            {'symbol': 'BTC', 'message': 'Provider unavailable'},
          ],
          'partial': true,
        }),
      );
      final service = GlobalPriceService(backend: api);
      final batch = await service.fetchQuotes({'USD', 'XAG', 'BTC'});
      expect(batch.quotes.keys, ['USD']);
      expect(batch.errors['USD'], contains('stale'));
      expect(batch.errors['XAG'], isNotEmpty);
      expect(batch.errors['BTC'], 'Provider unavailable');
      service.close();
    },
  );

  test(
    'rejects discredited domestic provider labels from backend responses',
    () async {
      final api = _api(
        (_) async => _json({
          'requested_symbols': ['USD', 'EUR', 'GOLD18', 'XAU'],
          'quotes': [
            {..._quote('USD', 100000, 'IRT'), 'provider': 'zarix'},
            {..._quote('EUR', 110000, 'IRT'), 'provider': 'zarix'},
            {
              ..._quote('GOLD18', 12000000, 'IRT'),
              'provider': 'persian-toolbox',
            },
            {..._quote('XAU', 4300, 'USD'), 'provider': 'zarix'},
          ],
          'issues': [],
          'partial': false,
        }),
      );
      final service = GlobalPriceService(backend: api);
      final batch = await service.fetchQuotes({'USD', 'EUR', 'GOLD18', 'XAU'});
      expect(batch.quotes.keys, ['XAU']);
      expect(batch.errors.keys, containsAll(['USD', 'EUR', 'GOLD18']));
      service.close();
    },
  );

  test('does not chart old PersianToolbox GOLD18 backend candles', () async {
    final now = DateTime.now().toUtc();
    final api = _api((request) async {
      if (request.url.path.endsWith('/market/quotes')) {
        return _json({
          'quotes': [
            {
              ..._quote('GOLD18', 12000000, 'IRT'),
              'provider': 'persian-toolbox',
            },
          ],
          'issues': [],
        });
      }
      return _json({
        'candles': [
          for (final minutesAgo in [2, 1])
            {
              'symbol': 'GOLD18',
              'timeframe': '1m',
              'currency': 'IRT',
              'provider': 'persian-toolbox',
              'opened_at': now
                  .subtract(Duration(minutes: minutesAgo))
                  .toIso8601String(),
              'closed_at': now
                  .subtract(Duration(minutes: minutesAgo - 1))
                  .toIso8601String(),
              'open': 12000000,
              'high': 12000000,
              'low': 12000000,
              'close': 12000000,
            },
        ],
      });
    });
    final history = MarketHistoryService(backend: api);
    await expectLater(
      history.fetchHistory('GOLD18', range: MarketHistoryRange.oneHour),
      throwsA(isA<MarketHistoryException>()),
    );
    history.close();
  });

  test('a Wallex quote without source time keeps its DELAYED label', () async {
    final api = _api(
      (request) async => _json({
        'requested_symbols': ['BTC'],
        'quotes': [
          {
            ..._quote('BTC', 65000, 'USDT'),
            'provider': 'wallex',
            'provider_timestamp': null,
            'freshness_status': 'DELAYED',
            'data_quality_status': 'VALID',
          },
        ],
        'issues': [],
        'partial': false,
      }),
    );
    final service = GlobalPriceService(backend: api);
    final batch = await service.fetchQuotes({'BTC'});
    expect(batch.errors, isEmpty);
    expect(batch.quotes['BTC']!.freshnessStatus, 'DELAYED');
    expect(batch.quotes['BTC']!.isStale, isTrue);
    service.close();
  });

  test('old collector candles do not hide current provider history', () async {
    final now = DateTime.now().toUtc();
    final requestedProviders = <String?>[];
    final api = _api((request) async {
      if (request.url.path.endsWith('/market/quotes')) {
        return _json({
          'quotes': [_quote('BTC', 83000, 'USDT')..['provider'] = 'wallex'],
          'issues': [],
        });
      }
      final provider = request.url.queryParameters['provider'];
      requestedProviders.add(provider);
      final offsets = provider == 'quote-collector'
          ? [400, 399, 398]
          : [25, 20, 12, 2];
      return _json({
        'candles': [
          for (final hours in offsets)
            {
              'symbol': 'BTC',
              'timeframe': '1h',
              'currency': 'USDT',
              'provider': provider ?? 'wallex',
              'opened_at': now
                  .subtract(Duration(hours: hours))
                  .toIso8601String(),
              'closed_at': now
                  .subtract(Duration(hours: hours - 1))
                  .toIso8601String(),
              'open': 83000,
              'high': 84000,
              'low': 82000,
              'close': 83500,
            },
        ],
      });
    });
    final history = MarketHistoryService(backend: api);
    final series = await history.fetchHistory(
      'BTC',
      range: MarketHistoryRange.oneDay,
      forceRefresh: true,
    );
    expect(requestedProviders, ['quote-collector', 'wallex']);
    expect(series.providerLabel, 'GoldBrain · wallex');
    expect(series.candles, hasLength(3));
    history.close();
  });

  test(
    'domestic weekly chart uses sourced daily candles when hourly is absent',
    () async {
      final now = DateTime.now().toUtc();
      final rows = [
        for (final daysAgo in [6, 5, 4, 3, 2, 1])
          {
            'symbol': 'GOLD18',
            'timeframe': '1d',
            'currency': 'IRT',
            'provider': 'navasan',
            'opened_at': now
                .subtract(Duration(days: daysAgo))
                .toIso8601String(),
            'closed_at': now
                .subtract(Duration(days: daysAgo - 1))
                .toIso8601String(),
            'open': 12000000,
            'high': 12100000,
            'low': 11900000,
            'close': 12050000,
            'quality_flags': ['unit_from_provider_catalog'],
          },
      ];
      final requestedTimeframes = <String>[];
      final api = _api((request) async {
        if (request.url.path.endsWith('/market/quotes')) {
          return _json({
            'quotes': [_quote('GOLD18', 12000000, 'IRT')],
            'issues': [],
          });
        }
        final timeframe = request.url.queryParameters['timeframe']!;
        requestedTimeframes.add(timeframe);
        return _json({'candles': timeframe == '1d' ? rows : []});
      });
      final history = MarketHistoryService(backend: api);
      final series = await history.fetchHistory(
        'GOLD18',
        range: MarketHistoryRange.oneWeek,
      );
      expect(requestedTimeframes, containsAll(['1h', '1d']));
      expect(series.providerLabel, 'GoldBrain · navasan · unit unverified');
      expect(series.candles, hasLength(6));
      expect(series.currency, 'IRT');
      expect(series.isStale, isTrue);
      history.close();
    },
  );

  test(
    'original chart keeps actual candle times and aligns quote provider and Rial unit',
    () async {
      final rows = _candles();
      final api = _api((request) async {
        if (request.url.path.endsWith('/market/quotes')) {
          return _json({
            'quotes': [_quote('USD', 1000000, 'IRR')],
            'issues': [],
          });
        }
        expect(request.url.path, '/api/v1/market/USD/candles');
        expect(request.url.queryParameters['provider'], 'quote-collector');
        expect(request.url.queryParameters['timeframe'], '1m');
        return _json({'candles': rows});
      });
      final history = MarketHistoryService(backend: api);
      final series = await history.fetchHistory(
        'USD',
        range: MarketHistoryRange.oneHour,
      );
      expect(series.candles, hasLength(2));
      expect(series.currency, 'IRT');
      expect(series.candles.first.close, 100000);
      expect(
        series.candles.first.time.toUtc(),
        DateTime.parse(rows.first['opened_at']! as String),
      );
      expect(series.provider, MarketHistoryProvider.backend);
      expect(series.isStale, isFalse);
      expect(series.isLocalHistory, isFalse);
      history.close();
    },
  );

  test(
    'empty or mixed-provider backend candles never create a chart',
    () async {
      for (final rows in [
        <Map<String, Object>>[],
        _candles()..last['provider'] = 'other-source',
      ]) {
        final api = _api(
          (request) async => request.url.path.endsWith('/market/quotes')
              ? _json({
                  'quotes': [_quote('USD', 1000000, 'IRR')],
                  'issues': [],
                })
              : _json({'candles': rows}),
        );
        final history = MarketHistoryService(backend: api);
        await expectLater(
          history.fetchHistory('USD', range: MarketHistoryRange.oneHour),
          throwsA(isA<MarketHistoryException>()),
        );
        history.close();
      }
    },
  );

  test(
    'cached backend history is explicitly stale on network failure',
    () async {
      var failed = false;
      final api = _api((request) async {
        if (failed) return _json({}, status: 503);
        return request.url.path.endsWith('/market/quotes')
            ? _json({
                'quotes': [_quote('USD', 1000000, 'IRR')],
                'issues': [],
              })
            : _json({
                'candles': _candles()
                    .map((row) => {...row, 'provider': 'navasan'})
                    .toList(),
              });
      });
      final history = MarketHistoryService(backend: api);
      final first = await history.fetchHistory(
        'USD',
        range: MarketHistoryRange.oneHour,
      );
      failed = true;
      final offline = await history.fetchHistory(
        'USD',
        range: MarketHistoryRange.oneHour,
        forceRefresh: true,
      );
      expect(offline.isStale, isTrue);
      expect(offline.candles, same(first.candles));
      history.close();
    },
  );

  test(
    'connectivity reflects backend reachability without external probes',
    () async {
      final api = _api((request) async {
        expect(request.url.path, '/api/v1/health');
        return _json({
          'status': 'ok',
          'version': 'test',
          'environment': 'test',
        });
      });
      final internet = InternetConnectionService(backend: api);
      expect(await internet.hasInternetAccess(), isTrue);
      internet.close();
    },
  );

  test(
    'currency display never assumes Tether parity or seeded FX prices',
    () async {
      expect(
        CurrencyService.convert(
          value: 10,
          sourceCode: 'USDT',
          targetCode: 'USD',
        ),
        isNull,
      );
      expect(
        CurrencyService.convert(
          value: 100,
          sourceCode: 'IRR',
          targetCode: 'IRT',
        ),
        10,
      );
      expect(CurrencyService.unitsPerUsdFor('JPY'), isNull);
      final fx = CurrencyRateStore(
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      expect(await fx.refresh(), isFalse);
      expect(fx.lastError, isNotNull);
      fx.dispose();
    },
  );
}

GoldBrainBackendClient _api(
  Future<http.Response> Function(http.Request) handler,
) => GoldBrainBackendClient(
  config: GoldBrainBackendConfig(
    baseUri: Uri.parse('http://127.0.0.1:8000'),
    apiKey: '',
  ),
  client: MockClient(handler),
)..setAccessToken('adapter-test');

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

Map<String, Object?> _quote(
  String symbol,
  double price,
  String currency, {
  DateTime? at,
}) => {
  'symbol': symbol,
  'name': symbol,
  'currency': currency,
  'price': price,
  'updated_at': (at ?? DateTime.now().toUtc()).toIso8601String(),
  'provider': 'adapter-fixture',
  'change_percent': null,
};

List<Map<String, Object>> _candles() {
  final now = DateTime.now().toUtc();
  final minute = DateTime.utc(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
  );
  return [
    for (final offset in [2, 1])
      {
        'symbol': 'USD',
        'timeframe': '1m',
        'currency': 'IRR',
        'provider': 'quote-collector',
        'opened_at': minute
            .subtract(Duration(minutes: offset))
            .toIso8601String(),
        'closed_at': minute
            .subtract(Duration(minutes: offset - 1))
            .toIso8601String(),
        'open': 1000000,
        'high': 1000100,
        'low': 999900,
        'close': 1000000,
      },
  ];
}
