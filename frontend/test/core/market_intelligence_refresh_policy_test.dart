import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';
import 'package:goldbrain/core/market_intelligence_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('OpenRouter free auto analysis is never scheduled below 60 minutes', () {
    final service = _RecordingIntelligenceService(freeRouter: true);
    final store = MarketIntelligenceStore(
      service: service,
      analysisInterval: const Duration(minutes: 5),
    );

    expect(
      store.analysisInterval,
      MarketIntelligenceStore.freeRouterMinimumAnalysisInterval,
    );
    expect(store.availableAnalysisIntervals, const <Duration>[
      Duration(minutes: 60),
    ]);

    store.setAnalysisInterval(const Duration(minutes: 5));
    expect(store.analysisInterval, const Duration(minutes: 60));
    store.dispose();
    service.close();
  });

  test('migrates a persisted 5 minute free-router interval to 60', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'market_intelligence.interval_minutes_v1': 5,
    });
    final service = _RecordingIntelligenceService(freeRouter: true);
    final store = MarketIntelligenceStore(
      service: service,
      inputLoader: (_) async => _input(),
    );

    await store.start(languageCode: 'persian');

    expect(store.analysisInterval, const Duration(minutes: 60));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt('market_intelligence.interval_minutes_v1'), 60);

    store.dispose();
    service.close();
  });

  test(
    'unchanged evidence skips automatic AI calls but manual force runs',
    () async {
      var now = DateTime.utc(2026, 8, 13, 10);
      final input = _input();
      final service = _RecordingIntelligenceService();
      final store = MarketIntelligenceStore(
        service: service,
        inputLoader: (_) async => input,
        analysisInterval: const Duration(minutes: 10),
        clock: () => now,
      );

      await store.start(languageCode: 'persian');
      expect(service.calls, 1);

      now = now.add(const Duration(minutes: 11));
      await store.refreshAll();
      expect(service.calls, 1);

      await store.refreshAll(force: true);
      expect(service.calls, 2);

      store.dispose();
      service.close();
    },
  );
}

MarketIntelligenceInput _input() => MarketIntelligenceInput(
  languageCode: 'persian',
  quotes: <IntelligenceQuoteEvidence>[
    IntelligenceQuoteEvidence(
      symbol: 'GOLD18',
      price: 20000000,
      unit: 'IRT',
      updatedAt: DateTime.utc(2026, 8, 13, 9, 59),
      source: 'verified-test',
    ),
  ],
  news: const <IntelligenceNewsEvidence>[],
  collectedAt: DateTime.utc(2026, 8, 13, 10),
);

class _RecordingIntelligenceService extends MarketIntelligenceService {
  _RecordingIntelligenceService({this.freeRouter = false})
    : super(
        completion:
            ({
              required messages,
              required systemPrompt,
              required temperature,
            }) async => '{}',
      );

  final bool freeRouter;
  int calls = 0;

  @override
  bool get usesRateLimitedFreeRouter => freeRouter;

  @override
  Future<MarketIntelligenceBatchResult> analyzeBatch(
    MarketIntelligenceInput input, {
    Iterable<String> symbols = supportedIntelligenceSymbols,
  }) async {
    calls++;
    final reports = <String, MarketIntelligenceReport>{};
    for (final rawSymbol in symbols) {
      final symbol = rawSymbol.toUpperCase();
      reports[symbol] = MarketIntelligenceReport(
        symbol: symbol,
        direction: MarketScenarioDirection.neutral,
        summary: 'شواهد معتبر بازار هنوز ترکیبی است.',
        reasons: const <String>['داده‌های منبع‌دار بررسی شدند.'],
        generatedAt: input.collectedAt,
        evidenceFingerprint: input.evidenceFingerprintFor(symbol),
        languageCode: input.languageCode,
      );
    }
    return MarketIntelligenceBatchResult(
      reports: reports,
      issues: const <String, MarketIntelligenceAssetIssue>{},
    );
  }
}
