import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';
import 'package:goldbrain/core/market_intelligence_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  MarketIntelligenceInput allAssetsInput(String language) {
    const units = <String, String>{
      'GOLD18': 'IRT',
      'XAU': 'USD',
      'XAG': 'USD',
      'USD': 'IRT',
      'USDT': 'IRT',
      'BTC': 'USDT',
      'ETH': 'USDT',
    };
    const historyUnits = <String, String>{
      'GOLD18': 'IRT',
      'XAU': 'USD',
      'XAG': 'USD',
      'USD': 'IRT',
      'USDT': 'IRT',
      'BTC': 'USD',
      'ETH': 'USD',
    };
    const prices = <String, double>{
      'GOLD18': 19100000,
      'XAU': 4383,
      'XAG': 65.5,
      'USD': 187500,
      'USDT': 187700,
      'BTC': 64000,
      'ETH': 1875,
    };
    return MarketIntelligenceInput(
      languageCode: language,
      collectedAt: DateTime.utc(2026, 8, 10, 20),
      quotes: MarketIntelligenceStore.supportedSymbols
          .map(
            (symbol) => IntelligenceQuoteEvidence(
              symbol: symbol,
              price: prices[symbol]!,
              unit: units[symbol]!,
              updatedAt: DateTime.utc(2026, 8, 10, 19, 59),
              source: 'verified-live-$symbol',
            ),
          )
          .toList(growable: false),
      news: <IntelligenceNewsEvidence>[
        IntelligenceNewsEvidence(
          id: 'market-news-1',
          title: 'طلا نقره دلار اونس بیت کوین و اتریوم',
          summary: 'گزارش منبع‌دار از شرایط دارایی‌های اصلی بازار.',
          publishedAt: DateTime.utc(2026, 8, 10, 19),
          source: 'test-news',
        ),
      ],
      histories: MarketIntelligenceStore.supportedSymbols
          .map((symbol) {
            final price = prices[symbol]!;
            final historyBase = symbol == 'BTC' || symbol == 'ETH'
                ? price * 0.995
                : price;
            return IntelligenceHistoryEvidence(
              symbol: symbol,
              unit: historyUnits[symbol]!,
              source: 'verified-history-$symbol',
              points: List<IntelligenceHistoryPoint>.generate(
                16,
                (index) => IntelligenceHistoryPoint(
                  time: DateTime.utc(
                    2026,
                    8,
                    10,
                    4,
                  ).add(Duration(hours: index)),
                  close: historyBase * (0.995 + index * 0.0003),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  String persianBatchResponse([Iterable<String>? requested]) {
    final symbols = requested ?? MarketIntelligenceStore.supportedSymbols;
    return jsonEncode(<String, Object>{
      'reports': symbols
          .map(
            (symbol) => <String, Object?>{
              'symbol': symbol,
              'direction': 'neutral',
              'scenario_estimate_percent': 52,
              'forecast_target_price': null,
              'forecast_target_unit': null,
              'summary': 'شواهد منبع‌دار بازار در حال حاضر ترکیبی است.',
              'reasons': <String>[
                'روند قیمت و خبرها جهت کاملاً یکسانی ندارند.',
              ],
            },
          )
          .toList(growable: false),
    });
  }

  test('uses one batch call and stores a report for every asset', () async {
    var completionCalls = 0;
    final service = MarketIntelligenceService(
      clock: () => DateTime.utc(2026, 8, 10, 20),
      completion:
          ({
            required messages,
            required systemPrompt,
            required temperature,
          }) async {
            completionCalls++;
            return persianBatchResponse();
          },
    );
    final store = MarketIntelligenceStore(
      service: service,
      inputLoader: (language) async => allAssetsInput(language),
      clock: () => DateTime.utc(2026, 8, 10, 20),
    );

    await store.start(languageCode: 'persian');

    expect(completionCalls, 1);
    expect(store.loading, isFalse);
    expect(store.errorMessage, isNull);
    expect(store.reportsBySymbol, hasLength(7));
    expect(store.report?.symbol, 'GOLD18');
    expect(store.nextRefreshAt, isNotNull);
    expect(store.analysisInterval, const Duration(minutes: 10));
    store.dispose();
    service.close();
  });

  test(
    'selection and 5/10 minute interval form a stable UI contract',
    () async {
      final service = MarketIntelligenceService(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async => persianBatchResponse(),
      );
      final store = MarketIntelligenceStore(
        service: service,
        inputLoader: (language) async => allAssetsInput(language),
      );
      await store.start(languageCode: 'persian');

      store.selectSymbol('btc');
      store.setAnalysisInterval(const Duration(minutes: 5));

      expect(store.selectedSymbol, 'BTC');
      expect(store.reportFor('btc')?.symbol, 'BTC');
      expect(store.report?.symbol, 'BTC');
      expect(store.analysisInterval, const Duration(minutes: 5));

      store.setAnalysisInterval(const Duration(minutes: 7));
      expect(store.analysisInterval, const Duration(minutes: 10));
      store.dispose();
      service.close();
    },
  );

  test('overlapping refreshes share one in-flight batch request', () async {
    final response = Completer<String>();
    var completionCalls = 0;
    final service = MarketIntelligenceService(
      completion:
          ({required messages, required systemPrompt, required temperature}) {
            completionCalls++;
            return response.future;
          },
    );
    final store = MarketIntelligenceStore(
      service: service,
      inputLoader: (language) async => allAssetsInput(language),
    );
    store.updateLanguage('persian', refresh: false);

    final first = store.refreshAll(force: true);
    final second = store.refreshAll(force: true);
    await Future<void>.delayed(Duration.zero);
    expect(completionCalls, 1);

    response.complete(persianBatchResponse());
    await Future.wait<void>(<Future<void>>[first, second]);
    expect(completionCalls, 1);
    store.dispose();
    service.close();
  });

  test(
    'hides a cached report in another language and refreshes immediately',
    () async {
      final oldReport = MarketIntelligenceReport(
        symbol: 'GOLD18',
        direction: MarketScenarioDirection.upward,
        scenarioEstimatePercent: 60,
        summary: 'The old English market analysis is still cached.',
        reasons: const <String>['It must not appear in the Persian interface.'],
        generatedAt: DateTime.utc(2026, 8, 10, 19, 59),
        evidenceFingerprint: 'old',
        languageCode: 'english',
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'market_intelligence.reports_v2': jsonEncode(<String, Object?>{
          'GOLD18': oldReport.toJson(),
        }),
      });
      final called = Completer<void>();
      final response = Completer<String>();
      final service = MarketIntelligenceService(
        completion:
            ({required messages, required systemPrompt, required temperature}) {
              if (!called.isCompleted) called.complete();
              return response.future;
            },
      );
      final store = MarketIntelligenceStore(
        service: service,
        inputLoader: (language) async => allAssetsInput(language),
      );

      await store.start(languageCode: 'persian', refreshImmediately: false);
      await called.future;
      expect(store.report, isNull);

      response.complete(persianBatchResponse());
      await (() async {
        while (store.loading) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      })().timeout(const Duration(seconds: 2));
      expect(store.report?.languageCode, 'persian');
      expect(store.reportsBySymbol, hasLength(7));
      store.dispose();
      service.close();
    },
  );
}
