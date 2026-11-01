import 'dart:math' as math;

import 'market_forecast.dart';
import 'market_intelligence_service.dart';

/// Builds price scenarios from verified history without asking an LLM to
/// invent a price. Each horizon is evaluated independently and fails closed.
class MarketForecastEngine {
  const MarketForecastEngine();

  static const int methodVersion = 1;

  Map<String, Map<MarketForecastHorizon, MarketForecast>> generateAll(
    MarketIntelligenceInput input, {
    Iterable<String> symbols = supportedIntelligenceSymbols,
  }) {
    final output = <String, Map<MarketForecastHorizon, MarketForecast>>{};
    for (final rawSymbol in symbols) {
      final symbol = rawSymbol.trim().toUpperCase();
      if (!supportedIntelligenceSymbols.contains(symbol)) continue;
      final generated = generateForSymbol(input, symbol);
      if (generated.isNotEmpty) output[symbol] = generated;
    }
    return Map.unmodifiable(output);
  }

  Map<MarketForecastHorizon, MarketForecast> generateForSymbol(
    MarketIntelligenceInput input,
    String rawSymbol,
  ) {
    final symbol = rawSymbol.trim().toUpperCase();
    final quote = input.quotes
        .where(
          (candidate) =>
              candidate.symbol.toUpperCase() == symbol &&
              candidate.price.isFinite &&
              candidate.price > 0,
        )
        .firstOrNull;
    if (quote == null) return const <MarketForecastHorizon, MarketForecast>{};

    final histories = input.histories
        .where(
          (candidate) =>
              candidate.symbol.toUpperCase() == symbol &&
              !candidate.isProxy &&
              candidate.unit.trim().isNotEmpty &&
              candidate.source.trim().isNotEmpty,
        )
        .map((candidate) => _sanitize(candidate, input.collectedAt))
        .where((candidate) => candidate.points.length >= 2)
        .toList(growable: false);
    if (histories.isEmpty) {
      return const <MarketForecastHorizon, MarketForecast>{};
    }

    final result = <MarketForecastHorizon, MarketForecast>{};
    for (final horizon in MarketForecastHorizon.values) {
      final forecast = _generate(
        symbol: symbol,
        quote: quote,
        histories: histories,
        horizon: horizon,
        collectedAt: input.collectedAt.toUtc(),
      );
      if (forecast != null) result[horizon] = forecast;
    }
    return Map.unmodifiable(result);
  }

  MarketForecast? _generate({
    required String symbol,
    required IntelligenceQuoteEvidence quote,
    required List<IntelligenceHistoryEvidence> histories,
    required MarketForecastHorizon horizon,
    required DateTime collectedAt,
  }) {
    final requirement = _requirementFor(horizon);
    final candidates = histories
        .where((history) {
          if (!requirement.allowedRanges.contains(history.range)) return false;
          if (history.points.length < requirement.minimumPoints) return false;
          final coverage = _coverageHours(history.points);
          if (coverage < requirement.minimumCoverageHours) return false;
          if (_medianGapHours(history.points) >
              requirement.maximumMedianGapHours) {
            return false;
          }
          return _isFresh(
            symbol,
            horizon,
            collectedAt,
            history.points.last.time.toUtc(),
          );
        })
        .toList(growable: true);
    if (candidates.isEmpty) return null;

    candidates.sort((left, right) {
      final leftPreferred = requirement.allowedRanges.indexOf(left.range);
      final rightPreferred = requirement.allowedRanges.indexOf(right.range);
      if (leftPreferred != rightPreferred) {
        return leftPreferred.compareTo(rightPreferred);
      }
      final freshness = right.points.last.time.compareTo(left.points.last.time);
      if (freshness != 0) return freshness;
      return right.points.length.compareTo(left.points.length);
    });
    final history = candidates.first;
    final points = _windowForHorizon(history.points, horizon);
    if (points.length < requirement.minimumPoints ||
        _coverageHours(points) < requirement.minimumCoverageHours) {
      return null;
    }

    final quoteUnit = quote.unit.trim().toUpperCase();
    final historyUnit = history.unit.trim().toUpperCase();
    if (historyUnit.isEmpty) return null;
    final historyAnchor = points.last.close;
    final quoteAge = collectedAt.difference(quote.updatedAt.toUtc());
    final quoteFresh =
        quoteAge >= const Duration(minutes: -2) &&
        quoteAge <= _maximumQuoteAge(symbol);
    final quoteHasProvenance = quote.source.trim().isNotEmpty;
    final quoteSameUnit = quoteUnit == historyUnit;
    final quoteDistance = quoteSameUnit
        ? (quote.price - historyAnchor).abs() / quote.price
        : double.infinity;
    if (quoteFresh &&
        quoteHasProvenance &&
        quoteSameUnit &&
        quoteDistance > _trackingTolerance(symbol)) {
      // A fresh quote in the same unit represents the current regime. If it
      // materially disagrees with the selected history, falling back to the
      // stale history anchor would publish a scenario detached from the
      // observed market. This horizon must fail closed instead.
      return null;
    }
    final quoteTracksHistory =
        quoteFresh &&
        quoteHasProvenance &&
        quoteSameUnit &&
        quoteDistance <= _trackingTolerance(symbol);
    final useQuoteAnchor = quoteFresh && quoteTracksHistory;
    final anchorPrice = useQuoteAnchor ? quote.price : historyAnchor;
    final unit = useQuoteAnchor ? quoteUnit : historyUnit;
    if (!anchorPrice.isFinite || anchorPrice <= 0 || unit.isEmpty) return null;

    final statistics = _robustStatistics(points, horizon.duration.inHours);
    if (statistics == null) return null;
    final quality = _dataQuality(
      horizon: horizon,
      points: points,
      collectedAt: collectedAt,
      latestAt: points.last.time.toUtc(),
      quoteTracksHistory: quoteTracksHistory,
    );
    if (quality < 50) return null;

    final maximumMove = _maximumMove(
      symbol,
      horizon,
      statistics.forecastVolatility,
    );
    final projectedLogMove = statistics.projectedLogMove.clamp(
      -maximumMove,
      maximumMove,
    );
    final pointEstimate = anchorPrice * math.exp(projectedLogMove);
    if (!pointEstimate.isFinite || pointEstimate <= 0) return null;

    // 80% model interval (z ~= 1.2816). Sparse/noisy evidence widens it.
    final qualityInflation = 1 + ((100 - quality) / 100);
    final halfWidth = math.max(
      0.0005,
      1.2816 * statistics.forecastVolatility * qualityInflation,
    );
    final lower = anchorPrice * math.exp(projectedLogMove - halfWidth);
    final upper = anchorPrice * math.exp(projectedLogMove + halfWidth);
    if (!lower.isFinite || !upper.isFinite || lower <= 0 || upper < lower) {
      return null;
    }

    final neutralThreshold = math.max(
      0.00035,
      statistics.forecastVolatility * 0.12,
    );
    final direction = projectedLogMove.abs() <= neutralThreshold
        ? MarketForecastDirection.neutral
        : projectedLogMove.isNegative
        ? MarketForecastDirection.downward
        : MarketForecastDirection.upward;
    final agreementBonus = statistics.signalAgreement * 12;
    final confidence = (quality * 0.72 + agreementBonus).round().clamp(0, 85);
    final targetFor = collectedAt.add(horizon.duration);
    final numericalEvidence = points
        .map(
          (point) =>
              '${point.time.toUtc().millisecondsSinceEpoch}:${point.close}',
        )
        .join(',');
    final fingerprint = _fingerprint(
      '$symbol|${horizon.wireName}|${history.source}|'
      '${history.range}|$unit|${points.first.time.toUtc().millisecondsSinceEpoch}|'
      '${points.last.time.toUtc().millisecondsSinceEpoch}|$anchorPrice|'
      '${useQuoteAnchor ? quote.updatedAt.toUtc().millisecondsSinceEpoch : ''}|'
      '${useQuoteAnchor ? quote.source : ''}|$numericalEvidence|$methodVersion',
    );
    return MarketForecast(
      id: '$symbol-${horizon.wireName}-${collectedAt.millisecondsSinceEpoch}-$fingerprint',
      symbol: symbol,
      horizon: horizon,
      direction: direction,
      generatedAt: collectedAt,
      targetFor: targetFor,
      anchorPrice: anchorPrice,
      pointEstimate: pointEstimate,
      lowerBound: lower,
      upperBound: upper,
      unit: unit,
      confidenceScore: confidence,
      dataQualityPercent: quality,
      evidencePointCount: points.length,
      evidenceFingerprint: fingerprint,
      sources: List.unmodifiable(<String>[
        history.source,
        if (useQuoteAnchor && quote.source != history.source) quote.source,
      ]),
      historyRange: history.range,
      sourceLatestAt: points.last.time.toUtc(),
      methodVersion: methodVersion,
    );
  }

  IntelligenceHistoryEvidence _sanitize(
    IntelligenceHistoryEvidence history,
    DateTime collectedAt,
  ) {
    final maximum = collectedAt.toUtc();
    final byTime = <int, IntelligenceHistoryPoint>{};
    for (final point in history.points) {
      final time = point.time.toUtc();
      if (!point.close.isFinite || point.close <= 0 || time.isAfter(maximum)) {
        continue;
      }
      byTime[time.millisecondsSinceEpoch] = IntelligenceHistoryPoint(
        time: time,
        close: point.close,
      );
    }
    var points = byTime.values.toList(growable: false)
      ..sort((left, right) => left.time.compareTo(right.time));
    // The production store already samples histories, but direct engine
    // callers must not be able to turn Theil-Sen into unbounded O(n²) work.
    if (points.length > 240) {
      points = points.sublist(points.length - 240);
    }
    return IntelligenceHistoryEvidence(
      symbol: history.symbol.toUpperCase(),
      unit: history.unit.toUpperCase(),
      source: history.source.trim(),
      range: history.range,
      points: List.unmodifiable(points),
      isProxy: history.isProxy,
    );
  }

  List<IntelligenceHistoryPoint> _windowForHorizon(
    List<IntelligenceHistoryPoint> source,
    MarketForecastHorizon horizon,
  ) {
    final maximumLookback = switch (horizon) {
      MarketForecastHorizon.oneHour => const Duration(hours: 2),
      MarketForecastHorizon.twelveHours => const Duration(hours: 36),
      MarketForecastHorizon.twentyFourHours => const Duration(days: 10),
    };
    final cutoff = source.last.time.toUtc().subtract(maximumLookback);
    return source
        .where((point) => !point.time.toUtc().isBefore(cutoff))
        .toList(growable: false);
  }

  _RobustStatistics? _robustStatistics(
    List<IntelligenceHistoryPoint> points,
    int horizonHours,
  ) {
    if (points.length < 2) return null;
    final origin = points.first.time.toUtc();
    final xs = points
        .map((point) => point.time.toUtc().difference(origin).inSeconds / 3600)
        .toList(growable: false);
    final logs = points
        .map((point) => math.log(point.close))
        .toList(growable: false);
    final coverage = xs.last;
    if (!coverage.isFinite || coverage <= 0) return null;

    final pairSlopes = <double>[];
    // Theil-Sen remains robust to single bad ticks. Limit pair count for long
    // histories by stepping through older points deterministically.
    final stride = points.length > 100 ? 2 : 1;
    for (var left = 0; left < points.length - 1; left += stride) {
      for (var right = left + 1; right < points.length; right += stride) {
        final gap = xs[right] - xs[left];
        if (gap > 0) pairSlopes.add((logs[right] - logs[left]) / gap);
      }
    }
    if (pairSlopes.isEmpty) return null;
    final theilSen = _median(pairSlopes);

    final hourlyReturns = <double>[];
    final residualRates = <double>[];
    for (var index = 1; index < points.length; index++) {
      final gap = xs[index] - xs[index - 1];
      if (gap <= 0) continue;
      final value = (logs[index] - logs[index - 1]) / gap;
      hourlyReturns.add(value);
      residualRates.add(
        math
                .pow((logs[index] - logs[index - 1]) - (theilSen * gap), 2)
                .toDouble() /
            gap,
      );
    }
    if (hourlyReturns.isEmpty || residualRates.isEmpty) return null;
    final returnMedian = _median(hourlyReturns);
    final returnMad = _median(
      hourlyReturns.map((value) => (value - returnMedian).abs()).toList(),
    );
    final robustScale = math.max(1e-8, returnMad * 1.4826);
    var weightedSum = 0.0;
    var weightTotal = 0.0;
    for (var index = 0; index < hourlyReturns.length; index++) {
      final clipped = hourlyReturns[index].clamp(
        returnMedian - (4 * robustScale),
        returnMedian + (4 * robustScale),
      );
      final weight = 1 + (index / math.max(1, hourlyReturns.length - 1));
      weightedSum += clipped * weight;
      weightTotal += weight;
    }
    final recentMean = weightedSum / weightTotal;

    final fastPeriod = math.min(5, points.length);
    final slowPeriod = math.min(12, points.length);
    final fast = _ema(logs, fastPeriod);
    final slow = _ema(logs, slowPeriod);
    final emaSlope = (fast - slow) / math.max(1.0, coverage * 0.25);
    var hourlyTrend =
        (0.50 * theilSen) + (0.35 * recentMean) + (0.15 * emaSlope);
    final extrapolationReliability = (coverage / (horizonHours * 2)).clamp(
      0.0,
      1.0,
    );
    hourlyTrend *= 0.35 + (0.65 * extrapolationReliability);
    final projected = hourlyTrend * horizonHours;

    final varianceRate = _median(residualRates).clamp(0.0, double.infinity);
    final volatilityPerSqrtHour = math.sqrt(varianceRate * 1.4826);
    final forecastVolatility = math.max(
      0.00025,
      volatilityPerSqrtHour * math.sqrt(horizonHours),
    );
    final signs = <int>[
      theilSen.sign.toInt(),
      recentMean.sign.toInt(),
      emaSlope.sign.toInt(),
    ].where((value) => value != 0).toList(growable: false);
    final agreement = signs.isEmpty
        ? 0.0
        : math.max(
                signs.where((value) => value > 0).length,
                signs.where((value) => value < 0).length,
              ) /
              signs.length;
    return _RobustStatistics(
      projectedLogMove: projected,
      forecastVolatility: forecastVolatility,
      signalAgreement: agreement,
    );
  }

  double _ema(List<double> values, int period) {
    final alpha = 2 / (period + 1);
    var value = values.first;
    for (var index = 1; index < values.length; index++) {
      value = (alpha * values[index]) + ((1 - alpha) * value);
    }
    return value;
  }

  int _dataQuality({
    required MarketForecastHorizon horizon,
    required List<IntelligenceHistoryPoint> points,
    required DateTime collectedAt,
    required DateTime latestAt,
    required bool quoteTracksHistory,
  }) {
    final requirement = _requirementFor(horizon);
    final coverage = _coverageHours(points);
    final sampleRatio = points.length / requirement.minimumPoints;
    final coverageRatio = coverage / requirement.minimumCoverageHours;
    final medianGap = _medianGapHours(points);
    final densityRatio = requirement.maximumMedianGapHours / medianGap;
    final ageHours = math.max(
      0.0,
      collectedAt.difference(latestAt).inSeconds / 3600,
    );
    final maximumAgeHours = _maximumHistoryAgeHours(horizon);
    final freshness = (1 - (ageHours / maximumAgeHours)).clamp(0.0, 1.0);
    var score = 10; // exact, non-proxy provenance is required before here.
    score += (math.min(1.0, sampleRatio / 2) * 25).round();
    score += (math.min(1.0, coverageRatio / 2) * 20).round();
    score += (math.min(1.0, densityRatio) * 15).round();
    score += (freshness * 20).round();
    if (quoteTracksHistory) score += 10;
    return score.clamp(0, 100);
  }

  bool _isFresh(
    String symbol,
    MarketForecastHorizon horizon,
    DateTime collectedAt,
    DateTime latestAt,
  ) {
    final age = collectedAt.difference(latestAt);
    if (age.isNegative) return false;
    if (horizon == MarketForecastHorizon.oneHour) {
      return age <=
          (symbol == 'USD' || symbol == 'GOLD18'
              ? const Duration(hours: 3)
              : const Duration(minutes: 45));
    }
    if (horizon == MarketForecastHorizon.twelveHours) {
      return age <=
          (symbol == 'USD' || symbol == 'GOLD18'
              ? const Duration(hours: 4)
              : const Duration(hours: 3));
    }
    final weekend =
        collectedAt.weekday == DateTime.saturday ||
        collectedAt.weekday == DateTime.sunday;
    if ((symbol == 'XAU' || symbol == 'XAG') && weekend) {
      return age <= const Duration(hours: 72);
    }
    if (symbol == 'BTC' || symbol == 'ETH') {
      return age <= const Duration(hours: 6);
    }
    return age <= const Duration(hours: 30);
  }

  double _maximumHistoryAgeHours(MarketForecastHorizon horizon) =>
      switch (horizon) {
        MarketForecastHorizon.oneHour => 3,
        MarketForecastHorizon.twelveHours => 4,
        MarketForecastHorizon.twentyFourHours => 30,
      };

  Duration _maximumQuoteAge(String symbol) =>
      symbol == 'USD' || symbol == 'GOLD18'
      ? const Duration(hours: 3)
      : const Duration(minutes: 20);

  double _trackingTolerance(String symbol) => switch (symbol) {
    'BTC' || 'ETH' => 0.12,
    _ => 0.08,
  };

  double _maximumMove(
    String symbol,
    MarketForecastHorizon horizon,
    double forecastVolatility,
  ) {
    final hardCap = switch ((symbol, horizon)) {
      ('BTC' || 'ETH', MarketForecastHorizon.oneHour) => 0.05,
      ('BTC' || 'ETH', MarketForecastHorizon.twelveHours) => 0.10,
      ('BTC' || 'ETH', MarketForecastHorizon.twentyFourHours) => 0.15,
      ('USD' || 'GOLD18', MarketForecastHorizon.oneHour) => 0.02,
      ('USD' || 'GOLD18', MarketForecastHorizon.twelveHours) => 0.05,
      ('USD' || 'GOLD18', MarketForecastHorizon.twentyFourHours) => 0.08,
      (_, MarketForecastHorizon.oneHour) => 0.02,
      (_, MarketForecastHorizon.twelveHours) => 0.04,
      _ => 0.07,
    };
    return math.min(hardCap, math.max(0.003, forecastVolatility * 3));
  }

  double _coverageHours(List<IntelligenceHistoryPoint> points) =>
      points.length < 2
      ? 0
      : points.last.time
                .toUtc()
                .difference(points.first.time.toUtc())
                .inSeconds /
            3600;

  double _medianGapHours(List<IntelligenceHistoryPoint> points) {
    final gaps = <double>[];
    for (var index = 1; index < points.length; index++) {
      final gap =
          points[index].time
              .toUtc()
              .difference(points[index - 1].time.toUtc())
              .inSeconds /
          3600;
      if (gap > 0) gaps.add(gap);
    }
    return gaps.isEmpty ? double.infinity : _median(gaps);
  }

  _ForecastRequirement _requirementFor(MarketForecastHorizon horizon) =>
      switch (horizon) {
        MarketForecastHorizon.oneHour => const _ForecastRequirement(
          allowedRanges: <String>['oneHour'],
          minimumPoints: 6,
          minimumCoverageHours: 1 / 3,
          maximumMedianGapHours: 1 / 3,
        ),
        MarketForecastHorizon.twelveHours => const _ForecastRequirement(
          allowedRanges: <String>['oneDay', 'oneWeek'],
          minimumPoints: 8,
          minimumCoverageHours: 4,
          maximumMedianGapHours: 4,
        ),
        MarketForecastHorizon.twentyFourHours => const _ForecastRequirement(
          allowedRanges: <String>['oneWeek'],
          minimumPoints: 6,
          minimumCoverageHours: 72,
          maximumMedianGapHours: 30,
        ),
      };

  double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  String _fingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _ForecastRequirement {
  const _ForecastRequirement({
    required this.allowedRanges,
    required this.minimumPoints,
    required this.minimumCoverageHours,
    required this.maximumMedianGapHours,
  });

  final List<String> allowedRanges;
  final int minimumPoints;
  final double minimumCoverageHours;
  final double maximumMedianGapHours;
}

class _RobustStatistics {
  const _RobustStatistics({
    required this.projectedLogMove,
    required this.forecastVolatility,
    required this.signalAgreement,
  });

  final double projectedLogMove;
  final double forecastVolatility;
  final double signalAgreement;
}
