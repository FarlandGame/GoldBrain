enum MarketForecastHorizon { oneHour, twelveHours, twentyFourHours }

const Set<String> _supportedForecastSymbols = <String>{
  'GOLD18',
  'XAU',
  'XAG',
  'USD',
  'USDT',
  'BTC',
  'ETH',
};

extension MarketForecastHorizonX on MarketForecastHorizon {
  Duration get duration => switch (this) {
    MarketForecastHorizon.oneHour => const Duration(hours: 1),
    MarketForecastHorizon.twelveHours => const Duration(hours: 12),
    MarketForecastHorizon.twentyFourHours => const Duration(hours: 24),
  };

  String get wireName => switch (this) {
    MarketForecastHorizon.oneHour => '1h',
    MarketForecastHorizon.twelveHours => '12h',
    MarketForecastHorizon.twentyFourHours => '24h',
  };

  static MarketForecastHorizon? parse(Object? value) => switch (value) {
    '1h' || 'oneHour' => MarketForecastHorizon.oneHour,
    '12h' || 'twelveHours' => MarketForecastHorizon.twelveHours,
    '24h' || 'twentyFourHours' => MarketForecastHorizon.twentyFourHours,
    _ => null,
  };
}

enum MarketForecastDirection { upward, downward, neutral }

/// A deterministic, source-backed price scenario.
///
/// [lowerBound] and [upperBound] form an 80% model uncertainty interval. It
/// is not a guarantee and it is not a statistically calibrated probability.
/// No instance may be created without a real anchor, exact (non-proxy)
/// history, a target timestamp and explicit provenance.
class MarketForecast {
  const MarketForecast({
    required this.id,
    required this.symbol,
    required this.horizon,
    required this.direction,
    required this.generatedAt,
    required this.targetFor,
    required this.anchorPrice,
    required this.pointEstimate,
    required this.lowerBound,
    required this.upperBound,
    required this.unit,
    required this.confidenceScore,
    required this.dataQualityPercent,
    required this.evidencePointCount,
    required this.evidenceFingerprint,
    required this.sources,
    required this.historyRange,
    required this.sourceLatestAt,
    this.intervalLevel = 0.80,
    this.methodVersion = 1,
  });

  final String id;
  final String symbol;
  final MarketForecastHorizon horizon;
  final MarketForecastDirection direction;
  final DateTime generatedAt;
  final DateTime targetFor;
  final double anchorPrice;
  final double pointEstimate;
  final double lowerBound;
  final double upperBound;
  final String unit;

  /// A bounded model-quality score, deliberately not named probability.
  final int confidenceScore;
  final int dataQualityPercent;
  final int evidencePointCount;
  final String evidenceFingerprint;
  final List<String> sources;
  final String historyRange;
  final DateTime sourceLatestAt;
  final double intervalLevel;
  final int methodVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'symbol': symbol,
    'horizon': horizon.wireName,
    'direction': direction.name,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'targetFor': targetFor.toUtc().toIso8601String(),
    'anchorPrice': anchorPrice,
    'pointEstimate': pointEstimate,
    'lowerBound': lowerBound,
    'upperBound': upperBound,
    'unit': unit,
    'confidenceScore': confidenceScore,
    'dataQualityPercent': dataQualityPercent,
    'evidencePointCount': evidencePointCount,
    'evidenceFingerprint': evidenceFingerprint,
    'sources': sources,
    'historyRange': historyRange,
    'sourceLatestAt': sourceLatestAt.toUtc().toIso8601String(),
    'intervalLevel': intervalLevel,
    'methodVersion': methodVersion,
  };

  static MarketForecast? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    final symbol = value['symbol']?.toString().trim().toUpperCase() ?? '';
    final horizon = MarketForecastHorizonX.parse(value['horizon']);
    final directionName = value['direction']?.toString();
    final direction = MarketForecastDirection.values
        .where((item) => item.name == directionName)
        .firstOrNull;
    final generatedAt = DateTime.tryParse(
      value['generatedAt']?.toString() ?? '',
    );
    final targetFor = DateTime.tryParse(value['targetFor']?.toString() ?? '');
    final sourceLatestAt = DateTime.tryParse(
      value['sourceLatestAt']?.toString() ?? '',
    );
    final anchor = _finitePositive(value['anchorPrice']);
    final estimate = _finitePositive(value['pointEstimate']);
    final lower = _finitePositive(value['lowerBound']);
    final upper = _finitePositive(value['upperBound']);
    final unit = value['unit']?.toString().trim().toUpperCase() ?? '';
    final fingerprint = value['evidenceFingerprint']?.toString().trim() ?? '';
    final historyRange = value['historyRange']?.toString().trim() ?? '';
    final rawSources = value['sources'];
    final sources = rawSources is List
        ? rawSources
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .take(8)
              .toList(growable: false)
        : const <String>[];
    final rawConfidence = value['confidenceScore'];
    final rawQuality = value['dataQualityPercent'];
    final rawPointCount = value['evidencePointCount'];
    final rawMethodVersion = value['methodVersion'];
    if (id.isEmpty ||
        !_supportedForecastSymbols.contains(symbol) ||
        horizon == null ||
        direction == null ||
        generatedAt == null ||
        targetFor == null ||
        sourceLatestAt == null ||
        anchor == null ||
        estimate == null ||
        lower == null ||
        upper == null ||
        lower > estimate ||
        estimate > upper ||
        unit.isEmpty ||
        fingerprint.isEmpty ||
        historyRange.isEmpty ||
        sources.isEmpty ||
        sources.any((source) => source.trim().isEmpty) ||
        rawConfidence is! num ||
        rawConfidence < 0 ||
        rawConfidence > 85 ||
        rawQuality is! num ||
        rawQuality < 50 ||
        rawQuality > 100 ||
        rawPointCount is! num ||
        rawPointCount < 6 ||
        rawMethodVersion is! num ||
        rawMethodVersion.round() != 1 ||
        sourceLatestAt.isAfter(generatedAt) ||
        !targetFor.isAfter(generatedAt)) {
      return null;
    }
    final expectedTarget = generatedAt.toUtc().add(horizon.duration);
    if ((targetFor.toUtc().difference(expectedTarget).inSeconds).abs() > 1) {
      return null;
    }
    if ((direction == MarketForecastDirection.upward && estimate <= anchor) ||
        (direction == MarketForecastDirection.downward && estimate >= anchor)) {
      return null;
    }
    final neutralMaximumDistance = ((upper - lower) / 2).clamp(
      anchor * 0.002,
      anchor * 0.02,
    );
    if (direction == MarketForecastDirection.neutral &&
        (estimate - anchor).abs() > neutralMaximumDistance) {
      return null;
    }
    return MarketForecast(
      id: id,
      symbol: symbol,
      horizon: horizon,
      direction: direction,
      generatedAt: generatedAt.toUtc(),
      targetFor: targetFor.toUtc(),
      anchorPrice: anchor,
      pointEstimate: estimate,
      lowerBound: lower,
      upperBound: upper,
      unit: unit,
      confidenceScore: rawConfidence.round(),
      dataQualityPercent: _boundedInt(rawQuality, maximum: 100),
      evidencePointCount: _boundedInt(rawPointCount, maximum: 100000),
      evidenceFingerprint: fingerprint,
      sources: List.unmodifiable(sources),
      historyRange: historyRange,
      sourceLatestAt: sourceLatestAt.toUtc(),
      intervalLevel:
          _finitePositive(value['intervalLevel'])?.clamp(0.5, 0.99) ?? 0.80,
      methodVersion: rawMethodVersion.round(),
    );
  }
}

class MarketForecastOutcome {
  const MarketForecastOutcome({
    required this.actualAt,
    required this.actualPrice,
    required this.actualSource,
    required this.absoluteError,
    required this.absolutePercentageError,
    required this.directionHit,
    required this.intervalHit,
  });

  final DateTime actualAt;
  final double actualPrice;
  final String actualSource;
  final double absoluteError;
  final double absolutePercentageError;
  final bool directionHit;
  final bool intervalHit;

  Map<String, Object?> toJson() => <String, Object?>{
    'actualAt': actualAt.toUtc().toIso8601String(),
    'actualPrice': actualPrice,
    'actualSource': actualSource,
    'absoluteError': absoluteError,
    'absolutePercentageError': absolutePercentageError,
    'directionHit': directionHit,
    'intervalHit': intervalHit,
  };

  static MarketForecastOutcome? fromJson(Object? value) {
    if (value is! Map) return null;
    final actualAt = DateTime.tryParse(value['actualAt']?.toString() ?? '');
    final actualPrice = _finitePositive(value['actualPrice']);
    final absoluteError = _finiteNonNegative(value['absoluteError']);
    final percentageError = _finiteNonNegative(
      value['absolutePercentageError'],
    );
    final source = value['actualSource']?.toString().trim() ?? '';
    if (actualAt == null ||
        actualPrice == null ||
        absoluteError == null ||
        percentageError == null ||
        source.isEmpty ||
        value['directionHit'] is! bool ||
        value['intervalHit'] is! bool) {
      return null;
    }
    return MarketForecastOutcome(
      actualAt: actualAt.toUtc(),
      actualPrice: actualPrice,
      actualSource: source,
      absoluteError: absoluteError,
      absolutePercentageError: percentageError,
      directionHit: value['directionHit'] as bool,
      intervalHit: value['intervalHit'] as bool,
    );
  }
}

class MarketForecastRecord {
  const MarketForecastRecord({required this.forecast, this.outcome});

  final MarketForecast forecast;
  final MarketForecastOutcome? outcome;

  bool get isEvaluated => outcome != null;

  MarketForecastRecord withOutcome(MarketForecastOutcome value) =>
      MarketForecastRecord(forecast: forecast, outcome: value);

  Map<String, Object?> toJson() => <String, Object?>{
    'forecast': forecast.toJson(),
    'outcome': outcome?.toJson(),
  };

  static MarketForecastRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final forecast = MarketForecast.fromJson(value['forecast']);
    if (forecast == null) return null;
    final rawOutcome = value['outcome'];
    final outcome = rawOutcome == null
        ? null
        : MarketForecastOutcome.fromJson(rawOutcome);
    if (rawOutcome != null && outcome == null) return null;
    if (outcome != null) {
      final maximumDelay = switch (forecast.horizon) {
        MarketForecastHorizon.oneHour => const Duration(minutes: 30),
        MarketForecastHorizon.twelveHours => const Duration(hours: 3),
        MarketForecastHorizon.twentyFourHours => const Duration(hours: 12),
      };
      if (outcome.actualAt.isBefore(forecast.targetFor) ||
          outcome.actualAt.isAfter(forecast.targetFor.add(maximumDelay)) ||
          _normalizedForecastSource(outcome.actualSource) !=
              _normalizedForecastSource(forecast.sources.first)) {
        return null;
      }
      final expectedError = (outcome.actualPrice - forecast.pointEstimate)
          .abs();
      final expectedPercentage = expectedError / outcome.actualPrice * 100;
      if ((expectedError - outcome.absoluteError).abs() >
              _numericTolerance(expectedError) ||
          (expectedPercentage - outcome.absolutePercentageError).abs() >
              _numericTolerance(expectedPercentage)) {
        return null;
      }
      final actualMove = outcome.actualPrice - forecast.anchorPrice;
      final widthBand = (forecast.upperBound - forecast.lowerBound) * 0.08;
      final anchorBand = forecast.anchorPrice * 0.0005;
      final neutralBand = widthBand > anchorBand ? widthBand : anchorBand;
      final expectedDirectionHit = switch (forecast.direction) {
        MarketForecastDirection.upward => actualMove > neutralBand,
        MarketForecastDirection.downward => actualMove < -neutralBand,
        MarketForecastDirection.neutral => actualMove.abs() <= neutralBand,
      };
      final expectedIntervalHit =
          outcome.actualPrice >= forecast.lowerBound &&
          outcome.actualPrice <= forecast.upperBound;
      if (outcome.directionHit != expectedDirectionHit ||
          outcome.intervalHit != expectedIntervalHit) {
        return null;
      }
    }
    return MarketForecastRecord(forecast: forecast, outcome: outcome);
  }
}

class MarketForecastMetrics {
  const MarketForecastMetrics({
    required this.sampleCount,
    required this.meanAbsoluteError,
    required this.meanAbsolutePercentageError,
    required this.directionalHitRate,
    required this.intervalHitRate,
    required this.unit,
  });

  static const minimumDisplaySamples = 10;

  final int sampleCount;
  final double meanAbsoluteError;
  final double meanAbsolutePercentageError;
  final double directionalHitRate;
  final double intervalHitRate;
  final String unit;

  bool get isDisplayReady => sampleCount >= minimumDisplaySamples;
}

double? _finitePositive(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
}

String _normalizedForecastSource(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

double? _finiteNonNegative(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
}

int _boundedInt(Object? value, {required int maximum}) =>
    value is num ? value.round().clamp(0, maximum) : 0;

double _numericTolerance(double value) =>
    value.abs() < 1 ? 1e-9 : value.abs() * 1e-9;
