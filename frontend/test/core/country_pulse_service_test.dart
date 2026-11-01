import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/country_pulse_service.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:goldbrain/core/market_pulse.dart';

void main() {
  final sessionEnd = DateTime.utc(2026, 9, 30, 7);
  Map<String, dynamic> shanghaiResponse() => {
    'country': 'china',
    'window': '24h',
    'index_symbol': '000001.SS',
    'index_name': 'SSE Composite',
    'currency': 'CNY',
    'unit': 'index_points',
    'index_provider': 'Yahoo Finance public chart',
    'index_status': 'available',
    'index_points': [
      for (final (i, minutes) in [
        330,
        300,
        270,
        240,
        210,
        120,
        90,
        60,
        30,
        0,
      ].indexed)
        {
          'time': sessionEnd
              .subtract(Duration(minutes: minutes))
              .toIso8601String(),
          'close': 100 + i,
        },
    ],
    'news_status': 'unavailable',
    'news_tone': null,
    'checked_at': sessionEnd.toIso8601String(),
  };

  CountryPulseEvidence shanghai(Map<String, dynamic> response) =>
      CountryPulseEvidence.fromJson(
        response,
        'china',
        MarketHistoryRange.oneDay,
      );

  test('a complete SSE session can score without relaxing asset coverage', () {
    final evidence = shanghai(shanghaiResponse());
    expect(evidence.series.observedSpan, const Duration(hours: 5, minutes: 30));
    expect(
      const MarketPulseCalculator()
          .calculate(evidence.series, now: sessionEnd)
          .score,
      isNull,
    );
    final pulse = evidence.calculatePulse(now: sessionEnd);
    expect(pulse.score, greaterThan(50));
    expect(pulse.sampleCount, 10);
    expect(pulse.priceReturnPercent, closeTo(9, 1e-10));
    expect(pulse.hasNews, isFalse);
    expect(pulse.hasVolume, isFalse);
    expect(evidence.series.currency, 'CNY');
    expect(evidence.series.candles.first.close, 100);
    expect(evidence.series.candles.last.close, 109);
  });

  test('SSE session policy rejects shorter and sparse observations', () {
    final shorter = shanghaiResponse();
    (shorter['index_points'] as List).removeAt(0);
    expect(shanghai(shorter).calculatePulse(now: sessionEnd).score, isNull);
    final sparse = shanghaiResponse();
    final points = sparse['index_points'] as List;
    sparse['index_points'] = [points.first, points[4], points.last];
    expect(shanghai(sparse).calculatePulse(now: sessionEnd).score, isNull);
    final empty = shanghaiResponse()..['index_points'] = <Object>[];
    expect(shanghai(empty).calculatePulse(now: sessionEnd).score, isNull);
  });

  test('SSE session policy preserves source stale and latest age gates', () {
    final stale = shanghaiResponse()..['index_status'] = 'stale';
    expect(shanghai(stale).calculatePulse(now: sessionEnd).score, isNull);
    expect(
      shanghai(
        shanghaiResponse(),
      ).calculatePulse(now: sessionEnd.add(const Duration(hours: 9))).score,
      isNull,
    );
  });

  test('SSE session policy preserves future and unordered data gates', () {
    final future = shanghaiResponse();
    ((future['index_points'] as List).last as Map)['time'] = sessionEnd
        .add(const Duration(minutes: 6))
        .toIso8601String();
    expect(shanghai(future).calculatePulse(now: sessionEnd).score, isNull);
    final unordered = shanghaiResponse();
    unordered['index_points'] = (unordered['index_points'] as List).reversed
        .toList();
    expect(() => shanghai(unordered), throwsFormatException);
  });

  test(
    'wrong country index or currency cannot use the SSE session threshold',
    () {
      for (final field in {
        'index_symbol': '^GSPC',
        'currency': 'USD',
      }.entries) {
        final response = shanghaiResponse()..[field.key] = field.value;
        expect(
          shanghai(response).calculatePulse(now: sessionEnd).score,
          isNull,
        );
      }
      final response = shanghaiResponse()
        ..['country'] = 'usa'
        ..['index_symbol'] = '^GSPC'
        ..['currency'] = 'USD';
      final usa = CountryPulseEvidence.fromJson(
        response,
        'usa',
        MarketHistoryRange.oneDay,
      );
      expect(usa.calculatePulse(now: sessionEnd).score, isNull);
      response['unit'] = 'USD';
      expect(
        () => CountryPulseEvidence.fromJson(
          response,
          'usa',
          MarketHistoryRange.oneDay,
        ),
        throwsFormatException,
      );
    },
  );

  test('weekly SSE history retains its normal coverage requirement', () {
    final response = shanghaiResponse()..['window'] = '7d';
    final evidence = CountryPulseEvidence.fromJson(
      response,
      'china',
      MarketHistoryRange.oneWeek,
    );
    expect(evidence.calculatePulse(now: sessionEnd).score, isNull);
  });

  test(
    'country evidence rejects a mismatched country and never invents index points',
    () {
      final now = DateTime.now().toUtc();
      final response = <String, dynamic>{
        'country': 'iran',
        'window': '7d',
        'index_symbol': 'TEDPIX',
        'index_name': 'Tehran Exchange Price Index',
        'currency': 'INDEX',
        'unit': 'index_points',
        'index_provider': 'TSETMC',
        'index_status': 'unavailable',
        'index_points': <Object>[],
        'news_status': 'unavailable',
        'news_tone': null,
        'checked_at': now.toIso8601String(),
      };
      final evidence = CountryPulseEvidence.fromJson(
        response,
        'iran',
        MarketHistoryRange.oneWeek,
      );
      expect(evidence.series.candles, isEmpty);
      expect(evidence.series.isStale, isTrue);
      expect(
        () => CountryPulseEvidence.fromJson(
          response,
          'usa',
          MarketHistoryRange.oneWeek,
        ),
        throwsFormatException,
      );
    },
  );
}
