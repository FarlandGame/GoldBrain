import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/currency_service.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('keeps ZARIX global metals separate from domestic gold', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.host, 'zarix.online');
      expect(request.url.queryParameters['endpoint'], 'markets');
      expect(request.url.queryParameters['category'], 'gold');
      expect(request.headers['authorization'], isNull);
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {
            'items': [
              {
                'symbol': 'XAU18',
                'title': 'Gold 18K',
                'price': 18809300,
                'changePercent': 0.03,
                'unit': 'تومان / گرم',
                'updatedAt': '2026-08-10T17:25:47Z',
                'sourceTime': '2026-08-10T16:29:52Z',
                'source': 'tgju',
              },
              {
                'symbol': 'XAUUSD',
                'title': 'Global gold ounce',
                'price': 4361.2,
                'changePercent': 0.35,
                'unit': 'دلار',
                'updatedAt': '2026-08-10T17:25:47Z',
                'source': 'gold-api',
              },
              {
                'symbol': 'XAGUSD',
                'title': 'Global silver ounce',
                'price': 65.19,
                'changePercent': 0.3,
                'unit': 'دلار',
                'updatedAt': '2026-08-10T17:25:47Z',
                'source': 'gold-api',
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = GlobalPriceService(
      client: client,
      navasanApiKey: '',
      cacheDuration: const Duration(days: 1),
    );

    final first = await service.fetchQuotes(const {'GOLD18', 'XAU', 'XAG'});
    final second = await service.fetchQuotes(const {'XAU'});

    expect(first.isPartial, isTrue);
    expect(first.quotes, isNot(contains('GOLD18')));
    expect(first.errors, contains('GOLD18'));
    expect(first.quotes['XAU']!.currency, 'USD');
    expect(first.quotes['XAG']!.price, 65.19);
    expect(second.quotes['XAU'], same(first.quotes['XAU']));
    expect(requests, 1);
  });

  test(
    'prefers current Navasan domestic prices and rate-limits its free endpoint',
    () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      var navasanRequests = 0;
      final service = GlobalPriceService(
        navasanApiKey: 'test-navasan-key',
        domesticCacheDuration: const Duration(hours: 2),
        client: MockClient((request) async {
          if (request.url.host == 'api.navasan.tech') {
            navasanRequests++;
            expect(request.url.path, '/latest/');
            expect(request.url.scheme, 'https');
            return http.Response(
              jsonEncode({
                'usd_sell': {
                  'value': '1867000',
                  'change': 7000,
                  'currency': 'IRR',
                  'timestamp': now,
                },
                '18ayar': {
                  'value': '19075210',
                  'change': 2310,
                  'timestamp': now,
                },
              }),
              200,
            );
          }
          return http.Response('{}', 503);
        }),
      );

      final first = await service.fetchQuotes(const {'USD', 'GOLD18'});
      final second = await service.fetchQuotes(const {
        'USD',
        'GOLD18',
      }, forceRefresh: true);

      expect(first.isComplete, isTrue);
      expect(first.quotes['USD']!.provider, GlobalPriceProvider.navasan);
      expect(first.quotes['USD']!.price, 186700);
      expect(first.quotes['GOLD18']!.provider, GlobalPriceProvider.navasan);
      expect(first.quotes['GOLD18']!.price, 19075210);
      expect(second.quotes['USD']!.provider, GlobalPriceProvider.navasan);
      expect(navasanRequests, 1);
      service.close();
    },
  );

  test(
    'leaves domestic prices unavailable and uses global metal fallback',
    () async {
      final requestedUrls = <String>[];
      final client = MockClient((request) async {
        requestedUrls.add(request.url.toString());
        if (request.url.host == 'zarix.online') {
          final category = request.url.queryParameters['category'];
          if (category == 'currencies') {
            return http.Response(
              jsonEncode({
                'ok': true,
                'data': {
                  'items': [
                    {
                      'symbol': 'USD',
                      'title': 'US Dollar',
                      'price': 185400,
                      'changePercent': 0.7,
                      'unit': 'تومان',
                      'updatedAt': '2026-08-10T17:25:47Z',
                      'source': 'tgju',
                    },
                  ],
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{}', 503);
        }

        if (request.url.path.endsWith('/price/XAU')) {
          return http.Response(
            jsonEncode({
              'currency': 'USD',
              'name': 'Gold',
              'price': 4358.7,
              'symbol': 'XAU',
              'updatedAt': '2026-08-10T17:22:03Z',
            }),
            200,
          );
        }
        return http.Response('{}', 502);
      });
      final service = GlobalPriceService(client: client, navasanApiKey: '');

      final result = await service.fetchQuotes(const {
        'USD',
        'GOLD18',
        'XAU',
        'ETH',
      });

      expect(result.isPartial, isTrue);
      expect(
        result.quotes.keys,
        contains('XAU'),
        reason: result.errors.toString(),
      );
      expect(result.quotes, isNot(contains('USD')));
      expect(result.quotes, isNot(contains('GOLD18')));
      expect(result.quotes['XAU']!.provider, GlobalPriceProvider.goldApi);
      expect(result.errors.keys, containsAll(<String>['USD', 'GOLD18', 'ETH']));
      expect(
        requestedUrls.where((url) => url.contains('category=currencies')),
        isEmpty,
      );
      expect(
        requestedUrls.where((url) => url.contains('gold-api.com/price/XAU')),
        hasLength(1),
      );
      expect(
        requestedUrls.where((url) => url.contains('gold-api.com/price/ETH')),
        hasLength(1),
      );
    },
  );

  test('keeps ZARIX crypto quotes denominated in USDT', () async {
    final service = GlobalPriceService(
      navasanApiKey: '',
      client: MockClient((request) async {
        expect(request.url.queryParameters['category'], 'crypto');
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'items': [
                {
                  'symbol': 'BTC',
                  'title': 'Bitcoin',
                  'price': 63878,
                  'changePercent': -2.1,
                  'unit': 'USDT',
                  'updatedAt': '2026-08-10T17:25:47Z',
                  'source': 'coingecko',
                },
                {
                  'symbol': 'ETH',
                  'title': 'Ethereum',
                  'price': 1871.76,
                  'changePercent': -2.8,
                  'unit': 'USDT',
                  'updatedAt': '2026-08-10T17:25:47Z',
                  'source': 'coingecko',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await service.fetchQuotes(const {'BTC', 'ETH'});

    expect(result.isComplete, isTrue);
    expect(result.quotes['BTC']!.currency, 'USDT');
    expect(result.quotes['BTC']!.changePercent, -2.1);
    expect(result.quotes['ETH']!.currency, 'USDT');
    expect(result.quotes['ETH']!.upstreamSource, 'coingecko');
  });

  test('rejects unsupported symbols without making a request', () async {
    var requests = 0;
    final service = GlobalPriceService(
      navasanApiKey: '',
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );

    expect(
      () => service.fetchQuote('OIL'),
      throwsA(isA<GlobalPriceException>()),
    );
    expect(requests, 0);
  });

  test(
    'does not replace Navasan timeout with a ZARIX currency price',
    () async {
      var requests = 0;
      final service = GlobalPriceService(
        navasanApiKey: 'test-key',
        timeout: const Duration(milliseconds: 1),
        client: MockClient((request) async {
          requests++;
          expect(request.url.host, 'api.navasan.tech');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response('{}', 200);
        }),
      );

      final result = await service.fetchQuotes(const {'USD'});

      expect(result.quotes, isEmpty);
      expect(result.errors, contains('USD'));
      expect(requests, 1);
    },
  );

  test('rejects a ZARIX quote whose denomination is ambiguous', () async {
    final service = GlobalPriceService(
      navasanApiKey: '',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'items': [
                {
                  'symbol': 'BTC',
                  'title': 'Bitcoin',
                  'price': 63878,
                  'unit': 'USD',
                  'updatedAt': '2026-08-10T17:25:47Z',
                  'source': 'unknown',
                },
              ],
            },
          }),
          200,
        );
      }),
      goldApiBaseUri: Uri.parse('https://fallback.invalid/'),
    );

    final result = await service.fetchQuotes(const {'BTC'});

    expect(result.quotes, isEmpty);
    expect(result.errors, contains('BTC'));
  });

  test('formats USDT explicitly instead of claiming USD', () {
    expect(
      CurrencyService.formatPrice(
        value: 63878,
        selectedCode: 'USDT',
        language: GoldBrainLanguage.english,
      ),
      '63,878.00 USDT',
    );
  });

  test('Chinese language defaults to CNY and localizes its name', () {
    expect(
      CurrencyService.resolveCurrencyCode(
        selectedCode: 'auto',
        language: GoldBrainLanguage.chinese,
      ),
      'CNY',
    );
    expect(
      CurrencyService.localizedName(
        code: 'CNY',
        language: GoldBrainLanguage.chinese,
      ),
      '人民币',
    );
  });

  test('new languages choose regional automatic currencies', () {
    expect(
      CurrencyService.resolveCurrencyCode(
        selectedCode: 'auto',
        language: GoldBrainLanguage.arabic,
      ),
      'SAR',
    );
    expect(
      CurrencyService.resolveCurrencyCode(
        selectedCode: 'auto',
        language: GoldBrainLanguage.turkish,
      ),
      'TRY',
    );
    expect(
      CurrencyService.resolveCurrencyCode(
        selectedCode: 'auto',
        language: GoldBrainLanguage.french,
      ),
      'EUR',
    );
    expect(
      CurrencyService.localizedName(
        code: 'TRY',
        language: GoldBrainLanguage.turkish,
      ),
      'Türk Lirası',
    );
  });

  test('automatic display currency follows every supported language', () {
    const expected = {
      GoldBrainLanguage.persian: 'IRT',
      GoldBrainLanguage.english: 'USD',
      GoldBrainLanguage.japanese: 'JPY',
      GoldBrainLanguage.russian: 'RUB',
      GoldBrainLanguage.chinese: 'CNY',
      GoldBrainLanguage.arabic: 'SAR',
      GoldBrainLanguage.turkish: 'TRY',
      GoldBrainLanguage.french: 'EUR',
    };

    for (final entry in expected.entries) {
      expect(
        CurrencyService.resolveCurrencyCode(
          selectedCode: 'auto',
          language: entry.key,
        ),
        entry.value,
      );
    }
  });

  test('converts sourced prices to the selected display currency', () {
    CurrencyService.updateIranianTomanPerUsd(200000);
    CurrencyService.updateInternationalRates(const {'USD': 1, 'JPY': 150});

    expect(
      CurrencyService.formatPrice(
        value: 20000000,
        sourceCode: 'IRT',
        selectedCode: 'USD',
        language: GoldBrainLanguage.persian,
      ),
      r'100.00 $',
    );
    expect(
      CurrencyService.formatPrice(
        value: 20000000,
        sourceCode: 'IRT',
        selectedCode: 'auto',
        language: GoldBrainLanguage.japanese,
      ),
      '15,000 ¥',
    );
  });
}
