import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_persistence_policy.dart';

import 'global_price_service.dart';
import 'market_history_service.dart';

class LocalQuoteHistoryStore {
  LocalQuoteHistoryStore({
    this.retention = const Duration(days: 31),
    this.maxPointsPerSymbol = 2600,
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  // v1 did not persist provider/upstream provenance. That allowed quotes from
  // incompatible source or unit regimes to be joined into one misleading
  // line. v2 also accepted unrealistically large domestic jumps before its
  // discontinuity threshold was tightened. Neither schema is migrated.
  static const _storageKey = 'goldbrain_verified_quote_history_v3';
  static const minimumChartPoints = 6;
  static const staleAfter = Duration(minutes: 12);

  final Duration retention;
  final int maxPointsPerSymbol;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Map<String, List<_LocalQuotePoint>> _points = {};
  bool _loaded = false;
  Future<void>? _loadInFlight;

  Future<void> recordQuotes(Map<String, GlobalPriceQuote> quotes) async {
    if (quotes.isEmpty) return;
    await _ensureLoaded();
    final now = DateTime.now();
    final cutoff = now.subtract(retention);

    for (final quote in quotes.values) {
      if (!quote.price.isFinite ||
          quote.price <= 0 ||
          quote.hasDisallowedDomesticSource) {
        continue;
      }
      final time = quote.updatedAt;
      if (time.isBefore(cutoff) ||
          time.isAfter(now.add(const Duration(minutes: 5)))) {
        continue;
      }
      final symbol = quote.symbol.trim().toUpperCase();
      if (symbol.isEmpty) continue;
      final list = _points.putIfAbsent(symbol, () => []);
      list.removeWhere((point) => point.time.isBefore(cutoff));
      final upstreamSource = _normalizeSource(quote.upstreamSource);
      final existingIndex = list.indexWhere(
        (point) =>
            point.time.millisecondsSinceEpoch == time.millisecondsSinceEpoch,
      );
      final point = _LocalQuotePoint(
        time: time,
        price: quote.price,
        currency: quote.currency,
        provider: quote.provider,
        upstreamSource: upstreamSource,
        changePercent: quote.changePercent,
      );

      if (list.isNotEmpty) {
        final latest = list.last;
        // A late response must not append an older point after a newer quote.
        if (existingIndex < 0 && time.isBefore(latest.time)) continue;

        // Never connect points across provider, upstream-source or unit
        // changes. Start a fresh observable regime and wait for enough real
        // samples before exposing another line.
        if (latest.regimeKey != point.regimeKey ||
            _isUnexplainedDomesticDiscontinuity(
              symbol: symbol,
              previous: latest,
              next: point,
            )) {
          list.clear();
        }
      }

      final replacementIndex = list.indexWhere(
        (candidate) =>
            candidate.time.millisecondsSinceEpoch ==
            time.millisecondsSinceEpoch,
      );
      if (replacementIndex >= 0) {
        list[replacementIndex] = point;
      } else {
        list.add(point);
      }
      list.sort((a, b) => a.time.compareTo(b.time));
      if (list.length > maxPointsPerSymbol) {
        list.removeRange(0, list.length - maxPointsPerSymbol);
      }
    }
    await _persist();
  }

  Future<MarketHistorySeries?> historyFor(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
  }) async {
    await _ensureLoaded();
    final normalized = symbol.trim().toUpperCase();
    final duration = _duration(range);
    final cutoff = DateTime.now().subtract(duration);
    final consistent = _currentRegimePoints(normalized, cutoff: cutoff);
    if (!_hasEnoughCoverage(consistent, range)) return null;
    final latest = consistent.last;
    final now = DateTime.now();

    return MarketHistorySeries(
      symbol: normalized,
      currency: latest.currency,
      range: range,
      candles: List.unmodifiable(
        consistent.map(
          (point) => MarketCandle(
            time: point.time,
            open: point.price,
            high: point.price,
            low: point.price,
            close: point.price,
          ),
        ),
      ),
      provider: MarketHistoryProvider.localDevice,
      providerLabel: 'Device-recorded · ${latest.sourceLabel}',
      fetchedAt: latest.time,
      isLocalHistory: true,
      isStale: now.difference(latest.time) > staleAfter,
    );
  }

  Future<int> pointCountFor(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
  }) async {
    await _ensureLoaded();
    final normalized = symbol.trim().toUpperCase();
    final cutoff = DateTime.now().subtract(_duration(range));
    return _currentRegimePoints(normalized, cutoff: cutoff).length;
  }

  Future<LocalQuoteHistoryStatus> statusFor(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
  }) async {
    await _ensureLoaded();
    final normalized = symbol.trim().toUpperCase();
    final points = _currentRegimePoints(
      normalized,
      cutoff: DateTime.now().subtract(_duration(range)),
    );
    final observedSpan = points.length < 2
        ? Duration.zero
        : points.last.time.difference(points.first.time);
    final minimumSpan = minimumObservedSpan(range);
    final latest = points.isEmpty ? null : points.last;
    return LocalQuoteHistoryStatus(
      pointCount: points.length,
      observedSpan: observedSpan,
      minimumObservedSpan: minimumSpan,
      hasEnoughData:
          points.length >= minimumChartPoints && observedSpan >= minimumSpan,
      isStale:
          latest != null && DateTime.now().difference(latest.time) > staleAfter,
      sourceLabel: latest?.sourceLabel,
      currency: latest?.currency,
    );
  }

  static Duration minimumObservedSpan(MarketHistoryRange range) =>
      switch (range) {
        MarketHistoryRange.oneHour => const Duration(minutes: 10),
        MarketHistoryRange.oneDay => const Duration(hours: 1),
        MarketHistoryRange.oneWeek => const Duration(hours: 6),
        MarketHistoryRange.oneMonth => const Duration(days: 21),
      };

  Duration _duration(MarketHistoryRange range) => switch (range) {
    MarketHistoryRange.oneHour => const Duration(hours: 1),
    MarketHistoryRange.oneDay => const Duration(days: 1),
    MarketHistoryRange.oneWeek => const Duration(days: 7),
    MarketHistoryRange.oneMonth => const Duration(days: 30),
  };

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final active = _loadInFlight;
    if (active != null) return active;
    final request = _load();
    _loadInFlight = request;
    try {
      await request;
    } finally {
      _loadInFlight = null;
    }
  }

  Future<void> _load() async {
    final preferences = await _preferencesLoader();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _loaded = true;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final now = DateTime.now();
      final cutoff = now.subtract(retention);
      for (final entry in decoded.entries) {
        final symbol = entry.key.toString().trim().toUpperCase();
        final rows = entry.value;
        if (symbol.isEmpty || rows is! List) continue;
        final parsed = <_LocalQuotePoint>[];
        for (final rawPoint in rows) {
          if (rawPoint is! Map) continue;
          final milliseconds = rawPoint['time'];
          final price = rawPoint['price'];
          final currency = rawPoint['currency']?.toString().toUpperCase();
          final providerName = rawPoint['provider']?.toString();
          final upstreamSource = rawPoint['upstreamSource']?.toString();
          final provider = GlobalPriceProvider.values
              .where((candidate) => candidate.name == providerName)
              .firstOrNull;
          final changePercent = rawPoint['changePercent'];
          if (milliseconds is! int ||
              price is! num ||
              !price.toDouble().isFinite ||
              price <= 0 ||
              currency == null ||
              currency.isEmpty ||
              provider == null) {
            continue;
          }
          if (GlobalPriceQuote.isDisallowedDomesticSource(
            symbol: symbol,
            provider: provider,
            upstreamSource: upstreamSource,
          )) {
            continue;
          }
          final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
          if (time.isBefore(cutoff) ||
              time.isAfter(now.add(const Duration(minutes: 5)))) {
            continue;
          }
          parsed.add(
            _LocalQuotePoint(
              time: time,
              price: price.toDouble(),
              currency: currency,
              provider: provider,
              upstreamSource: _normalizeSource(upstreamSource),
              changePercent: changePercent is num
                  ? changePercent.toDouble()
                  : null,
            ),
          );
        }
        parsed.sort((a, b) => a.time.compareTo(b.time));
        final deduplicated = <int, _LocalQuotePoint>{
          for (final point in parsed) point.time.millisecondsSinceEpoch: point,
        }.values.toList()..sort((a, b) => a.time.compareTo(b.time));
        final currentRegime = deduplicated.isEmpty
            ? <_LocalQuotePoint>[]
            : deduplicated
                  .where(
                    (point) => point.regimeKey == deduplicated.last.regimeKey,
                  )
                  .toList();
        final continuous = _latestContinuousSegment(symbol, currentRegime);
        if (continuous.length > maxPointsPerSymbol) {
          continuous.removeRange(0, continuous.length - maxPointsPerSymbol);
        }
        if (continuous.isNotEmpty) _points[symbol] = continuous;
      }
    } on FormatException {
      // Corrupt local history is ignored; it is never converted into chart data.
    } finally {
      _loaded = true;
    }
  }

  Future<void> _persist() async {
    if (!LocalPersistencePolicy.instance.canWrite) return;
    final preferences = await _preferencesLoader();
    final encoded = <String, Object>{
      for (final entry in _points.entries)
        entry.key: entry.value
            .map(
              (point) => {
                'time': point.time.millisecondsSinceEpoch,
                'price': point.price,
                'currency': point.currency,
                'provider': point.provider.name,
                'upstreamSource': point.upstreamSource,
                'changePercent': point.changePercent,
              },
            )
            .toList(growable: false),
    };
    await preferences.setString(_storageKey, jsonEncode(encoded));
  }

  List<_LocalQuotePoint> _currentRegimePoints(
    String symbol, {
    required DateTime cutoff,
  }) {
    final selected = (_points[symbol] ?? const <_LocalQuotePoint>[])
        .where((point) => !point.time.isBefore(cutoff))
        .toList(growable: false);
    if (selected.isEmpty) return const [];
    final regimeKey = selected.last.regimeKey;
    return selected
        .where((point) => point.regimeKey == regimeKey)
        .toList(growable: false);
  }

  bool _hasEnoughCoverage(
    List<_LocalQuotePoint> points,
    MarketHistoryRange range,
  ) {
    if (points.length < minimumChartPoints) return false;
    return points.last.time.difference(points.first.time) >=
        minimumObservedSpan(range);
  }

  List<_LocalQuotePoint> _latestContinuousSegment(
    String symbol,
    List<_LocalQuotePoint> points,
  ) {
    if (points.length < 2) return points;
    var start = 0;
    for (var index = 1; index < points.length; index++) {
      if (_isUnexplainedDomesticDiscontinuity(
        symbol: symbol,
        previous: points[index - 1],
        next: points[index],
      )) {
        start = index;
      }
    }
    return points.sublist(start);
  }

  bool _isUnexplainedDomesticDiscontinuity({
    required String symbol,
    required _LocalQuotePoint previous,
    required _LocalQuotePoint next,
  }) {
    if (symbol != 'USD' && symbol != 'GOLD18') return false;
    final gap = next.time.difference(previous.time);
    if (gap.isNegative || gap > const Duration(hours: 24)) return false;
    final observedPercent =
        ((next.price - previous.price) / previous.price) * 100;
    if (observedPercent.abs() < 7.5) return false;

    // A genuine extreme market move can be retained when the provider itself
    // reports a matching daily change. Otherwise the safe interpretation is
    // a unit/source regime transition, so the old segment is not connected.
    final reported = next.changePercent;
    if (reported == null || !reported.isFinite) return true;
    final allowedDifference = (observedPercent.abs() * 0.35)
        .clamp(8.0, double.infinity)
        .toDouble();
    return (reported - observedPercent).abs() > allowedDifference;
  }

  static String _normalizeSource(String? source) {
    final normalized = source?.trim().toLowerCase();
    return normalized == null || normalized.isEmpty
        ? 'unspecified'
        : normalized;
  }
}

class LocalQuoteHistoryStatus {
  const LocalQuoteHistoryStatus({
    required this.pointCount,
    required this.observedSpan,
    required this.minimumObservedSpan,
    required this.hasEnoughData,
    required this.isStale,
    this.sourceLabel,
    this.currency,
  });

  final int pointCount;
  final Duration observedSpan;
  final Duration minimumObservedSpan;
  final bool hasEnoughData;
  final bool isStale;
  final String? sourceLabel;
  final String? currency;
}

class _LocalQuotePoint {
  const _LocalQuotePoint({
    required this.time,
    required this.price,
    required this.currency,
    required this.provider,
    required this.upstreamSource,
    this.changePercent,
  });

  final DateTime time;
  final double price;
  final String currency;
  final GlobalPriceProvider provider;
  final String upstreamSource;
  final double? changePercent;

  String get regimeKey => '${provider.name}|$upstreamSource|$currency';

  String get sourceLabel {
    final base = switch (provider) {
      GlobalPriceProvider.navasan => 'Navasan',
      GlobalPriceProvider.zarix => 'ZARIX',
      GlobalPriceProvider.goldApi => 'Gold API',
      GlobalPriceProvider.backend => 'GoldBrain',
    };
    return upstreamSource == 'unspecified' ? base : '$base · $upstreamSource';
  }
}
