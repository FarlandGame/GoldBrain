import 'dart:math' as math;

import 'market_history_service.dart';

/// A descriptive reading of observed prices, never a forecast or trade signal.
class MarketPulse {
  const MarketPulse({
    required this.score,
    required this.reason,
    required this.priceReturnPercent,
    required this.volatilityPercent,
    required this.hasVolume,
    required this.hasNews,
    required this.sampleCount,
  });

  final int? score;
  final String? reason;
  final double? priceReturnPercent;
  final double? volatilityPercent;
  final bool hasVolume;
  final bool hasNews;
  final int sampleCount;

  bool get hasScore => score != null;
}

class MarketPulseCalculator {
  const MarketPulseCalculator();

  static double _tanh(double value) {
    final bounded = value.clamp(-20.0, 20.0);
    return 2 / (1 + math.exp(-2 * bounded)) - 1;
  }

  MarketPulse calculate(
    MarketHistorySeries series, {
    double? newsTone,
    DateTime? now,
    Duration? minimumObservedSpan,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    MarketPulse unavailable(String reason) => MarketPulse(
      score: null,
      reason: reason,
      priceReturnPercent: null,
      volatilityPercent: null,
      hasVolume: false,
      hasNews: false,
      sampleCount: series.candles.length,
    );

    if (series.isStale || series.hasDisallowedDomesticSource) {
      return unavailable('Source history is stale or unverified.');
    }
    final points = series.candles;
    if (points.length < 4)
      return unavailable(
        'Insufficient history: at least four observations are required.',
      );
    DateTime? previous;
    for (final point in points) {
      final time = point.time.toUtc();
      if (!point.close.isFinite ||
          point.close <= 0 ||
          (previous != null && !time.isAfter(previous)) ||
          time.isAfter(current.add(const Duration(minutes: 5)))) {
        return unavailable(
          'History contains invalid or unordered observations.',
        );
      }
      previous = time;
    }
    final domestic = const {'USD', 'EUR', 'GOLD18'}.contains(series.symbol);
    final maxAge = switch (series.range) {
      MarketHistoryRange.oneHour => const Duration(minutes: 15),
      MarketHistoryRange.oneDay =>
        domestic ? const Duration(hours: 3) : const Duration(hours: 8),
      MarketHistoryRange.oneWeek ||
      MarketHistoryRange.oneMonth => const Duration(days: 4),
    };
    if (current.difference(points.last.time.toUtc()) > maxAge) {
      return unavailable('Latest market observation is too old.');
    }
    final minimumCoverage = switch (series.range) {
      MarketHistoryRange.oneHour => 0.25,
      MarketHistoryRange.oneDay => 0.25,
      MarketHistoryRange.oneWeek => 0.50,
      MarketHistoryRange.oneMonth => 0.65,
    };
    final requiredSpan =
        minimumObservedSpan ??
        Duration(
          microseconds: (series.requestedSpan.inMicroseconds * minimumCoverage)
              .ceil(),
        );
    if (requiredSpan <= Duration.zero || series.observedSpan < requiredSpan) {
      return unavailable('Insufficient coverage for the selected window.');
    }
    // A cached HTTP response is not evidence that its last market observation
    // is current. The source-specific stale flag remains authoritative.
    final logReturns = <double>[
      for (var i = 1; i < points.length; i++)
        math.log(points[i].close / points[i - 1].close),
    ];
    final mean = logReturns.reduce((a, b) => a + b) / logReturns.length;
    final variance =
        logReturns
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        (logReturns.length - 1);
    final sigma = math.sqrt(variance);
    final netReturn = math.log(points.last.close / points.first.close);
    final periodVolatility = sigma * math.sqrt(logReturns.length);
    final directionalStrength = _tanh(netReturn / (0.01 + periodVolatility));
    final volatilityDamping = 1 / (1 + 5 * periodVolatility);
    var score = 50 + 45 * directionalStrength * volatilityDamping;

    var hasVolume = false;
    if (!series.isPriceSample &&
        points.every((point) => point.volume != null && point.volume! > 0)) {
      final split = points.length ~/ 2;
      final earlier =
          points
              .take(split)
              .map((point) => point.volume!)
              .reduce((a, b) => a + b) /
          split;
      final laterCount = points.length - split;
      final later =
          points
              .skip(split)
              .map((point) => point.volume!)
              .reduce((a, b) => a + b) /
          laterCount;
      final volumeConfirmation =
          50 + 50 * directionalStrength.sign * _tanh(math.log(later / earlier));
      score = 0.85 * score + 0.15 * volumeConfirmation;
      hasVolume = true;
    }
    final hasNews = newsTone != null && newsTone.isFinite;
    if (hasNews) {
      final sentimentScore = 50 + newsTone.clamp(-10.0, 10.0) * 5;
      score = 0.80 * score + 0.20 * sentimentScore;
    }
    return MarketPulse(
      score: score.round().clamp(0, 100),
      reason: null,
      priceReturnPercent: (math.exp(netReturn) - 1) * 100,
      volatilityPercent: periodVolatility * 100,
      hasVolume: hasVolume,
      hasNews: hasNews,
      sampleCount: points.length,
    );
  }
}
