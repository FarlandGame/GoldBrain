import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/market_forecast.dart';
import 'package:goldbrain/core/market_forecast_engine.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);

  MarketIntelligenceInput input({
    bool includeOneHour = true,
    bool includeOneDay = true,
    bool includeOneWeek = true,
    bool proxyWeek = false,
    Duration latestOffset = Duration.zero,
    double quotePrice = 1011,
  }) {
    List<IntelligenceHistoryPoint> points({
      required int count,
      required Duration gap,
      required double step,
    }) => List<IntelligenceHistoryPoint>.generate(count, (index) {
      final fromLatest = count - 1 - index;
      return IntelligenceHistoryPoint(
        time: now.subtract(latestOffset).subtract(gap * fromLatest),
        close: 1000 * (1 + (step * index)),
      );
    });

    return MarketIntelligenceInput(
      languageCode: 'persian',
      quotes: <IntelligenceQuoteEvidence>[
        IntelligenceQuoteEvidence(
          symbol: 'XAU',
          price: quotePrice,
          unit: 'USD',
          updatedAt: now.subtract(const Duration(minutes: 2)),
          source: 'live-source',
        ),
      ],
      news: const <IntelligenceNewsEvidence>[],
      histories: <IntelligenceHistoryEvidence>[
        if (includeOneHour)
          IntelligenceHistoryEvidence(
            symbol: 'XAU',
            unit: 'USD',
            source: 'exact-1h',
            range: 'oneHour',
            points: points(
              count: 13,
              gap: const Duration(minutes: 5),
              step: 0.0008,
            ),
          ),
        if (includeOneDay)
          IntelligenceHistoryEvidence(
            symbol: 'XAU',
            unit: 'USD',
            source: 'exact-24h',
            range: 'oneDay',
            points: points(
              count: 25,
              gap: const Duration(hours: 1),
              step: 0.00045,
            ),
          ),
        if (includeOneWeek)
          IntelligenceHistoryEvidence(
            symbol: 'XAU',
            unit: 'USD',
            source: 'exact-7d',
            range: 'oneWeek',
            isProxy: proxyWeek,
            points: points(
              count: 8,
              gap: const Duration(days: 1),
              step: 0.0015,
            ),
          ),
      ],
      collectedAt: now,
    );
  }

  test('builds independent 1h, 12h and 24h source-backed forecasts', () {
    const engine = MarketForecastEngine();

    final forecasts = engine.generateForSymbol(input(), 'XAU');

    expect(forecasts.keys, containsAll(MarketForecastHorizon.values));
    for (final entry in forecasts.entries) {
      final forecast = entry.value;
      expect(forecast.targetFor, now.add(entry.key.duration));
      expect(forecast.lowerBound, lessThanOrEqualTo(forecast.pointEstimate));
      expect(forecast.upperBound, greaterThanOrEqualTo(forecast.pointEstimate));
      expect(forecast.intervalLevel, 0.80);
      expect(forecast.sources, isNotEmpty);
      expect(forecast.dataQualityPercent, inInclusiveRange(50, 100));
      expect(forecast.confidenceScore, lessThanOrEqualTo(85));
      expect(forecast.unit, 'USD');
    }
    expect(forecasts[MarketForecastHorizon.oneHour]!.historyRange, 'oneHour');
    expect(
      forecasts[MarketForecastHorizon.twelveHours]!.historyRange,
      'oneDay',
    );
    expect(
      forecasts[MarketForecastHorizon.twentyFourHours]!.historyRange,
      'oneWeek',
    );
  });

  test('missing short history removes only the 1h horizon', () {
    const engine = MarketForecastEngine();

    final forecasts = engine.generateForSymbol(
      input(includeOneHour: false),
      'XAU',
    );

    expect(forecasts, isNot(contains(MarketForecastHorizon.oneHour)));
    expect(forecasts, contains(MarketForecastHorizon.twelveHours));
    expect(forecasts, contains(MarketForecastHorizon.twentyFourHours));
  });

  test('never creates a 24h numerical target from proxy history', () {
    const engine = MarketForecastEngine();

    final forecasts = engine.generateForSymbol(input(proxyWeek: true), 'XAU');

    expect(forecasts, isNot(contains(MarketForecastHorizon.twentyFourHours)));
    expect(forecasts, contains(MarketForecastHorizon.oneHour));
  });

  test('fails closed for stale evidence instead of extrapolating it', () {
    const engine = MarketForecastEngine();

    final forecasts = engine.generateForSymbol(
      input(latestOffset: const Duration(days: 5)),
      'XAU',
    );

    expect(forecasts, isEmpty);
  });

  test('fails closed when a fresh same-unit quote diverges from history', () {
    const engine = MarketForecastEngine();

    final forecasts = engine.generateForSymbol(input(quotePrice: 1120), 'XAU');

    expect(forecasts, isEmpty);
  });

  test('ignores future points and empty provenance', () {
    const engine = MarketForecastEngine();
    final evidence = input();
    final futureHistory = IntelligenceHistoryEvidence(
      symbol: 'XAU',
      unit: 'USD',
      source: '',
      range: 'oneHour',
      points: <IntelligenceHistoryPoint>[
        IntelligenceHistoryPoint(
          time: now.add(const Duration(minutes: 1)),
          close: 5000,
        ),
        IntelligenceHistoryPoint(
          time: now.add(const Duration(minutes: 2)),
          close: 9000,
        ),
      ],
    );
    final augmented = MarketIntelligenceInput(
      languageCode: evidence.languageCode,
      quotes: evidence.quotes,
      news: evidence.news,
      histories: <IntelligenceHistoryEvidence>[
        futureHistory,
        ...evidence.histories,
      ],
      collectedAt: evidence.collectedAt,
    );

    final forecasts = engine.generateForSymbol(augmented, 'XAU');

    expect(forecasts, isNotEmpty);
    expect(
      forecasts.values.every(
        (forecast) => forecast.sources.every((source) => source.isNotEmpty),
      ),
      isTrue,
    );
    expect(
      forecasts.values.every(
        (forecast) => !forecast.sourceLatestAt.isAfter(now),
      ),
      isTrue,
    );
  });

  test('same evidence yields deterministic values and fingerprints', () {
    const engine = MarketForecastEngine();
    final evidence = input();

    final first = engine.generateForSymbol(evidence, 'XAU');
    final second = engine.generateForSymbol(evidence, 'XAU');

    for (final horizon in MarketForecastHorizon.values) {
      expect(second[horizon]!.pointEstimate, first[horizon]!.pointEstimate);
      expect(
        second[horizon]!.evidenceFingerprint,
        first[horizon]!.evidenceFingerprint,
      );
    }
  });
}
