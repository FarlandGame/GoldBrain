import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_api_client.dart';
import 'backend_connection.dart';

enum GlobalPriceProvider { navasan, zarix, goldApi, backend }

class MarketAssetMetadata {
  const MarketAssetMetadata({
    required this.symbol,
    required this.name,
    required this.assetClass,
    required this.quoteCurrency,
    required this.liveQuote,
    required this.forecast,
  });

  final String symbol;
  final String name;
  final String assetClass;
  final String quoteCurrency;
  final bool liveQuote;
  final bool forecast;
}

class MarketAssetCatalog {
  const MarketAssetCatalog({required this.assets, required this.isFallback});

  final List<MarketAssetMetadata> assets;

  /// A dated bootstrap list, never evidence of a current market-cap ranking.
  final bool isFallback;
}

class GlobalPriceQuote {
  const GlobalPriceQuote({
    required this.symbol,
    required this.name,
    required this.currency,
    required this.price,
    required this.updatedAt,
    required this.provider,
    this.changePercent,
    this.upstreamSource,
    this.unit,
    this.market,
    this.freshnessStatus,
    this.dataQualityStatus,
    this.providerTimestamp,
    this.receivedAt,
    this.fallbackFrom,
    this.wasCached = false,
  });

  final String symbol;
  final String name;
  final String currency;
  final double price;
  final DateTime updatedAt;
  final GlobalPriceProvider provider;
  final double? changePercent;
  final String? upstreamSource;
  final String? unit;
  final String? market;
  final String? freshnessStatus;
  final String? dataQualityStatus;
  final DateTime? providerTimestamp;
  final DateTime? receivedAt;
  final String? fallbackFrom;
  final bool wasCached;

  bool get hasDisallowedDomesticSource => isDisallowedDomesticSource(
    symbol: symbol,
    provider: provider,
    upstreamSource: upstreamSource,
  );

  static bool isDisallowedDomesticSource({
    required String symbol,
    required GlobalPriceProvider provider,
    String? upstreamSource,
  }) {
    final asset = symbol.trim().toUpperCase();
    final source = upstreamSource?.trim().toLowerCase();
    final zarix = provider == GlobalPriceProvider.zarix || source == 'zarix';
    if (asset == 'GOLD18') {
      return zarix || source == 'persian-toolbox' || source == 'persiantoolbox';
    }
    return (asset == 'USD' || asset == 'EUR') && zarix;
  }

  bool get isStale {
    if (wasCached) return true;
    if (freshnessStatus == 'STALE' ||
        freshnessStatus == 'DELAYED' ||
        freshnessStatus == 'UNAVAILABLE') {
      return true;
    }
    if (dataQualityStatus != null && dataQualityStatus != 'VALID') {
      return true;
    }
    final age = DateTime.now().difference(updatedAt);
    return age.isNegative || age > const Duration(minutes: 5);
  }

  GlobalPriceQuote asCached() => GlobalPriceQuote(
    symbol: symbol,
    name: name,
    currency: currency,
    price: price,
    updatedAt: updatedAt,
    provider: provider,
    changePercent: changePercent,
    upstreamSource: upstreamSource,
    unit: unit,
    market: market,
    freshnessStatus: freshnessStatus,
    dataQualityStatus: dataQualityStatus,
    providerTimestamp: providerTimestamp,
    receivedAt: receivedAt,
    fallbackFrom: fallbackFrom,
    wasCached: true,
  );

  String get providerLabel => switch (provider) {
    GlobalPriceProvider.navasan => 'Navasan',
    GlobalPriceProvider.zarix => 'ZARIX',
    GlobalPriceProvider.goldApi => 'Gold API',
    GlobalPriceProvider.backend =>
      upstreamSource?.isNotEmpty == true
          ? 'GoldBrain · $upstreamSource'
          : 'GoldBrain',
  };
}

class GlobalPriceBatch {
  const GlobalPriceBatch({
    required this.requestedSymbols,
    required this.quotes,
    required this.errors,
  });

  final Set<String> requestedSymbols;
  final Map<String, GlobalPriceQuote> quotes;
  final Map<String, String> errors;

  int get successCount => quotes.length;
  bool get isComplete =>
      requestedSymbols.isNotEmpty && successCount == requestedSymbols.length;
  bool get isPartial => quotes.isNotEmpty && !isComplete;
}

class GlobalPriceException implements Exception {
  const GlobalPriceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GlobalPriceService {
  GlobalPriceService({
    http.Client? client,
    GoldBrainBackendClient? backend,
    this.cacheDuration = const Duration(minutes: 4),
    this.timeout = const Duration(seconds: 12),
    Uri? zarixEndpoint,
    Uri? goldApiBaseUri,
    String? navasanApiKey,
    Uri? navasanEndpoint,
    this.domesticCacheDuration = const Duration(hours: 2),
  }) : _client = client ?? http.Client(),
       _backend =
           backend ??
           (client == null &&
                   zarixEndpoint == null &&
                   goldApiBaseUri == null &&
                   navasanApiKey == null &&
                   navasanEndpoint == null
               ? BackendConnection.instance.api
               : null),
       _ownsClient = client == null,
       _zarixEndpoint = zarixEndpoint ?? Uri.parse('https://zarix.online/api/'),
       _goldApiBaseUri =
           goldApiBaseUri ?? Uri.parse('https://api.gold-api.com/'),
       _navasanApiKey = (navasanApiKey ?? '').trim(),
       _navasanEndpoint =
           navasanEndpoint ?? Uri.parse('https://api.navasan.tech/');

  static const supportedSymbols = {
    'USD',
    'EUR',
    'GOLD18',
    'XAU',
    'XAG',
    'USDT',
    'BTC',
    'ETH',
    'BNB',
    'XRP',
    'USDC',
    'SOL',
    'TRX',
    'ZEC',
    'HYPE',
    'DOGE',
    'XMR',
    'LINK',
    'ADA',
    'LEO',
    'XLM',
    'BCH',
    'NEAR',
    'UNI',
    'LTC',
    'DOT',
    'PAXG',
    'NOT',
    'AVAX',
    'TON',
    'PEPE',
    'ARB',
  };

  /// Used only until the authenticated backend asset catalog can be read.
  /// Crypto membership is a 2026-09-25 snapshot, not a live ranking.
  static const fallbackAssetCatalog = <MarketAssetMetadata>[
    MarketAssetMetadata(
      symbol: 'GOLD18',
      name: 'Gold 18K',
      assetClass: 'metal',
      quoteCurrency: 'IRT',
      liveQuote: true,
      forecast: true,
    ),
    MarketAssetMetadata(
      symbol: 'XAU',
      name: 'Global Gold Ounce',
      assetClass: 'metal',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'XAG',
      name: 'Silver',
      assetClass: 'metal',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'USD',
      name: 'US Dollar',
      assetClass: 'fiat',
      quoteCurrency: 'IRT',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'EUR',
      name: 'Euro',
      assetClass: 'fiat',
      quoteCurrency: 'IRT',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'BTC',
      name: 'Bitcoin',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: true,
    ),
    MarketAssetMetadata(
      symbol: 'ETH',
      name: 'Ethereum',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'USDT',
      name: 'Tether',
      assetClass: 'crypto',
      quoteCurrency: 'IRT',
      liveQuote: true,
      forecast: true,
    ),
    MarketAssetMetadata(
      symbol: 'BNB',
      name: 'BNB',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'XRP',
      name: 'XRP',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'USDC',
      name: 'USDC',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'SOL',
      name: 'Solana',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'TRX',
      name: 'TRON',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'ZEC',
      name: 'Zcash',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'HYPE',
      name: 'Hyperliquid',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'DOGE',
      name: 'Dogecoin',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'XMR',
      name: 'Monero',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'LINK',
      name: 'Chainlink',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'ADA',
      name: 'Cardano',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'LEO',
      name: 'UNUS SED LEO',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'XLM',
      name: 'Stellar',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'BCH',
      name: 'Bitcoin Cash',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'NEAR',
      name: 'NEAR Protocol',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'UNI',
      name: 'Uniswap',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'LTC',
      name: 'Litecoin',
      assetClass: 'crypto',
      quoteCurrency: 'USD',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'DOT',
      name: 'Polkadot',
      assetClass: 'crypto',
      quoteCurrency: 'USDT',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'PAXG',
      name: 'PAX Gold',
      assetClass: 'crypto',
      quoteCurrency: 'USDT',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'NOT',
      name: 'Notcoin',
      assetClass: 'crypto',
      quoteCurrency: 'USDT',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'AVAX',
      name: 'Avalanche',
      assetClass: 'crypto',
      quoteCurrency: 'USDT',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'TON',
      name: 'Toncoin',
      assetClass: 'crypto',
      quoteCurrency: 'USDT',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'PEPE',
      name: 'Pepe',
      assetClass: 'crypto',
      quoteCurrency: 'USDT',
      liveQuote: true,
      forecast: false,
    ),
    MarketAssetMetadata(
      symbol: 'ARB',
      name: 'Arbitrum',
      assetClass: 'crypto',
      quoteCurrency: 'USDT',
      liveQuote: true,
      forecast: false,
    ),
  ];

  Future<MarketAssetCatalog> fetchAssetCatalog() async {
    final backend = _backend;
    if (backend != null) {
      try {
        final assets = await backend.marketAssets();
        return MarketAssetCatalog(
          assets: List.unmodifiable(
            assets.map(
              (asset) => MarketAssetMetadata(
                symbol: asset.symbol,
                name: asset.name,
                assetClass: asset.assetClass,
                quoteCurrency: asset.quoteCurrency,
                liveQuote: asset.liveQuote,
                forecast: asset.forecast,
              ),
            ),
          ),
          isFallback: false,
        );
      } catch (_) {
        // Catalog discovery must not prevent cached prices from being shown.
      }
    }
    return const MarketAssetCatalog(
      assets: fallbackAssetCatalog,
      isFallback: true,
    );
  }

  static const _goldApiSymbols = {'XAU', 'XAG', 'BTC', 'ETH'};
  static const _domesticSymbols = {'USD', 'GOLD18'};
  static const _navasanSymbolMap = {'USD': 'usd_sell', 'GOLD18': '18ayar'};

  static const _zarixCategories = {
    'XAU': 'gold',
    'XAG': 'gold',
    'BTC': 'crypto',
    'ETH': 'crypto',
  };

  static const _zarixSymbolMap = {
    'XAUUSD': 'XAU',
    'XAGUSD': 'XAG',
    'USDT': 'USDT',
    'BTC': 'BTC',
    'ETH': 'ETH',
  };

  final http.Client _client;
  final GoldBrainBackendClient? _backend;
  final bool _ownsClient;
  final Uri _zarixEndpoint;
  final Uri _goldApiBaseUri;
  final String _navasanApiKey;
  final Uri _navasanEndpoint;
  final Duration cacheDuration;
  final Duration domesticCacheDuration;
  final Duration timeout;
  final Map<String, ({GlobalPriceQuote quote, DateTime fetchedAt})> _cache = {};
  ({Map<String, GlobalPriceQuote> quotes, DateTime fetchedAt})?
  _navasanLatestCache;

  Future<GlobalPriceQuote> fetchQuote(
    String symbol, {
    bool forceRefresh = false,
  }) async {
    final normalized = symbol.trim().toUpperCase();
    final result = await fetchQuotes({normalized}, forceRefresh: forceRefresh);
    final quote = result.quotes[normalized];
    if (quote != null) return quote;
    throw GlobalPriceException(
      result.errors[normalized] ?? 'No price is available for $normalized.',
    );
  }

  Future<GlobalPriceBatch> fetchQuotes(
    Iterable<String> symbols, {
    bool forceRefresh = false,
  }) async {
    final requested = symbols
        .map((symbol) => symbol.trim().toUpperCase())
        .where((symbol) => symbol.isNotEmpty)
        .toSet();
    if (_backend != null) {
      return _fetchBackendQuotes(requested, forceRefresh: forceRefresh);
    }
    final quotes = <String, GlobalPriceQuote>{};
    final errors = <String, String>{};
    final pending = <String>{};
    final now = DateTime.now();

    for (final symbol in requested) {
      if (!supportedSymbols.contains(symbol)) {
        errors[symbol] = 'Unsupported price symbol: $symbol';
        continue;
      }
      final cached = _cache[symbol];
      if (!forceRefresh &&
          cached != null &&
          !cached.quote.hasDisallowedDomesticSource &&
          now.difference(cached.fetchedAt) < cacheDuration) {
        quotes[symbol] = cached.quote;
      } else {
        pending.add(symbol);
      }
    }

    final zarixPending = <String>{...pending};
    if (_navasanApiKey.isNotEmpty && pending.any(_domesticSymbols.contains)) {
      try {
        final domesticQuotes = await _fetchNavasanLatest();
        for (final symbol in pending.where(_domesticSymbols.contains)) {
          final quote = domesticQuotes[symbol];
          if (quote == null) continue;
          _cacheQuote(quote);
          quotes[symbol] = quote;
          errors.remove(symbol);
          zarixPending.remove(symbol);
        }
      } on GlobalPriceException {
        // An unavailable domestic source must remain unavailable. Global
        // reference feeds are not substitutes for Iranian-market prices.
      }
    }

    final categories = zarixPending
        .map((symbol) => _zarixCategories[symbol])
        .whereType<String>()
        .toSet();
    final zarixResults = await Future.wait(
      categories.map(_captureZarixCategory),
    );

    for (final categoryResult in zarixResults) {
      if (categoryResult.error != null) {
        for (final symbol in zarixPending.where(
          (symbol) => _zarixCategories[symbol] == categoryResult.category,
        )) {
          errors[symbol] = categoryResult.error!;
        }
        continue;
      }

      for (final entry in categoryResult.quotes.entries) {
        if (zarixPending.contains(entry.key)) {
          _cacheQuote(entry.value);
          quotes[entry.key] = entry.value;
          errors.remove(entry.key);
        }
      }
    }

    final unresolved = pending.where((symbol) => !quotes.containsKey(symbol));
    final fallbackSymbols = unresolved.where(_goldApiSymbols.contains).toSet();
    final fallbackResults = await Future.wait(
      fallbackSymbols.map(_captureGoldApiQuote),
    );

    for (final fallbackResult in fallbackResults) {
      final quote = fallbackResult.quote;
      if (quote != null) {
        _cacheQuote(quote);
        quotes[quote.symbol] = quote;
        errors.remove(quote.symbol);
      } else {
        errors[fallbackResult.symbol] = fallbackResult.error!;
      }
    }

    for (final symbol in pending.where(
      (symbol) => !quotes.containsKey(symbol),
    )) {
      errors.putIfAbsent(
        symbol,
        () => 'The price provider did not return $symbol.',
      );
    }

    return GlobalPriceBatch(
      requestedSymbols: Set.unmodifiable(requested),
      quotes: Map.unmodifiable(quotes),
      errors: Map.unmodifiable(errors),
    );
  }

  /// The original cards consume this DTO unchanged; production data and
  /// provider credentials now belong to the authenticated GoldBrain backend.
  Future<GlobalPriceBatch> _fetchBackendQuotes(
    Set<String> requested, {
    required bool forceRefresh,
  }) async {
    // The backend catalog is authoritative and can change independently of
    // this bootstrap snapshot; only reject malformed symbols at this edge.
    final validSymbol = RegExp(r'^[A-Z0-9]{2,15}$');
    final supported = requested.where(validSymbol.hasMatch).toSet();
    final errors = <String, String>{
      for (final symbol in requested.difference(supported))
        symbol: 'Unsupported price symbol: $symbol',
    };
    final quotes = <String, GlobalPriceQuote>{};
    if (supported.isNotEmpty) {
      try {
        final batch = await _backend!.fetchQuotes(
          supported,
          forceRefresh: forceRefresh,
        );
        final now = DateTime.now().toUtc();
        for (final symbol in supported) {
          final quote = batch.quotes[symbol];
          if (quote == null ||
              quote.updatedAt.isAfter(now) ||
              quote.dataQualityStatus == 'INVALID' ||
              GlobalPriceQuote.isDisallowedDomesticSource(
                symbol: symbol,
                provider: GlobalPriceProvider.backend,
                upstreamSource: quote.provider,
              )) {
            errors[symbol] =
                batch.issues[symbol] ??
                'GoldBrain has no valid current quote for $symbol.';
            continue;
          }
          // Rial and Toman are the only fixed conversion used at this boundary.
          final rial = quote.currency == 'IRR';
          quotes[symbol] = GlobalPriceQuote(
            symbol: quote.symbol,
            name: quote.name,
            currency: rial ? 'IRT' : quote.currency,
            price: rial ? quote.price / 10 : quote.price,
            updatedAt: quote.updatedAt.toLocal(),
            provider: GlobalPriceProvider.backend,
            changePercent: quote.changePercent,
            upstreamSource: quote.provider,
            unit: quote.unit,
            market: quote.market,
            freshnessStatus: quote.freshnessStatus,
            dataQualityStatus: quote.dataQualityStatus,
            providerTimestamp: quote.providerTimestamp,
            receivedAt: quote.receivedAt,
            fallbackFrom: quote.fallbackFrom,
          );
          if (batch.issues.containsKey(symbol)) {
            errors[symbol] = batch.issues[symbol]!;
          } else if (quotes[symbol]!.isStale &&
              !(quote.freshnessStatus?.toUpperCase() == 'DELAYED' &&
                  quote.dataQualityStatus == 'VALID')) {
            errors[symbol] =
                'GoldBrain quote is stale; showing its actual source time.';
          }
        }
      } on GoldBrainBackendException catch (error) {
        for (final symbol in supported) {
          errors[symbol] = error.message;
        }
      } on FormatException {
        for (final symbol in supported) {
          errors[symbol] = 'GoldBrain returned invalid market data.';
        }
      }
    }
    return GlobalPriceBatch(
      requestedSymbols: Set.unmodifiable(requested),
      quotes: Map.unmodifiable(quotes),
      errors: Map.unmodifiable(errors),
    );
  }

  Future<Map<String, GlobalPriceQuote>> _fetchNavasanLatest() async {
    if (_navasanApiKey.isEmpty) return const {};
    if (_navasanEndpoint.scheme != 'https') {
      throw const GlobalPriceException(
        'Navasan requires HTTPS so its API key is never sent in clear text.',
      );
    }
    final cached = _navasanLatestCache;
    final now = DateTime.now();
    if (cached != null &&
        now.difference(cached.fetchedAt) < domesticCacheDuration) {
      return cached.quotes;
    }

    final uri = _navasanEndpoint
        .resolve('latest/')
        .replace(queryParameters: {'api_key': _navasanApiKey});
    final response = await _get(uri, providerName: 'Navasan');
    final body = _decodeObject(response.bodyBytes, providerName: 'Navasan');
    final quotes = <String, GlobalPriceQuote>{};
    for (final entry in _navasanSymbolMap.entries) {
      final raw = body[entry.value];
      if (raw is! Map) continue;
      // Navasan's own widget matches these raw symbols in Toman. Only an
      // explicit Rial currency field changes the provider-boundary factor.
      final rawCurrency = (raw['currency']?.toString() ?? 'IRT')
          .trim()
          .toUpperCase();
      if (!const {
        'IRT',
        'TOMAN',
        'TMN',
        'IRR',
        'RLS',
        'RIAL',
      }.contains(rawCurrency)) {
        continue;
      }
      final expectedUnit = entry.key == 'GOLD18' ? 'gram_18k' : 'currency_unit';
      if ((raw['unit']?.toString() ?? expectedUnit).trim().toLowerCase() !=
          expectedUnit) {
        continue;
      }
      final divisor = const {'IRR', 'RLS', 'RIAL'}.contains(rawCurrency)
          ? 10.0
          : 1.0;
      final rawPrice = _positiveNumber(raw['value']);
      final price = rawPrice == null ? null : rawPrice / divisor;
      final timestamp = _positiveInteger(raw['timestamp']);
      if (price == null || timestamp == null) continue;
      final rawChange = _signedNumber(raw['change']);
      final change = rawChange == null ? null : rawChange / divisor;
      final previous = change == null ? null : price - change;
      final changePercent = previous == null || previous <= 0
          ? null
          : (change! / previous) * 100;
      quotes[entry.key] = GlobalPriceQuote(
        symbol: entry.key,
        name: entry.key,
        currency: 'IRT',
        price: price,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          timestamp * 1000,
          isUtc: true,
        ).toLocal(),
        provider: GlobalPriceProvider.navasan,
        changePercent: changePercent,
        upstreamSource: entry.value,
      );
    }
    if (quotes.isEmpty) {
      throw const GlobalPriceException(
        'Navasan returned no usable domestic prices.',
      );
    }
    final frozen = Map<String, GlobalPriceQuote>.unmodifiable(quotes);
    _navasanLatestCache = (quotes: frozen, fetchedAt: now);
    return frozen;
  }

  Future<_ZarixCategoryResult> _captureZarixCategory(String category) async {
    try {
      return _ZarixCategoryResult(
        category: category,
        quotes: await _fetchZarixCategory(category),
      );
    } on GlobalPriceException catch (error) {
      return _ZarixCategoryResult(category: category, error: error.message);
    } catch (_) {
      return _ZarixCategoryResult(
        category: category,
        error: 'ZARIX could not provide this market category.',
      );
    }
  }

  Future<Map<String, GlobalPriceQuote>> _fetchZarixCategory(
    String category,
  ) async {
    final uri = _zarixEndpoint.replace(
      queryParameters: {
        'endpoint': 'markets',
        'category': category,
        'page': '1',
        'limit': '100',
      },
    );
    final response = await _get(uri, providerName: 'ZARIX');
    final body = _decodeObject(response.bodyBytes, providerName: 'ZARIX');
    if (body['ok'] != true) {
      throw const GlobalPriceException(
        'ZARIX returned an unsuccessful response.',
      );
    }

    final data = body['data'];
    final items = data is Map ? data['items'] : null;
    if (items is! List) {
      throw const GlobalPriceException('ZARIX returned invalid market data.');
    }

    final quotes = <String, GlobalPriceQuote>{};
    for (final rawItem in items) {
      if (rawItem is! Map) continue;
      final rawSymbol = rawItem['symbol']?.toString().trim().toUpperCase();
      final symbol = _zarixSymbolMap[rawSymbol];
      if (symbol == null) continue;

      final price = rawItem['price'];
      final updatedAt =
          _parseDate(rawItem['sourceTime']) ?? _parseDate(rawItem['updatedAt']);
      final currency = _currencyCode(rawItem['unit']?.toString(), symbol);
      if (price is! num ||
          !price.toDouble().isFinite ||
          price <= 0 ||
          updatedAt == null ||
          currency == null) {
        continue;
      }

      final rawChange = rawItem['changePercent'];
      final upstreamSource = rawItem['source']?.toString().trim();
      quotes[symbol] = GlobalPriceQuote(
        symbol: symbol,
        name: rawItem['title']?.toString().trim().isNotEmpty == true
            ? rawItem['title'].toString().trim()
            : symbol,
        currency: currency,
        price: price.toDouble(),
        updatedAt: updatedAt.toLocal(),
        provider: GlobalPriceProvider.zarix,
        changePercent: rawChange is num ? rawChange.toDouble() : null,
        upstreamSource: upstreamSource?.isEmpty == true ? null : upstreamSource,
      );
    }

    if (quotes.isEmpty) {
      throw const GlobalPriceException('ZARIX returned no supported prices.');
    }
    return quotes;
  }

  Future<_GoldApiResult> _captureGoldApiQuote(String symbol) async {
    try {
      return _GoldApiResult(
        symbol: symbol,
        quote: await _fetchGoldApiQuote(symbol),
      );
    } on GlobalPriceException catch (error) {
      return _GoldApiResult(symbol: symbol, error: error.message);
    } catch (_) {
      return _GoldApiResult(
        symbol: symbol,
        error: 'Gold API could not provide $symbol.',
      );
    }
  }

  Future<GlobalPriceQuote> _fetchGoldApiQuote(String symbol) async {
    final uri = _goldApiBaseUri.resolve('price/$symbol');
    final response = await _get(uri, providerName: 'Gold API');
    final body = _decodeObject(response.bodyBytes, providerName: 'Gold API');
    final price = body['price'];
    final updatedAt = _parseDate(body['updatedAt']);
    final returnedSymbol = body['symbol']?.toString().toUpperCase() ?? symbol;
    if (price is! num ||
        !price.toDouble().isFinite ||
        price <= 0 ||
        updatedAt == null ||
        returnedSymbol != symbol) {
      throw const GlobalPriceException('Gold API returned invalid price data.');
    }

    return GlobalPriceQuote(
      symbol: symbol,
      name: body['name']?.toString() ?? symbol,
      currency: body['currency']?.toString().toUpperCase() ?? 'USD',
      price: price.toDouble(),
      updatedAt: updatedAt.toLocal(),
      provider: GlobalPriceProvider.goldApi,
      upstreamSource: 'gold-api.com',
    );
  }

  Future<http.Response> _get(Uri uri, {required String providerName}) async {
    late final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw GlobalPriceException('$providerName request timed out.');
    } on http.ClientException {
      throw GlobalPriceException('Could not connect to $providerName.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GlobalPriceException(
        '$providerName request failed (HTTP ${response.statusCode}).',
      );
    }
    return response;
  }

  Map<String, dynamic> _decodeObject(
    List<int> bytes, {
    required String providerName,
  }) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // A sanitized provider-specific error is thrown below.
    }
    throw GlobalPriceException('$providerName returned invalid JSON.');
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String? _currencyCode(String? unit, String symbol) {
    final normalized = unit?.trim().toUpperCase() ?? '';
    if ((symbol == 'BTC' || symbol == 'ETH') && normalized == 'USDT') {
      return 'USDT';
    }
    if (symbol == 'USDT' && normalized.contains('تومان')) {
      return 'IRT';
    }
    if ((symbol == 'XAU' || symbol == 'XAG') &&
        (normalized.contains('دلار') || normalized.contains('USD'))) {
      return 'USD';
    }
    return null;
  }

  double? _positiveNumber(Object? value) {
    final normalized = value?.toString().replaceAll(',', '').trim();
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse('$normalized');
    return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
  }

  double? _signedNumber(Object? value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    final normalized = value.toString().replaceAll(',', '').trim();
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(normalized);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  int? _positiveInteger(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  void _cacheQuote(GlobalPriceQuote quote) {
    _cache[quote.symbol] = (quote: quote, fetchedAt: DateTime.now());
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class _ZarixCategoryResult {
  const _ZarixCategoryResult({
    required this.category,
    this.quotes = const {},
    this.error,
  });

  final String category;
  final Map<String, GlobalPriceQuote> quotes;
  final String? error;
}

class _GoldApiResult {
  const _GoldApiResult({required this.symbol, this.quote, this.error});

  final String symbol;
  final GlobalPriceQuote? quote;
  final String? error;
}
