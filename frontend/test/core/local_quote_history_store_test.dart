import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/local_quote_history_store.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'persists, deduplicates and restores only verified quote points',
    () async {
      final now = DateTime.now();
      final store = LocalQuoteHistoryStore();
      await store.recordQuotes({
        'USD': _quote('USD', 92000, now.subtract(const Duration(minutes: 15))),
      });
      await store.recordQuotes({
        'USD': _quote('USD', 92100, now.subtract(const Duration(minutes: 15))),
      });
      await store.recordQuotes({
        'USD': _quote('USD', 92200, now.subtract(const Duration(minutes: 12))),
      });
      await store.recordQuotes({
        'USD': _quote('USD', 92250, now.subtract(const Duration(minutes: 9))),
      });
      await store.recordQuotes({
        'USD': _quote('USD', 92275, now.subtract(const Duration(minutes: 6))),
      });
      await store.recordQuotes({
        'USD': _quote('USD', 92290, now.subtract(const Duration(minutes: 3))),
      });
      await store.recordQuotes({'USD': _quote('USD', 92300, now)});

      final restored = LocalQuoteHistoryStore();
      final history = await restored.historyFor(
        'USD',
        range: MarketHistoryRange.oneHour,
      );

      expect(history, isNotNull);
      expect(history!.provider, MarketHistoryProvider.localDevice);
      expect(history.isLocalHistory, isTrue);
      expect(history.candles, hasLength(6));
      expect(history.candles.first.close, 92100);
      expect(history.candles.last.close, 92300);
      expect(history.providerLabel, 'Device-recorded · Navasan · usd_sell');
    },
  );

  test(
    'requires enough real points and time coverage and enforces a safe cap',
    () async {
      final now = DateTime.now();
      final store = LocalQuoteHistoryStore(maxPointsPerSymbol: 6);
      await store.recordQuotes({
        'GOLD18': _quote(
          'GOLD18',
          7000000,
          now.subtract(const Duration(days: 8)),
        ),
      });
      expect(await store.historyFor('GOLD18'), isNull);

      for (var index = 0; index < 8; index++) {
        await store.recordQuotes({
          'GOLD18': _quote(
            'GOLD18',
            7100000 + index.toDouble(),
            now.subtract(Duration(minutes: (7 - index) * 3)),
          ),
        });
      }

      final history = await store.historyFor(
        'GOLD18',
        range: MarketHistoryRange.oneHour,
      );
      expect(history, isNotNull);
      expect(history!.candles, hasLength(6));
      expect(history.candles.first.close, 7100002);
      expect(history.candles.last.close, 7100007);
    },
  );

  test('does not expose incompatible v1 history', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'goldbrain_verified_quote_history_v1':
          '{"USD":[{"time":$now,"price":92000,"currency":"IRT"}]}',
    });

    final status = await LocalQuoteHistoryStore().statusFor(
      'USD',
      range: MarketHistoryRange.oneHour,
    );

    expect(status.pointCount, 0);
    expect(status.hasEnoughData, isFalse);
  });

  test(
    'does not draw six points compressed into an insufficient window',
    () async {
      final now = DateTime.now();
      final store = LocalQuoteHistoryStore();
      for (var index = 0; index < 6; index++) {
        await store.recordQuotes({
          'USD': _quote(
            'USD',
            92000 + index.toDouble(),
            now.subtract(Duration(minutes: 5 - index)),
          ),
        });
      }

      final status = await store.statusFor(
        'USD',
        range: MarketHistoryRange.oneHour,
      );
      expect(status.pointCount, 6);
      expect(status.observedSpan, const Duration(minutes: 5));
      expect(status.hasEnoughData, isFalse);
      expect(
        await store.historyFor('USD', range: MarketHistoryRange.oneHour),
        isNull,
      );
    },
  );

  test('starts a new regime when provider/upstream source changes', () async {
    final now = DateTime.now();
    final store = LocalQuoteHistoryStore();
    for (var index = 0; index < 6; index++) {
      await store.recordQuotes({
        'USD': _quote(
          'USD',
          92000 + index.toDouble(),
          now.subtract(Duration(minutes: (5 - index) * 3)),
        ),
      });
    }
    expect(
      await store.historyFor('USD', range: MarketHistoryRange.oneHour),
      isNotNull,
    );

    await store.recordQuotes({
      'USD': _quote(
        'USD',
        92010,
        now.add(const Duration(seconds: 1)),
        source: 'replacement-feed',
      ),
    });

    final restored = LocalQuoteHistoryStore();
    final status = await restored.statusFor(
      'USD',
      range: MarketHistoryRange.oneHour,
    );
    expect(status.pointCount, 1);
    expect(status.sourceLabel, 'Navasan · replacement-feed');
    expect(
      await restored.historyFor('USD', range: MarketHistoryRange.oneHour),
      isNull,
    );
  });

  test('splits an unexplained domestic quote discontinuity', () async {
    final now = DateTime.now();
    final store = LocalQuoteHistoryStore();
    for (var index = 0; index < 6; index++) {
      await store.recordQuotes({
        'USD': _quote(
          'USD',
          92000 + index.toDouble(),
          now.subtract(Duration(minutes: (6 - index) * 3)),
          changePercent: 0.4,
        ),
      });
    }
    await store.recordQuotes({
      'USD': _quote('USD', 187000, now, changePercent: 0.7),
    });

    final status = await store.statusFor(
      'USD',
      range: MarketHistoryRange.oneHour,
    );
    expect(status.pointCount, 1);
    expect(status.hasEnoughData, isFalse);
  });

  test('marks sufficiently covered local history stale', () async {
    final now = DateTime.now();
    final store = LocalQuoteHistoryStore();
    for (var index = 0; index < 6; index++) {
      await store.recordQuotes({
        'GOLD18': _quote(
          'GOLD18',
          19000000 + index.toDouble(),
          now.subtract(Duration(minutes: 45 - index * 5)),
        ),
      });
    }

    final history = await store.historyFor(
      'GOLD18',
      range: MarketHistoryRange.oneHour,
    );
    expect(history, isNotNull);
    expect(history!.isStale, isTrue);
    expect(history.observedSpan, const Duration(minutes: 25));
  });

  test(
    'does not restore old domestic ZARIX or PersianToolbox points',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      Map<String, Object> point(String provider, String source) => {
        'time': now,
        'price': 100000,
        'currency': 'IRT',
        'provider': provider,
        'upstreamSource': source,
      };
      SharedPreferences.setMockInitialValues({
        'goldbrain_verified_quote_history_v3': jsonEncode({
          'USD': [point('zarix', 'tgju')],
          'EUR': [point('backend', 'zarix')],
          'GOLD18': [point('backend', 'persian-toolbox')],
          'XAU': [point('zarix', 'gold-api')],
        }),
      });
      final store = LocalQuoteHistoryStore();
      for (final symbol in ['USD', 'EUR', 'GOLD18']) {
        expect(await store.pointCountFor(symbol), 0);
      }
      expect(await store.pointCountFor('XAU'), 1);
    },
  );
}

GlobalPriceQuote _quote(
  String symbol,
  double price,
  DateTime time, {
  String source = 'usd_sell',
  double? changePercent,
}) {
  return GlobalPriceQuote(
    symbol: symbol,
    name: symbol,
    currency: 'IRT',
    price: price,
    updatedAt: time,
    provider: GlobalPriceProvider.navasan,
    upstreamSource: source,
    changePercent: changePercent,
  );
}
