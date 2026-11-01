import 'dart:math' as math;

import 'market_forecast.dart';
import 'market_intelligence_service.dart';

/// Keeps immutable forecasts and evaluates them only after their target time
/// against an exact, source-backed history point in the same unit.
class MarketForecastLedger {
  MarketForecastLedger({
    Iterable<MarketForecastRecord> records = const <MarketForecastRecord>[],
  }) : _records = List<MarketForecastRecord>.from(records) {
    _normalize();
  }

  static const int maximumRecords = 1000;

  List<MarketForecastRecord> _records;

  List<MarketForecastRecord> get records => List.unmodifiable(_records);

  bool add(MarketForecast forecast) {
    if (_records.any((record) => record.forecast.id == forecast.id)) {
      return false;
    }
    final bucket = _bucketFor(forecast);
    final existingIndex = _records.indexWhere(
      (record) =>
          record.outcome == null &&
          record.forecast.symbol == forecast.symbol &&
          record.forecast.horizon == forecast.horizon &&
          record.forecast.unit == forecast.unit &&
          _bucketFor(record.forecast) == bucket,
    );
    if (existingIndex >= 0) {
      _records[existingIndex] = MarketForecastRecord(forecast: forecast);
      _normalize();
      return true;
    }
    _records.add(MarketForecastRecord(forecast: forecast));
    _normalize();
    return true;
  }

  int evaluate(MarketIntelligenceInput input) {
    var evaluated = 0;
    final now = input.collectedAt.toUtc();
    final updated = <MarketForecastRecord>[];
    for (final record in _records) {
      final forecast = record.forecast;
      if (record.outcome != null || now.isBefore(forecast.targetFor.toUtc())) {
        updated.add(record);
        continue;
      }
      final actual = _findActual(input.histories, forecast, now);
      if (actual == null) {
        // A missing observation after the evaluation window is not silently
        // scored and must not remain pending forever (provider outage, market
        // closure or source-regime change). It expires without affecting any
        // accuracy metric.
        if (!now.isAfter(forecast.targetFor.add(_toleranceFor(forecast)))) {
          updated.add(record);
        }
        continue;
      }
      final error = (actual.price - forecast.pointEstimate).abs();
      final percentage = error / actual.price * 100;
      final actualMove = actual.price - forecast.anchorPrice;
      final neutralBand = math.max(
        forecast.anchorPrice * 0.0005,
        (forecast.upperBound - forecast.lowerBound) * 0.08,
      );
      final directionHit = switch (forecast.direction) {
        MarketForecastDirection.upward => actualMove > neutralBand,
        MarketForecastDirection.downward => actualMove < -neutralBand,
        MarketForecastDirection.neutral => actualMove.abs() <= neutralBand,
      };
      updated.add(
        record.withOutcome(
          MarketForecastOutcome(
            actualAt: actual.time,
            actualPrice: actual.price,
            actualSource: actual.source,
            absoluteError: error,
            absolutePercentageError: percentage,
            directionHit: directionHit,
            intervalHit:
                actual.price >= forecast.lowerBound &&
                actual.price <= forecast.upperBound,
          ),
        ),
      );
      evaluated++;
    }
    _records = updated;
    _normalize();
    return evaluated;
  }

  MarketForecastMetrics? metricsFor(
    String rawSymbol,
    MarketForecastHorizon horizon, {
    String? unit,
  }) {
    final symbol = rawSymbol.trim().toUpperCase();
    final records = _records
        .where(
          (record) =>
              record.outcome != null &&
              record.forecast.symbol == symbol &&
              record.forecast.horizon == horizon,
        )
        .toList(growable: false);
    if (records.isEmpty) return null;
    records.sort(
      (left, right) =>
          right.forecast.generatedAt.compareTo(left.forecast.generatedAt),
    );
    final selectedUnit =
        unit?.trim().toUpperCase() ?? records.first.forecast.unit;
    final sameUnit = records
        .where((record) => record.forecast.unit == selectedUnit)
        .toList(growable: false);
    if (sameUnit.isEmpty) return null;
    final sampleCount = sameUnit.length;
    final mae =
        sameUnit.fold<double>(
          0,
          (sum, record) => sum + record.outcome!.absoluteError,
        ) /
        sampleCount;
    final mape =
        sameUnit.fold<double>(
          0,
          (sum, record) => sum + record.outcome!.absolutePercentageError,
        ) /
        sampleCount;
    final directionalHits = sameUnit
        .where((record) => record.outcome!.directionHit)
        .length;
    final intervalHits = sameUnit
        .where((record) => record.outcome!.intervalHit)
        .length;
    return MarketForecastMetrics(
      sampleCount: sampleCount,
      meanAbsoluteError: mae,
      meanAbsolutePercentageError: mape,
      directionalHitRate: directionalHits / sampleCount * 100,
      intervalHitRate: intervalHits / sampleCount * 100,
      unit: selectedUnit,
    );
  }

  List<Object?> toJson() =>
      _records.map((record) => record.toJson()).toList(growable: false);

  static MarketForecastLedger fromJson(Object? value) {
    if (value is! List) return MarketForecastLedger();
    return MarketForecastLedger(
      records: value
          .map(MarketForecastRecord.fromJson)
          .whereType<MarketForecastRecord>(),
    );
  }

  _ActualPoint? _findActual(
    List<IntelligenceHistoryEvidence> histories,
    MarketForecast forecast,
    DateTime collectedAt,
  ) {
    final tolerance = _toleranceFor(forecast);
    final candidates = <_ActualPoint>[];
    for (final history in histories) {
      if (history.isProxy ||
          history.symbol.toUpperCase() != forecast.symbol ||
          history.unit.toUpperCase() != forecast.unit ||
          history.source.trim().isEmpty ||
          _normalizedSource(history.source) !=
              _normalizedSource(forecast.sources.first)) {
        continue;
      }
      for (final point in history.points) {
        final time = point.time.toUtc();
        if (time.isBefore(forecast.targetFor.toUtc()) ||
            time.isAfter(collectedAt) ||
            !point.close.isFinite ||
            point.close <= 0) {
          continue;
        }
        final distance = time.difference(forecast.targetFor.toUtc());
        if (distance <= tolerance) {
          candidates.add(
            _ActualPoint(
              time: time,
              price: point.close,
              source: history.source,
              distance: distance,
            ),
          );
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) {
      final distance = left.distance.compareTo(right.distance);
      if (distance != 0) return distance;
      return left.time.compareTo(right.time);
    });
    return candidates.first;
  }

  void _normalize() {
    final byId = <String, MarketForecastRecord>{};
    for (final record in _records) {
      final existing = byId[record.forecast.id];
      if (existing == null ||
          (existing.outcome == null && record.outcome != null)) {
        byId[record.forecast.id] = record;
      }
    }
    _records = byId.values.toList(growable: true)
      ..sort(
        (left, right) =>
            left.forecast.generatedAt.compareTo(right.forecast.generatedAt),
      );
    final pending = _records.where((record) => !record.isEvaluated).toList();
    final evaluated = _records.where((record) => record.isEvaluated).toList();
    final keptEvaluated = evaluated.length <= maximumRecords
        ? evaluated
        : evaluated.sublist(evaluated.length - maximumRecords);
    // A pending 24-hour checkpoint must survive the frequent 5-minute refresh
    // cycle until its target can be observed.
    _records = <MarketForecastRecord>[...keptEvaluated, ...pending]
      ..sort(
        (left, right) =>
            left.forecast.generatedAt.compareTo(right.forecast.generatedAt),
      );
  }

  int _bucketFor(MarketForecast forecast) {
    final bucket = switch (forecast.horizon) {
      MarketForecastHorizon.oneHour => const Duration(minutes: 15),
      MarketForecastHorizon.twelveHours => const Duration(hours: 1),
      MarketForecastHorizon.twentyFourHours => const Duration(hours: 2),
    };
    return forecast.generatedAt.toUtc().millisecondsSinceEpoch ~/
        bucket.inMilliseconds;
  }

  Duration _toleranceFor(MarketForecast forecast) => switch (forecast.horizon) {
    MarketForecastHorizon.oneHour => const Duration(minutes: 30),
    MarketForecastHorizon.twelveHours => const Duration(hours: 3),
    MarketForecastHorizon.twentyFourHours => const Duration(hours: 12),
  };
}

String _normalizedSource(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class _ActualPoint {
  const _ActualPoint({
    required this.time,
    required this.price,
    required this.source,
    required this.distance,
  });

  final DateTime time;
  final double price;
  final String source;
  final Duration distance;
}
