import 'dart:async';

import 'package:flutter/widgets.dart';

import 'currency_service.dart';
import 'global_price_service.dart';
import 'internet_connection_service.dart';
import 'local_quote_history_store.dart';
import 'market_history_service.dart';
import 'market_quote_persistent_cache.dart';

enum InternetConnectionStatus { unknown, online, offline }

/// Shared, lifecycle-aware source of truth for all current market prices.
class LiveMarketStore extends ChangeNotifier with WidgetsBindingObserver {
  LiveMarketStore({
    GlobalPriceService? service,
    InternetConnectionService? internetService,
    LocalQuoteHistoryStore? localHistoryStore,
    MarketQuotePersistentCache? quoteCache,
    this.discoverAssets = false,
    this.refreshAfter = const Duration(minutes: 1),
    this.autoRefreshInterval = const Duration(minutes: 1),
    this.offlineRetryInterval = const Duration(seconds: 10),
    Iterable<String>? symbols,
  }) : trackedSymbols = Set.unmodifiable(
         symbols ??
             (discoverAssets
                 ? GlobalPriceService.supportedSymbols
                 : defaultTrackedSymbols),
       ),
       _service =
           service ??
           GlobalPriceService(cacheDuration: const Duration(seconds: 30)),
       _internetService = internetService ?? InternetConnectionService(),
       _localHistoryStore = localHistoryStore ?? LocalQuoteHistoryStore(),
       _quoteCache = quoteCache ?? MarketQuotePersistentCache() {
    _assets = discoverAssets
        ? GlobalPriceService.fallbackAssetCatalog
        : GlobalPriceService.fallbackAssetCatalog
            .where((asset) => trackedSymbols.contains(asset.symbol))
            .toList(growable: false);
  }

  static final LiveMarketStore instance = LiveMarketStore(discoverAssets: true);

  static const defaultTrackedSymbols = {
    'USD',
    'GOLD18',
    'XAU',
    'XAG',
    'USDT',
    'BTC',
    'ETH',
  };

  final GlobalPriceService _service;
  final InternetConnectionService _internetService;
  final LocalQuoteHistoryStore _localHistoryStore;
  final MarketQuotePersistentCache _quoteCache;
  final bool discoverAssets;
  final Duration refreshAfter;
  final Duration autoRefreshInterval;
  final Duration offlineRetryInterval;
  Set<String> trackedSymbols;

  late List<MarketAssetMetadata> _assets;
  bool _catalogIsFallback = true;
  DateTime? _catalogLastAttempt;
  bool _cacheLoaded = false;

  GlobalPriceBatch? _batch;
  DateTime? _loadedAt;
  DateTime? _lastAttemptAt;
  Future<GlobalPriceBatch>? _inFlight;
  bool _loading = false;
  InternetConnectionStatus _connectionStatus = InternetConnectionStatus.unknown;
  Timer? _refreshTimer;
  int _autoRefreshClients = 0;
  bool _lifecycleActive = true;
  bool _disposed = false;

  GlobalPriceBatch? get batch => _batch;
  List<MarketAssetMetadata> get assets => _assets;
  bool get catalogIsFallback => _catalogIsFallback;
  Map<String, GlobalPriceQuote> get quotes => _batch?.quotes ?? const {};
  bool get loading => _loading;
  bool get hasData => quotes.isNotEmpty;
  bool get hasError => _batch != null && _batch!.errors.isNotEmpty;
  DateTime? get loadedAt => _loadedAt;
  DateTime? get lastAttemptAt => _lastAttemptAt;
  InternetConnectionStatus get connectionStatus => _connectionStatus;
  bool get isOffline => _connectionStatus == InternetConnectionStatus.offline;
  bool get autoRefreshActive => _autoRefreshClients > 0;

  GlobalPriceQuote? quoteFor(String symbol) =>
      quotes[symbol.trim().toUpperCase()];

  Future<MarketHistorySeries?> localHistoryFor(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
  }) => _localHistoryStore.historyFor(symbol, range: range);

  Future<int> localHistoryPointCount(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
  }) => _localHistoryStore.pointCountFor(symbol, range: range);

  Future<LocalQuoteHistoryStatus> localHistoryStatus(
    String symbol, {
    MarketHistoryRange range = MarketHistoryRange.oneWeek,
  }) => _localHistoryStore.statusFor(symbol, range: range);

  /// Registers a UI owner for periodic refresh. Multiple screens can safely
  /// share this store; the timer stops only after the last owner is disposed.
  void startAutoRefresh({bool immediate = true}) {
    if (_disposed) return;
    _autoRefreshClients++;
    if (_autoRefreshClients > 1) return;
    WidgetsBinding.instance.addObserver(this);
    if (immediate) {
      unawaited(_runScheduledRefresh());
    } else {
      _scheduleNextRefresh();
    }
  }

  void stopAutoRefresh() {
    if (_autoRefreshClients == 0) return;
    _autoRefreshClients--;
    if (_autoRefreshClients > 0) return;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<GlobalPriceBatch> retryNow() => load(forceRefresh: true);

  Future<GlobalPriceBatch> load({bool forceRefresh = false}) {
    final active = _inFlight;
    if (active != null) return active;
    final loadedAt = _loadedAt;
    if (!forceRefresh &&
        _batch != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < refreshAfter) {
      return Future.value(_batch);
    }

    final request = _load(forceRefresh: forceRefresh);
    _inFlight = request;
    return request.whenComplete(() => _inFlight = null);
  }

  Future<GlobalPriceBatch> _load({required bool forceRefresh}) async {
    _loading = true;
    _lastAttemptAt = DateTime.now();
    notifyListeners();

    await _loadCachedQuotes(trackedSymbols);
    await _refreshCatalogIfNeeded();
    await _loadCachedQuotes(trackedSymbols);

    final connectivityFuture = _internetService.hasInternetAccess();
    GlobalPriceBatch fresh;
    try {
      fresh = await _service.fetchQuotes(
        trackedSymbols,
        // Scheduled/manual refresh must bypass both store and service caches.
        forceRefresh: forceRefresh,
      );
    } catch (_) {
      fresh = GlobalPriceBatch(
        requestedSymbols: trackedSymbols,
        quotes: const {},
        errors: {
          for (final symbol in trackedSymbols)
            symbol: 'The live price request failed.',
        },
      );
    }

    final probeSucceeded = fresh.quotes.isNotEmpty
        ? true
        : await connectivityFuture;
    final previous = _batch;
    final freshNetworkData = fresh.quotes.isNotEmpty;
    if (freshNetworkData) {
      try {
        await _localHistoryStore.recordQuotes(fresh.quotes);
        await _quoteCache.put(fresh.quotes);
      } catch (_) {
        // A local persistence failure must never hide otherwise valid live
        // prices or incorrectly mark the network as offline.
      }
    }
    _connectionStatus = freshNetworkData || probeSucceeded
        ? InternetConnectionStatus.online
        : InternetConnectionStatus.offline;

    // Keep the last verified quote visible on a temporary outage, while the
    // per-symbol errors explicitly mark those values as stale.
    if (previous != null && previous.quotes.isNotEmpty && !fresh.isComplete) {
      final mergedQuotes = <String, GlobalPriceQuote>{
        ...previous.quotes,
        ...fresh.quotes,
      };
      final mergedErrors = <String, String>{...fresh.errors};
      for (final symbol in previous.quotes.keys) {
        if (!fresh.quotes.containsKey(symbol)) {
          mergedQuotes[symbol] = previous.quotes[symbol]!.asCached();
          mergedErrors.putIfAbsent(
            symbol,
            () => 'Latest refresh failed; showing the last verified quote.',
          );
        }
      }
      _batch = GlobalPriceBatch(
        requestedSymbols: fresh.requestedSymbols,
        quotes: Map.unmodifiable(mergedQuotes),
        errors: Map.unmodifiable(mergedErrors),
      );
    } else {
      _batch = fresh;
    }

    final freshUsdQuote = fresh.quotes['USD'];
    if (freshUsdQuote != null &&
        freshUsdQuote.currency == 'IRT' &&
        !fresh.errors.containsKey('USD')) {
      CurrencyService.updateIranianTomanPerUsd(
        freshUsdQuote.price,
        observedAt: freshUsdQuote.updatedAt,
      );
    }
    final freshTetherQuote = fresh.quotes['USDT'];
    if (freshTetherQuote != null &&
        freshTetherQuote.currency == 'IRT' &&
        !fresh.errors.containsKey('USDT')) {
      CurrencyService.updateUsdtTomanPrice(
        freshTetherQuote.price,
        observedAt: freshTetherQuote.updatedAt,
      );
    }

    if (freshNetworkData) _loadedAt = DateTime.now();
    _loading = false;
    notifyListeners();
    return _batch!;
  }

  Future<void> _loadCachedQuotes(Set<String> symbols) async {
    if (_cacheLoaded &&
        _batch?.quotes.keys.toSet().containsAll(symbols) == true) {
      return;
    }
    try {
      final cached = await _quoteCache.load(symbols);
      if (cached.isEmpty) return;
      final previous = _batch;
      final merged = <String, GlobalPriceQuote>{
        ...cached,
        ...?previous?.quotes,
      };
      final errors = <String, String>{
        for (final symbol in cached.keys)
          symbol: 'Showing the last sourced observation from local storage.',
        ...?previous?.errors,
      };
      _batch = GlobalPriceBatch(
        requestedSymbols: symbols,
        quotes: Map.unmodifiable(merged),
        errors: Map.unmodifiable(errors),
      );
      final usd = cached['USD'];
      if (usd != null && usd.currency == 'IRT') {
        CurrencyService.updateIranianTomanPerUsd(
          usd.price,
          observedAt: usd.updatedAt,
        );
      }
      final tether = cached['USDT'];
      if (tether != null && tether.currency == 'IRT') {
        CurrencyService.updateUsdtTomanPrice(
          tether.price,
          observedAt: tether.updatedAt,
        );
      }
      notifyListeners();
    } catch (_) {
      // A broken device cache must not block network prices.
    } finally {
      _cacheLoaded = true;
    }
  }

  Future<void> _refreshCatalogIfNeeded() async {
    if (!discoverAssets) return;
    final lastAttempt = _catalogLastAttempt;
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < const Duration(minutes: 5)) {
      return;
    }
    _catalogLastAttempt = DateTime.now();
    final catalog = await _service.fetchAssetCatalog();
    _assets = catalog.assets;
    _catalogIsFallback = catalog.isFallback;
    if (!catalog.isFallback) {
      trackedSymbols = Set.unmodifiable(
        catalog.assets
            .where((asset) => asset.liveQuote)
            .map((asset) => asset.symbol),
      );
    }
    notifyListeners();
  }

  Future<void> _runScheduledRefresh() async {
    if (_disposed || _autoRefreshClients == 0 || !_lifecycleActive) return;
    try {
      await load(forceRefresh: true);
    } finally {
      _scheduleNextRefresh();
    }
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();
    if (_disposed || _autoRefreshClients == 0 || !_lifecycleActive) return;
    final delay = isOffline ? offlineRetryInterval : autoRefreshInterval;
    _refreshTimer = Timer(delay, _runScheduledRefresh);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_lifecycleActive == active) return;
    _lifecycleActive = active;
    if (active) {
      unawaited(_runScheduledRefresh());
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _refreshTimer?.cancel();
    if (_autoRefreshClients > 0) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _autoRefreshClients = 0;
    _service.close();
    _internetService.close();
    super.dispose();
  }
}
