import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/market_history_persistent_cache.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'restores exact candles without turning a recent observation stale',
    () async {
      final now = DateTime.now();
      final cache = MarketHistoryPersistentCache();
      final source = MarketHistorySeries(
        symbol: 'XAU',
        currency: 'USD',
        range: MarketHistoryRange.oneDay,
        candles: [
          _candle(now.subtract(const Duration(hours: 2)), 4300),
          _candle(now.subtract(const Duration(hours: 1)), 4315),
          _candle(now, 4308),
        ],
        provider: MarketHistoryProvider.zarix,
        providerLabel: 'ZARIX · yahoo_v8',
        fetchedAt: now,
      );

      await cache.put(source);
      final restored = await MarketHistoryPersistentCache().get(
        'XAU',
        range: MarketHistoryRange.oneDay,
      );

      expect(restored, isNotNull);
      expect(restored!.isStale, isFalse);
      expect(restored.provider, MarketHistoryProvider.zarix);
      expect(restored.candles.map((point) => point.close), [4300, 4315, 4308]);
      expect(
        restored.candles.map((point) => point.time.millisecondsSinceEpoch),
        source.candles.map((point) => point.time.millisecondsSinceEpoch),
      );
    },
  );

  test('preserves source staleness across a recent disk-cache reuse', () async {
    final now = DateTime.now();
    final cache = MarketHistoryPersistentCache();
    await cache.put(
      MarketHistorySeries(
        symbol: 'GOLD18',
        currency: 'IRT',
        range: MarketHistoryRange.oneWeek,
        candles: [
          _candle(now.subtract(const Duration(days: 4)), 19000000),
          _candle(now.subtract(const Duration(days: 3)), 19100000),
        ],
        provider: MarketHistoryProvider.tgju,
        providerLabel: 'TGJU · real daily OHLC · 2 sessions',
        fetchedAt: now,
        isStale: true,
      ),
    );

    final restored = await MarketHistoryPersistentCache().get(
      'GOLD18',
      range: MarketHistoryRange.oneWeek,
    );

    expect(restored, isNotNull);
    expect(restored!.isStale, isTrue);
  });

  test('rejects corrupt and future cached values', () async {
    SharedPreferences.setMockInitialValues({
      'goldbrain_verified_market_history_v3':
          '{"XAU:oneDay":{"fetchedAt":9999999999999,"provider":"zarix","candles":[[9999999999999,1,1,1,1],[9999999999998,2,2,2,2]]}}',
    });
    final restored = await MarketHistoryPersistentCache().get(
      'XAU',
      range: MarketHistoryRange.oneDay,
    );
    expect(restored, isNull);
  });

  test('rejects legacy domestic ZARIX and PersianToolbox history', () async {
    final now = DateTime.now();
    Map<String, Object> series(
      String symbol,
      String provider,
      String providerLabel,
    ) => {
      'symbol': symbol,
      'currency': 'IRT',
      'provider': provider,
      'providerLabel': providerLabel,
      'fetchedAt': now.millisecondsSinceEpoch,
      'candles': [
        [
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          100,
          100,
          100,
          100,
        ],
        [now.millisecondsSinceEpoch, 101, 101, 101, 101],
      ],
    };
    SharedPreferences.setMockInitialValues({
      'goldbrain_verified_market_history_v3': jsonEncode({
        'USD:oneWeek': series('USD', 'zarix', 'ZARIX · tgju'),
        'EUR:oneWeek': series('EUR', 'zarix', 'ZARIX · frankfurter'),
        'GOLD18:oneWeek': series(
          'GOLD18',
          'navasan',
          'GoldBrain · persian-toolbox',
        ),
        'GOLD18:oneMonth': series(
          'GOLD18',
          'backend',
          'GoldBrain · quote-collector',
        ),
      }),
    });
    final cache = MarketHistoryPersistentCache();
    for (final symbol in ['USD', 'EUR', 'GOLD18']) {
      expect(
        await cache.get(symbol, range: MarketHistoryRange.oneWeek),
        isNull,
      );
    }
    expect(
      await cache.get('GOLD18', range: MarketHistoryRange.oneMonth),
      isNull,
    );
  });
}

MarketCandle _candle(DateTime time, double value) => MarketCandle(
  time: time,
  open: value,
  high: value,
  low: value,
  close: value,
);
