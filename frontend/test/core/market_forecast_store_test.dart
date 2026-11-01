import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/local_persistence_policy.dart';
import 'package:goldbrain/core/market_forecast.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';
import 'package:goldbrain/core/market_intelligence_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 8, 20, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalPersistencePolicy.instance.setSuspended(false);
  });

  tearDown(() {
    LocalPersistencePolicy.instance.setSuspended(false);
  });

  MarketIntelligenceInput evidence(DateTime at, {double offset = 0}) {
    List<IntelligenceHistoryPoint> points(
      int count,
      Duration gap,
      double step,
    ) => List<IntelligenceHistoryPoint>.generate(count, (index) {
      final remaining = count - 1 - index;
      return IntelligenceHistoryPoint(
        time: at.subtract(gap * remaining),
        close: 1000 * (1 + offset + (step * index)),
      );
    });
    return MarketIntelligenceInput(
      languageCode: 'persian',
      collectedAt: at,
      quotes: <IntelligenceQuoteEvidence>[
        IntelligenceQuoteEvidence(
          symbol: 'XAU',
          price: 1011 + (offset * 1000),
          unit: 'USD',
          updatedAt: at,
          source: 'verified-live',
        ),
      ],
      news: const <IntelligenceNewsEvidence>[],
      histories: <IntelligenceHistoryEvidence>[
        IntelligenceHistoryEvidence(
          symbol: 'XAU',
          unit: 'USD',
          source: 'verified-1h',
          range: 'oneHour',
          points: points(13, const Duration(minutes: 5), 0.0008),
        ),
        IntelligenceHistoryEvidence(
          symbol: 'XAU',
          unit: 'USD',
          source: 'verified-24h',
          range: 'oneDay',
          points: points(25, const Duration(hours: 1), 0.00045),
        ),
        IntelligenceHistoryEvidence(
          symbol: 'XAU',
          unit: 'USD',
          source: 'verified-7d',
          range: 'oneWeek',
          points: points(8, const Duration(days: 1), 0.0015),
        ),
      ],
    );
  }

  Map<String, Object> cachedReports() => <String, Object>{
    'market_intelligence.reports_v2': jsonEncode(<String, Object?>{
      for (final symbol in MarketIntelligenceStore.supportedSymbols)
        symbol: MarketIntelligenceReport(
          symbol: symbol,
          direction: MarketScenarioDirection.neutral,
          summary: 'گزارش قبلی معتبر بازار.',
          reasons: const <String>['داده‌های معتبر بررسی شده‌اند.'],
          generatedAt: now,
          evidenceFingerprint: 'cached-$symbol',
          languageCode: 'persian',
        ).toJson(),
    }),
  };

  MarketIntelligenceService noAiService() => MarketIntelligenceService(
    completion:
        ({required messages, required systemPrompt, required temperature}) =>
            throw StateError('deterministic refresh must not call AI'),
  );

  test('refreshes all deterministic horizons without an AI request', () async {
    SharedPreferences.setMockInitialValues(cachedReports());
    var current = evidence(now);
    final service = noAiService();
    final store = MarketIntelligenceStore(
      service: service,
      inputLoader: (_) async => current,
      clock: () => current.collectedAt,
    );
    await store.start(languageCode: 'persian', refreshImmediately: false);

    await store.refreshForecasts();

    expect(
      store.forecastsFor('XAU').keys,
      containsAll(MarketForecastHorizon.values),
    );
    expect(
      store.forecastFor('XAU', MarketForecastHorizon.oneHour)?.targetFor,
      now.add(const Duration(hours: 1)),
    );
    expect(
      store.nextForecastRefreshAt,
      current.collectedAt.add(const Duration(minutes: 5)),
    );

    final firstFingerprint = store
        .forecastFor('XAU', MarketForecastHorizon.twelveHours)!
        .evidenceFingerprint;
    current = evidence(now.add(const Duration(minutes: 5)), offset: 0.0005);
    await store.refreshForecasts();
    expect(
      store
          .forecastFor('XAU', MarketForecastHorizon.twelveHours)!
          .evidenceFingerprint,
      isNot(firstFingerprint),
    );
    store.dispose();
    service.close();
  });

  test(
    'persists separately from reports_v2 and restores active targets',
    () async {
      SharedPreferences.setMockInitialValues(cachedReports());
      final service = noAiService();
      final first = MarketIntelligenceStore(
        service: service,
        inputLoader: (_) async => evidence(now),
        clock: () => now,
      );
      await first.start(languageCode: 'persian', refreshImmediately: false);
      await first.refreshForecasts();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('market_forecast.active_v1'), isNotNull);
      expect(preferences.getString('market_forecast.ledger_v1'), isNotNull);
      expect(
        preferences.getString('market_intelligence.reports_v2'),
        isNotNull,
      );
      first.dispose();

      final restored = MarketIntelligenceStore(
        service: service,
        inputLoader: (_) async => evidence(now),
        clock: () => now,
      );
      await restored.start(languageCode: 'persian', refreshImmediately: false);
      expect(
        restored.forecastFor('XAU', MarketForecastHorizon.twentyFourHours),
        isNotNull,
      );
      restored.dispose();
      service.close();
    },
  );

  test('retention suspension keeps forecasts memory-only', () async {
    SharedPreferences.setMockInitialValues(cachedReports());
    LocalPersistencePolicy.instance.setSuspended(true);
    final service = noAiService();
    final store = MarketIntelligenceStore(
      service: service,
      inputLoader: (_) async => evidence(now),
      clock: () => now,
    );
    await store.start(languageCode: 'persian', refreshImmediately: false);
    await store.refreshForecasts();

    expect(store.forecastsFor('XAU'), isNotEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('market_forecast.active_v1'), isNull);
    expect(preferences.getString('market_forecast.ledger_v1'), isNull);
    store.dispose();
    service.close();
  });

  test('restore rejects a forecast generated far in the future', () async {
    final generatedAt = now.add(const Duration(days: 365));
    final corruptFuture = MarketForecast(
      id: 'future-forecast',
      symbol: 'XAU',
      horizon: MarketForecastHorizon.twelveHours,
      direction: MarketForecastDirection.upward,
      generatedAt: generatedAt,
      targetFor: generatedAt.add(const Duration(hours: 12)),
      anchorPrice: 1000,
      pointEstimate: 1010,
      lowerBound: 980,
      upperBound: 1030,
      unit: 'USD',
      confidenceScore: 60,
      dataQualityPercent: 75,
      evidencePointCount: 20,
      evidenceFingerprint: 'future-evidence',
      sources: const <String>['verified-future-source'],
      historyRange: 'oneDay',
      sourceLatestAt: generatedAt,
    );
    final validCurrent = MarketForecast(
      id: 'current-forecast',
      symbol: 'XAU',
      horizon: MarketForecastHorizon.oneHour,
      direction: MarketForecastDirection.upward,
      generatedAt: now,
      targetFor: now.add(const Duration(hours: 1)),
      anchorPrice: 1000,
      pointEstimate: 1005,
      lowerBound: 990,
      upperBound: 1020,
      unit: 'USD',
      confidenceScore: 60,
      dataQualityPercent: 75,
      evidencePointCount: 20,
      evidenceFingerprint: 'current-evidence',
      sources: const <String>['verified-current-source'],
      historyRange: 'oneHour',
      sourceLatestAt: now,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      ...cachedReports(),
      'market_forecast.active_v1': jsonEncode(<String, Object?>{
        'XAU': <String, Object?>{
          '1h': validCurrent.toJson(),
          '12h': corruptFuture.toJson(),
        },
      }),
    });
    final service = noAiService();
    final store = MarketIntelligenceStore(
      service: service,
      inputLoader: (_) async => evidence(now),
      clock: () => now,
    );

    await store.start(languageCode: 'persian', refreshImmediately: false);

    expect(store.forecastFor('XAU', MarketForecastHorizon.twelveHours), isNull);
    store.dispose();
    service.close();
  });

  test(
    'an older overlapping AI evidence load cannot replace a newer forecast',
    () async {
      SharedPreferences.setMockInitialValues(cachedReports());
      final olderLoad = Completer<MarketIntelligenceInput>();
      final newerLoad = Completer<MarketIntelligenceInput>();
      var loadCount = 0;
      final service = MarketIntelligenceService(
        clock: () => now.add(const Duration(minutes: 5)),
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async => jsonEncode(<String, Object>{
              'reports': <Object>[
                <String, Object?>{
                  'symbol': 'XAU',
                  'direction': 'neutral',
                  'scenario_estimate_percent': 52,
                  'forecast_target_price': null,
                  'forecast_target_unit': null,
                  'summary':
                      'Verified market evidence was reviewed for this scenario.',
                  'reasons': <String>[
                    'Verified price history was used in the analysis.',
                  ],
                },
              ],
            }),
      );
      final store = MarketIntelligenceStore(
        service: service,
        inputLoader: (_) {
          loadCount++;
          return loadCount == 1 ? olderLoad.future : newerLoad.future;
        },
        clock: () => now.add(const Duration(minutes: 5)),
      );
      final aiRefresh = store.refresh(force: true, symbols: const {'XAU'});
      expect(loadCount, 1);
      final deterministicRefresh = store.refreshForecasts();
      expect(loadCount, 2);

      newerLoad.complete(
        evidence(now.add(const Duration(minutes: 5)), offset: 0.0005),
      );
      await deterministicRefresh;
      expect(
        store
            .forecastFor('XAU', MarketForecastHorizon.twelveHours)
            ?.generatedAt,
        now.add(const Duration(minutes: 5)),
      );

      olderLoad.complete(evidence(now));
      await aiRefresh;
      expect(
        store
            .forecastFor('XAU', MarketForecastHorizon.twelveHours)
            ?.generatedAt,
        now.add(const Duration(minutes: 5)),
      );

      store.dispose();
      service.close();
    },
  );
}
