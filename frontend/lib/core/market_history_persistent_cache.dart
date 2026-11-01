import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'market_history_service.dart';
import 'local_persistence_policy.dart';

/// Persists only validated upstream candles. It never creates, interpolates,
/// or changes a market value.
class MarketHistoryPersistentCache {
  MarketHistoryPersistentCache({
    Future<SharedPreferences> Function()? preferencesLoader,
    this.maxPointsPerSeries = 1500,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  // Earlier schemas could contain domestic series assembled before the
  // Navasan Jalali-date fix and did not preserve whether the provider's last
  // observation was already stale. Do not reconnect those points to current
  // data or silently turn an old TGJU session into a fresh one after reload.
  static const _storageKey = 'goldbrain_verified_market_history_v3';

  final Future<SharedPreferences> Function() _preferencesLoader;
  final int maxPointsPerSeries;

  Future<void> put(MarketHistorySeries series) async {
    if (!LocalPersistencePolicy.instance.canWrite) return;
    if (series.isLocalHistory ||
        series.hasDisallowedDomesticSource ||
        series.candles.length < 2)
      return;
    final preferences = await _preferencesLoader();
    final root = _readRoot(preferences.getString(_storageKey));
    final key = _key(series.symbol, series.range);
    final points = series.candles.length <= maxPointsPerSeries
        ? series.candles
        : series.candles.sublist(series.candles.length - maxPointsPerSeries);
    root[key] = {
      'symbol': series.symbol,
      'currency': series.currency,
      'range': series.range.name,
      'provider': series.provider.name,
      'providerLabel': series.providerLabel,
      'fetchedAt': series.fetchedAt.millisecondsSinceEpoch,
      'isProxy': series.isProxy,
      'wasStale': series.isStale,
      'candles': points
          .map(
            (candle) => [
              candle.time.millisecondsSinceEpoch,
              candle.open,
              candle.high,
              candle.low,
              candle.close,
            ],
          )
          .toList(growable: false),
    };
    _prune(root);
    await preferences.setString(_storageKey, jsonEncode(root));
  }

  Future<MarketHistorySeries?> get(
    String symbol, {
    required MarketHistoryRange range,
  }) async {
    final preferences = await _preferencesLoader();
    final root = _readRoot(preferences.getString(_storageKey));
    final raw = root[_key(symbol, range)];
    if (raw is! Map) return null;
    final fetchedAtMs = raw['fetchedAt'];
    final providerName = raw['provider']?.toString();
    final rows = raw['candles'];
    if (fetchedAtMs is! num || providerName == null || rows is! List) {
      return null;
    }
    final fetchedAt = DateTime.fromMillisecondsSinceEpoch(fetchedAtMs.toInt());
    final now = DateTime.now();
    if (fetchedAt.isAfter(now.add(const Duration(minutes: 5))) ||
        now.difference(fetchedAt) > _maximumAge(range)) {
      return null;
    }

    final cutoff = DateTime.now().subtract(
      _duration(range) + _cutoffTolerance(range),
    );
    final candles = <MarketCandle>[];
    for (final row in rows) {
      if (row is! List || row.length < 5 || row[0] is! num) continue;
      final values = row.skip(1).take(4).map(_positiveNumber).toList();
      if (values.any((value) => value == null)) continue;
      final time = DateTime.fromMillisecondsSinceEpoch((row[0] as num).toInt());
      if (time.isBefore(cutoff) ||
          time.isAfter(now.add(const Duration(minutes: 5)))) {
        continue;
      }
      final open = values[0]!;
      final high = values[1]!;
      final low = values[2]!;
      final close = values[3]!;
      if (high < low ||
          high < open ||
          high < close ||
          low > open ||
          low > close) {
        continue;
      }
      candles.add(
        MarketCandle(
          time: time,
          open: open,
          high: high,
          low: low,
          close: close,
        ),
      );
    }
    candles.sort((a, b) => a.time.compareTo(b.time));
    final deduplicated = <int, MarketCandle>{
      for (final candle in candles) candle.time.millisecondsSinceEpoch: candle,
    }.values.toList()..sort((a, b) => a.time.compareTo(b.time));
    if (deduplicated.length < 2) return null;

    final providers = MarketHistoryProvider.values.where(
      (value) => value.name == providerName,
    );
    if (providers.isEmpty ||
        providers.first == MarketHistoryProvider.localDevice) {
      return null;
    }
    final provider = providers.first;
    final normalizedSymbol = symbol.trim().toUpperCase();
    final domestic =
        normalizedSymbol == 'USD' ||
        normalizedSymbol == 'EUR' ||
        normalizedSymbol == 'GOLD18';
    final domesticProvider =
        provider == MarketHistoryProvider.navasan ||
        provider == MarketHistoryProvider.tgju ||
        provider == MarketHistoryProvider.arzhaam;
    if (domestic != domesticProvider) return null;
    if (range != MarketHistoryRange.oneWeek &&
        provider == MarketHistoryProvider.tgju) {
      // TGJU is deliberately a daily-only fallback. Never restore an old
      // TGJU series into an intraday chart.
      return null;
    }
    final lastObservation = deduplicated.last.time;
    final observationStale =
        raw['wasStale'] == true ||
        now.difference(lastObservation) > _maximumObservationAge(range);
    final series = MarketHistorySeries(
      symbol: raw['symbol']?.toString().toUpperCase() ?? symbol.toUpperCase(),
      currency: raw['currency']?.toString().toUpperCase() ?? 'USD',
      range: range,
      candles: List.unmodifiable(deduplicated),
      provider: provider,
      providerLabel: raw['providerLabel']?.toString() ?? provider.name,
      fetchedAt: fetchedAt,
      isProxy: raw['isProxy'] == true,
      isStale: observationStale,
    );
    return series.hasDisallowedDomesticSource ? null : series;
  }

  Map<String, dynamic> _readRoot(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      // Ignore corrupt cache. It is never converted into market data.
    }
    return <String, dynamic>{};
  }

  void _prune(Map<String, dynamic> root) {
    final oldest = DateTime.now().subtract(const Duration(days: 31));
    root.removeWhere((_, value) {
      if (value is! Map || value['fetchedAt'] is! num) return true;
      final fetchedAt = DateTime.fromMillisecondsSinceEpoch(
        (value['fetchedAt'] as num).toInt(),
      );
      return fetchedAt.isBefore(oldest);
    });
  }

  String _key(String symbol, MarketHistoryRange range) =>
      '${symbol.trim().toUpperCase()}:${range.name}';

  double? _positiveNumber(Object? value) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
  }

  Duration _duration(MarketHistoryRange range) => switch (range) {
    MarketHistoryRange.oneHour => const Duration(hours: 1),
    MarketHistoryRange.oneDay => const Duration(days: 1),
    MarketHistoryRange.oneWeek => const Duration(days: 7),
    MarketHistoryRange.oneMonth => const Duration(days: 30),
  };

  Duration _maximumAge(MarketHistoryRange range) => switch (range) {
    MarketHistoryRange.oneHour => const Duration(hours: 4),
    MarketHistoryRange.oneDay => const Duration(days: 2),
    MarketHistoryRange.oneWeek => const Duration(days: 8),
    MarketHistoryRange.oneMonth => const Duration(days: 31),
  };

  Duration _maximumObservationAge(MarketHistoryRange range) => switch (range) {
    MarketHistoryRange.oneHour => const Duration(hours: 3),
    MarketHistoryRange.oneDay => const Duration(hours: 30),
    MarketHistoryRange.oneWeek => const Duration(hours: 48),
    MarketHistoryRange.oneMonth => const Duration(hours: 48),
  };

  Duration _cutoffTolerance(MarketHistoryRange range) => switch (range) {
    MarketHistoryRange.oneHour => const Duration(minutes: 10),
    MarketHistoryRange.oneDay => const Duration(hours: 1),
    MarketHistoryRange.oneWeek => const Duration(hours: 3),
    MarketHistoryRange.oneMonth => const Duration(days: 1),
  };
}
