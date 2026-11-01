import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:goldbrain/screens/dashboard_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';

void main() {
  test('daily index closes form one trend line across the weekend', () {
    final candles = [
      _sample(DateTime.utc(2026, 9, 24, 20), 6500),
      _sample(DateTime.utc(2026, 9, 25, 20), 6450),
      _sample(DateTime.utc(2026, 9, 28, 20), 6600),
      _sample(DateTime.utc(2026, 9, 29, 20), 6400),
      _sample(DateTime.utc(2026, 9, 30, 20), 6300),
    ];
    final canvas = TestRecordingCanvas();
    _painter(
      candles,
      connectDailyIndexObservations: true,
    ).paint(canvas, const Size(600, 300));

    final line = _linePath(canvas);
    final contours = line.computeMetrics().toList();
    final markers = _pointMarkers(canvas);
    expect(markers, hasLength(5));
    expect(contours, hasLength(1));
    final expectedLength = List.generate(
      markers.length - 1,
      (i) => (markers[i + 1] - markers[i]).distance,
    ).reduce((a, b) => a + b);
    expect(contours.single.length, closeTo(expectedLength, 0.01));
    _expectNear(
      contours.single.getTangentForOffset(0)!.position,
      markers.first,
    );
    _expectNear(
      contours.single.getTangentForOffset(contours.single.length)!.position,
      markers.last,
    );

    // Real timestamps remain on the x-axis: Friday -> Monday spans three
    // times Thursday -> Friday, with no invented weekend observations.
    expect(
      markers[2].dx - markers[1].dx,
      closeTo(3 * (markers[1].dx - markers[0].dx), 0.01),
    );
    // Sample charts retain the existing glow/line strokes and point markers,
    // without adding an OHLC-style filled area below sampled index values.
    expect(_pathPaints(canvas).map((paint) => paint.style), [
      PaintingStyle.stroke,
      PaintingStyle.stroke,
    ]);
  });

  test('ordinary price samples still break the line at long intraday gaps', () {
    final start = DateTime.utc(2026, 9, 30, 8);
    final candles = [
      _sample(start, 100),
      _sample(start.add(const Duration(hours: 1)), 110),
      _sample(start.add(const Duration(hours: 7)), 90),
    ];
    final canvas = TestRecordingCanvas();
    // Leave the new flag at its default, as domestic sample charts do.
    _painter(candles).paint(canvas, const Size(600, 300));

    final contours = _linePath(canvas).computeMetrics().toList();
    final markers = _pointMarkers(canvas);
    expect(markers, hasLength(3));
    expect(contours, hasLength(1));
    expect(
      contours.single.length,
      closeTo((markers[1] - markers[0]).distance, 0.01),
    );
    _expectNear(
      contours.single.getTangentForOffset(contours.single.length)!.position,
      markers[1],
    );
    // The distant sample remains a point; the earlier line does not reach it.
    expect((markers.last - markers[1]).distance, greaterThan(100));
  });

  test('changing daily index connection mode requests a repaint', () {
    final candles = [
      _sample(DateTime.utc(2026, 9, 29), 6500),
      _sample(DateTime.utc(2026, 9, 30), 6400),
    ];
    final disconnected = _painter(candles);
    final connected = _painter(candles, connectDailyIndexObservations: true);
    expect(connected.shouldRepaint(disconnected), isTrue);
    expect(disconnected.shouldRepaint(connected), isTrue);
    expect(
      connected.shouldRepaint(
        _painter(candles, connectDailyIndexObservations: true),
      ),
      isFalse,
    );
  });
}

MarketCandle _sample(DateTime time, double price) => MarketCandle(
  time: time,
  open: price,
  high: price,
  low: price,
  close: price,
  isPriceSample: true,
);

NeuralChartPainter _painter(
  List<MarketCandle> candles, {
  bool connectDailyIndexObservations = false,
}) => NeuralChartPainter(
  palette: themePalettes[GoldBrainTheme.white]!,
  candles: candles,
  isPriceSample: true,
  connectDailyIndexObservations: connectDailyIndexObservations,
  animationProgress: 0,
  scanProgress: 0,
);

Path _linePath(TestRecordingCanvas canvas) =>
    canvas.invocations
            .where((record) => record.invocation.memberName == #drawPath)
            .map((record) => record.invocation.positionalArguments)
    .singleWhere((args) => ((args[1] as Paint).strokeWidth - 2.4).abs() < 0.001)
            .first
        as Path;

Iterable<Paint> _pathPaints(TestRecordingCanvas canvas) => canvas.invocations
    .where((record) => record.invocation.memberName == #drawPath)
    .map((record) => record.invocation.positionalArguments[1] as Paint);

List<Offset> _pointMarkers(TestRecordingCanvas canvas) => canvas.invocations
    .where((record) => record.invocation.memberName == #drawCircle)
    .map((record) => record.invocation.positionalArguments)
    .where((args) => args[1] == 2.4)
    .map((args) => args[0] as Offset)
    .toList();

void _expectNear(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 0.01));
  expect(actual.dy, closeTo(expected.dy, 0.01));
}
