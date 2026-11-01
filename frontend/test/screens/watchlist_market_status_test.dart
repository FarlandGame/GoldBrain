import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/global_price_service.dart';
import 'package:goldbrain/core/internet_connection_service.dart';
import 'package:goldbrain/core/live_market_store.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/screens/watchlist_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'watchlist follows backend catalog and does not call stale prices live',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = LiveMarketStore(
        service: _CatalogPriceService(),
        internetService: _OnlineInternetService(),
        discoverAssets: true,
      );
      addTearDown(store.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WatchlistScreen(
              palette: themePalettes[GoldBrainTheme.gold]!,
              selectedLanguage: GoldBrainLanguage.english,
              currencyCode: 'USD',
              marketStore: store,
            ),
          ),
        ),
      );
      await store.load();
      await tester.pump();

      expect(find.text('Bitcoin'), findsOneWidget);
      expect(find.text('Euro'), findsOneWidget);
      expect(find.text('18K Gold'), findsNothing);
      expect(find.text('STALE'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.textContaining('Saved asset list'), findsNothing);

      await tester.tap(find.text('STALE'));
      await tester.pump();
      expect(find.textContaining('Status: STALE'), findsOneWidget);
      expect(
        find.textContaining('Source: GoldBrain · test-btc'),
        findsOneWidget,
      );
    },
  );
}

class _CatalogPriceService extends GlobalPriceService {
  @override
  Future<MarketAssetCatalog> fetchAssetCatalog() async =>
      const MarketAssetCatalog(
        assets: [
          MarketAssetMetadata(
            symbol: 'BTC',
            name: 'Bitcoin',
            assetClass: 'crypto',
            quoteCurrency: 'USD',
            liveQuote: true,
            forecast: true,
          ),
          MarketAssetMetadata(
            symbol: 'EUR',
            name: 'Euro',
            assetClass: 'fiat',
            quoteCurrency: 'IRT',
            liveQuote: true,
            forecast: false,
          ),
        ],
        isFallback: false,
      );

  @override
  Future<GlobalPriceBatch> fetchQuotes(
    Iterable<String> symbols, {
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now().toUtc();
    return GlobalPriceBatch(
      requestedSymbols: symbols.toSet(),
      quotes: {
        'BTC': GlobalPriceQuote(
          symbol: 'BTC',
          name: 'Bitcoin',
          currency: 'USD',
          price: 65000,
          updatedAt: now.subtract(const Duration(minutes: 20)),
          provider: GlobalPriceProvider.backend,
          upstreamSource: 'test-btc',
          freshnessStatus: 'STALE',
          providerTimestamp: now.subtract(const Duration(minutes: 20)),
          receivedAt: now,
        ),
        'EUR': GlobalPriceQuote(
          symbol: 'EUR',
          name: 'Euro',
          currency: 'IRT',
          price: 150000,
          updatedAt: now,
          provider: GlobalPriceProvider.backend,
          upstreamSource: 'test-fx',
          freshnessStatus: 'LIVE',
          providerTimestamp: now,
          receivedAt: now,
        ),
      },
      errors: const {},
    );
  }
}

class _OnlineInternetService extends InternetConnectionService {
  @override
  Future<bool> hasInternetAccess() async => true;
}
