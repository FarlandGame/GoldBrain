import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/currency_service.dart';
import 'package:goldbrain/core/gapgpt_service.dart';
import 'package:goldbrain/core/market_forecast.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';
import 'package:goldbrain/core/market_intelligence_store.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/widgets/deep_market_analysis_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'compact RTL card selects every asset and a five-minute interval without overflow',
    (tester) async {
      // Keep this interaction test independent from the developer machine's
      // persisted OpenRouter configuration. The free router deliberately
      // exposes only the truthful 60-minute automatic interval.
      final aiService = GapGptService(
        apiKey: 'test-key',
        baseUrl: 'https://api.gapgpt.app/v1',
        model: 'gpt-4o-mini',
      );
      final intelligenceService = MarketIntelligenceService(
        aiService: aiService,
      );
      final store = MarketIntelligenceStore(service: intelligenceService);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: Center(
                child: SizedBox(
                  width: 330,
                  child: DeepMarketAnalysisCard(
                    palette: themePalettes[GoldBrainTheme.white]!,
                    language: GoldBrainLanguage.persian,
                    store: store,
                    densityScale: 0.78,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('deep-analysis-asset-menu')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('deep-analysis-asset-menu')));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(7));
      await tester.tap(find.text('بیت‌کوین').last);
      await tester.pumpAndSettle();
      expect(store.selectedSymbol, 'BTC');

      await tester.tap(
        find.byKey(const ValueKey('deep-analysis-interval-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('هر 5 دقیقه').last);
      await tester.pumpAndSettle();
      expect(store.analysisInterval, const Duration(minutes: 5));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      intelligenceService.close();
      aiService.close();
    },
  );

  testWidgets('reduced motion disables the score animation', (tester) async {
    final store = MarketIntelligenceStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Center(
              child: SizedBox(
                width: 420,
                child: DeepMarketAnalysisCard(
                  palette: themePalettes[GoldBrainTheme.black]!,
                  language: GoldBrainLanguage.english,
                  store: store,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final animation = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('analysis-gauge-animation')),
    );
    expect(animation.duration, Duration.zero);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('free-router card truthfully shows a 60-minute auto interval', (
    tester,
  ) async {
    final aiService = GapGptService(
      apiKey: 'test-key',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'openrouter/free',
    );
    final intelligenceService = MarketIntelligenceService(aiService: aiService);
    final store = MarketIntelligenceStore(
      service: intelligenceService,
      analysisInterval: const Duration(minutes: 5),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            child: DeepMarketAnalysisCard(
              palette: themePalettes[GoldBrainTheme.black]!,
              language: GoldBrainLanguage.persian,
              store: store,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('خودکار 60د · پلن رایگان'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('deep-analysis-interval-menu')));
    await tester.pumpAndSettle();
    expect(find.text('هر 60 دقیقه'), findsOneWidget);
    expect(find.text('هر 5 دقیقه'), findsNothing);
    expect(find.text('هر 10 دقیقه'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    intelligenceService.close();
    aiService.close();
  });

  testWidgets('cached report from another language is never rendered', (
    tester,
  ) async {
    final englishReport = MarketIntelligenceReport(
      symbol: 'GOLD18',
      direction: MarketScenarioDirection.upward,
      scenarioEstimatePercent: 74,
      summary: 'ENGLISH-CACHE-MUST-NOT-APPEAR',
      reasons: const <String>['English cached reason'],
      generatedAt: DateTime.utc(2026, 8, 11, 12),
      evidenceFingerprint: 'cached-evidence',
      languageCode: 'english',
      forecastTargetPrice: 19200000,
      forecastTargetSymbol: 'GOLD18',
      forecastTargetUnit: 'IRT',
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'market_intelligence.reports_v2': jsonEncode(<String, Object?>{
        'GOLD18': englishReport.toJson(),
      }),
    });
    final store = MarketIntelligenceStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: SizedBox(
                width: 440,
                child: DeepMarketAnalysisCard(
                  palette: themePalettes[GoldBrainTheme.white]!,
                  language: GoldBrainLanguage.persian,
                  store: store,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('ENGLISH-CACHE-MUST-NOT-APPEAR'), findsNothing);
    expect(find.byKey(const ValueKey('start-deep-analysis')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets(
    'compact card exposes source-backed horizons, direction and bounded metrics',
    (tester) async {
      final generatedAt = DateTime.now().toUtc();
      MarketForecast forecast(
        MarketForecastHorizon horizon,
        MarketForecastDirection direction, {
        DateTime? at,
        String? id,
      }) {
        final anchor = 20000000.0;
        final point = switch (direction) {
          MarketForecastDirection.upward => 20200000.0,
          MarketForecastDirection.downward => 19800000.0,
          MarketForecastDirection.neutral => 20000000.0,
        };
        final createdAt = at ?? generatedAt;
        return MarketForecast(
          id: id ?? 'widget-${horizon.wireName}',
          symbol: 'GOLD18',
          horizon: horizon,
          direction: direction,
          generatedAt: createdAt,
          targetFor: createdAt.add(horizon.duration),
          anchorPrice: anchor,
          pointEstimate: point,
          lowerBound: 19200000,
          upperBound: 20800000,
          unit: 'IRT',
          confidenceScore: 68,
          dataQualityPercent: 82,
          evidencePointCount: 25,
          evidenceFingerprint: 'widget-${horizon.wireName}-${createdAt.hour}',
          sources: const <String>['verified-widget-history'],
          historyRange: horizon == MarketForecastHorizon.oneHour
              ? 'oneHour'
              : horizon == MarketForecastHorizon.twelveHours
              ? 'oneDay'
              : 'oneWeek',
          sourceLatestAt: createdAt,
        );
      }

      final active = <MarketForecastHorizon, MarketForecast>{
        MarketForecastHorizon.oneHour: forecast(
          MarketForecastHorizon.oneHour,
          MarketForecastDirection.downward,
        ),
        MarketForecastHorizon.twelveHours: forecast(
          MarketForecastHorizon.twelveHours,
          MarketForecastDirection.upward,
        ),
        MarketForecastHorizon.twentyFourHours: forecast(
          MarketForecastHorizon.twentyFourHours,
          MarketForecastDirection.neutral,
        ),
      };
      final evaluated = List<MarketForecastRecord>.generate(10, (index) {
        final createdAt = generatedAt.subtract(Duration(days: index + 2));
        final item = forecast(
          MarketForecastHorizon.twelveHours,
          MarketForecastDirection.upward,
          at: createdAt,
          id: 'evaluated-$index',
        );
        const actualPrice = 20200000.0;
        final error = (actualPrice - item.pointEstimate).abs();
        return MarketForecastRecord(
          forecast: item,
          outcome: MarketForecastOutcome(
            actualAt: item.targetFor,
            actualPrice: actualPrice,
            actualSource: item.sources.first,
            absoluteError: error,
            absolutePercentageError: error / actualPrice * 100,
            directionHit: true,
            intervalHit: true,
          ),
        );
      });
      SharedPreferences.setMockInitialValues(<String, Object>{
        'market_intelligence.reports_v2': jsonEncode(<String, Object?>{
          for (final symbol in MarketIntelligenceStore.supportedSymbols)
            symbol: MarketIntelligenceReport(
              symbol: symbol,
              direction: MarketScenarioDirection.neutral,
              scenarioEstimatePercent: 52,
              summary: 'Verified AI narrative kept separate from the model.',
              reasons: const <String>['Verified evidence was reviewed.'],
              generatedAt: generatedAt,
              evidenceFingerprint: 'widget-report-$symbol',
              languageCode: 'english',
            ).toJson(),
        }),
        'market_forecast.active_v1': jsonEncode(<String, Object?>{
          'GOLD18': <String, Object?>{
            for (final entry in active.entries)
              entry.key.wireName: entry.value.toJson(),
          },
        }),
        'market_forecast.ledger_v1': jsonEncode(
          evaluated.map((record) => record.toJson()).toList(growable: false),
        ),
      });
      final store = MarketIntelligenceStore();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 330,
              child: DeepMarketAnalysisCard(
                palette: themePalettes[GoldBrainTheme.white]!,
                language: GoldBrainLanguage.english,
                store: store,
                densityScale: 0.78,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('UP model scenario'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('deep-analysis-forecast-interval')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('deep-analysis-forecast-provenance')),
        findsOneWidget,
      );
      expect(find.textContaining('direction hit 100%'), findsOneWidget);
      expect(find.textContaining('10000%'), findsNothing);
      final initialLayoutError = tester.takeException();
      expect(initialLayoutError, isNull, reason: 'initial 12h layout');

      await tester.tap(
        find.byKey(const ValueKey('deep-analysis-forecast-horizon-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 hour').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('DOWN model scenario'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '1h layout');

      await tester.tap(
        find.byKey(const ValueKey('deep-analysis-forecast-horizon-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('24-hour observed-price scenario').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('24-hour scenario near the observation'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: '24h layout');

      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  testWidgets('forecast target follows the selected display currency', (
    tester,
  ) async {
    CurrencyService.updateIranianTomanPerUsd(200000);
    final generatedAt = DateTime.now().toUtc();
    final report = MarketIntelligenceReport(
      symbol: 'GOLD18',
      direction: MarketScenarioDirection.upward,
      scenarioEstimatePercent: 64,
      summary: 'Verified upward test scenario.',
      reasons: const <String>['Aligned test indicators.'],
      generatedAt: generatedAt,
      evidenceFingerprint: 'target-currency-test',
      languageCode: 'english',
      forecastTargetPrice: 20000000,
      forecastTargetSymbol: 'GOLD18',
      forecastTargetUnit: 'IRT',
    );
    final forecast = MarketForecast(
      id: 'widget-currency-forecast',
      symbol: 'GOLD18',
      horizon: MarketForecastHorizon.twelveHours,
      direction: MarketForecastDirection.upward,
      generatedAt: generatedAt,
      targetFor: generatedAt.add(const Duration(hours: 12)),
      anchorPrice: 19000000,
      pointEstimate: 20000000,
      lowerBound: 18500000,
      upperBound: 21500000,
      unit: 'IRT',
      confidenceScore: 65,
      dataQualityPercent: 78,
      evidencePointCount: 25,
      evidenceFingerprint: 'widget-currency-evidence',
      sources: const <String>['verified-widget-history'],
      historyRange: 'oneDay',
      sourceLatestAt: generatedAt,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.currency_code': 'USD',
      'settings.language_code': 'english',
      'settings.ai_signals_enabled': false,
      'market_intelligence.reports_v2': jsonEncode(<String, Object?>{
        'GOLD18': report.toJson(),
      }),
      'market_forecast.active_v1': jsonEncode(<String, Object?>{
        'GOLD18': <String, Object?>{'12h': forecast.toJson()},
      }),
    });
    await SettingsStore.instance.load();
    final store = MarketIntelligenceStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 520,
            child: DeepMarketAnalysisCard(
              palette: themePalettes[GoldBrainTheme.black]!,
              language: GoldBrainLanguage.english,
              store: store,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining(r'GOLD18  100.00 $'), findsOneWidget);
    expect(find.textContaining('IRT'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
