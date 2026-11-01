import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/live_market_store.dart';
import 'package:goldbrain/core/market_history_service.dart';
import 'package:goldbrain/core/country_pulse_service.dart';
import 'package:goldbrain/core/backend_api_client.dart';
import 'package:goldbrain/screens/dashboard_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:goldbrain/core/currency_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dashboard pulse paints only injected verified XAU candles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.sound_enabled': false,
      'settings.music_enabled': false,
      'settings.motion_enabled': false,
      'settings.reduced_motion': true,
    });
    tester.view.physicalSize = const Size(1600, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final history = _FakeHistoryService();
    final marketStore = LiveMarketStore(
      service: _StaticPriceService(),
      autoRefreshInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          selectedTheme: GoldBrainTheme.blue,
          selectedLanguage: GoldBrainLanguage.english,
          marketStore: marketStore,
          historyService: history,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<NeuralChartPainter>();
    expect(painters, isNotEmpty);
    expect(painters.first.candles.map((point) => point.close), [
      4300,
      4310,
      4305,
    ]);
    expect(
      find.byKey(const ValueKey('dashboard-history-unavailable')),
      findsNothing,
    );

    await tester.tap(find.text('1H'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(history.requestedRanges, contains(MarketHistoryRange.oneHour));

    await tester.ensureVisible(
      find.byKey(const ValueKey('open-dashboard-history')),
    );
    await tester.tap(find.byKey(const ValueKey('open-dashboard-history')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('dashboard-history-dialog')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    marketStore.dispose();
    history.close();
  });

  testWidgets(
    'pulse offers tracked assets and six country choices without fabricating Iran',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings.sound_enabled': false,
        'settings.music_enabled': false,
        'settings.motion_enabled': false,
        'settings.reduced_motion': true,
      });
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final history = _PulseHistoryService();
      final marketStore = LiveMarketStore(
        service: _StaticPriceService(),
        autoRefreshInterval: const Duration(hours: 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            selectedTheme: GoldBrainTheme.blue,
            selectedLanguage: GoldBrainLanguage.english,
            marketStore: marketStore,
            historyService: history,
            countryPulseService: _UnavailableIranService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('asset-pulse-score')), findsOneWidget);
      final picker = tester.widget<DropdownButton<String>>(
        find.byKey(const ValueKey('pulse-asset-picker')),
      );
      expect(
        picker.items!.map((item) => item.value),
        containsAll([
          'country:usa',
          'country:germany',
          'country:japan',
          'country:china',
          'country:france',
          'country:iran',
          'BTC',
          'GOLD18',
        ]),
      );
      expect(find.byType(ChoiceChip), findsNothing);

      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('pulse-asset-picker')),
          )
          .onChanged!('BTC');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(history.requestedSymbols, contains('BTC'));

      _selectPulse(tester, 'country:iran');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.textContaining('Tehran Exchange Price Index'),
        findsOneWidget,
      );
      expect(find.textContaining('100/100'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('asset-pulse-score')))
            .data,
        '—',
      );
      expect(
        find.byKey(const ValueKey('dashboard-history-unavailable')),
        findsOneWidget,
      );
      expect(_chartCloses(tester), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      marketStore.dispose();
      history.close();
    },
  );

  testWidgets('country pulse explains when a guest must sign in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.language_code': 'persian',
      'settings.sound_enabled': false,
      'settings.music_enabled': false,
      'settings.motion_enabled': false,
      'settings.reduced_motion': true,
    });
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final history = _PulseHistoryService();
    final marketStore = LiveMarketStore(
      service: _StaticPriceService(),
      autoRefreshInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          selectedTheme: GoldBrainTheme.blue,
          selectedLanguage: GoldBrainLanguage.persian,
          marketStore: marketStore,
          historyService: history,
          countryPulseService: _UnauthorizedCountryService(),
        ),
      ),
    );
    _selectPulse(tester, 'country:iran');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final status = tester.widget<Text>(
      find.byKey(const ValueKey('country-pulse-status')),
    );
    expect(
      status.data,
      anyOf(
        'برای دریافت دادهٔ بازار کشورها وارد حساب شوید.',
        'Sign in to load country market data.',
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    marketStore.dispose();
    history.close();
  });

  testWidgets(
    'all country windows replace the main chart and retain index units',
    (tester) async {
      _configureView(tester);
      CurrencyService.updateIranianTomanPerUsd(100000);
      CurrencyService.updateInternationalRates(const {'EUR': 0.9, 'JPY': 150});
      final history = _PulseHistoryService();
      final countries = _AvailableCountryService();
      final store = LiveMarketStore(
        service: _StaticPriceService(),
        autoRefreshInterval: const Duration(hours: 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            selectedTheme: GoldBrainTheme.blue,
            selectedLanguage: GoldBrainLanguage.english,
            marketStore: store,
            historyService: history,
            countryPulseService: countries,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('1H'));
      await tester.pump();
      final assetRequests = history.requestedSymbols.length;
      for (final country in [
        'usa',
        'germany',
        'japan',
        'china',
        'france',
        'iran',
      ]) {
        _selectPulse(tester, 'country:$country');
        await tester.pump();
        expect(find.text('1H'), findsNothing);
        for (final entry in {
          '24H': MarketHistoryRange.oneDay,
          '7D': MarketHistoryRange.oneWeek,
          '30D': MarketHistoryRange.oneMonth,
        }.entries) {
          await tester.tap(find.text(entry.key));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(countries.requests.last, (country, entry.value));
          expect(_chartCloses(tester), countries.closes(country));
          expect(
            tester
                .widgetList<CustomPaint>(find.byType(CustomPaint))
                .map((widget) => widget.painter)
                .whereType<NeuralChartPainter>()
                .single
                .connectDailyIndexObservations,
            entry.value != MarketHistoryRange.oneDay,
          );
          expect(
            find.byKey(const ValueKey('asset-pulse-score')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('country-pulse-status')),
                )
                .data,
            contains('index only; news unavailable'),
          );
          final scoreBeforeCurrencyChange = tester
              .widget<Text>(find.byKey(const ValueKey('asset-pulse-score')))
              .data;
          for (final currency in ['IRT', 'USD']) {
            await SettingsStore.instance.saveCurrencyCode(currency);
            await tester.pump();
            expect(SettingsStore.instance.currencyCode, currency);
            expect(_chartCloses(tester), countries.closes(country));
            expect(
              tester
                  .widget<Text>(find.byKey(const ValueKey('asset-pulse-score')))
                  .data,
              scoreBeforeCurrencyChange,
            );
          }
        }
      }
      expect(history.requestedSymbols.length, assetRequests);
      await tester.ensureVisible(
        find.byKey(const ValueKey('open-dashboard-history')),
      );
      await tester.tap(find.byKey(const ValueKey('open-dashboard-history')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('dashboard-history-dialog')),
        findsOneWidget,
      );
      expect(_chartCloses(tester), countries.closes('iran'));
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<NeuralChartPainter>()
            .every((painter) => painter.connectDailyIndexObservations),
        isTrue,
      );
      Navigator.of(
        tester.element(find.byKey(const ValueKey('dashboard-history-dialog'))),
      ).pop();
      await tester.pump(const Duration(milliseconds: 400));
      _selectPulse(tester, 'BTC');
      await tester.pump();
      expect(history.requestedSymbols.last, 'BTC');
      expect(_chartCloses(tester), [100, 101, 102, 103, 104]);
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.painter)
            .whereType<NeuralChartPainter>()
            .single
            .connectDailyIndexObservations,
        isFalse,
      );
      expect(find.text('1H'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      history.close();
    },
  );

  testWidgets('China 24h scores a complete short exchange session', (
    tester,
  ) async {
    _configureView(tester);
    final history = _PulseHistoryService();
    final store = LiveMarketStore(
      service: _StaticPriceService(),
      autoRefreshInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          selectedTheme: GoldBrainTheme.blue,
          selectedLanguage: GoldBrainLanguage.english,
          marketStore: store,
          historyService: history,
          countryPulseService: _ShanghaiSessionService(),
        ),
      ),
    );
    await tester.pump();
    _selectPulse(tester, 'country:china');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_chartCloses(tester), [3000, 3001, 3002, 3003, 3004]);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('asset-pulse-score'))).data,
      isNot('—'),
    );
    expect(find.textContaining('Insufficient coverage'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    history.close();
  });

  testWidgets('late country response cannot overwrite a selected asset', (
    tester,
  ) async {
    _configureView(tester);
    final history = _PulseHistoryService();
    final countries = _PendingCountryService();
    final store = LiveMarketStore(
      service: _StaticPriceService(),
      autoRefreshInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          selectedTheme: GoldBrainTheme.blue,
          selectedLanguage: GoldBrainLanguage.english,
          marketStore: store,
          historyService: history,
          countryPulseService: countries,
        ),
      ),
    );
    await tester.pump();
    _selectPulse(tester, 'country:germany');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dashboard-history-loading')),
      findsOneWidget,
    );
    _selectPulse(tester, 'XAU');
    await tester.pump();
    countries.pending.complete(
      await _AvailableCountryService().fetch(
        'germany',
        MarketHistoryRange.oneDay,
      ),
    );
    await tester.pump();
    expect(_chartCloses(tester), [100, 101, 102, 103, 104]);
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('pulse-asset-picker')),
          )
          .value,
      'XAU',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    history.close();
  });
}

void _configureView(WidgetTester tester) {
  SharedPreferences.setMockInitialValues({
    'settings.sound_enabled': false,
    'settings.music_enabled': false,
    'settings.motion_enabled': false,
    'settings.reduced_motion': true,
  });
  tester.view.physicalSize = const Size(1600, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _selectPulse(WidgetTester tester, String value) => tester
    .widget<DropdownButton<String>>(
      find.byKey(const ValueKey('pulse-asset-picker')),
    )
    .onChanged!(value);

List<double> _chartCloses(WidgetTester tester) =>
    tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<NeuralChartPainter>()
        .firstOrNull
        ?.candles
        .map((point) => point.close)
        .toList() ??
    [];

class _PendingCountryService extends CountryPulseService {
  final pending = Completer<CountryPulseEvidence>();
  @override
  Future<CountryPulseEvidence> fetch(
    String country,
    MarketHistoryRange range,
  ) => pending.future;
}

class _AvailableCountryService extends CountryPulseService {
  final requests = <(String, MarketHistoryRange)>[];
  List<double> closes(String country) => [
    for (var i = 0; i < 5; i++) 10000 + country.length * 100 + i.toDouble(),
  ];
  @override
  Future<CountryPulseEvidence> fetch(
    String country,
    MarketHistoryRange range,
  ) async {
    requests.add((country, range));
    final now = DateTime.now().toUtc();
    final days = range == MarketHistoryRange.oneMonth
        ? 30
        : range == MarketHistoryRange.oneWeek
        ? 7
        : 1;
    final prices = closes(country);
    return CountryPulseEvidence(
      country: country,
      indexName: '$country index',
      indexProvider: 'test index provider',
      indexStatus: 'available',
      newsStatus: 'unavailable',
      series: MarketHistorySeries(
        symbol: 'INDEX-$country',
        currency: country == 'japan' ? 'JPY' : 'EUR',
        range: range,
        candles: [
          for (var i = 0; i < 5; i++)
            _candle(
              now.subtract(Duration(hours: days * 6 * (4 - i))),
              prices[i],
            ),
        ],
        provider: MarketHistoryProvider.backend,
        providerLabel: 'test index provider',
        fetchedAt: now,
        isPriceSample: true,
      ),
    );
  }
}

class _ShanghaiSessionService extends CountryPulseService {
  @override
  Future<CountryPulseEvidence> fetch(
    String country,
    MarketHistoryRange range,
  ) async {
    final now = DateTime.now().toUtc();
    return CountryPulseEvidence(
      country: country,
      indexName: 'SSE Composite',
      indexProvider: 'test index provider',
      indexStatus: 'available',
      newsStatus: 'unavailable',
      series: MarketHistorySeries(
        symbol: '000001.SS',
        currency: 'CNY',
        range: range,
        candles: [
          for (var i = 0; i < 5; i++)
            _candle(
              now.subtract(Duration(seconds: 4950 * (4 - i))),
              3000 + i.toDouble(),
            ),
        ],
        provider: MarketHistoryProvider.backend,
        providerLabel: 'test index provider',
        fetchedAt: now,
        isPriceSample: true,
      ),
    );
  }
}

class _UnauthorizedCountryService extends CountryPulseService {
  @override
  Future<CountryPulseEvidence> fetch(
    String country,
    MarketHistoryRange range,
  ) async {
    throw const GoldBrainBackendException(
      'http_401',
      'Authentication required.',
    );
  }
}

class _FakeHistoryService extends MarketHistoryService {
  final List<MarketHistoryRange> requestedRanges = [];

  @override
  Future<MarketHistorySeries> fetchHistory(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
    bool forceRefresh = false,
  }) async {
    requestedRanges.add(range);
    final now = DateTime.now();
    return MarketHistorySeries(
      symbol: 'XAU',
      currency: 'USD',
      range: range,
      candles: [
        _candle(now.subtract(const Duration(minutes: 30)), 4300),
        _candle(now.subtract(const Duration(minutes: 15)), 4310),
        _candle(now, 4305),
      ],
      provider: MarketHistoryProvider.zarix,
      providerLabel: 'ZARIX · verified-test-source',
      fetchedAt: now,
    );
  }
}

class _StaticPriceService extends GlobalPriceService {
  @override
  Future<GlobalPriceBatch> fetchQuotes(
    Iterable<String> symbols, {
    bool forceRefresh = false,
  }) async => GlobalPriceBatch(
    requestedSymbols: symbols.toSet(),
    quotes: const {},
    errors: const {},
  );
}

class _PulseHistoryService extends MarketHistoryService {
  final List<String> requestedSymbols = [];

  @override
  Future<MarketHistorySeries> fetchHistory(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
    bool forceRefresh = false,
  }) async {
    requestedSymbols.add(symbol);
    final now = DateTime.now();
    return MarketHistorySeries(
      symbol: symbol,
      currency: 'USD',
      range: range,
      candles: [
        for (var i = 0; i < 5; i++)
          _candle(
            now.subtract(Duration(hours: (4 - i) * 3)),
            100 + i.toDouble(),
          ),
      ],
      provider: MarketHistoryProvider.backend,
      providerLabel: 'GoldBrain · test',
      fetchedAt: now,
    );
  }
}

class _UnavailableIranService extends CountryPulseService {
  @override
  Future<CountryPulseEvidence> fetch(
    String country,
    MarketHistoryRange range,
  ) async {
    final now = DateTime.now();
    return CountryPulseEvidence(
      country: country,
      indexName: 'Tehran Exchange Price Index',
      indexProvider: 'TSETMC',
      indexStatus: 'unavailable',
      newsStatus: 'unavailable',
      series: MarketHistorySeries(
        symbol: 'TEDPIX',
        currency: 'INDEX',
        range: range,
        candles: const [],
        provider: MarketHistoryProvider.backend,
        providerLabel: 'TSETMC',
        fetchedAt: now,
        isStale: true,
      ),
    );
  }
}

MarketCandle _candle(DateTime time, double close) => MarketCandle(
  time: time,
  open: close,
  high: close,
  low: close,
  close: close,
);
