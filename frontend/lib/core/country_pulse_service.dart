import 'backend_api_client.dart';
import 'backend_connection.dart';
import 'market_history_service.dart';
import 'market_pulse.dart';

class CountryPulseEvidence {
  const CountryPulseEvidence({
    required this.country,
    required this.indexName,
    required this.indexProvider,
    required this.indexStatus,
    required this.newsStatus,
    required this.series,
    this.newsTone,
  });

  final String country;
  final String indexName;
  final String indexProvider;
  final String indexStatus;
  final String newsStatus;
  final double? newsTone;
  final MarketHistorySeries series;

  MarketPulse calculatePulse({DateTime? now}) {
    // SSE's regular session runs from 09:30 to 15:00 local time, with a
    // lunch break. A complete observed session spans 5.5 hours, so the
    // generic six-hour 24h coverage gate would reject it every day.
    // Only this exact country/index policy can use the session threshold.
    final isShanghaiIntraday =
        country == 'china' &&
        series.symbol == '000001.SS' &&
        series.currency == 'CNY' &&
        series.provider == MarketHistoryProvider.backend &&
        series.isPriceSample &&
        series.range == MarketHistoryRange.oneDay;
    return const MarketPulseCalculator().calculate(
      series,
      newsTone: newsTone,
      now: now,
      minimumObservedSpan: isShanghaiIntraday
          ? const Duration(hours: 5, minutes: 30)
          : null,
    );
  }

  factory CountryPulseEvidence.fromJson(
    Map<String, dynamic> body,
    String country,
    MarketHistoryRange range,
  ) {
    final window = switch (range) {
      MarketHistoryRange.oneDay => '24h',
      MarketHistoryRange.oneWeek => '7d',
      MarketHistoryRange.oneMonth => '30d',
      MarketHistoryRange.oneHour => throw const FormatException(
        'Unsupported country pulse window',
      ),
    };
    if (body['country'] != country ||
        body['window'] != window ||
        body['unit'] != 'index_points' ||
        !{'available', 'stale', 'unavailable'}.contains(body['index_status']) ||
        !{'available', 'unavailable'}.contains(body['news_status'])) {
      throw const FormatException('Invalid country pulse identity or status');
    }
    final rows = body['index_points'];
    if (rows is! List) throw const FormatException('Invalid index points');
    final points = <MarketCandle>[];
    DateTime? previous;
    for (final row in rows) {
      if (row is! Map) throw const FormatException('Invalid index point');
      final time = DateTime.tryParse('${row['time']}')?.toUtc();
      final price = row['close'];
      if (time == null ||
          price is! num ||
          !price.isFinite ||
          price <= 0 ||
          (previous != null && !time.isAfter(previous))) {
        throw const FormatException('Invalid or unordered country index');
      }
      previous = time;
      points.add(
        MarketCandle(
          time: time,
          open: price.toDouble(),
          high: price.toDouble(),
          low: price.toDouble(),
          close: price.toDouble(),
          isPriceSample: true,
        ),
      );
    }
    final checked = DateTime.tryParse('${body['checked_at']}')?.toUtc();
    if (checked == null)
      throw const FormatException('Missing country evidence time');
    final tone = body['news_tone'];
    return CountryPulseEvidence(
      country: country,
      indexName: '${body['index_name']}',
      indexProvider: '${body['index_provider']}',
      indexStatus: '${body['index_status']}',
      newsStatus: '${body['news_status']}',
      newsTone:
          body['news_status'] == 'available' && tone is num && tone.isFinite
          ? tone.toDouble()
          : null,
      series: MarketHistorySeries(
        symbol: '${body['index_symbol']}',
        currency: '${body['currency']}',
        range: range,
        candles: List.unmodifiable(points),
        provider: MarketHistoryProvider.backend,
        providerLabel: '${body['index_provider']}',
        fetchedAt: checked,
        isPriceSample: true,
        isStale: body['index_status'] != 'available',
      ),
    );
  }
}

class CountryPulseService {
  CountryPulseService({GoldBrainBackendClient? backend})
    : _backend = backend ?? BackendConnection.instance.api;

  final GoldBrainBackendClient _backend;

  Future<CountryPulseEvidence> fetch(
    String country,
    MarketHistoryRange range,
  ) async {
    final window = switch (range) {
      MarketHistoryRange.oneDay => '24h',
      MarketHistoryRange.oneWeek => '7d',
      MarketHistoryRange.oneMonth => '30d',
      MarketHistoryRange.oneHour => throw const FormatException(
        'Unsupported country pulse window',
      ),
    };
    final body = await _backend.countryPulseEvidence(country, window);
    return CountryPulseEvidence.fromJson(body, country, range);
  }
}
