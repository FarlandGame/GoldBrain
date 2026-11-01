import 'backend_api_client.dart';

const mvpSymbols = ['GOLD18', 'USDT', 'BTC'];

double? paperQuotePrice(BackendMarketQuote? quote, String currency) {
  if (quote == null) return null;
  String canonical(String c) => ['TMN', 'TOMAN'].contains(c) ? 'IRT' : c;
  final source = canonical(quote.currency), target = canonical(currency);
  if (source == target) return quote.price;
  if (source == 'IRR' && target == 'IRT') return quote.price / 10;
  if (source == 'IRT' && target == 'IRR') return quote.price * 10;
  return null;
}

/// Only unconditional MVP horizons are enabled. Conditional 4h USDT and 7d
/// GOLD18 require a future server capability, not a client-side guess.
List<String> horizonsFor(String symbol) => switch (symbol) {
  'GOLD18' => const ['1h', '24h'],
  'USDT' => const ['15m', '1h', '24h'],
  'BTC' => const ['15m', '1h', '4h', '24h'],
  _ => const [],
};

// The backend worker persists completed 1m and 1h candles.
String timeframeFor(String horizon) => horizon == '15m' ? '1m' : '1h';

Map<String, dynamic> object(Object? value) {
  if (value is! Map<String, dynamic>)
    throw const FormatException('Expected object');
  return value;
}

String stringField(Map<String, dynamic> value, String key) {
  final result = value[key];
  if (result is! String || result.trim().isEmpty)
    throw FormatException('Invalid $key');
  return result.trim();
}

double numberField(
  Map<String, dynamic> value,
  String key, {
  bool positive = false,
}) {
  final raw = value[key];
  final result = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (result == null || !result.isFinite || (positive && result <= 0)) {
    throw FormatException('Invalid $key');
  }
  return result;
}

double? optionalNumber(Map<String, dynamic> value, String key) =>
    value[key] == null ? null : numberField(value, key);

DateTime dateField(Map<String, dynamic> value, String key) {
  final result = DateTime.tryParse(stringField(value, key));
  if (result == null || !result.isUtc)
    throw FormatException('Timestamp needs timezone: $key');
  return result.toUtc();
}

List<T> listField<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) throw const FormatException('Expected list');
  return List.unmodifiable(value.map((item) => parse(object(item))));
}

List<String> optionalStringList(Object? value) {
  if (value == null) return const <String>[];
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('Expected string list');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

class BackendCandle {
  BackendCandle.fromJson(Map<String, dynamic> json)
    : symbol = stringField(json, 'symbol'),
      timeframe = stringField(json, 'timeframe'),
      currency = stringField(json, 'currency'),
      provider = stringField(json, 'provider'),
      openedAt = dateField(json, 'opened_at'),
      closedAt = dateField(json, 'closed_at'),
      open = numberField(json, 'open', positive: true),
      high = numberField(json, 'high', positive: true),
      low = numberField(json, 'low', positive: true),
      close = numberField(json, 'close', positive: true),
      volume = optionalNumber(json, 'volume'),
      qualityFlags = optionalStringList(json['quality_flags']) {
    if (!closedAt.isAfter(openedAt) ||
        low > high ||
        low > open ||
        low > close ||
        high < open ||
        high < close ||
        (volume != null && volume! < 0)) {
      throw const FormatException('Invalid OHLC candle');
    }
  }
  final String symbol, timeframe, currency, provider;
  final DateTime openedAt, closedAt;
  final double open, high, low, close;
  final double? volume;
  final List<String> qualityFlags;
}

class BackendPriceSample {
  BackendPriceSample.fromJson(Map<String, dynamic> json)
    : symbol = stringField(json, 'symbol'),
      price = numberField(json, 'price', positive: true),
      currency = stringField(json, 'currency'),
      unit = stringField(json, 'unit'),
      market = stringField(json, 'market'),
      provider = stringField(json, 'provider'),
      providerTimestamp = dateField(json, 'provider_timestamp'),
      receivedAt = dateField(json, 'received_at'),
      freshnessStatus = stringField(json, 'freshness_status'),
      dataQualityStatus = stringField(json, 'data_quality_status'),
      qualityFlags = optionalStringList(json['quality_flags']);

  final String symbol, currency, unit, market, provider;
  final String freshnessStatus, dataQualityStatus;
  final double price;
  final DateTime providerTimestamp, receivedAt;
  final List<String> qualityFlags;
}

/// Forecasts currently omit currency. Only borrow a history unit when its
/// completed anchor candle matches the server forecast; otherwise withhold it.
String? verifiedForecastCurrency(
  BackendForecast forecast,
  List<BackendCandle> candles,
) {
  final evidence = candles.where(
    (c) =>
        c.symbol == forecast.symbol &&
        c.timeframe == forecast.timeframe &&
        !c.closedAt.isAfter(forecast.generatedAt),
  );
  if (evidence.isEmpty) return null;
  final anchor = evidence.last;
  if ((anchor.close - forecast.anchorPrice).abs() > forecast.anchorPrice * 1e-8)
    return null;
  if (evidence.any(
    (c) => c.currency != anchor.currency || c.provider != anchor.provider,
  ))
    return null;
  return anchor.currency;
}

class BackendMetrics {
  BackendMetrics.fromJson(Map<String, dynamic> json)
    : symbol = stringField(json, 'symbol'),
      horizon = stringField(json, 'horizon'),
      calibration = stringField(json, 'calibration_status'),
      samples = numberField(json, 'sample_count').toInt(),
      independentSamples = numberField(
        json,
        'independent_sample_count',
      ).toInt(),
      mae = optionalNumber(json, 'mean_absolute_error'),
      mape = optionalNumber(json, 'mean_absolute_percentage_error'),
      directionalAccuracy = optionalNumber(json, 'directional_hit_rate'),
      intervalAccuracy = optionalNumber(json, 'interval_hit_rate'),
      brier = optionalNumber(json, 'brier_score') {
    if (samples < 0 ||
        independentSamples < 0 ||
        independentSamples > samples ||
        [
          directionalAccuracy,
          intervalAccuracy,
        ].any((n) => n != null && (n < 0 || n > 100)) ||
        (brier != null && (brier! < 0 || brier! > 1)) ||
        [mae, mape].any((n) => n != null && n < 0)) {
      throw const FormatException('Invalid metrics');
    }
  }
  final String symbol, horizon, calibration;
  final int samples, independentSamples;
  final double? mae, mape, directionalAccuracy, intervalAccuracy, brier;
}

class BackendNewsArticle {
  BackendNewsArticle.fromJson(Map<String, dynamic> json)
    : id = stringField(json, 'article_id'),
      title = stringField(json, 'title'),
      summary = json['summary'] is String ? json['summary'] as String : '',
      source = stringField(json, 'source'),
      url = stringField(json, 'url'),
      publishedAt = dateField(json, 'published_at');
  final String id, title, summary, source, url;
  final DateTime publishedAt;
  Uri? get safeUri {
    final uri = Uri.tryParse(url);
    return uri != null &&
            ['https', 'http'].contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? uri
        : null;
  }
}

class BackendNews {
  BackendNews.fromJson(Map<String, dynamic> json)
    : articles = listField(json['articles'], BackendNewsArticle.fromJson),
      fetchedAt = dateField(json, 'fetched_at'),
      sourceErrors = Map<String, dynamic>.unmodifiable(
        object(json['source_errors']),
      );
  final List<BackendNewsArticle> articles;
  final DateTime fetchedAt;
  final Map<String, dynamic> sourceErrors;
}

class BackendAnalysis {
  BackendAnalysis.fromJson(Map<String, dynamic> json)
    : forecast =
          BackendForecast.fromJson(json['forecast']) ??
          (throw const FormatException('Invalid forecast')),
      summary = stringField(json, 'scenario_summary'),
      bullish = stringField(json, 'bullish_scenario'),
      bearish = stringField(json, 'bearish_scenario'),
      invalidation = (json['invalidation_factors'] as List).cast<String>(),
      news = listField(json['relevant_news'], BackendNewsArticle.fromJson),
      narrative = json['ai_narrative'] as String?;
  final BackendForecast forecast;
  final String summary, bullish, bearish;
  final List<String> invalidation;
  final List<BackendNewsArticle> news;
  final String? narrative;
}

class BackendDevice {
  BackendDevice.fromJson(Map<String, dynamic> json)
    : id = stringField(json, 'session_id'),
      name = stringField(json, 'device_name'),
      current = json['current'] == true,
      lastSeen = dateField(json, 'last_seen_at'),
      expiresAt = dateField(json, 'expires_at');
  final String id, name;
  final bool current;
  final DateTime lastSeen, expiresAt;
}

class BackendAlert {
  BackendAlert.fromJson(Map<String, dynamic> json)
    : id = stringField(json, 'alert_id'),
      symbol = stringField(json, 'symbol'),
      condition = stringField(json, 'condition'),
      threshold = numberField(json, 'threshold', positive: true),
      enabled = json['enabled'] == true,
      triggeredAt = json['last_triggered_at'] == null
          ? null
          : dateField(json, 'last_triggered_at');
  final String id, symbol, condition;
  final double threshold;
  final bool enabled;
  final DateTime? triggeredAt;
}

class BackendPosition {
  BackendPosition.fromJson(Map<String, dynamic> json)
    : symbol = stringField(json, 'symbol'),
      quantity = numberField(json, 'quantity', positive: true),
      averagePrice = numberField(json, 'average_entry_price', positive: true);
  final String symbol;
  final double quantity, averagePrice;
}

class BackendTrade {
  BackendTrade.fromJson(Map<String, dynamic> json)
    : id = stringField(json, 'trade_id'),
      symbol = stringField(json, 'symbol'),
      side = stringField(json, 'side'),
      quantity = numberField(json, 'quantity', positive: true),
      price = numberField(json, 'price', positive: true),
      fee = numberField(json, 'fee'),
      realizedPnl = numberField(json, 'realized_pnl'),
      executedAt = dateField(json, 'executed_at'),
      reason = json['reason'] as String?,
      forecastId = json['forecast_id'] as String?;
  final String id, symbol, side;
  final double quantity, price, fee, realizedPnl;
  final DateTime executedAt;
  final String? reason, forecastId;
}

class BackendPortfolio {
  BackendPortfolio.fromJson(Map<String, dynamic> json)
    : name = stringField(object(json['account']), 'name'),
      currency = stringField(object(json['account']), 'base_currency'),
      initialBalance = numberField(
        object(json['account']),
        'initial_balance',
        positive: true,
      ),
      cash = numberField(object(json['account']), 'cash_balance'),
      positions = listField(json['positions'], BackendPosition.fromJson),
      trades = listField(json['recent_trades'], BackendTrade.fromJson);
  final String name, currency;
  final double initialBalance, cash;
  final List<BackendPosition> positions;
  final List<BackendTrade> trades;
}

bool quoteIsFresh(BackendMarketQuote quote, {DateTime? now}) {
  final age = (now ?? DateTime.now().toUtc()).difference(quote.updatedAt);
  // Conservative UI guard pending a per-market freshness capability.
  return !age.isNegative && age <= const Duration(minutes: 5);
}

class BackendDataStatus {
  BackendDataStatus.fromJson(Map<String, dynamic> json)
    : symbol = stringField(json, 'symbol'),
      status = stringField(json, 'status'),
      observedAt = json['observed_at'] == null
          ? null
          : dateField(json, 'observed_at'),
      ageSeconds = optionalNumber(json, 'age_seconds')?.toInt() {
    if (!['fresh', 'stale', 'missing'].contains(status) ||
        (ageSeconds != null && ageSeconds! < 0))
      throw const FormatException('Invalid data status');
  }
  final String symbol, status;
  final DateTime? observedAt;
  final int? ageSeconds;
}

class BackendOverview {
  BackendOverview.fromJson(Map<String, dynamic> json)
    : generatedAt = dateField(json, 'generated_at') {
    final rows = json['assets'];
    if (rows is! List) throw const FormatException('Missing overview assets');
    for (final item in rows) {
      final row = object(item);
      final symbol = stringField(row, 'symbol');
      if (!mvpSymbols.contains(symbol)) continue;
      if (statuses.containsKey(symbol))
        throw const FormatException('Duplicate overview asset');
      final status = BackendDataStatus.fromJson(object(row['data_status']));
      if (status.symbol != symbol)
        throw const FormatException('Data status mismatch');
      statuses[symbol] = status;
      if (row['quote'] != null) {
        final quote = BackendMarketQuote.fromJson(row['quote']);
        if (quote == null || quote.symbol != symbol)
          throw const FormatException('Invalid overview quote');
        quotes[symbol] = quote;
      }
      // Overview's forecast summary currently omits horizon/timeframe. Do not
      // mislabel it as 1h; the UI reads /forecast/latest with explicit filters.
    }
  }
  final DateTime generatedAt;
  final Map<String, BackendMarketQuote> quotes = {};
  final Map<String, BackendDataStatus> statuses = {};
}

class BackendGoldContext {
  BackendGoldContext.fromJson(Map<String, dynamic> json)
    : goldPrice = numberField(json, 'gold18_price', positive: true),
      impliedPrice = numberField(json, 'implied_gold18_price', positive: true),
      premium = numberField(json, 'premium_percent'),
      state = stringField(json, 'premium_state'),
      ouncePrice = numberField(json, 'gold_ounce_price', positive: true),
      tetherPrice = numberField(json, 'tether_price', positive: true),
      observedAt = dateField(json, 'observed_at');
  final double goldPrice, impliedPrice, premium, ouncePrice, tetherPrice;
  final String state;
  final DateTime observedAt;
  String? verifiedCurrency(BackendOverview overview) {
    final gold = overview.quotes['GOLD18'], tether = overview.quotes['USDT'];
    if (gold == null ||
        tether == null ||
        gold.currency != tether.currency ||
        overview.statuses['GOLD18']?.status != 'fresh' ||
        overview.statuses['USDT']?.status != 'fresh' ||
        !quoteIsFresh(gold) ||
        !quoteIsFresh(tether) ||
        (gold.price - goldPrice).abs() > goldPrice * .000001 ||
        (tether.price - tetherPrice).abs() > tetherPrice * .000001 ||
        DateTime.now().toUtc().difference(observedAt).isNegative ||
        DateTime.now().toUtc().difference(observedAt) >
            const Duration(minutes: 5))
      return null;
    return gold.currency;
  }
}
