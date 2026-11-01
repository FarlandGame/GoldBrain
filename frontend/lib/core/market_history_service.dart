import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'market_history_persistent_cache.dart';
import 'backend_api_client.dart';
import 'backend_connection.dart';
import 'backend_types.dart';
import 'currency_service.dart';
import 'global_price_service.dart';
import '../screens/selection_screen.dart';

enum MarketHistoryRange { oneHour, oneDay, oneWeek, oneMonth }

enum MarketHistoryProvider {
  zarix,
  navasan,
  arzhaam,
  tgju,
  kraken,
  yahooFinance,
  localDevice,
  backend,
}

class MarketCandle {
  const MarketCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.isPriceSample = false,
    this.volume,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double? volume;

  /// A single observed price adapted for the existing line-chart painter.
  /// Its equal OHLC coordinates are display-only, not a provider OHLC bar.
  final bool isPriceSample;
}

class MarketHistorySeries {
  const MarketHistorySeries({
    required this.symbol,
    required this.currency,
    required this.range,
    required this.candles,
    required this.provider,
    required this.providerLabel,
    required this.fetchedAt,
    this.isProxy = false,
    this.isLocalHistory = false,
    this.isPriceSample = false,
    this.isStale = false,
  });

  final String symbol;
  final String currency;
  final MarketHistoryRange range;
  final List<MarketCandle> candles;
  final MarketHistoryProvider provider;
  final String providerLabel;
  final DateTime fetchedAt;

  /// True when the chart is a transparent market proxy (COMEX futures), not
  /// the exact spot instrument used by the current-price provider.
  final bool isProxy;
  final bool isLocalHistory;
  final bool isPriceSample;
  final bool isStale;

  bool get hasDisallowedDomesticSource {
    final asset = symbol.trim().toUpperCase();
    if (asset != 'USD' && asset != 'EUR' && asset != 'GOLD18') {
      return false;
    }
    final label = providerLabel.toLowerCase();
    if (provider == MarketHistoryProvider.zarix || label.contains('zarix')) {
      return true;
    }
    // Old quote aggregates in the device cache do not retain their source
    // tick IDs, so their domestic provenance cannot be revalidated offline.
    if (label.contains('quote-collector')) return true;
    return asset == 'GOLD18' &&
        (label.contains('persian-toolbox') || label.contains('persiantoolbox'));
  }

  Duration get observedSpan => candles.length < 2
      ? Duration.zero
      : candles.last.time.difference(candles.first.time);

  Duration get requestedSpan => switch (range) {
    MarketHistoryRange.oneHour => const Duration(hours: 1),
    MarketHistoryRange.oneDay => const Duration(days: 1),
    MarketHistoryRange.oneWeek => const Duration(days: 7),
    MarketHistoryRange.oneMonth => const Duration(days: 30),
  };

  double get observedCoverageRatio {
    if (requestedSpan.inMilliseconds <= 0) return 0;
    return (observedSpan.inMilliseconds / requestedSpan.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  /// The chart always uses the timestamps actually returned or recorded.
  /// A sparse local series is never stretched across the requested range.
  ({DateTime start, DateTime end}) get actualTimeDomain {
    if (candles.isEmpty) return (start: fetchedAt, end: fetchedAt);
    return (start: candles.first.time, end: candles.last.time);
  }

  MarketHistorySeries withStaleState(bool value) => MarketHistorySeries(
    symbol: symbol,
    currency: currency,
    range: range,
    candles: candles,
    provider: provider,
    providerLabel: providerLabel,
    fetchedAt: fetchedAt,
    isProxy: isProxy,
    isLocalHistory: isLocalHistory,
    isPriceSample: isPriceSample,
    isStale: value,
  );

  MarketHistorySeries asStale() => withStaleState(true);

  /// Applies one FX snapshot to every OHLC value. Missing rates keep the
  /// original currency and values, so a chart is never falsely relabeled.
  ({
    MarketHistorySeries series,
    bool conversionStale,
    bool conversionUnavailable,
  })
  forDisplay({
    required String selectedCode,
    required GoldBrainLanguage language,
  }) {
    final conversion = CurrencyService.convertForDisplay(
      value: 1,
      sourceCode: currency,
      selectedCode: selectedCode,
      language: language,
    );
    if (conversion.unavailable) {
      return (
        series: this,
        conversionStale: false,
        conversionUnavailable: true,
      );
    }
    if (conversion.currencyCode == currency) {
      return (
        series: this,
        conversionStale: false,
        conversionUnavailable: false,
      );
    }
    final factor = conversion.value;
    return (
      series: MarketHistorySeries(
        symbol: symbol,
        currency: conversion.currencyCode,
        range: range,
        candles: List.unmodifiable(
          candles.map(
            (candle) => MarketCandle(
              time: candle.time,
              open: candle.open * factor,
              high: candle.high * factor,
              low: candle.low * factor,
              close: candle.close * factor,
              isPriceSample: candle.isPriceSample,
              volume: candle.volume,
            ),
          ),
        ),
        provider: provider,
        providerLabel: providerLabel,
        fetchedAt: fetchedAt,
        isProxy: isProxy,
        isLocalHistory: isLocalHistory,
        isPriceSample: isPriceSample,
        isStale: isStale,
      ),
      conversionStale: conversion.isStale,
      conversionUnavailable: false,
    );
  }
}

class MarketHistoryException implements Exception {
  const MarketHistoryException(this.message, {this.unavailable = false});

  final String message;
  final bool unavailable;

  @override
  String toString() => message;
}

class MarketHistoryService {
  MarketHistoryService({
    http.Client? client,
    GoldBrainBackendClient? backend,
    this.cacheDuration = const Duration(minutes: 1),
    // The free Navasan plan refreshes upstream data every two hours and has a
    // very small monthly quota. Keep verified domestic history for the same
    // interval so automatic UI refreshes do not burn that quota for identical
    // data. Premium callers can inject a shorter duration explicitly.
    this.domesticCacheDuration = const Duration(hours: 2),
    this.timeout = const Duration(seconds: 12),
    String? navasanApiKey,
    Uri? navasanEndpoint,
    String? arzhaamApiKey,
    Uri? arzhaamEndpoint,
    Uri? zarixEndpoint,
    Uri? krakenEndpoint,
    Uri? yahooBaseUri,
    MarketHistoryPersistentCache? persistentCache,
    this.allowPublicDomesticFallback = false,
  }) : _client = client ?? http.Client(),
       _backend =
           backend ??
           (client == null &&
                   navasanApiKey == null &&
                   navasanEndpoint == null &&
                   arzhaamApiKey == null &&
                   arzhaamEndpoint == null &&
                   zarixEndpoint == null &&
                   krakenEndpoint == null &&
                   yahooBaseUri == null
               ? BackendConnection.instance.api
               : null),
       _ownsClient = client == null,
       _navasanApiKey = (navasanApiKey ?? '').trim(),
       _navasanEndpoint =
           navasanEndpoint ?? Uri.parse('https://api.navasan.tech/'),
       _arzhaamApiKey = (arzhaamApiKey ?? '').trim(),
       _arzhaamEndpoint = arzhaamEndpoint ?? Uri.parse('https://arzhaam.ir/'),
       _zarixEndpoint = zarixEndpoint ?? Uri.parse('https://zarix.online/api/'),
       _krakenEndpoint =
           krakenEndpoint ?? Uri.parse('https://api.kraken.com/0/public/OHLC'),
       _yahooBaseUri =
           yahooBaseUri ??
           Uri.parse('https://query2.finance.yahoo.com/v8/finance/chart/'),
       _persistentCache = persistentCache ?? MarketHistoryPersistentCache();

  static const supportedSymbols = GlobalPriceService.supportedSymbols;

  static const domesticSymbols = {'USD', 'EUR', 'GOLD18'};

  static const _navasanSymbols = {'USD': 'usd_sell', 'GOLD18': '18ayar'};

  static final Map<String, ({List<MarketCandle> candles, DateTime fetchedAt})>
  _navasanDayCache =
      <String, ({List<MarketCandle> candles, DateTime fetchedAt})>{};

  static final Map<String, Future<List<MarketCandle>>> _navasanDayInFlight =
      <String, Future<List<MarketCandle>>>{};

  static final Map<String, ({List<MarketCandle> candles, DateTime fetchedAt})>
  _navasanOhlcCache =
      <String, ({List<MarketCandle> candles, DateTime fetchedAt})>{};

  static final Map<String, Future<List<MarketCandle>>> _navasanOhlcInFlight =
      <String, Future<List<MarketCandle>>>{};

  static const _arzhaamSymbols = {'USD': 'usd', 'GOLD18': 'gold_18'};

  static final _tgjuHistoryUris = <String, Uri>{
    'USD': Uri.parse(
      'https://english.tgju.org/profile/price_dollar_rl/history',
    ),
    'GOLD18': Uri.parse('https://english.tgju.org/profile/geram18/history'),
  };

  static const _zarixSymbols = {
    'XAU': 'XAUUSD',
    'XAG': 'XAGUSD',
    'BTC': 'BTCUSD',
    'ETH': 'ETHUSD',
  };

  static const _krakenPairs = {'BTC': 'XBTUSD', 'ETH': 'ETHUSD'};

  static const _yahooMetalSymbols = {'XAU': 'GC=F', 'XAG': 'SI=F'};

  final http.Client _client;
  final GoldBrainBackendClient? _backend;
  final bool _ownsClient;
  final Duration cacheDuration;
  final Duration domesticCacheDuration;
  final Duration timeout;
  final bool allowPublicDomesticFallback;
  final String _navasanApiKey;
  final Uri _navasanEndpoint;
  final String _arzhaamApiKey;
  final Uri _arzhaamEndpoint;
  final Uri _zarixEndpoint;
  final Uri _krakenEndpoint;
  final Uri _yahooBaseUri;
  final MarketHistoryPersistentCache _persistentCache;
  final Map<String, ({MarketHistorySeries series, DateTime fetchedAt})> _cache =
      {};

  bool isHistoryConfiguredFor(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
  }) {
    final normalized = symbol.trim().toUpperCase();
    if (_backend != null) {
      return RegExp(r'^[A-Z0-9]{2,15}$').hasMatch(normalized);
    }
    if (!supportedSymbols.contains(normalized)) return false;
    if (!domesticSymbols.contains(normalized)) return true;
    if (normalized == 'EUR' || range == MarketHistoryRange.oneMonth) {
      return false;
    }
    return _navasanApiKey.isNotEmpty ||
        _arzhaamApiKey.isNotEmpty ||
        (allowPublicDomesticFallback && range == MarketHistoryRange.oneWeek);
  }

  Future<MarketHistorySeries> fetchHistory(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
    bool forceRefresh = false,
  }) async {
    final normalized = symbol.trim().toUpperCase();
    final supported = _backend != null
        ? RegExp(r'^[A-Z0-9]{2,15}$').hasMatch(normalized)
        : supportedSymbols.contains(normalized);
    if (!supported) {
      throw MarketHistoryException(
        'No verified historical source is available for $normalized.',
        unavailable: true,
      );
    }
    if (_backend != null) {
      return _fetchBackendHistory(
        normalized,
        range,
        forceRefresh: forceRefresh,
      );
    }

    final cacheKey = '$normalized:${range.name}';
    final cached = _cache[cacheKey];
    final isDomestic = domesticSymbols.contains(normalized);
    final effectiveCacheDuration = isDomestic
        ? domesticCacheDuration
        : cacheDuration;
    // A force refresh may bypass ordinary/global history caches. Domestic
    // Navasan data is deliberately still rate-limited because several UI and
    // intelligence owners can request it independently every minute.
    if (cached != null &&
        !cached.series.hasDisallowedDomesticSource &&
        DateTime.now().difference(cached.fetchedAt) < effectiveCacheDuration &&
        (!forceRefresh || isDomestic)) {
      return cached.series;
    }

    if (isDomestic) {
      final persisted = await _persistentCache.get(normalized, range: range);
      if (persisted != null &&
          DateTime.now().difference(persisted.fetchedAt) <
              effectiveCacheDuration) {
        // Reusing a recent provider response must not erase source staleness:
        // e.g. a TGJU daily session can be older than 48h even though the HTTP
        // response itself was cached only minutes ago.
        _cache[cacheKey] = (series: persisted, fetchedAt: persisted.fetchedAt);
        return persisted;
      }
    }

    final failures = <String>[];
    if (isDomestic) {
      if (normalized == 'EUR' || range == MarketHistoryRange.oneMonth) {
        final stale = await _staleFallback(cacheKey, normalized, range);
        if (stale != null) return stale;
        throw MarketHistoryException(
          'The direct-provider adapter has no verified ${range.name} history for $normalized.',
          unavailable: true,
        );
      }
      if (_navasanApiKey.isNotEmpty && _navasanEndpoint.scheme != 'https') {
        throw const MarketHistoryException(
          'Navasan history requires an HTTPS endpoint so the API key is not sent in clear text.',
          unavailable: true,
        );
      }
      // Prefer Navasan when the account has historical access. Intraday views
      // use exact dailyCurrency ticks; 7D uses the official one-request OHLC
      // endpoint. Raw responses are shared across chart/intelligence owners.
      if (_navasanApiKey.isNotEmpty) {
        try {
          final result = await _fetchNavasan(normalized, range);
          await _cacheResult(cacheKey, result);
          return result;
        } on MarketHistoryException catch (error) {
          failures.add(error.message);
        }
      }

      // Arzhaam is an optional JSON history fallback when ARZHAAM_API_KEY is
      // configured. Its 7d endpoint can provide a dense series without HTML
      // scraping.
      if (_arzhaamApiKey.isNotEmpty) {
        try {
          final result = await _fetchArzhaam(normalized, range);
          await _cacheResult(cacheKey, result);
          return result;
        } on MarketHistoryException catch (error) {
          failures.add(error.message);
        }
      }

      // HTML history is intentionally opt-in. It is useful for installations
      // that have permission to consume it, but it must not silently replace
      // the licensed JSON source or trigger unexpected network requests.
      if (allowPublicDomesticFallback && range == MarketHistoryRange.oneWeek) {
        try {
          final result = await _fetchTgjuDailyHistory(normalized, range);
          await _cacheResult(cacheKey, result);
          return result;
        } on MarketHistoryException catch (error) {
          failures.add(error.message);
        }
      }

      final stale = await _staleFallback(cacheKey, normalized, range);
      if (stale != null) return stale;

      if (_navasanApiKey.isEmpty && _arzhaamApiKey.isEmpty) {
        throw const MarketHistoryException(
          'Verified Iranian intraday history is not configured. Set NAVASAN_API_KEY before launch; no chart points are generated.',
          unavailable: true,
        );
      }

      throw MarketHistoryException(
        failures.isEmpty
            ? 'No verified Iranian-market chart points are available for $normalized.'
            : failures.join(' '),
        unavailable: false,
      );
    }

    try {
      final result = await _fetchZarix(normalized, range);
      await _cacheResult(cacheKey, result);
      return result;
    } on MarketHistoryException catch (error) {
      failures.add(error.message);
    }

    if (_krakenPairs.containsKey(normalized)) {
      try {
        final result = await _fetchKraken(normalized, range);
        await _cacheResult(cacheKey, result);
        return result;
      } on MarketHistoryException catch (error) {
        failures.add(error.message);
      }
    }

    if (_yahooMetalSymbols.containsKey(normalized)) {
      try {
        final result = await _fetchYahooMetalProxy(normalized, range);
        await _cacheResult(cacheKey, result);
        return result;
      } on MarketHistoryException catch (error) {
        failures.add(error.message);
      }
    }

    final stale = await _staleFallback(cacheKey, normalized, range);
    if (stale != null) return stale;

    throw MarketHistoryException(
      failures.isEmpty
          ? 'No verified chart points are available for $normalized.'
          : failures.join(' '),
    );
  }

  Future<MarketHistorySeries> _fetchBackendHistory(
    String symbol,
    MarketHistoryRange range, {
    required bool forceRefresh,
  }) async {
    // Separate the backend cache from old direct-provider/device histories.
    final key = 'backend:$symbol:${range.name}';
    final stored = _cache[key];
    final cached = stored?.series.hasDisallowedDomesticSource == true
        ? null
        : stored;
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < cacheDuration) {
      return cached.series;
    }
    if (domesticSymbols.contains(symbol) &&
        range == MarketHistoryRange.oneDay) {
      try {
        final series = await _fetchBackendPriceSamples(symbol, range);
        _cache[key] = (series: series, fetchedAt: DateTime.now());
        return series;
      } on GoldBrainBackendException catch (error) {
        if (cached != null) return cached.series.asStale();
        throw MarketHistoryException(error.message);
      } on FormatException {
        if (cached != null) return cached.series.asStale();
        throw const MarketHistoryException(
          'GoldBrain returned invalid price samples.',
        );
      } on MarketHistoryException {
        if (cached != null) return cached.series.asStale();
        rethrow;
      }
    }
    try {
      String? provider;
      try {
        final quotes = await _backend!.fetchQuotes({symbol});
        provider = quotes.quotes[symbol]?.provider;
      } on GoldBrainBackendException {
        // Stored history remains usable if a current provider is unavailable.
        // The client rejects a mixed-provider candle response.
      }
      var timeframe = range == MarketHistoryRange.oneHour ? '1m' : '1h';
      final requiredFrom = range == MarketHistoryRange.oneHour
          ? null
          : DateTime.now().toUtc().subtract(_duration(range));
      late List<BackendCandle> response;
      try {
        response = await _fetchBackendCandles(
          symbol,
          timeframe,
          quoteProvider: provider,
          limit: range == MarketHistoryRange.oneMonth ? 750 : null,
          requiredFrom: requiredFrom,
        );
        if (response.length < 2) {
          throw MarketHistoryException(
            'GoldBrain has too few verified $symbol candles for this range.',
            unavailable: true,
          );
        }
      } on MarketHistoryException {
        if (!domesticSymbols.contains(symbol) ||
            (range != MarketHistoryRange.oneWeek &&
                range != MarketHistoryRange.oneMonth))
          rethrow;
        // Navasan documents daily OHLC, not hourly OHLC. Use its real daily
        // sessions only when a dense same-source intraday series is absent.
        timeframe = '1d';
        response = await _fetchBackendCandles(
          symbol,
          timeframe,
          quoteProvider: provider,
          limit: 40,
          requiredFrom: requiredFrom,
        );
      }
      final now = DateTime.now().toUtc();
      final cutoff = now.subtract(_duration(range));
      final rows = response
          .where((row) => !row.openedAt.isBefore(cutoff))
          .toList();
      if (rows.length < 2) {
        throw MarketHistoryException(
          'GoldBrain has too few verified $symbol candles for this range.',
          unavailable: true,
        );
      }
      final rial = rows.first.currency == 'IRR';
      final divisor = rial ? 10.0 : 1.0;
      final unitUnverified = rows.any(
        (row) => row.qualityFlags.contains('unit_from_provider_catalog'),
      );
      final sourceLabel =
          rows.first.qualityFlags.contains('price_sample_not_ohlc')
          ? 'GoldBrain · ${rows.first.provider} price samples (not OHLC)'
          : 'GoldBrain · ${rows.first.provider}';
      final series = MarketHistorySeries(
        symbol: symbol,
        currency: rial ? 'IRT' : rows.first.currency,
        range: range,
        candles: List.unmodifiable(
          rows.map(
            (row) => MarketCandle(
              time: row.openedAt.toLocal(),
              open: row.open / divisor,
              high: row.high / divisor,
              low: row.low / divisor,
              close: row.close / divisor,
              volume: row.volume,
            ),
          ),
        ),
        provider: MarketHistoryProvider.backend,
        providerLabel: unitUnverified
            ? '$sourceLabel · unit unverified'
            : sourceLabel,
        fetchedAt: now.toLocal(),
        isStale:
            unitUnverified ||
            now.difference(rows.last.closedAt) >
                (timeframe == '1m'
                    ? const Duration(minutes: 5)
                    : timeframe == '1d'
                    ? const Duration(days: 3)
                    : const Duration(hours: 2)),
      );
      _cache[key] = (series: series, fetchedAt: now);
      return series;
    } on GoldBrainBackendException catch (error) {
      if (cached != null) return cached.series.asStale();
      throw MarketHistoryException(error.message);
    } on FormatException {
      if (cached != null) return cached.series.asStale();
      throw const MarketHistoryException(
        'GoldBrain returned invalid historical candles.',
      );
    } on MarketHistoryException {
      if (cached != null) return cached.series.asStale();
      rethrow;
    }
  }

  Future<MarketHistorySeries> _fetchBackendPriceSamples(
    String symbol,
    MarketHistoryRange range,
  ) async {
    final samples = await _backend!.priceSamples24h(symbol);
    if (samples.length < 2) {
      throw MarketHistoryException(
        'GoldBrain has too few source-timestamped $symbol price samples for a 24h chart.',
        unavailable: true,
      );
    }
    final first = samples.first;
    if (samples.any(
      (sample) =>
          sample.currency != first.currency ||
          sample.unit != first.unit ||
          sample.market != first.market ||
          sample.provider != first.provider,
    )) {
      throw const FormatException('Mixed price samples');
    }
    final rial = first.currency == 'IRR';
    final divisor = rial ? 10.0 : 1.0;
    final now = DateTime.now().toUtc();
    final points = <MarketCandle>[
      for (final sample in samples)
        MarketCandle(
          time: sample.providerTimestamp.toLocal(),
          open: sample.price / divisor,
          high: sample.price / divisor,
          low: sample.price / divisor,
          close: sample.price / divisor,
          isPriceSample: true,
        ),
    ];
    return MarketHistorySeries(
      symbol: symbol,
      currency: rial ? 'IRT' : first.currency,
      range: range,
      candles: List.unmodifiable(points),
      provider: MarketHistoryProvider.backend,
      providerLabel: 'GoldBrain · ${first.provider} price samples (not OHLC)',
      fetchedAt: now.toLocal(),
      isPriceSample: true,
      isStale:
          now.difference(samples.last.providerTimestamp) >
          const Duration(hours: 3),
    );
  }

  Future<List<BackendCandle>> _fetchBackendCandles(
    String symbol,
    String timeframe, {
    String? quoteProvider,
    int? limit,
    DateTime? requiredFrom,
  }) async {
    final providers = <String?>['quote-collector'];
    final normalizedQuoteProvider = quoteProvider?.trim().toLowerCase();
    if (normalizedQuoteProvider != null &&
        normalizedQuoteProvider.isNotEmpty &&
        !GlobalPriceQuote.isDisallowedDomesticSource(
          symbol: symbol,
          provider: GlobalPriceProvider.backend,
          upstreamSource: normalizedQuoteProvider,
        ) &&
        !providers.contains(normalizedQuoteProvider)) {
      providers.add(normalizedQuoteProvider);
    }
    providers.add(null);
    for (final provider in providers) {
      try {
        final rows = await _backend!.candles(
          symbol,
          timeframe,
          provider: provider,
          limit: limit,
        );
        if (rows.length >= 2 &&
            (requiredFrom == null ||
                rows
                        .where((row) => !row.openedAt.isBefore(requiredFrom))
                        .length >=
                    2) &&
            !rows.any(
              (row) => GlobalPriceQuote.isDisallowedDomesticSource(
                symbol: symbol,
                provider: GlobalPriceProvider.backend,
                upstreamSource: row.provider,
              ),
            ) &&
            (requiredFrom == null ||
                !rows.first.openedAt.isAfter(
                  requiredFrom.add(
                    timeframe == '1m'
                        ? const Duration(minutes: 5)
                        : timeframe == '1d'
                        ? const Duration(days: 2)
                        : const Duration(hours: 2),
                  ),
                ))) {
          return rows;
        }
      } on FormatException {
        // A provider series that is malformed or mixed is not chartable.
      }
    }
    return const <BackendCandle>[];
  }

  Future<MarketHistorySeries> _fetchArzhaam(
    String symbol,
    MarketHistoryRange range,
  ) async {
    if (range == MarketHistoryRange.oneMonth) {
      throw const MarketHistoryException(
        'Arzhaam 30-day history has not been verified.',
        unavailable: true,
      );
    }
    if (_arzhaamApiKey.isEmpty) {
      throw const MarketHistoryException(
        'Arzhaam history is not configured. Set ARZHAAM_API_KEY to use its Iranian-market history API.',
        unavailable: true,
      );
    }
    if (_arzhaamEndpoint.scheme != 'https') {
      throw const MarketHistoryException(
        'Arzhaam history requires HTTPS.',
        unavailable: true,
      );
    }
    final assetId = _arzhaamSymbols[symbol];
    if (assetId == null) {
      throw MarketHistoryException('Arzhaam does not map $symbol.');
    }
    final requestedRange = range == MarketHistoryRange.oneWeek ? '7d' : '24h';
    final uri = _arzhaamEndpoint
        .resolve('api/rates/history/$assetId')
        .replace(queryParameters: {'range': requestedRange});

    late final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {
              'X-App-Key': _arzhaamApiKey,
              'accept': 'application/json',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const MarketHistoryException('Arzhaam history request timed out.');
    } on http.ClientException {
      throw const MarketHistoryException(
        'Could not connect to Arzhaam history.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _safeProviderError(response.bodyBytes);
      if (response.statusCode == 401) {
        throw MarketHistoryException(
          'Arzhaam rejected ARZHAAM_API_KEY (HTTP 401). $detail',
        );
      }
      if (response.statusCode == 403) {
        throw MarketHistoryException(
          'Arzhaam history is not enabled for this plan (HTTP 403). $detail',
        );
      }
      if (response.statusCode == 429) {
        throw MarketHistoryException(
          'Arzhaam history rate limit was reached (HTTP 429). $detail',
        );
      }
      throw MarketHistoryException(
        'Arzhaam history request failed (HTTP ${response.statusCode}). $detail',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } on FormatException {
      throw const MarketHistoryException('Arzhaam returned invalid JSON.');
    }
    if (decoded is! Map) {
      throw const MarketHistoryException(
        'Arzhaam returned an invalid history payload.',
      );
    }
    final rawPoints = decoded['points'];
    if (rawPoints is! List) {
      throw const MarketHistoryException('Arzhaam returned no history points.');
    }
    final candles = <MarketCandle>[];
    for (final raw in rawPoints.whereType<Map>()) {
      final time = DateTime.tryParse(raw['timestamp']?.toString() ?? '');
      final value = raw['price'];
      final price = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (time == null || price == null || !price.isFinite || price <= 0)
        continue;
      candles.add(
        MarketCandle(
          time: time.toLocal(),
          open: price,
          high: price,
          low: price,
          close: price,
        ),
      );
    }
    var result = _deduplicateCandles(candles);
    if (range == MarketHistoryRange.oneHour && result.isNotEmpty) {
      final cutoff = result.last.time.subtract(const Duration(hours: 1));
      result = result.where((candle) => !candle.time.isBefore(cutoff)).toList();
    }
    if (result.length < 2) {
      throw MarketHistoryException(
        'Arzhaam returned too few real points for ${range.name}.',
      );
    }
    _validateCandles(result, range, provider: 'Arzhaam');
    return MarketHistorySeries(
      symbol: symbol,
      currency: 'IRT',
      range: range,
      candles: List.unmodifiable(result),
      provider: MarketHistoryProvider.arzhaam,
      providerLabel: 'Arzhaam · $assetId · $requestedRange',
      fetchedAt: DateTime.now(),
    );
  }

  String _safeProviderError(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          return error['message'].toString();
        }
      }
    } catch (_) {}
    return '';
  }

  Future<MarketHistorySeries> _fetchNavasan(
    String symbol,
    MarketHistoryRange range,
  ) async {
    if (_navasanApiKey.isEmpty) {
      throw const MarketHistoryException(
        'Navasan history is not configured. Set NAVASAN_API_KEY to use the licensed Iranian-market history API.',
        unavailable: true,
      );
    }
    if (_navasanEndpoint.scheme != 'https') {
      throw const MarketHistoryException(
        'Navasan history requires an HTTPS endpoint so the API key is not sent in clear text.',
        unavailable: true,
      );
    }

    final item = _navasanSymbols[symbol]!;
    if (range == MarketHistoryRange.oneMonth) {
      throw const MarketHistoryException(
        'This direct Navasan history adapter has no verified 30-day series.',
        unavailable: true,
      );
    }
    late final List<MarketCandle> selected;
    late final String providerLabel;
    if (range == MarketHistoryRange.oneWeek) {
      selected = await _fetchNavasanDailyOhlc(item);
      _validateCandles(selected, range, provider: 'Navasan');
      providerLabel = 'Navasan · $item · daily OHLC';
    } else {
      final dayCount = range == MarketHistoryRange.oneDay ? 2 : 1;
      final candles = await _fetchNavasanTickDays(item, dayCount: dayCount);
      if (candles.length < 2) {
        throw const MarketHistoryException(
          'Navasan returned too few tick points.',
        );
      }

      selected = List<MarketCandle>.from(candles);
      final now = DateTime.now();
      final cutoff = range == MarketHistoryRange.oneHour
          ? now.subtract(const Duration(hours: 1))
          : now.subtract(const Duration(hours: 24));
      selected.removeWhere((candle) => candle.time.isBefore(cutoff));
      _validateIntradayCandles(selected, provider: 'Navasan');
      providerLabel = 'Navasan · $item · real tick history';
    }

    final latest = selected.last.time;
    final staleAfter = switch (range) {
      MarketHistoryRange.oneHour => const Duration(hours: 3),
      MarketHistoryRange.oneDay => const Duration(hours: 30),
      MarketHistoryRange.oneWeek => const Duration(hours: 48),
      MarketHistoryRange.oneMonth => const Duration(hours: 48),
    };
    return MarketHistorySeries(
      symbol: symbol,
      currency: 'IRT',
      range: range,
      candles: List.unmodifiable(selected),
      provider: MarketHistoryProvider.navasan,
      providerLabel: providerLabel,
      fetchedAt: DateTime.now(),
      isStale: DateTime.now().difference(latest) > staleAfter,
    );
  }

  Future<List<MarketCandle>> _fetchNavasanTickDays(
    String item, {
    required int dayCount,
  }) async {
    final now = DateTime.now();
    final candles = <MarketCandle>[];
    final failures = <String>[];
    for (var offset = 0; offset < dayCount; offset++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: offset));
      try {
        candles.addAll(await _fetchNavasanDay(item, day));
      } on MarketHistoryException catch (error) {
        failures.add(error.message);
      }
    }
    final deduplicated = _deduplicateCandles(candles);
    if (deduplicated.isEmpty && failures.isNotEmpty) {
      throw MarketHistoryException(failures.join(' '));
    }
    return deduplicated;
  }

  Future<List<MarketCandle>> _fetchNavasanDay(String item, DateTime day) async {
    final cacheKey =
        '${_navasanCacheNamespace()}:$item:${day.year}-${day.month}-${day.day}';
    final cached = _navasanDayCache[cacheKey];
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final effectiveDuration = isToday
        ? domesticCacheDuration
        : const Duration(days: 1);
    if (cached != null &&
        now.difference(cached.fetchedAt) < effectiveDuration) {
      return cached.candles;
    }

    final active = _navasanDayInFlight[cacheKey];
    if (active != null) return active;

    final request = _requestNavasanDay(item, day, cacheKey);
    _navasanDayInFlight[cacheKey] = request;
    return request.whenComplete(() => _navasanDayInFlight.remove(cacheKey));
  }

  Future<List<MarketCandle>> _requestNavasanDay(
    String item,
    DateTime day,
    String cacheKey,
  ) async {
    // Despite accepting a Unix timestamp according to an older copy of the
    // provider guide, the live Navasan endpoint currently rejects timestamps
    // with `Invalid date parameter value`. Its documented Jalali date form is
    // accepted consistently, so send that exact calendar date instead.
    final date = formatNavasanDate(day);
    final uri = _navasanEndpoint
        .resolve('dailyCurrency/')
        .replace(
          queryParameters: {
            'api_key': _navasanApiKey,
            'item': item,
            'date': date,
          },
        );
    final body = await _getJsonValue(uri, provider: 'Navasan');
    final parsed = _deduplicateCandles(_parseNavasanTicks(_extractRows(body)));
    _navasanDayCache[cacheKey] = (
      candles: List<MarketCandle>.unmodifiable(parsed),
      fetchedAt: DateTime.now(),
    );
    return parsed;
  }

  Future<MarketHistorySeries> _fetchTgjuDailyHistory(
    String symbol,
    MarketHistoryRange range,
  ) async {
    final uri = _tgjuHistoryUris[symbol];
    if (uri == null) {
      throw MarketHistoryException(
        'TGJU history is not available for $symbol.',
      );
    }
    late final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'user-agent': 'Mozilla/5.0 GoldBrain/1.0',
              'accept': 'text/html,application/xhtml+xml',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const MarketHistoryException('TGJU history request timed out.');
    } on http.ClientException {
      throw const MarketHistoryException('Could not connect to TGJU history.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MarketHistoryException(
        'TGJU history request failed (HTTP ${response.statusCode}).',
      );
    }

    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final rows = RegExp(
      r'<tr[^>]*>(.*?)</tr>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html);
    final candles = <MarketCandle>[];
    final cellPattern = RegExp(
      r'<td[^>]*>(.*?)</td>',
      caseSensitive: false,
      dotAll: true,
    );
    final tagPattern = RegExp(r'<[^>]+>');

    String clean(String value) => _normalizeDigits(
      value
          .replaceAll(tagPattern, '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&#x200C;', '')
          .replaceAll('&#8204;', '')
          .trim(),
    );

    double? price(String value) {
      final normalized = clean(
        value,
      ).replaceAll(',', '').replaceAll('٬', '').replaceAll(' ', '');
      final parsed = double.tryParse(normalized);
      if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
      // TGJU domestic-history pages publish prices in rial; GoldBrain's
      // domestic live-price unit is toman (IRT).
      return parsed / 10.0;
    }

    for (final row in rows) {
      final cells = cellPattern
          .allMatches(row.group(1) ?? '')
          .map((match) => clean(match.group(1) ?? ''))
          .toList(growable: false);
      if (cells.length < 7) continue;
      final dateText = _normalizeDigits(cells[6]).replaceAll('/', '-');
      final date = _parseGregorianOrJalaliDate(dateText);
      final open = price(cells[0]);
      final low = price(cells[1]);
      final high = price(cells[2]);
      final close = price(cells[3]);
      if (date == null ||
          open == null ||
          low == null ||
          high == null ||
          close == null) {
        continue;
      }
      candles.add(
        MarketCandle(
          // TGJU publishes a trading date without a time-of-day. Store it at
          // the start of the local day so a same-day candle is never rejected
          // as a future value when the app refreshes before noon.
          time: DateTime(date.year, date.month, date.day),
          open: open,
          high: high,
          low: low,
          close: close,
        ),
      );
    }

    final deduplicated = _deduplicateCandles(candles);
    if (deduplicated.length < 4) {
      throw const MarketHistoryException(
        'TGJU returned too few daily trading-session points.',
      );
    }

    // A calendar 7-day cutoff can leave only 2-3 points after weekends and
    // market holidays. For the 7D domestic view we keep the latest 8 REAL
    // trading sessions instead. No interpolation or synthetic candle is made.
    final recent = deduplicated.length <= 8
        ? deduplicated
        : deduplicated.sublist(deduplicated.length - 8);
    final now = DateTime.now().add(const Duration(minutes: 5));
    DateTime? previous;
    for (final candle in recent) {
      if (!_hasValidOhlc(candle) || candle.time.isAfter(now)) {
        throw const MarketHistoryException(
          'TGJU returned invalid daily OHLC data.',
        );
      }
      if (previous != null && !candle.time.isAfter(previous)) {
        throw const MarketHistoryException(
          'TGJU returned unordered daily history.',
        );
      }
      previous = candle.time;
    }
    if (now.difference(recent.last.time) > const Duration(days: 14)) {
      throw const MarketHistoryException('TGJU returned stale daily history.');
    }
    return MarketHistorySeries(
      symbol: symbol,
      currency: 'IRT',
      range: range,
      candles: List.unmodifiable(recent),
      provider: MarketHistoryProvider.tgju,
      providerLabel: 'TGJU · real daily OHLC · ${recent.length} sessions',
      fetchedAt: DateTime.now(),
      isStale:
          DateTime.now().difference(recent.last.time) >
          const Duration(hours: 48),
    );
  }

  Future<List<MarketCandle>> _fetchNavasanDailyOhlc(String item) async {
    final cacheKey = '${_navasanCacheNamespace()}:$item:ohlc:oneWeek';
    final cached = _navasanOhlcCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < domesticCacheDuration) {
      return List<MarketCandle>.from(cached.candles);
    }

    final active = _navasanOhlcInFlight[cacheKey];
    if (active != null) return List<MarketCandle>.from(await active);

    final request = _requestNavasanDailyOhlc(item, cacheKey);
    _navasanOhlcInFlight[cacheKey] = request;
    try {
      return List<MarketCandle>.from(await request);
    } finally {
      _navasanOhlcInFlight.remove(cacheKey);
    }
  }

  Future<List<MarketCandle>> _requestNavasanDailyOhlc(
    String item,
    String cacheKey,
  ) async {
    final now = DateTime.now().toUtc();
    final start = now.subtract(const Duration(days: 7));
    final uri = _navasanEndpoint
        .resolve('ohlcSearch/')
        .replace(
          queryParameters: {
            'api_key': _navasanApiKey,
            'item': item,
            'start': '${start.millisecondsSinceEpoch ~/ 1000}',
            'end': '${now.millisecondsSinceEpoch ~/ 1000}',
          },
        );
    final body = await _getJsonValue(uri, provider: 'Navasan');
    final parsed = _deduplicateCandles(_parseNavasanOhlc(_extractRows(body)));
    _navasanOhlcCache[cacheKey] = (
      candles: List<MarketCandle>.unmodifiable(parsed),
      fetchedAt: DateTime.now(),
    );
    return parsed;
  }

  String _navasanCacheNamespace() => Object.hash(
    _navasanEndpoint.scheme,
    _navasanEndpoint.host,
    _navasanEndpoint.port,
    _navasanApiKey,
  ).toString();

  List<Object?> _extractRows(Object? body) {
    if (body is List) return body;
    if (body is! Map) return const <Object?>[];
    for (final key in const <String>['data', 'result', 'items', 'rates']) {
      final candidate = body[key];
      if (candidate is List) return candidate;
      if (candidate is Map) {
        final nestedLists = candidate.values.whereType<List>();
        if (nestedLists.isNotEmpty) return nestedLists.first;
      }
    }
    if (body.containsKey('timestamp')) return <Object?>[body];
    final mappedRows = body.values.whereType<Map>().toList(growable: false);
    return mappedRows.length == body.length ? mappedRows : const <Object?>[];
  }

  List<MarketCandle> _parseNavasanTicks(List<Object?> rows) {
    final candles = <MarketCandle>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final timestamp = _integer(row['timestamp']);
      final value = _navasanTomanPrice(row['value'], row['currency']);
      if (timestamp == null || value == null) continue;
      candles.add(
        MarketCandle(
          time: DateTime.fromMillisecondsSinceEpoch(
            timestamp * 1000,
            isUtc: true,
          ).toLocal(),
          open: value,
          high: value,
          low: value,
          close: value,
        ),
      );
    }
    return candles;
  }

  List<MarketCandle> _parseNavasanOhlc(List<Object?> rows) {
    final candles = <MarketCandle>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final timestamp = _integer(row['timestamp']);
      final open = _navasanTomanPrice(row['open'], row['currency']);
      final high = _navasanTomanPrice(row['high'], row['currency']);
      final low = _navasanTomanPrice(row['low'], row['currency']);
      final close = _navasanTomanPrice(row['close'], row['currency']);
      if (timestamp == null ||
          open == null ||
          high == null ||
          low == null ||
          close == null) {
        continue;
      }
      candles.add(
        MarketCandle(
          time: DateTime.fromMillisecondsSinceEpoch(
            timestamp * 1000,
            isUtc: true,
          ).toLocal(),
          open: open,
          high: high,
          low: low,
          close: close,
        ),
      );
    }
    return candles;
  }

  List<MarketCandle> _deduplicateCandles(List<MarketCandle> candles) {
    final byTimestamp = <int, MarketCandle>{
      for (final candle in candles) candle.time.millisecondsSinceEpoch: candle,
    };
    return byTimestamp.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  Future<MarketHistorySeries> _fetchZarix(
    String symbol,
    MarketHistoryRange range,
  ) async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(_duration(range));
    final uri = _zarixEndpoint.replace(
      queryParameters: {
        'endpoint': 'chart',
        'symbol': _zarixSymbols[symbol]!,
        'interval': switch (range) {
          MarketHistoryRange.oneHour => '5m',
          MarketHistoryRange.oneDay => '15m',
          MarketHistoryRange.oneWeek => '1h',
          MarketHistoryRange.oneMonth => '1h',
        },
        'from': '${from.millisecondsSinceEpoch ~/ 1000}',
        'to': '${now.millisecondsSinceEpoch ~/ 1000}',
      },
    );
    final body = await _getObject(uri, provider: 'ZARIX');
    if (body['ok'] != true || body['data'] is! Map) {
      throw const MarketHistoryException('ZARIX returned invalid chart data.');
    }
    final data = body['data'] as Map;
    final candles = _parseObjectCandles(data['candles']);
    _validateCandles(candles, range, provider: 'ZARIX');
    final meta = data['meta'];
    final upstream = meta is Map ? meta['provider']?.toString() : null;
    return MarketHistorySeries(
      symbol: symbol,
      currency: 'USD',
      range: range,
      candles: List.unmodifiable(candles),
      provider: MarketHistoryProvider.zarix,
      providerLabel: upstream == null || upstream.isEmpty
          ? 'ZARIX'
          : 'ZARIX · $upstream',
      fetchedAt: DateTime.now(),
    );
  }

  Future<MarketHistorySeries> _fetchKraken(
    String symbol,
    MarketHistoryRange range,
  ) async {
    final since =
        DateTime.now()
            .toUtc()
            .subtract(_duration(range))
            .millisecondsSinceEpoch ~/
        1000;
    final uri = _krakenEndpoint.replace(
      queryParameters: {
        'pair': _krakenPairs[symbol]!,
        'interval': switch (range) {
          MarketHistoryRange.oneHour => '1',
          MarketHistoryRange.oneDay => '15',
          MarketHistoryRange.oneWeek => '60',
          MarketHistoryRange.oneMonth => '60',
        },
        'since': '$since',
      },
    );
    final body = await _getObject(uri, provider: 'Kraken');
    final errors = body['error'];
    if (errors is List && errors.isNotEmpty) {
      throw const MarketHistoryException('Kraken rejected the chart request.');
    }
    final result = body['result'];
    if (result is! Map) {
      throw const MarketHistoryException('Kraken returned invalid chart data.');
    }
    Object? rows;
    for (final entry in result.entries) {
      if (entry.key.toString() != 'last' && entry.value is List) {
        rows = entry.value;
        break;
      }
    }
    final candles = _parseArrayCandles(rows);
    _validateCandles(candles, range, provider: 'Kraken');
    return MarketHistorySeries(
      symbol: symbol,
      currency: 'USD',
      range: range,
      candles: List.unmodifiable(candles),
      provider: MarketHistoryProvider.kraken,
      providerLabel: 'Kraken Spot',
      fetchedAt: DateTime.now(),
    );
  }

  Future<MarketHistorySeries> _fetchYahooMetalProxy(
    String symbol,
    MarketHistoryRange range,
  ) async {
    final yahooSymbol = _yahooMetalSymbols[symbol]!;
    final uri = _yahooBaseUri
        .resolve(Uri.encodeComponent(yahooSymbol))
        .replace(
          queryParameters: {
            'interval': switch (range) {
              MarketHistoryRange.oneHour => '5m',
              MarketHistoryRange.oneDay => '15m',
              MarketHistoryRange.oneWeek => '1h',
              MarketHistoryRange.oneMonth => '1d',
            },
            'range': switch (range) {
              MarketHistoryRange.oneMonth => '1mo',
              MarketHistoryRange.oneWeek => '7d',
              _ => '1d',
            },
          },
        );
    final body = await _getObject(
      uri,
      provider: 'Yahoo Finance',
      headers: const {'user-agent': 'GoldBrain/1.0'},
    );
    final chart = body['chart'];
    final results = chart is Map ? chart['result'] : null;
    if (results is! List || results.isEmpty || results.first is! Map) {
      throw const MarketHistoryException(
        'Yahoo Finance returned no metal chart data.',
      );
    }
    final result = results.first as Map;
    final timestamps = result['timestamp'];
    final indicators = result['indicators'];
    final quotes = indicators is Map ? indicators['quote'] : null;
    if (timestamps is! List ||
        quotes is! List ||
        quotes.isEmpty ||
        quotes.first is! Map) {
      throw const MarketHistoryException(
        'Yahoo Finance returned invalid metal chart data.',
      );
    }
    final quote = quotes.first as Map;
    final opens = quote['open'];
    final highs = quote['high'];
    final lows = quote['low'];
    final closes = quote['close'];
    if (opens is! List || highs is! List || lows is! List || closes is! List) {
      throw const MarketHistoryException(
        'Yahoo Finance returned incomplete metal chart data.',
      );
    }
    final length = [
      timestamps.length,
      opens.length,
      highs.length,
      lows.length,
      closes.length,
    ].reduce((a, b) => a < b ? a : b);
    final candles = <MarketCandle>[];
    for (var index = 0; index < length; index++) {
      final time = timestamps[index];
      final open = _number(opens[index]);
      final high = _number(highs[index]);
      final low = _number(lows[index]);
      final close = _number(closes[index]);
      if (time is! num ||
          open == null ||
          high == null ||
          low == null ||
          close == null) {
        continue;
      }
      candles.add(
        MarketCandle(
          time: DateTime.fromMillisecondsSinceEpoch(
            time.toInt() * 1000,
            isUtc: true,
          ).toLocal(),
          open: open,
          high: high,
          low: low,
          close: close,
        ),
      );
    }
    _validateCandles(candles, range, provider: 'Yahoo Finance');
    return MarketHistorySeries(
      symbol: symbol,
      currency: 'USD',
      range: range,
      candles: List.unmodifiable(candles),
      provider: MarketHistoryProvider.yahooFinance,
      providerLabel: symbol == 'XAU'
          ? 'Yahoo Finance · COMEX Gold Futures proxy'
          : 'Yahoo Finance · COMEX Silver Futures proxy',
      fetchedAt: DateTime.now(),
      isProxy: true,
    );
  }

  List<MarketCandle> _parseObjectCandles(Object? value) {
    if (value is! List) return const [];
    final candles = <MarketCandle>[];
    for (final raw in value) {
      if (raw is! Map) continue;
      final timestamp = raw['time'];
      final open = _number(raw['open']);
      final high = _number(raw['high']);
      final low = _number(raw['low']);
      final close = _number(raw['close']);
      if (timestamp is! num ||
          open == null ||
          high == null ||
          low == null ||
          close == null) {
        continue;
      }
      candles.add(
        MarketCandle(
          time: DateTime.fromMillisecondsSinceEpoch(
            timestamp.toInt() * 1000,
            isUtc: true,
          ).toLocal(),
          open: open,
          high: high,
          low: low,
          close: close,
        ),
      );
    }
    return candles;
  }

  List<MarketCandle> _parseArrayCandles(Object? value) {
    if (value is! List) return const [];
    final candles = <MarketCandle>[];
    for (final raw in value) {
      if (raw is! List || raw.length < 5 || raw[0] is! num) continue;
      final open = _number(raw[1]);
      final high = _number(raw[2]);
      final low = _number(raw[3]);
      final close = _number(raw[4]);
      if (open == null || high == null || low == null || close == null)
        continue;
      candles.add(
        MarketCandle(
          time: DateTime.fromMillisecondsSinceEpoch(
            (raw[0] as num).toInt() * 1000,
            isUtc: true,
          ).toLocal(),
          open: open,
          high: high,
          low: low,
          close: close,
        ),
      );
    }
    return candles;
  }

  Future<Map<String, dynamic>> _getObject(
    Uri uri, {
    required String provider,
    Map<String, String>? headers,
  }) async {
    final decoded = await _getJsonValue(
      uri,
      provider: provider,
      headers: headers,
    );
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw MarketHistoryException('$provider returned invalid chart JSON.');
  }

  Future<Object?> _getJsonValue(
    Uri uri, {
    required String provider,
    Map<String, String>? headers,
  }) async {
    late final http.Response response;
    try {
      response = await _client.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      throw MarketHistoryException('$provider chart request timed out.');
    } on http.ClientException {
      throw MarketHistoryException('Could not connect to $provider charts.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MarketHistoryException(
        '$provider chart request failed (HTTP ${response.statusCode}).',
      );
    }
    if (response.bodyBytes.length > 5 * 1024 * 1024) {
      throw MarketHistoryException('$provider chart response was too large.');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      // Sanitized provider error below.
    }
    throw MarketHistoryException('$provider returned invalid chart JSON.');
  }

  void _validateIntradayCandles(
    List<MarketCandle> candles, {
    required String provider,
  }) {
    candles.sort((a, b) => a.time.compareTo(b.time));
    if (candles.length < 2) {
      throw MarketHistoryException('$provider returned too few chart points.');
    }
    final latestAllowed = DateTime.now().add(const Duration(minutes: 5));
    DateTime? previous;
    for (final candle in candles) {
      if (!_hasValidOhlc(candle) || candle.time.isAfter(latestAllowed)) {
        throw MarketHistoryException('$provider returned invalid OHLC values.');
      }
      if (previous != null && !candle.time.isAfter(previous)) {
        throw MarketHistoryException(
          '$provider returned unordered chart data.',
        );
      }
      previous = candle.time;
    }
  }

  void _validateCandles(
    List<MarketCandle> candles,
    MarketHistoryRange range, {
    required String provider,
  }) {
    candles.sort((a, b) => a.time.compareTo(b.time));
    final cutoff = DateTime.now().subtract(
      _duration(range) + _cutoffTolerance(range),
    );
    candles.removeWhere((candle) => candle.time.isBefore(cutoff));
    if (candles.length < 2) {
      throw MarketHistoryException('$provider returned too few chart points.');
    }
    final latestAllowed = DateTime.now().add(const Duration(minutes: 5));
    DateTime? previous;
    for (final candle in candles) {
      if (!_hasValidOhlc(candle) || candle.time.isAfter(latestAllowed)) {
        throw MarketHistoryException('$provider returned invalid OHLC values.');
      }
      if (previous != null && !candle.time.isAfter(previous)) {
        throw MarketHistoryException(
          '$provider returned unordered chart data.',
        );
      }
      previous = candle.time;
    }
  }

  bool _hasValidOhlc(MarketCandle candle) {
    final validPrices = <double>[
      candle.open,
      candle.high,
      candle.low,
      candle.close,
    ].every((value) => value.isFinite && value > 0);
    if (!validPrices || candle.high < candle.low) return false;
    return candle.high >= candle.open &&
        candle.high >= candle.close &&
        candle.low <= candle.open &&
        candle.low <= candle.close;
  }

  String _normalizeDigits(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    var output = value;
    for (var index = 0; index < 10; index++) {
      output = output
          .replaceAll(persian[index], '$index')
          .replaceAll(arabic[index], '$index');
    }
    return output;
  }

  DateTime? _parseGregorianOrJalaliDate(String value) {
    final normalized = _normalizeDigits(value.trim()).replaceAll('/', '-');
    final parts = normalized.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (year >= 1700) {
      final parsed = DateTime.tryParse(
        '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}',
      );
      return parsed;
    }
    if (year < 1200 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    return _jalaliToGregorian(year, month, day);
  }

  // Integer-only conversion adapted from the standard Jalali calendar
  // algorithm. It lets the public TGJU fallback retain the source's exact
  // Persian dates instead of assigning fabricated Gregorian timestamps.
  DateTime? _jalaliToGregorian(int jy, int jm, int jd) {
    var jalaliYear = jy + 1595;
    var days =
        -355668 +
        (365 * jalaliYear) +
        ((jalaliYear ~/ 33) * 8) +
        (((jalaliYear % 33) + 3) ~/ 4) +
        jd +
        (jm < 7 ? (jm - 1) * 31 : ((jm - 7) * 30) + 186);
    var gy = 400 * (days ~/ 146097);
    days %= 146097;
    if (days > 36524) {
      gy += 100 * (--days ~/ 36524);
      days %= 36524;
      if (days >= 365) days++;
    }
    gy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      gy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    var gd = days + 1;
    final leap = (gy % 4 == 0 && gy % 100 != 0) || gy % 400 == 0;
    const monthDays = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    var gm = 1;
    for (final baseLength in monthDays) {
      final length = gm == 2 && leap ? 29 : baseLength;
      if (gd <= length) break;
      gd -= length;
      gm++;
    }
    if (gm > 12) return null;
    return DateTime(gy, gm, gd);
  }

  static String formatNavasanDate(DateTime value) {
    final (year, month, day) = _gregorianToJalali(
      value.year,
      value.month,
      value.day,
    );
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  // Integer-only Gregorian -> Jalali conversion. Keeping it local avoids a
  // calendar dependency in the network layer and makes the request date
  // deterministic in tests.
  static (int, int, int) _gregorianToJalali(int gy, int gm, int gd) {
    const cumulativeDays = <int>[
      0,
      31,
      59,
      90,
      120,
      151,
      181,
      212,
      243,
      273,
      304,
      334,
    ];
    final sourceYear = gy;
    var year = gy - 1600;
    final month = gm - 1;
    final day = gd - 1;
    var dayNumber =
        (365 * year) +
        ((year + 3) ~/ 4) -
        ((year + 99) ~/ 100) +
        ((year + 399) ~/ 400) +
        cumulativeDays[month] +
        day;
    final gregorianLeap =
        (sourceYear % 4 == 0 && sourceYear % 100 != 0) || sourceYear % 400 == 0;
    if (month > 1 && gregorianLeap) dayNumber++;

    var jalaliDayNumber = dayNumber - 79;
    final cycles = jalaliDayNumber ~/ 12053;
    jalaliDayNumber %= 12053;
    var jalaliYear = 979 + (33 * cycles) + (4 * (jalaliDayNumber ~/ 1461));
    jalaliDayNumber %= 1461;
    if (jalaliDayNumber >= 366) {
      jalaliYear += (jalaliDayNumber - 1) ~/ 365;
      jalaliDayNumber = (jalaliDayNumber - 1) % 365;
    }
    final jalaliMonth = jalaliDayNumber < 186
        ? 1 + (jalaliDayNumber ~/ 31)
        : 7 + ((jalaliDayNumber - 186) ~/ 30);
    final jalaliDay =
        1 +
        (jalaliDayNumber < 186
            ? jalaliDayNumber % 31
            : (jalaliDayNumber - 186) % 30);
    return (jalaliYear, jalaliMonth, jalaliDay);
  }

  double? _number(Object? value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null || !parsed.isFinite || parsed <= 0) return null;
    return parsed;
  }

  double? _navasanTomanPrice(Object? value, Object? rawCurrency) {
    final price = _number(value);
    if (price == null) return null;
    final currency = (rawCurrency?.toString() ?? 'IRT').trim().toUpperCase();
    if (const {'IRT', 'TOMAN', 'TMN'}.contains(currency)) return price;
    if (const {'IRR', 'RLS', 'RIAL'}.contains(currency)) return price / 10;
    return null;
  }

  int? _integer(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  Duration _duration(MarketHistoryRange range) => switch (range) {
    MarketHistoryRange.oneHour => const Duration(hours: 1),
    MarketHistoryRange.oneDay => const Duration(days: 1),
    MarketHistoryRange.oneWeek => const Duration(days: 7),
    MarketHistoryRange.oneMonth => const Duration(days: 30),
  };

  Duration _cutoffTolerance(MarketHistoryRange range) => switch (range) {
    MarketHistoryRange.oneHour => const Duration(minutes: 10),
    MarketHistoryRange.oneDay => const Duration(hours: 1),
    MarketHistoryRange.oneWeek => const Duration(hours: 3),
    MarketHistoryRange.oneMonth => const Duration(days: 1),
  };

  Future<void> _cacheResult(String cacheKey, MarketHistorySeries series) async {
    if (series.hasDisallowedDomesticSource) return;
    _cache[cacheKey] = (series: series, fetchedAt: DateTime.now());
    try {
      await _persistentCache.put(series);
    } catch (_) {
      // Disk cache is an availability aid; it must never hide fresh data.
    }
  }

  Future<MarketHistorySeries?> _staleFallback(
    String cacheKey,
    String symbol,
    MarketHistoryRange range,
  ) async {
    final memory = _cache[cacheKey]?.series;
    if (memory != null && !memory.hasDisallowedDomesticSource) {
      return memory.asStale();
    }
    try {
      return (await _persistentCache.get(symbol, range: range))?.asStale();
    } catch (_) {
      return null;
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
