import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:goldbrain/core/market_pulse.dart';

void main() {
  final now = DateTime.utc(2026, 9, 27, 12);

  MarketHistorySeries series(
    List<double> closes, {
    bool stale = false,
    bool volume = false,
    bool reverseTime = false,
  }) => MarketHistorySeries(
    symbol: 'BTC',
    currency: 'USD',
    range: MarketHistoryRange.oneDay,
    candles: [
      for (var i = 0; i < closes.length; i++)
        MarketCandle(
          time: now.subtract(
            Duration(hours: reverseTime ? i * 3 : (closes.length - i - 1) * 3),
          ),
          open: closes[i],
          high: closes[i],
          low: closes[i],
          close: closes[i],
          volume: volume ? (i + 1) * 100 : null,
        ),
    ],
    provider: MarketHistoryProvider.backend,
    providerLabel: 'GoldBrain · source',
    fetchedAt: now,
    isStale: stale,
  );

  test(
    'increasing observations yield a higher descriptive pulse than falling ones',
    () {
      const calculator = MarketPulseCalculator();
      final up = calculator.calculate(
        series([100, 102, 104, 106, 108]),
        now: now,
      );
      final down = calculator.calculate(
        series([108, 106, 104, 102, 100]),
        now: now,
      );
      expect(up.score, greaterThan(50));
      expect(down.score, lessThan(50));
      expect(up.score, greaterThan(down.score!));
      expect(up.hasVolume, isFalse);
      expect(up.hasNews, isFalse);
    },
  );

  test('volume and sourced news alter the score only when provided', () {
    const calculator = MarketPulseCalculator();
    final data = series([100, 102, 103, 104, 106], volume: true);
    final priceAndVolume = calculator.calculate(data, now: now);
    final withNews = calculator.calculate(data, newsTone: -5, now: now);
    expect(priceAndVolume.hasVolume, isTrue);
    expect(priceAndVolume.hasNews, isFalse);
    expect(withNews.hasNews, isTrue);
    expect(withNews.score, lessThan(priceAndVolume.score!));
  });

  test('sparse, stale and unordered history cannot produce a score', () {
    const calculator = MarketPulseCalculator();
    expect(
      calculator.calculate(series([100, 101, 102]), now: now).score,
      isNull,
    );
    expect(
      calculator
          .calculate(series([100, 101, 102, 103], stale: true), now: now)
          .score,
      isNull,
    );
    expect(
      calculator
          .calculate(series([100, 101, 102, 103], reverseTime: true), now: now)
          .score,
      isNull,
    );
    expect(
      calculator
          .calculate(
            series([100, 101, 102, 103]),
            now: now.add(const Duration(hours: 9)),
          )
          .score,
      isNull,
    );
  });

  test('an invalid explicit coverage policy cannot produce a score', () {
    const calculator = MarketPulseCalculator();
    expect(
      calculator
          .calculate(
            series([100, 101, 102, 103]),
            now: now,
            minimumObservedSpan: Duration.zero,
          )
          .score,
      isNull,
    );
  });
}
