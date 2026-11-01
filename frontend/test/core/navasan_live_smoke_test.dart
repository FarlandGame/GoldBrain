import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final enabled = Platform.environment['RUN_NAVASAN_LIVE_SMOKE'] == '1';

  test(
    'Navasan returns domestic quotes and real seven-day chart sources',
    () async {
      final prices = GlobalPriceService();
      final history = MarketHistoryService();
      addTearDown(prices.close);
      addTearDown(history.close);

      final batch = await prices.fetchQuotes(const <String>{
        'USD',
        'GOLD18',
      }, forceRefresh: true);
      expect(batch.errors, isEmpty);
      expect(batch.quotes.keys, containsAll(<String>['USD', 'GOLD18']));
      for (final quote in batch.quotes.values) {
        expect(quote.price, greaterThan(0));
        expect(quote.provider, GlobalPriceProvider.navasan);
      }

      final usd = await history.fetchHistory(
        'USD',
        range: MarketHistoryRange.oneWeek,
        forceRefresh: true,
      );
      expect(usd.candles.length, greaterThanOrEqualTo(4));
      expect(usd.provider, MarketHistoryProvider.navasan);
      expect(usd.candles.every((candle) => candle.close > 0), isTrue);

      final gold = await history.fetchHistory(
        'GOLD18',
        range: MarketHistoryRange.oneWeek,
        forceRefresh: true,
      );
      expect(gold.candles.length, greaterThanOrEqualTo(4));
      expect(
        gold.provider,
        isIn(<MarketHistoryProvider>[
          MarketHistoryProvider.navasan,
          MarketHistoryProvider.tgju,
        ]),
      );
      expect(gold.candles.every((candle) => candle.close > 0), isTrue);
    },
    skip: enabled
        ? false
        : 'Set RUN_NAVASAN_LIVE_SMOKE=1 to call the live market APIs.',
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
