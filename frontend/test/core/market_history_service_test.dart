import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('formats Navasan request dates in the accepted Jalali form', () {
    expect(
      MarketHistoryService.formatNavasanDate(DateTime(2026, 8, 13)),
      '1405-05-22',
    );
  });

  test('parses real ZARIX OHLC points and preserves source evidence', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final service = MarketHistoryService(
      client: MockClient((request) async {
        expect(request.url.queryParameters['endpoint'], 'chart');
        expect(request.url.queryParameters['symbol'], 'BTCUSD');
        expect(request.url.queryParameters['interval'], '1h');
        expect(request.url.queryParameters, containsPair('from', isNotEmpty));
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'candles': [
                _objectCandle(now - 7200, 62000),
                _objectCandle(now - 3600, 62400),
                _objectCandle(now, 62150),
              ],
              'meta': {'provider': 'yahoo_v8'},
            },
          }),
          200,
        );
      }),
    );

    final result = await service.fetchHistory('BTC');

    expect(result.candles, hasLength(3));
    expect(result.candles.last.close, 62150);
    expect(result.provider, MarketHistoryProvider.zarix);
    expect(result.providerLabel, 'ZARIX · yahoo_v8');
    expect(result.isProxy, isFalse);
    service.close();
  });

  test('uses official Kraken OHLC fallback for crypto', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final service = MarketHistoryService(
      client: MockClient((request) async {
        if (request.url.queryParameters['endpoint'] == 'chart') {
          return http.Response('{}', 503);
        }
        expect(request.url.host, 'api.kraken.com');
        expect(request.url.queryParameters['pair'], 'XBTUSD');
        return http.Response(
          jsonEncode({
            'error': [],
            'result': {
              'XXBTZUSD': [
                [now - 7200, '62000', '62100', '61900', '62050', '0', '1', 3],
                [now - 3600, '62050', '62300', '62000', '62200', '0', '1', 3],
                [now, '62200', '62500', '62100', '62400', '0', '1', 3],
              ],
              'last': now,
            },
          }),
          200,
        );
      }),
    );

    final result = await service.fetchHistory('BTC');

    expect(result.provider, MarketHistoryProvider.kraken);
    expect(result.providerLabel, 'Kraken Spot');
    expect(result.candles.last.close, 62400);
    service.close();
  });

  test(
    'does not invent domestic history without a configured API key',
    () async {
      var requests = 0;
      final service = MarketHistoryService(
        navasanApiKey: '',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      for (final symbol in const ['USD', 'GOLD18']) {
        await expectLater(
          service.fetchHistory(symbol),
          throwsA(
            isA<MarketHistoryException>()
                .having((error) => error.unavailable, 'unavailable', isTrue)
                .having(
                  (error) => error.message,
                  'configuration hint',
                  contains('NAVASAN_API_KEY'),
                ),
          ),
        );
      }
      expect(requests, 0);
      service.close();
    },
  );

  test(
    'uses validated TGJU daily OHLC when Navasan has no Gold18 rows',
    () async {
      final html = StringBuffer('<table>');
      final today = DateTime.now().toUtc();
      for (var index = 0; index < 8; index++) {
        final day = today.subtract(Duration(days: index));
        final date =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}';
        final open = 190000000 + index * 100000;
        html.write(
          '<tr>'
          '<td>$open</td>'
          '<td>${open - 100000}</td>'
          '<td>${open + 200000}</td>'
          '<td>${open + 100000}</td>'
          '<td>0</td><td>0</td>'
          '<td>$date</td>'
          '</tr>',
        );
      }
      html.write('</table>');
      var navasanRequests = 0;
      var tgjuRequests = 0;
      final service = MarketHistoryService(
        navasanApiKey: 'empty-gold-history-test-key',
        allowPublicDomesticFallback: true,
        client: MockClient((request) async {
          if (request.url.host == 'api.navasan.tech') {
            navasanRequests++;
            return http.Response('{"data":[]}', 200);
          }
          expect(request.url.host, 'english.tgju.org');
          expect(request.url.path, contains('geram18/history'));
          tgjuRequests++;
          return http.Response(html.toString(), 200);
        }),
      );

      final result = await service.fetchHistory(
        'GOLD18',
        range: MarketHistoryRange.oneWeek,
      );

      expect(navasanRequests, 1);
      expect(tgjuRequests, 1);
      expect(result.provider, MarketHistoryProvider.tgju);
      expect(result.providerLabel, contains('real daily OHLC'));
      expect(result.currency, 'IRT');
      expect(result.candles, hasLength(8));
      expect(result.candles.first.close, greaterThan(10000000));
      service.close();
    },
  );

  test(
    'parses TGJU Persian dates without fabricating the calendar day',
    () async {
      final html = StringBuffer('<table>');
      String toPersianDigits(String value) => value
          .replaceAll('0', '۰')
          .replaceAll('1', '۱')
          .replaceAll('2', '۲')
          .replaceAll('3', '۳')
          .replaceAll('4', '۴')
          .replaceAll('5', '۵')
          .replaceAll('6', '۶')
          .replaceAll('7', '۷')
          .replaceAll('8', '۸')
          .replaceAll('9', '۹');
      final today = DateTime.now().toUtc();
      for (var offset = 0; offset < 8; offset++) {
        final jalaliDate = MarketHistoryService.formatNavasanDate(
          today.subtract(Duration(days: offset)),
        ).replaceAll('-', '/');
        html.write(
          '<tr><td>190000000</td><td>189000000</td>'
          '<td>191000000</td><td>190500000</td><td>0</td><td>0</td>'
          '<td>${toPersianDigits(jalaliDate)}</td></tr>',
        );
      }
      html.write('</table>');
      final service = MarketHistoryService(
        navasanApiKey: '',
        allowPublicDomesticFallback: true,
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(html.toString()), 200),
        ),
      );

      final result = await service.fetchHistory(
        'USD',
        range: MarketHistoryRange.oneWeek,
      );

      expect(result.provider, MarketHistoryProvider.tgju);
      expect(result.candles.last.time.year, today.year);
      expect(result.candles.last.time.month, today.month);
      expect(result.candles.last.time.day, today.day);
      service.close();
    },
  );

  test('parses exact Navasan weekly OHLC for USD in toman', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final service = MarketHistoryService(
      navasanApiKey: 'test-key',
      client: MockClient((request) async {
        expect(request.url.scheme, 'https');
        expect(request.url.path, '/ohlcSearch/');
        expect(request.url.queryParameters['api_key'], 'test-key');
        expect(request.url.queryParameters['item'], 'usd_sell');
        expect(request.url.queryParameters, containsPair('start', isNotEmpty));
        expect(request.url.queryParameters, containsPair('end', isNotEmpty));
        return http.Response(
          jsonEncode({
            'data': List.generate(7, (index) {
              final value = 184000 + (index * 500);
              final factor = index == 6 ? 10 : 1;
              return {
                'timestamp': now - ((6 - index) * 86400),
                if (index == 6) 'currency': 'IRR',
                'open': '${value * factor}',
                'high': '${(value + 300) * factor}',
                'low': '${(value - 200) * factor}',
                'close': '${(value + 100) * factor}',
              };
            }),
          }),
          200,
        );
      }),
    );

    final result = await service.fetchHistory(
      'USD',
      range: MarketHistoryRange.oneWeek,
    );

    expect(result.provider, MarketHistoryProvider.navasan);
    expect(result.providerLabel, 'Navasan · usd_sell · daily OHLC');
    expect(result.currency, 'IRT');
    expect(result.candles, hasLength(7));
    expect(result.candles.last.close, 187100);
    expect(result.isProxy, isFalse);
    service.close();
  });

  test(
    'reuses domestic history on forced refresh to protect the free quota',
    () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      var requests = 0;
      final service = MarketHistoryService(
        navasanApiKey: 'quota-cache-test-key',
        client: MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'data': List.generate(7, (index) {
                final value = 180000 + index * 100;
                return {
                  'timestamp': now - ((6 - index) * 86400),
                  'open': value,
                  'high': value + 100,
                  'low': value - 100,
                  'close': value + 50,
                };
              }),
            }),
            200,
          );
        }),
      );

      final first = await service.fetchHistory(
        'USD',
        range: MarketHistoryRange.oneWeek,
        forceRefresh: true,
      );
      final second = await service.fetchHistory(
        'USD',
        range: MarketHistoryRange.oneWeek,
        forceRefresh: true,
      );

      expect(requests, 1);
      expect(second.candles, same(first.candles));
      service.close();
    },
  );

  test('rejects future or internally inconsistent Navasan OHLC rows', () async {
    final future =
        DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch ~/
        1000;
    final service = MarketHistoryService(
      navasanApiKey: 'invalid-ohlc-test-key',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': [
              {
                'timestamp': future,
                'open': 100,
                'high': 90,
                'low': 80,
                'close': 95,
              },
              {
                'timestamp': future + 60,
                'open': 100,
                'high': 110,
                'low': 90,
                'close': 105,
              },
            ],
          }),
          200,
        ),
      ),
    );

    await expectLater(
      service.fetchHistory('USD', range: MarketHistoryRange.oneWeek),
      throwsA(isA<MarketHistoryException>()),
    );
    service.close();
  });

  test(
    'deduplicates concurrent domestic requests across service owners',
    () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(
          jsonEncode({
            'data': List.generate(7, (index) {
              final value = 19000000 + index * 1000;
              return {
                'timestamp': now - ((6 - index) * 86400),
                'open': value,
                'high': value + 1000,
                'low': value - 1000,
                'close': value + 500,
              };
            }),
          }),
          200,
        );
      });
      final first = MarketHistoryService(
        navasanApiKey: 'in-flight-dedupe-test-key',
        client: client,
      );
      final second = MarketHistoryService(
        navasanApiKey: 'in-flight-dedupe-test-key',
        client: client,
      );

      final results = await Future.wait([
        first.fetchHistory('GOLD18', range: MarketHistoryRange.oneWeek),
        second.fetchHistory('GOLD18', range: MarketHistoryRange.oneWeek),
      ]);

      expect(requests, 1);
      expect(results, everyElement(isA<MarketHistorySeries>()));
      first.close();
      second.close();
    },
  );

  test('parses real Navasan intraday ticks for one-hour Gold 18K', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final service = MarketHistoryService(
      navasanApiKey: 'test-key',
      client: MockClient((request) async {
        expect(request.url.path, '/dailyCurrency/');
        expect(request.url.queryParameters['item'], '18ayar');
        expect(
          request.url.queryParameters['date'],
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
        );
        return http.Response(
          jsonEncode([
            {'timestamp': now - 3000, 'value': '18900000'},
            {'timestamp': now - 1500, 'value': '189250000', 'currency': 'IRR'},
            {'timestamp': now, 'value': '18910000'},
          ]),
          200,
        );
      }),
    );

    final result = await service.fetchHistory(
      'GOLD18',
      range: MarketHistoryRange.oneHour,
    );

    expect(result.provider, MarketHistoryProvider.navasan);
    expect(result.currency, 'IRT');
    expect(result.candles.map((point) => point.close), [
      18900000,
      18925000,
      18910000,
    ]);
    expect(result.candles.first.open, result.candles.first.close);
    service.close();
  });

  test(
    'combines two Navasan trading days for the real 24-hour range',
    () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      var requestCount = 0;
      final service = MarketHistoryService(
        navasanApiKey: 'test-key',
        client: MockClient((request) async {
          requestCount++;
          final rows = requestCount == 1
              ? [
                  {'timestamp': now - 4 * 3600, 'value': '186500'},
                  {'timestamp': now, 'value': '187000'},
                ]
              : [
                  {'timestamp': now - 20 * 3600, 'value': '185500'},
                  {'timestamp': now - 18 * 3600, 'value': '186000'},
                ];
          return http.Response(jsonEncode({'result': rows}), 200);
        }),
      );

      final result = await service.fetchHistory(
        'USD',
        range: MarketHistoryRange.oneDay,
      );

      expect(requestCount, 2);
      expect(result.candles.map((point) => point.close), [
        185500,
        186000,
        186500,
        187000,
      ]);
      expect(result.observedSpan, greaterThan(const Duration(hours: 19)));
      service.close();
    },
  );

  test('never sends a domestic API key over plain HTTP', () async {
    var requests = 0;
    final service = MarketHistoryService(
      navasanApiKey: 'must-stay-secret',
      navasanEndpoint: Uri.parse('http://api.navasan.tech/'),
      client: MockClient((_) async {
        requests++;
        return http.Response('[]', 200);
      }),
    );

    await expectLater(
      service.fetchHistory('USD'),
      throwsA(
        isA<MarketHistoryException>().having(
          (error) => error.message,
          'secure transport error',
          contains('HTTPS'),
        ),
      ),
    );
    expect(requests, 0);
    service.close();
  });

  test('rejects invalid or fabricated-looking OHLC values', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final service = MarketHistoryService(
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'candles': [_objectCandle(now - 3600, 0), _objectCandle(now, -1)],
            },
          }),
          200,
        );
      }),
      krakenEndpoint: Uri.parse('https://also-fails.invalid/'),
    );

    await expectLater(
      service.fetchHistory('BTC'),
      throwsA(isA<MarketHistoryException>()),
    );
    service.close();
  });

  test(
    'requests a real five-minute XAU series for the one-hour range',
    () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final service = MarketHistoryService(
        client: MockClient((request) async {
          expect(request.url.queryParameters['symbol'], 'XAUUSD');
          expect(request.url.queryParameters['interval'], '5m');
          final from = int.parse(request.url.queryParameters['from']!);
          final to = int.parse(request.url.queryParameters['to']!);
          expect(to - from, inInclusiveRange(3590, 3610));
          return http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'candles': [
                  _objectCandle(now - 1800, 4300),
                  _objectCandle(now - 900, 4310),
                  _objectCandle(now, 4320),
                ],
                'meta': {'provider': 'yahoo_v8'},
              },
            }),
            200,
          );
        }),
      );

      final result = await service.fetchHistory(
        'XAU',
        range: MarketHistoryRange.oneHour,
      );
      expect(result.range, MarketHistoryRange.oneHour);
      expect(result.candles, hasLength(3));
      service.close();
    },
  );

  test(
    'falls back to persisted verified candles after provider failure',
    () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final working = MarketHistoryService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'data': {
                'candles': [
                  _objectCandle(now - 7200, 4300),
                  _objectCandle(now - 3600, 4310),
                  _objectCandle(now, 4320),
                ],
                'meta': {'provider': 'yahoo_v8'},
              },
            }),
            200,
          ),
        ),
      );
      await working.fetchHistory('XAU');
      working.close();

      final offline = MarketHistoryService(
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      final cached = await offline.fetchHistory('XAU');
      expect(cached.isStale, isTrue);
      expect(cached.candles.map((point) => point.close), [4300, 4310, 4320]);
      offline.close();
    },
  );

  test(
    'local chart domain follows actual samples instead of stretching 7d',
    () {
      final end = DateTime(2026, 8, 11, 12);
      final start = end.subtract(const Duration(hours: 8));
      final series = MarketHistorySeries(
        symbol: 'USD',
        currency: 'IRT',
        range: MarketHistoryRange.oneWeek,
        candles: [_modelCandle(start, 185000), _modelCandle(end, 187000)],
        provider: MarketHistoryProvider.localDevice,
        providerLabel: 'Device-recorded · ZARIX · tgju',
        fetchedAt: end,
        isLocalHistory: true,
      );

      expect(series.actualTimeDomain.start, start);
      expect(series.actualTimeDomain.end, end);
      expect(series.observedSpan, const Duration(hours: 8));
      expect(series.observedCoverageRatio, closeTo(8 / (7 * 24), 0.0001));
    },
  );
}

Map<String, Object> _objectCandle(int time, num close) {
  return {
    'time': time,
    'open': close,
    'high': close == 0 ? 0 : close + 10,
    'low': close == 0 ? 0 : close - 10,
    'close': close,
  };
}

MarketCandle _modelCandle(DateTime time, double close) => MarketCandle(
  time: time,
  open: close,
  high: close,
  low: close,
  close: close,
);
