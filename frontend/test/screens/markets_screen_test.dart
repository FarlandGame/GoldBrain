import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/internet_connection_service.dart';
import 'package:goldbrain/core/live_market_store.dart';
import 'package:goldbrain/core/local_quote_history_store.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:goldbrain/screens/markets_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows only verified market fields and source coverage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final service = GlobalPriceService(
      navasanApiKey: 'test-key',
      client: MockClient((request) async {
        if (request.url.host == 'api.navasan.tech') {
          return http.Response(
            jsonEncode({
              'usd_sell': {'value': 185400, 'timestamp': now},
              '18ayar': {'value': 18809300, 'timestamp': now},
            }),
            200,
          );
        }
        final category = request.url.queryParameters['category'];
        final items = switch (category) {
          'gold' => [
            _item('XAU18', 18809300, 0.03, 'تومان / گرم', 'tgju'),
            _item('XAUUSD', 4361.2, 0.35, 'دلار', 'gold-api'),
            _item('XAGUSD', 65.19, 0.3, 'دلار', 'gold-api'),
          ],
          'crypto' => [
            _item('USDT', 185700, 0.2, 'تومان', 'tgju'),
            _item('BTC', 63878, -2.1, 'USDT', 'coingecko'),
            _item('ETH', 1871.76, -2.8, 'USDT', 'coingecko'),
          ],
          _ => <Map<String, Object>>[],
        };
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {'items': items},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final historyService = MarketHistoryService(
      navasanApiKey: '',
      arzhaamApiKey: '',
      allowPublicDomesticFallback: true,
      client: MockClient((request) async {
        if (request.url.host == 'english.tgju.org') {
          return http.Response(_tgjuHistoryHtml(), 200);
        }
        expect(request.url.queryParameters['endpoint'], 'chart');
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'candles': [
                _candle(now - 7200, 4300),
                _candle(now - 3600, 4350),
                _candle(now, 4361.2),
              ],
              'meta': {'provider': 'yahoo_v8'},
            },
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarketsScreen(
              palette: themePalettes[GoldBrainTheme.gold]!,
              selectedLanguage: GoldBrainLanguage.english,
              currencyCode: 'auto',
              priceService: service,
              historyService: historyService,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('7/7 PRICES'), findsOneWidget);
    expect(find.byTooltip('Refresh prices'), findsOneWidget);
    expect(
      find.textContaining('101.45'),
      findsWidgets,
      reason: 'English + auto must display the sourced IRT quote in USD.',
    );
    expect(find.text('Navasan · 18ayar'), findsWidgets);
    expect(find.textContaining('Navasan free data refresh'), findsOneWidget);
    expect(
      find.textContaining('Source: TGJU · real daily OHLC'),
      findsOneWidget,
    );
    expect(find.text('1H'), findsOneWidget);

    await tester.tap(find.text('1H'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(
      find.text('Iranian-market history needs an API key'),
      findsOneWidget,
    );
    expect(find.textContaining('NAVASAN_API_KEY'), findsOneWidget);

    await tester.tap(find.text('7D'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.textContaining('Source: TGJU · real daily OHLC'),
      findsOneWidget,
    );

    await tester.tap(find.text('Global Gold Ounce'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.textContaining('Navasan free-tier data update'), findsNothing);
    expect(find.text('REAL PRICE HISTORY'), findsOneWidget);
    expect(find.textContaining('Source: ZARIX · yahoo_v8'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('expand-market-chart')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(
      find.byKey(const ValueKey('expanded-market-chart-dialog')),
      findsOneWidget,
    );
    expect(find.text('24H HIGH'), findsNothing);
    expect(find.text('VOLUME'), findsNothing);
    expect(find.text('OIL'), findsNothing);
    expect(find.text('NASDAQ'), findsNothing);
    expect(find.text('SPX'), findsNothing);
    expect(find.textContaining('DEMO'), findsNothing);
  });

  testWidgets('renders a local chart only after same-source time coverage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final localHistory = LocalQuoteHistoryStore();
    for (var index = 0; index < 6; index++) {
      await localHistory.recordQuotes({
        'GOLD18': _modelQuote(
          price: 19000000 + index * 1000,
          time: now.subtract(Duration(hours: 10 - index * 2)),
        ),
      });
    }
    final store = LiveMarketStore(
      service: _StaticGoldPriceService(now),
      internetService: InternetConnectionService(
        client: MockClient((_) async => http.Response('{"ok":true}', 200)),
        probeUris: [Uri.parse('https://probe.example/status')],
      ),
      localHistoryStore: localHistory,
      symbols: const {'GOLD18'},
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarketsScreen(
              palette: themePalettes[GoldBrainTheme.gold]!,
              selectedLanguage: GoldBrainLanguage.english,
              currencyCode: 'auto',
              marketStore: store,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.textContaining('verified same-source samples'), findsOneWidget);
    expect(find.textContaining('no interpolation'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'GOLD18 oneWeek chart, \d+ real points')),
      findsOneWidget,
    );
  });

  for (final completionOrder in [
    ['GOLD18', 'XAU'],
    ['XAU', 'GOLD18'],
  ]) {
    testWidgets(
      'retains pending chart after A to B to A navigation (${completionOrder.join(',')})',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime.now();
        final history = _PendingHistoryService();
        final store = LiveMarketStore(
          service: _StaticGoldPriceService(now),
          internetService: InternetConnectionService(
            client: MockClient((_) async => http.Response('{"ok":true}', 200)),
            probeUris: [Uri.parse('https://probe.example/status')],
          ),
          autoRefreshInterval: const Duration(hours: 1),
        );
        addTearDown(store.dispose);
        addTearDown(history.close);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MarketsScreen(
                  palette: themePalettes[GoldBrainTheme.gold]!,
                  selectedLanguage: GoldBrainLanguage.english,
                  currencyCode: 'IRT',
                  marketStore: store,
                  historyService: history,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Global Gold Ounce'));
        await tester.pump();
        await tester.tap(find.text('Gold 18K').first);
        await tester.pump();
        expect(history.requestedSymbols, ['GOLD18', 'XAU']);

        for (final symbol in completionOrder) {
          history.complete(symbol, now);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(
          find.bySemanticsLabel(RegExp(r'GOLD18 oneWeek chart, 3 real points')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('chart-unavailable')), findsNothing);
        expect(find.byKey(const ValueKey('chart-loading')), findsNothing);
        await tester.tap(find.text('Global Gold Ounce'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.bySemanticsLabel(RegExp(r'XAU oneWeek chart, 3 real points')),
          findsOneWidget,
        );
        expect(history.requestedSymbols, ['GOLD18', 'XAU']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _PendingHistoryService extends MarketHistoryService {
  final requestedSymbols = <String>[];
  final _pending = <String, Completer<MarketHistorySeries>>{};

  @override
  Future<MarketHistorySeries> fetchHistory(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
    bool forceRefresh = false,
  }) {
    requestedSymbols.add(symbol);
    final completer = Completer<MarketHistorySeries>();
    _pending[symbol] = completer;
    return completer.future;
  }

  void complete(String symbol, DateTime now) {
    _pending[symbol]!.complete(
      MarketHistorySeries(
        symbol: symbol,
        currency: symbol == 'GOLD18' ? 'IRT' : 'USD',
        range: MarketHistoryRange.oneWeek,
        candles: [
          for (var index = 0; index < 3; index++)
            MarketCandle(
              time: now.subtract(Duration(days: 6 - index * 3)),
              open: 100.0 + index,
              high: 101.0 + index,
              low: 99.0 + index,
              close: 100.0 + index,
            ),
        ],
        provider: MarketHistoryProvider.backend,
        providerLabel: 'test $symbol',
        fetchedAt: now,
      ),
    );
  }
}

Map<String, Object> _candle(int time, num close) => {
  'time': time,
  'open': close,
  'high': close + 5,
  'low': close - 5,
  'close': close,
};

Map<String, Object> _item(
  String symbol,
  num price,
  num change,
  String unit,
  String source,
) {
  return {
    'symbol': symbol,
    'title': symbol,
    'price': price,
    'changePercent': change,
    'unit': unit,
    'updatedAt': '2026-08-10T17:25:47Z',
    'source': source,
  };
}

String _tgjuHistoryHtml() {
  final now = DateTime.now();
  final html = StringBuffer('<table>');
  for (var index = 0; index < 8; index++) {
    final day = now.subtract(Duration(days: index));
    final date =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final open = 190000000 + index * 100000;
    html.write(
      '<tr><td>$open</td><td>${open - 100000}</td>'
      '<td>${open + 200000}</td><td>${open + 100000}</td>'
      '<td>0</td><td>0</td><td>$date</td></tr>',
    );
  }
  html.write('</table>');
  return html.toString();
}

GlobalPriceQuote _modelQuote({required double price, required DateTime time}) {
  return GlobalPriceQuote(
    symbol: 'GOLD18',
    name: 'Gold 18K',
    currency: 'IRT',
    price: price,
    updatedAt: time,
    provider: GlobalPriceProvider.navasan,
    changePercent: 0.1,
    upstreamSource: '18ayar',
  );
}

class _StaticGoldPriceService extends GlobalPriceService {
  _StaticGoldPriceService(this.now);

  final DateTime now;

  @override
  Future<GlobalPriceBatch> fetchQuotes(
    Iterable<String> symbols, {
    bool forceRefresh = false,
  }) async {
    return GlobalPriceBatch(
      requestedSymbols: symbols.toSet(),
      quotes: {'GOLD18': _modelQuote(price: 19006000, time: now)},
      errors: const {},
    );
  }
}
