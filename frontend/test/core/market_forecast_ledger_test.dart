import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/market_forecast.dart';
import 'package:goldbrain/core/market_forecast_ledger.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 8, 18, 12);

  MarketForecast forecast(int index) => MarketForecast(
    id: 'forecast-$index',
    symbol: 'GOLD18',
    horizon: MarketForecastHorizon.oneHour,
    direction: MarketForecastDirection.upward,
    generatedAt: generatedAt.add(Duration(minutes: index * 15)),
    targetFor: generatedAt.add(Duration(minutes: (index * 15) + 60)),
    anchorPrice: 100,
    pointEstimate: 102,
    lowerBound: 99,
    upperBound: 104,
    unit: 'IRT',
    confidenceScore: 70,
    dataQualityPercent: 80,
    evidencePointCount: 20,
    evidenceFingerprint: 'evidence-$index',
    sources: const <String>['verified-outcome'],
    historyRange: 'oneHour',
    sourceLatestAt: generatedAt,
  );

  MarketIntelligenceInput outcomeInput() => MarketIntelligenceInput(
    languageCode: 'persian',
    quotes: const <IntelligenceQuoteEvidence>[],
    news: const <IntelligenceNewsEvidence>[],
    histories: <IntelligenceHistoryEvidence>[
      IntelligenceHistoryEvidence(
        symbol: 'GOLD18',
        unit: 'IRT',
        source: '  VERIFIED-OUTCOME  ',
        range: 'oneHour',
        points: List<IntelligenceHistoryPoint>.generate(
          240,
          (index) => IntelligenceHistoryPoint(
            time: generatedAt.add(Duration(minutes: 50 + index)),
            close: 102.5,
          ),
        ),
      ),
    ],
    collectedAt: generatedAt.add(const Duration(hours: 5)),
  );

  test('evaluates only after target using same-unit exact source data', () {
    final ledger = MarketForecastLedger()..add(forecast(0));

    expect(ledger.evaluate(outcomeInput()), 1);

    final outcome = ledger.records.single.outcome!;
    expect(outcome.actualSource, '  VERIFIED-OUTCOME  ');
    expect(outcome.actualPrice, 102.5);
    expect(outcome.absoluteError, 0.5);
    expect(outcome.directionHit, isTrue);
    expect(outcome.intervalHit, isTrue);
  });

  test('proxy or mismatched-unit data can never evaluate an outcome', () {
    final ledger = MarketForecastLedger()..add(forecast(0));
    final wrong = outcomeInput();
    final input = MarketIntelligenceInput(
      languageCode: wrong.languageCode,
      quotes: wrong.quotes,
      news: wrong.news,
      collectedAt: generatedAt.add(const Duration(minutes: 70)),
      histories: <IntelligenceHistoryEvidence>[
        IntelligenceHistoryEvidence(
          symbol: 'GOLD18',
          unit: 'USD',
          source: 'proxy',
          range: 'oneHour',
          isProxy: true,
          points: wrong.histories.single.points,
        ),
      ],
    );

    expect(ledger.evaluate(input), 0);
    expect(ledger.records.single.outcome, isNull);
  });

  test('rejects look-ahead points and observations before the target', () {
    final ledger = MarketForecastLedger()..add(forecast(0));
    final input = MarketIntelligenceInput(
      languageCode: 'persian',
      quotes: const <IntelligenceQuoteEvidence>[],
      news: const <IntelligenceNewsEvidence>[],
      histories: <IntelligenceHistoryEvidence>[
        IntelligenceHistoryEvidence(
          symbol: 'GOLD18',
          unit: 'IRT',
          source: 'verified-outcome',
          range: 'oneHour',
          points: <IntelligenceHistoryPoint>[
            IntelligenceHistoryPoint(
              time: generatedAt.add(const Duration(minutes: 59)),
              close: 102,
            ),
            IntelligenceHistoryPoint(
              time: generatedAt.add(const Duration(minutes: 65)),
              close: 103,
            ),
          ],
        ),
      ],
      // The post-target point above has not happened at collection time.
      collectedAt: generatedAt.add(const Duration(minutes: 62)),
    );

    expect(ledger.evaluate(input), 0);
    expect(ledger.records.single.outcome, isNull);
  });

  test('a different exact provider regime cannot score the forecast', () {
    final ledger = MarketForecastLedger()..add(forecast(0));
    final original = outcomeInput();
    final input = MarketIntelligenceInput(
      languageCode: original.languageCode,
      quotes: original.quotes,
      news: original.news,
      collectedAt: original.collectedAt,
      histories: <IntelligenceHistoryEvidence>[
        IntelligenceHistoryEvidence(
          symbol: 'GOLD18',
          unit: 'IRT',
          source: 'different-provider',
          range: 'oneHour',
          points: original.histories.single.points,
        ),
      ],
    );

    expect(ledger.evaluate(input), 0);
  });

  test('metrics stay hidden until ten evaluated outcomes', () {
    final ledger = MarketForecastLedger();
    for (var index = 0; index < 10; index++) {
      ledger.add(forecast(index));
    }

    expect(ledger.evaluate(outcomeInput()), 10);
    final metrics = ledger.metricsFor('GOLD18', MarketForecastHorizon.oneHour)!;
    expect(metrics.sampleCount, 10);
    expect(metrics.isDisplayReady, isTrue);
    expect(metrics.meanAbsoluteError, 0.5);
    expect(metrics.directionalHitRate, 100);
    expect(metrics.intervalHitRate, 100);
  });

  test('JSON round-trip keeps validated records', () {
    final ledger = MarketForecastLedger()..add(forecast(0));
    ledger.evaluate(outcomeInput());

    final restored = MarketForecastLedger.fromJson(ledger.toJson());

    expect(restored.records, hasLength(1));
    expect(restored.records.single.forecast.id, 'forecast-0');
    expect(restored.records.single.outcome?.actualPrice, 102.5);
  });

  test('24h pending checkpoint survives high-frequency ledger pressure', () {
    final dayForecast = MarketForecast(
      id: 'day-checkpoint',
      symbol: 'GOLD18',
      horizon: MarketForecastHorizon.twentyFourHours,
      direction: MarketForecastDirection.upward,
      generatedAt: generatedAt,
      targetFor: generatedAt.add(const Duration(hours: 24)),
      anchorPrice: 100,
      pointEstimate: 102,
      lowerBound: 95,
      upperBound: 108,
      unit: 'IRT',
      confidenceScore: 70,
      dataQualityPercent: 80,
      evidencePointCount: 20,
      evidenceFingerprint: 'day-evidence',
      sources: const <String>['verified-outcome'],
      historyRange: 'oneWeek',
      sourceLatestAt: generatedAt,
    );
    final ledger = MarketForecastLedger()..add(dayForecast);
    for (var index = 0; index < 1500; index++) {
      ledger.add(
        MarketForecast(
          id: 'pressure-$index',
          symbol: 'XAU',
          horizon: MarketForecastHorizon.oneHour,
          direction: MarketForecastDirection.upward,
          generatedAt: generatedAt.add(Duration(minutes: index * 15)),
          targetFor: generatedAt.add(Duration(minutes: (index * 15) + 60)),
          anchorPrice: 100,
          pointEstimate: 101,
          lowerBound: 98,
          upperBound: 103,
          unit: 'USD',
          confidenceScore: 65,
          dataQualityPercent: 75,
          evidencePointCount: 12,
          evidenceFingerprint: 'pressure-evidence-$index',
          sources: const <String>['source'],
          historyRange: 'oneHour',
          sourceLatestAt: generatedAt.add(Duration(minutes: index * 15)),
        ),
      );
    }

    expect(
      ledger.records.any((record) => record.forecast.id == 'day-checkpoint'),
      isTrue,
    );
  });

  test('unresolved forecasts expire after their honest outcome window', () {
    final ledger = MarketForecastLedger();
    for (var index = 0; index < 200; index++) {
      ledger.add(forecast(index));
    }
    final input = MarketIntelligenceInput(
      languageCode: 'persian',
      quotes: const <IntelligenceQuoteEvidence>[],
      news: const <IntelligenceNewsEvidence>[],
      histories: const <IntelligenceHistoryEvidence>[],
      collectedAt: generatedAt.add(const Duration(days: 4)),
    );

    expect(ledger.evaluate(input), 0);
    expect(ledger.records, isEmpty);
  });

  test('restore rejects invalid quality, method and outcome provenance', () {
    final valid = forecast(0).toJson();
    final invalidQuality = <String, Object?>{...valid, 'dataQualityPercent': 0};
    final invalidMethod = <String, Object?>{...valid, 'methodVersion': 0};
    expect(MarketForecast.fromJson(invalidQuality), isNull);
    expect(MarketForecast.fromJson(invalidMethod), isNull);

    final record = <String, Object?>{
      'forecast': valid,
      'outcome': <String, Object?>{
        'actualAt': generatedAt.add(const Duration(hours: 1)).toIso8601String(),
        'actualPrice': 102.5,
        'actualSource': 'wrong-source',
        'absoluteError': 0.5,
        'absolutePercentageError': 0.5 / 102.5 * 100,
        'directionHit': true,
        'intervalHit': true,
      },
    };
    expect(MarketForecastRecord.fromJson(record), isNull);

    final inflated = <String, Object?>{
      'forecast': valid,
      'outcome': <String, Object?>{
        'actualAt': generatedAt.add(const Duration(hours: 1)).toIso8601String(),
        'actualPrice': 98,
        'actualSource': 'verified-outcome',
        'absoluteError': 4,
        'absolutePercentageError': 4 / 98 * 100,
        // An upward forecast with an actual fall cannot be a direction hit.
        'directionHit': true,
        'intervalHit': false,
      },
    };
    expect(MarketForecastRecord.fromJson(inflated), isNull);

    final unsupported = <String, Object?>{...valid, 'symbol': 'FAKE'};
    expect(MarketForecast.fromJson(unsupported), isNull);
  });
}
