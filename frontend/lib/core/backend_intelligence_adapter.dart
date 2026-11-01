import 'backend_api_client.dart';
import 'backend_types.dart';
import 'market_forecast.dart';
import 'market_intelligence_service.dart';

/// Maps persisted server predictions into the original animated UI models.
/// This adapter never calculates a target, confidence, or a trading signal.
class BackendIntelligenceAdapter {
  BackendIntelligenceAdapter(this.api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final GoldBrainBackendClient api;
  final DateTime Function() _clock;

  Future<BackendForecastEvidence> forecast(
    String symbol,
    MarketForecastHorizon horizon, {
    bool generateIfMissing = false,
  }) async {
    var value = await api.latestForecast(symbol, horizon.wireName);
    if (generateIfMissing &&
        (value == null || !value.targetAt.isAfter(_clock().toUtc()))) {
      value = await api.generateForecast(
        symbol: symbol,
        horizon: horizon.wireName,
        timeframe: '1h',
      );
    }
    if (value == null) {
      throw const MarketIntelligenceException(
        'insufficient_evidence',
        'The server has not published a forecast for this asset and horizon.',
      );
    }
    return evidence(value);
  }

  Future<BackendForecastEvidence> evidence(BackendForecast value) async {
    final quotes = await api.fetchQuotes([value.symbol]);
    final quote = quotes.quotes[value.symbol];
    if (quote == null || !quoteIsFresh(quote, now: _clock())) {
      throw const MarketIntelligenceException(
        'stale_evidence',
        'A fresh, timestamped server quote is required for this forecast.',
      );
    }
    final candles = await _verifiedCandles(
      value.symbol,
      value.timeframe,
      quoteProvider: quote.provider,
    );
    final unit = verifiedForecastCurrency(value, candles);
    final eligibleCandles = candles
        .where((row) => !row.closedAt.isAfter(value.generatedAt))
        .toList(growable: false);
    if (unit == null ||
        quote.currency != unit ||
        eligibleCandles.isEmpty ||
        !value.targetAt.isAfter(_clock().toUtc()) ||
        value.generatedAt.isAfter(_clock().toUtc())) {
      throw const MarketIntelligenceException(
        'insufficient_evidence',
        'The forecast currency, source, anchor or target time could not be verified.',
      );
    }
    return BackendForecastEvidence(value, eligibleCandles, unit);
  }

  /// Forecasts are generated from the worker's normalized quote candles. The
  /// live quote provider can be Wallex, Navasan, or another upstream source,
  /// so asking for that provider's candles would incorrectly hide valid
  /// server history. Prefer the normalized worker series and only fall back to
  /// the live provider when it has explicitly persisted matching candles.
  Future<List<BackendCandle>> _verifiedCandles(
    String symbol,
    String timeframe, {
    String? quoteProvider,
  }) async {
    final providers = <String>['quote-collector'];
    final normalizedQuoteProvider = quoteProvider?.trim().toLowerCase();
    if (normalizedQuoteProvider != null &&
        normalizedQuoteProvider.isNotEmpty &&
        !providers.contains(normalizedQuoteProvider)) {
      providers.add(normalizedQuoteProvider);
    }
    for (final provider in providers) {
      try {
        final candles = await api.candles(
          symbol,
          timeframe,
          provider: provider,
        );
        if (candles.isNotEmpty) return candles;
      } on FormatException {
        // A mixed or malformed provider series is not usable evidence; try
        // the next explicitly named source instead of guessing a value.
      }
    }
    return const <BackendCandle>[];
  }

  Future<MarketIntelligenceReport> analyze(
    String symbol,
    String language,
  ) async {
    final response = BackendAnalysis.fromJson(
      await api.deepAnalysis(
        symbol: symbol,
        horizon: '12h',
        timeframe: '1h',
        language: backendLanguage(language),
      ),
    );
    final value = response.forecast;
    if (value.symbol != symbol || value.horizon != '12h') {
      throw const FormatException('Deep-analysis identity mismatch');
    }
    final sourced = await evidence(value);
    final eligible = value.paperEligible;
    return MarketIntelligenceReport(
      symbol: symbol,
      direction: eligible
          ? switch (value.direction) {
              'upward' => MarketScenarioDirection.upward,
              'downward' => MarketScenarioDirection.downward,
              _ => MarketScenarioDirection.neutral,
            }
          : MarketScenarioDirection.insufficientData,
      // The gauge is a probability only after the server calibrated it.
      scenarioEstimatePercent:
          eligible && value.calibrationStatus == 'calibrated'
          ? ((value.direction == 'downward'
                        ? 1 - value.probabilityUp
                        : value.probabilityUp) *
                    100)
                .round()
          : null,
      summary: response.narrative?.trim().isNotEmpty == true
          ? response.narrative!
          : response.summary,
      reasons: List.unmodifiable([
        ...value.decisionReasons,
        ...value.reasons,
        response.bullish,
        response.bearish,
        ...response.invalidation,
        for (final article in response.news)
          '${article.source} · ${article.publishedAt.toIso8601String()} · ${article.title} · ${article.url}',
      ]),
      generatedAt: value.generatedAt,
      evidenceFingerprint: 'backend:${value.forecastId}',
      languageCode: language,
      forecastTargetPrice: eligible ? value.pointEstimate : null,
      forecastTargetSymbol: eligible ? symbol : null,
      forecastTargetUnit: eligible ? sourced.unit : null,
      forecastHorizonHours: 12,
      evidenceQualityPercent: value.dataQuality,
      historyPointCount: sourced.candles.length,
      relevantNewsCount: response.news.length,
    );
  }

  Future<MarketForecastMetrics?> metrics(
    String symbol,
    MarketForecastHorizon horizon,
    String unit,
  ) async {
    final value = await api.metrics(symbol, horizon.wireName);
    // Missing values are never turned into a zero error or a success rate.
    if (value.mae == null ||
        value.mape == null ||
        value.directionalAccuracy == null ||
        value.intervalAccuracy == null) {
      return null;
    }
    return MarketForecastMetrics(
      sampleCount: value.independentSamples,
      meanAbsoluteError: value.mae!,
      meanAbsolutePercentageError: value.mape!,
      directionalHitRate: value.directionalAccuracy!,
      intervalHitRate: value.intervalAccuracy!,
      unit: unit,
    );
  }
}

class BackendForecastEvidence {
  const BackendForecastEvidence(this.value, this.candles, this.unit);
  final BackendForecast value;
  final List<BackendCandle> candles;
  final String unit;

  MarketForecast? get displayForecast {
    final horizon = MarketForecastHorizonX.parse(value.horizon);
    if (horizon == null || !value.paperEligible) return null;
    return MarketForecast(
      id: value.forecastId,
      symbol: value.symbol,
      horizon: horizon,
      direction: switch (value.direction) {
        'upward' => MarketForecastDirection.upward,
        'downward' => MarketForecastDirection.downward,
        _ => MarketForecastDirection.neutral,
      },
      generatedAt: value.generatedAt,
      targetFor: value.targetAt,
      anchorPrice: value.anchorPrice,
      pointEstimate: value.pointEstimate,
      lowerBound: value.lowerBound,
      upperBound: value.upperBound,
      unit: unit,
      confidenceScore: value.confidenceScore,
      dataQualityPercent: value.dataQuality,
      evidencePointCount: candles.length,
      evidenceFingerprint: 'backend:${value.forecastId}',
      sources: List.unmodifiable(candles.map((row) => row.provider).toSet()),
      historyRange: value.timeframe,
      sourceLatestAt: candles.last.closedAt,
      // Backend currently computes an 80% interval (1.2816 * uncertainty).
      intervalLevel: 0.80,
      methodVersion: 2,
    );
  }
}

String backendLanguage(String language) =>
    const {
      'english': 'en',
      'persian': 'fa',
      'japanese': 'ja',
      'russian': 'ru',
      'chinese': 'zh',
      'arabic': 'ar',
      'turkish': 'tr',
      'french': 'fr',
    }[language] ??
    language;
