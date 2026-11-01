import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_translations.dart';
import '../core/currency_service.dart';
import '../core/global_price_service.dart';
import '../core/live_market_store.dart';
import '../core/local_quote_history_store.dart';
import '../core/market_history_service.dart';
import '../core/motion_preferences.dart';
import 'selection_screen.dart';

enum MarketFilter { all, gainers, losers, favorites }

class MarketsScreen extends StatefulWidget {
  const MarketsScreen({
    super.key,
    required this.palette,
    required this.selectedLanguage,
    required this.currencyCode,
    this.marketStore,
    this.priceService,
    this.historyService,
  });

  final ThemePalette palette;
  final GoldBrainLanguage selectedLanguage;
  final String currencyCode;
  final LiveMarketStore? marketStore;
  @Deprecated('Pass marketStore instead.')
  final GlobalPriceService? priceService;
  final MarketHistoryService? historyService;

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final LiveMarketStore _marketStore;
  late final bool _ownsMarketStore;
  late final MarketHistoryService _historyService;
  late final bool _ownsHistoryService;
  bool _isPriceLoading = false;
  Map<String, String> _priceErrors = const {};
  DateTime? _lastPriceUpdate;
  MarketHistoryRange _historyRange = MarketHistoryRange.oneWeek;
  final Map<String, MarketHistorySeries> _historyByKey = {};
  final Map<String, String> _historyErrors = {};
  final Map<String, LocalQuoteHistoryStatus> _localHistoryStatuses = {};
  final Set<String> _historyLoading = {};

  MarketFilter _filter = MarketFilter.all;
  int _selectedIndex = 0;
  final Set<String> _favorites = {'GOLD18', 'XAU', 'BTC'};

  ThemePalette get palette => widget.palette;

  List<_Asset> _assets = [
    _Asset(
      symbol: 'GOLD18',
      en: 'Gold 18K',
      fa: 'طلای ۱۸ عیار',
      ja: '18金',
      ru: 'Золото 18К',
      currency: 'IRT',
      icon: Icons.auto_awesome_rounded,
      accent: Color(0xFFFFD166),
    ),
    _Asset(
      symbol: 'XAU',
      en: 'Global Gold Ounce',
      fa: 'اونس جهانی طلا',
      ja: '金スポット',
      ru: 'Золото, унция',
      currency: 'USD',
      icon: Icons.circle_outlined,
      accent: Color(0xFFFFD166),
    ),
    _Asset(
      symbol: 'USD',
      en: 'US Dollar',
      fa: 'دلار آمریکا',
      ja: '米ドル',
      ru: 'Доллар США',
      currency: 'IRT',
      icon: Icons.attach_money_rounded,
      accent: Color(0xFF52E89A),
    ),
    _Asset(
      symbol: 'BTC',
      en: 'Bitcoin',
      fa: 'بیت‌کوین',
      ja: 'ビットコイン',
      ru: 'Биткоин',
      currency: 'USDT',
      icon: Icons.currency_bitcoin_rounded,
      accent: Color(0xFFFFA62B),
    ),
    _Asset(
      symbol: 'USDT',
      en: 'Tether',
      fa: 'تتر',
      ja: 'テザー',
      ru: 'Тетер',
      currency: 'IRT',
      icon: Icons.currency_exchange_rounded,
      accent: Color(0xFF52E89A),
    ),
    _Asset(
      symbol: 'ETH',
      en: 'Ethereum',
      fa: 'اتریوم',
      ja: 'イーサリアム',
      ru: 'Эфириум',
      currency: 'USDT',
      icon: Icons.diamond_outlined,
      accent: Color(0xFF9B8CFF),
    ),
    _Asset(
      symbol: 'XAG',
      en: 'Global Silver Ounce',
      fa: 'اونس جهانی نقره',
      ja: '銀スポット',
      ru: 'Серебро, унция',
      currency: 'USD',
      icon: Icons.brightness_7_outlined,
      accent: Color(0xFFC6D4E1),
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.marketStore != null) {
      _marketStore = widget.marketStore!;
      _ownsMarketStore = false;
    } else if (widget.priceService != null) {
      _marketStore = LiveMarketStore(service: widget.priceService);
      _ownsMarketStore = true;
    } else {
      _marketStore = LiveMarketStore.instance;
      _ownsMarketStore = false;
    }
    _ownsHistoryService = widget.historyService == null;
    _historyService = widget.historyService ?? MarketHistoryService();
    _marketStore.addListener(_onMarketStoreChanged);
    _syncQuotesFromStore();
    _marketStore.startAutoRefresh();
    unawaited(_loadSelectedHistory());
  }

  @override
  void dispose() {
    _marketStore.removeListener(_onMarketStoreChanged);
    _marketStore.stopAutoRefresh();
    if (_ownsMarketStore) _marketStore.dispose();
    if (_ownsHistoryService) _historyService.close();
    _searchController.dispose();
    super.dispose();
  }

  String get _historyKey => '${selectedAsset.symbol}:${_historyRange.name}';

  static const _additionalAssetNamesFa = {
    'DOT': 'پولکادات',
    'PAXG': 'پکس گلد',
    'NOT': 'نات کوین',
    'AVAX': 'اوالانچ',
    'TON': 'تون کوین',
    'PEPE': 'پپه',
    'ARB': 'اربیتروم',
  };

  void _syncQuotesFromStore() {
    final catalog = _marketStore.assets;
    if (catalog.isNotEmpty) {
      final selectedSymbol = _assets[_selectedIndex].symbol;
      final existing = {for (final asset in _assets) asset.symbol: asset};
      _assets = [
        for (final entry in catalog)
          existing[entry.symbol] ??
              _Asset(
                symbol: entry.symbol,
                en: entry.symbol == 'EUR' ? 'Euro' : entry.name,
                fa: entry.symbol == 'EUR'
                    ? 'یورو'
                    : _additionalAssetNamesFa[entry.symbol] ?? entry.name,
                ja: entry.symbol == 'EUR' ? 'ユーロ' : entry.name,
                ru: entry.symbol == 'EUR' ? 'Евро' : entry.name,
                currency: entry.quoteCurrency,
                icon: entry.symbol == 'EUR'
                    ? Icons.euro_rounded
                    : Icons.token_rounded,
                accent: entry.symbol == 'EUR'
                    ? const Color(0xFF52E89A)
                    : const Color(0xFF9B8CFF),
              ),
      ];
      final index = _assets.indexWhere(
        (asset) => asset.symbol == selectedSymbol,
      );
      _selectedIndex = index < 0 ? 0 : index;
    }
    for (final entry in _marketStore.quotes.entries) {
      final index = _assets.indexWhere((asset) => asset.symbol == entry.key);
      if (index >= 0) _assets[index] = _assets[index].withQuote(entry.value);
    }
    _isPriceLoading = _marketStore.loading;
    _priceErrors = _marketStore.batch?.errors ?? const {};
    _lastPriceUpdate = _marketStore.loadedAt;
  }

  void _onMarketStoreChanged() {
    if (!mounted) return;
    final previousUpdate = _lastPriceUpdate;
    setState(_syncQuotesFromStore);
    if (_lastPriceUpdate != null && _lastPriceUpdate != previousUpdate) {
      unawaited(_loadSelectedHistory(forceRefresh: true));
    }
  }

  String tr({
    required String en,
    required String fa,
    required String ja,
    required String ru,
    String? zh,
    String? ar,
    String? trText,
    String? fr,
  }) {
    switch (widget.selectedLanguage) {
      case GoldBrainLanguage.persian:
        return fa;
      case GoldBrainLanguage.japanese:
        return ja;
      case GoldBrainLanguage.russian:
        return ru;
      case GoldBrainLanguage.chinese:
        return zh ?? en;
      case GoldBrainLanguage.arabic:
        return ar ?? AppTranslations.arabic(en);
      case GoldBrainLanguage.turkish:
        return trText ?? AppTranslations.turkish(en);
      case GoldBrainLanguage.french:
        return fr ?? AppTranslations.french(en);
      case GoldBrainLanguage.english:
        return en;
    }
  }

  String assetName(_Asset asset) {
    switch (widget.selectedLanguage) {
      case GoldBrainLanguage.persian:
        return asset.fa;
      case GoldBrainLanguage.japanese:
        return asset.ja;
      case GoldBrainLanguage.russian:
        return asset.ru;
      case GoldBrainLanguage.chinese:
        return asset.en;
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic(asset.en);
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish(asset.en);
      case GoldBrainLanguage.french:
        return AppTranslations.french(asset.en);
      case GoldBrainLanguage.english:
        return asset.en;
    }
  }

  String formatAssetPrice(_Asset asset, [double? value]) {
    final amount = value ?? asset.price;
    if (amount == null) return '—';
    return CurrencyService.formatPrice(
      value: amount,
      sourceCode: asset.currency,
      selectedCode: widget.currencyCode,
      language: widget.selectedLanguage,
    );
  }

  String formatUpdateTime(DateTime? value) {
    if (value == null) return '—';
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  Future<void> _refreshGlobalPrices({bool showFeedback = false}) async {
    if (_marketStore.loading) return;

    GlobalPriceBatch? result;
    try {
      result = await _marketStore.load(forceRefresh: true);
    } on GlobalPriceException catch (error) {
      if (mounted) {
        setState(() => _priceErrors = {'all': error.message});
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _priceErrors = const {
            'all': 'An unexpected price refresh error occurred.',
          },
        );
      }
    } finally {}

    if (showFeedback && mounted) {
      final loaded = result?.successCount ?? 0;
      final missing =
          result?.errors.keys.join(', ') ?? _priceErrors.keys.join(', ');
      final message = loaded == _assets.length
          ? tr(
              en: 'All $loaded market prices were updated.',
              fa: 'هر $loaded قیمت بازار به‌روزرسانی شد.',
              ja: '$loaded 件すべての市場価格を更新しました。',
              ru: 'Обновлены все цены: $loaded.',
            )
          : tr(
              en: '$loaded of ${_assets.length} prices updated. Unavailable: $missing',
              fa: '$loaded از ${_assets.length} قیمت به‌روزرسانی شد. ناموجود: $missing',
              ja: '${_assets.length} 件中 $loaded 件を更新。取得不可: $missing',
              ru: 'Обновлено $loaded из ${_assets.length}. Недоступно: $missing',
            );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<_Asset> get visibleAssets {
    final query = _searchController.text.trim().toLowerCase();

    return _assets.where((asset) {
      final queryMatches =
          query.isEmpty ||
          asset.symbol.toLowerCase().contains(query) ||
          asset.en.toLowerCase().contains(query) ||
          asset.fa.contains(query) ||
          asset.ja.contains(query) ||
          asset.ru.toLowerCase().contains(query);

      final filterMatches = switch (_filter) {
        MarketFilter.all => true,
        MarketFilter.gainers => asset.change != null && asset.change! >= 0,
        MarketFilter.losers => asset.change != null && asset.change! < 0,
        MarketFilter.favorites => _favorites.contains(asset.symbol),
      };

      return queryMatches && filterMatches;
    }).toList();
  }

  _Asset get selectedAsset => _assets[_selectedIndex];

  void selectAsset(_Asset asset) {
    final index = _assets.indexWhere((item) => item.symbol == asset.symbol);
    if (index < 0) return;
    SystemSound.play(SystemSoundType.click);
    setState(() => _selectedIndex = index);
    unawaited(_loadSelectedHistory());
  }

  Future<void> _loadSelectedHistory({bool forceRefresh = false}) async {
    final symbol = selectedAsset.symbol;
    final range = _historyRange;
    final key = '$symbol:${range.name}';
    if (!forceRefresh && _historyByKey.containsKey(key)) return;
    if (_historyLoading.contains(key)) return;
    if (mounted) {
      setState(() {
        _historyLoading.add(key);
        _historyErrors.remove(key);
      });
    }
    try {
      MarketHistorySeries? series;
      Object? remoteError;
      try {
        series = await _historyService.fetchHistory(
          symbol,
          range: range,
          forceRefresh: forceRefresh,
        );
      } on MarketHistoryException catch (error) {
        remoteError = error;
        series = await _marketStore.localHistoryFor(symbol, range: range);
        _localHistoryStatuses[key] = await _marketStore.localHistoryStatus(
          symbol,
          range: range,
        );
      }
      if (!mounted) return;
      // Each key has at most one in-flight request. Preserve its result even
      // if the user visits another asset/range and returns before it completes.
      // Rendering reads only the currently selected key.
      if (series != null) {
        setState(() => _historyByKey[key] = series!);
      } else {
        final message = remoteError is MarketHistoryException
            ? remoteError.message
            : 'No verified chart points are available.';
        setState(() {
          _historyByKey.remove(key);
          _historyErrors[key] = message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyByKey.remove(key);
        _historyErrors[key] = 'An unexpected chart refresh error occurred.';
      });
    } finally {
      if (mounted) setState(() => _historyLoading.remove(key));
    }
  }

  void _changeHistoryRange(MarketHistoryRange range) {
    if (_historyRange == range) return;
    setState(() => _historyRange = range);
    unawaited(_loadSelectedHistory());
  }

  Future<void> _retryLocalHistory() async {
    await _marketStore.retryNow();
    if (!mounted) return;
    await _loadSelectedHistory(forceRefresh: true);
  }

  void toggleFavorite(_Asset asset) {
    SystemSound.play(SystemSoundType.click);
    setState(() {
      if (_favorites.contains(asset.symbol)) {
        _favorites.remove(asset.symbol);
      } else {
        _favorites.add(asset.symbol);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 940;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            if (compact) ...[
              SizedBox(height: 420, child: _buildExplorer()),
              const SizedBox(height: 16),
              SizedBox(height: 660, child: _buildDetails()),
            ] else
              SizedBox(
                height: 700,
                child: Row(
                  textDirection: TextDirection.ltr,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 360, child: _buildExplorer()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildDetails()),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    final loadedCount = _assets.where((asset) => asset.price != null).length;
    final coverage = loadedCount / _assets.length;
    final totalFailure = _priceErrors.isNotEmpty && loadedCount == 0;
    final partialFailure = _priceErrors.isNotEmpty && loadedCount > 0;
    final refreshDetails = _priceErrors.values.toSet().join(' ');
    final statusColor = totalFailure
        ? const Color(0xFFFF7182)
        : partialFailure || _isPriceLoading
        ? const Color(0xFFFFC857)
        : const Color(0xFF47E596);

    return Container(
      padding: const EdgeInsets.all(21),
      decoration: panelDecoration(),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              gradient: LinearGradient(
                colors: [
                  palette.primary.withValues(alpha: 0.22),
                  palette.secondary.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.34),
              ),
            ),
            child: Icon(
              Icons.candlestick_chart_rounded,
              color: palette.primary,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    en: 'Markets Command Center',
                    fa: 'مرکز فرماندهی بازارها',
                    ja: 'マーケット司令センター',
                    ru: 'Центр управления рынками',
                  ),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    en: 'Search, compare and inspect tracked assets.',
                    fa: 'دارایی‌ها را جست‌وجو، مقایسه و بررسی کنید.',
                    ja: '追跡資産を検索、比較、確認できます。',
                    ru: 'Ищите, сравнивайте и изучайте активы.',
                  ),
                  style: TextStyle(color: palette.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          _MoodGauge(
            palette: palette,
            progress: coverage,
            label: tr(
              en: 'PRICE COVERAGE',
              fa: 'پوشش قیمت',
              ja: '価格カバレッジ',
              ru: 'ПОКРЫТИЕ ЦЕН',
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: refreshDetails.isEmpty
                ? tr(
                    en: 'Refresh prices',
                    fa: 'به‌روزرسانی قیمت‌ها',
                    ja: '価格を更新',
                    ru: 'Обновить цены',
                    zh: '刷新价格',
                  )
                : tr(
                    en: 'Retry price refresh. $refreshDetails',
                    fa: 'تلاش دوباره برای قیمت‌ها. $refreshDetails',
                    ja: '価格更新を再試行。$refreshDetails',
                    ru: 'Повторить обновление цен. $refreshDetails',
                  ),
            onPressed: _isPriceLoading
                ? null
                : () => _refreshGlobalPrices(showFeedback: true),
            icon: _isPriceLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.primary,
                    ),
                  )
                : Icon(
                    totalFailure
                        ? Icons.cloud_off_rounded
                        : partialFailure
                        ? Icons.cloud_sync_rounded
                        : Icons.refresh_rounded,
                    color: totalFailure || partialFailure
                        ? statusColor
                        : palette.primary,
                  ),
          ),
          _FeedStatusChip(
            color: statusColor,
            text: tr(
              en: _isPriceLoading
                  ? 'UPDATING'
                  : partialFailure
                  ? '$loadedCount/${_assets.length} AVAILABLE'
                  : '$loadedCount/${_assets.length} PRICES',
              fa: _isPriceLoading
                  ? 'در حال به‌روزرسانی'
                  : partialFailure
                  ? '$loadedCount از ${_assets.length} قیمت در دسترس'
                  : '$loadedCount از ${_assets.length} قیمت',
              ja: _isPriceLoading
                  ? '更新中'
                  : partialFailure
                  ? '$loadedCount/${_assets.length} 件利用可'
                  : '$loadedCount/${_assets.length} 件',
              ru: _isPriceLoading
                  ? 'ОБНОВЛЕНИЕ'
                  : partialFailure
                  ? '$loadedCount/${_assets.length} ДОСТУПНО'
                  : '$loadedCount/${_assets.length} ЦЕН',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplorer() {
    final assets = visibleAssets;

    return Container(
      decoration: panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 15, 15, 11),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: palette.text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: tr(
                      en: 'Search symbol or asset...',
                      fa: 'جست‌وجوی نماد یا دارایی...',
                      ja: '銘柄や資産を検索...',
                      ru: 'Поиск символа или актива...',
                    ),
                    hintStyle: TextStyle(
                      color: palette.mutedText,
                      fontSize: 11,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: palette.primary,
                      size: 20,
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              color: palette.mutedText,
                              size: 18,
                            ),
                          ),
                    filled: true,
                    fillColor: palette.background.withValues(alpha: 0.45),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                        color: palette.primary.withValues(alpha: 0.13),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                        color: palette.primary.withValues(alpha: 0.70),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      filterButton(
                        MarketFilter.all,
                        tr(en: 'All', fa: 'همه', ja: 'すべて', ru: 'Все'),
                      ),
                      const SizedBox(width: 6),
                      filterButton(
                        MarketFilter.gainers,
                        tr(en: 'Gainers', fa: 'صعودی', ja: '上昇', ru: 'Рост'),
                      ),
                      const SizedBox(width: 6),
                      filterButton(
                        MarketFilter.losers,
                        tr(en: 'Losers', fa: 'نزولی', ja: '下落', ru: 'Падение'),
                      ),
                      const SizedBox(width: 6),
                      filterButton(
                        MarketFilter.favorites,
                        tr(
                          en: 'Saved',
                          fa: 'ذخیره‌شده',
                          ja: '保存済み',
                          ru: 'Сохранено',
                        ),
                        icon: Icons.star_rounded,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.primary.withValues(alpha: 0.10)),
          Expanded(
            child: assets.isEmpty
                ? Center(
                    child: Text(
                      tr(
                        en: 'No matching assets',
                        fa: 'دارایی مطابق پیدا نشد',
                        ja: '一致する資産がありません',
                        ru: 'Активы не найдены',
                      ),
                      style: TextStyle(color: palette.mutedText),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(9),
                    itemCount: assets.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      final conversion = CurrencyService.conversionStatus(
                        sourceCode: asset.currency,
                        selectedCode: widget.currencyCode,
                        language: widget.selectedLanguage,
                      );
                      return _AssetTile(
                        asset: asset,
                        name: assetName(asset),
                        palette: palette,
                        language: widget.selectedLanguage,
                        displayCurrencyCode: widget.currencyCode,
                        selected: selectedAsset.symbol == asset.symbol,
                        refreshFailed:
                            asset.isStale ||
                            _priceErrors.containsKey(asset.symbol) ||
                            conversion.isStale,
                        delayed:
                            asset.isDelayed &&
                            !_priceErrors.containsKey(asset.symbol) &&
                            !conversion.isStale,
                        conversionUnavailable: conversion.unavailable,
                        favorite: _favorites.contains(asset.symbol),
                        onTap: () => selectAsset(asset),
                        onFavorite: () => toggleFavorite(asset),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget filterButton(MarketFilter value, String label, {IconData? icon}) {
    return _FilterButton(
      label: label,
      icon: icon,
      selected: _filter == value,
      palette: palette,
      onTap: () => setState(() => _filter = value),
    );
  }

  Widget _buildHistoryPanel(_Asset asset) {
    final key = _historyKey;
    final series = _historyByKey[key];
    final display = series?.forDisplay(
      selectedCode: widget.currencyCode,
      language: widget.selectedLanguage,
    );
    final loading = _historyLoading.contains(key);
    final hasError = _historyErrors.containsKey(key);
    final localStatus = _localHistoryStatuses[key];
    final localPointCount = localStatus?.pointCount ?? 0;
    final providerSupportsHistory = MarketHistoryService.supportedSymbols
        .contains(asset.symbol);
    final needsDomesticSourceConfiguration =
        MarketHistoryService.domesticSymbols.contains(asset.symbol) &&
        !_historyService.isHistoryConfiguredFor(
          asset.symbol,
          range: _historyRange,
        );

    return Container(
      key: ValueKey('market-chart-${asset.symbol}-${_historyRange.name}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.29),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: palette.primary.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, color: asset.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(
                    en: 'REAL PRICE HISTORY',
                    fa: 'تاریخچه واقعی قیمت',
                    ja: '実際の価格履歴',
                    ru: 'РЕАЛЬНАЯ ИСТОРИЯ ЦЕН',
                  ),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _HistoryRangeButton(
                label: tr(en: '1H', fa: '۱ ساعت', ja: '1時間', ru: '1Ч'),
                selected: _historyRange == MarketHistoryRange.oneHour,
                palette: palette,
                onTap: () => _changeHistoryRange(MarketHistoryRange.oneHour),
              ),
              const SizedBox(width: 6),
              _HistoryRangeButton(
                label: tr(en: '24H', fa: '۲۴ ساعت', ja: '24時間', ru: '24Ч'),
                selected: _historyRange == MarketHistoryRange.oneDay,
                palette: palette,
                onTap: () => _changeHistoryRange(MarketHistoryRange.oneDay),
              ),
              const SizedBox(width: 6),
              _HistoryRangeButton(
                label: tr(en: '7D', fa: '۷ روز', ja: '7日', ru: '7Д'),
                selected: _historyRange == MarketHistoryRange.oneWeek,
                palette: palette,
                onTap: () => _changeHistoryRange(MarketHistoryRange.oneWeek),
              ),
              const SizedBox(width: 6),
              _HistoryRangeButton(
                label: tr(en: '30D', fa: '۳۰ روز', ja: '30日', ru: '30Д'),
                selected: _historyRange == MarketHistoryRange.oneMonth,
                palette: palette,
                onTap: () => _changeHistoryRange(MarketHistoryRange.oneMonth),
              ),
              const SizedBox(width: 7),
              IconButton(
                key: const ValueKey('expand-market-chart'),
                tooltip: tr(
                  en: 'Open large chart',
                  fa: 'باز کردن نمودار بزرگ',
                  ja: '大きなチャートを開く',
                  ru: 'Открыть большой график',
                ),
                onPressed: series == null
                    ? null
                    : () => _showExpandedChart(asset, series),
                icon: const Icon(Icons.open_in_full_rounded, size: 17),
                color: palette.primary,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Expanded(
            child: AnimatedSwitcher(
              duration: MotionPreferences.duration(320),
              child: loading && series == null
                  ? Center(
                      key: const ValueKey('chart-loading'),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.primary,
                      ),
                    )
                  : series != null
                  ? _InteractiveMarketChart(
                      key: ValueKey(
                        '${series.symbol}-${series.range.name}-${series.fetchedAt.millisecondsSinceEpoch}-${widget.currencyCode}',
                      ),
                      series: display!.series,
                      color: asset.accent,
                      textColor: palette.text,
                      mutedColor: palette.mutedText,
                      backgroundColor: palette.background,
                      onOpen: () => _showExpandedChart(asset, series),
                      openOnTap: true,
                    )
                  : _ChartUnavailable(
                      key: const ValueKey('chart-unavailable'),
                      palette: palette,
                      title: needsDomesticSourceConfiguration
                          ? tr(
                              en: 'Iranian-market history needs an API key',
                              fa: 'تاریخچهٔ بازار ایران به کلید API نیاز دارد',
                              ja: 'イラン市場履歴にはAPIキーが必要です',
                              ru: 'Для истории рынка Ирана нужен API-ключ',
                              zh: '伊朗市场历史数据需要 API 密钥',
                              ar: 'سجل السوق الإيراني يحتاج إلى مفتاح API',
                              trText:
                                  'İran piyasası geçmişi için API anahtarı gerekli',
                              fr: 'Une clé API est requise pour l’historique iranien',
                            )
                          : providerSupportsHistory
                          ? tr(
                              en: 'Historical data is temporarily unavailable',
                              fa: 'داده تاریخی موقتاً در دسترس نیست',
                              ja: '履歴データは一時的に利用できません',
                              ru: 'Исторические данные временно недоступны',
                            )
                          : tr(
                              en: 'Waiting for verified local price samples',
                              fa: 'در انتظار نمونه‌های واقعی بیشتر روی این دستگاه',
                              ja: 'この端末で検証済み価格を記録しています',
                              ru: 'Записываются проверенные локальные котировки',
                            ),
                      detail: needsDomesticSourceConfiguration
                          ? tr(
                              en: 'Set NAVASAN_API_KEY before launch. Until then, $localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} real same-source device samples are available; no missing points are generated.',
                              fa: 'پیش از اجرا NAVASAN_API_KEY را تنظیم کنید. تا آن زمان $localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} نمونهٔ واقعی هم‌منبع روی دستگاه ثبت شده است و هیچ نقطهٔ گمشده‌ای ساخته نمی‌شود.',
                              ja: '起動前に NAVASAN_API_KEY を設定してください。それまでは同一ソースの実測サンプルが $localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} 件あり、欠損点は生成しません。',
                              ru: 'Задайте NAVASAN_API_KEY до запуска. Пока доступно $localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} реальных точек одного источника; пропуски не создаются.',
                              zh: '请在启动前设置 NAVASAN_API_KEY。目前设备上有 $localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} 个同源真实样本，不会生成缺失点。',
                              ar: 'اضبط NAVASAN_API_KEY قبل التشغيل. حتى ذلك الحين توجد $localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} عينات حقيقية من المصدر نفسه، ولا يتم إنشاء نقاط مفقودة.',
                              trText:
                                  'Başlatmadan önce NAVASAN_API_KEY ayarlayın. Şimdilik aynı kaynaktan $localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} gerçek cihaz örneği var; eksik noktalar üretilmez.',
                              fr: 'Définissez NAVASAN_API_KEY avant le lancement. En attendant, $localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} échantillons réels de même source sont disponibles ; aucun point manquant n’est créé.',
                            )
                          : providerSupportsHistory
                          ? tr(
                              en: 'The providers returned no usable points. Try again.',
                              fa: 'منابع، نقطه قابل استفاده‌ای برنگرداندند؛ دوباره تلاش کنید.',
                              ja: '利用可能なデータ点が返されませんでした。再試行してください。',
                              ru: 'Источники не вернули пригодных точек. Повторите попытку.',
                            )
                          : tr(
                              en: '$localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} same-source updates · observed ${_formatDuration(localStatus?.observedSpan ?? Duration.zero)} / required ${_formatDuration(localStatus?.minimumObservedSpan ?? LocalQuoteHistoryStore.minimumObservedSpan(_historyRange))}. No upstream history is exposed for this Iranian symbol; no points are generated.',
                              fa: '$localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} به‌روزرسانی هم‌منبع · پوشش واقعی ${_formatDuration(localStatus?.observedSpan ?? Duration.zero)} از حداقل ${_formatDuration(localStatus?.minimumObservedSpan ?? LocalQuoteHistoryStore.minimumObservedSpan(_historyRange))}. برای این نماد ایرانی تاریخچهٔ بالادستی ارائه نشده و هیچ نقطه‌ای ساخته نمی‌شود.',
                              ja: '同一ソースの更新 $localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} 件 · 観測 ${_formatDuration(localStatus?.observedSpan ?? Duration.zero)} / 必要 ${_formatDuration(localStatus?.minimumObservedSpan ?? LocalQuoteHistoryStore.minimumObservedSpan(_historyRange))}。点は生成しません。',
                              ru: '$localPointCount/${LocalQuoteHistoryStore.minimumChartPoints} обновлений из одного источника · наблюдается ${_formatDuration(localStatus?.observedSpan ?? Duration.zero)} из требуемых ${_formatDuration(localStatus?.minimumObservedSpan ?? LocalQuoteHistoryStore.minimumObservedSpan(_historyRange))}. Точки не создаются.',
                            ),
                      onRetry: needsDomesticSourceConfiguration
                          ? () => _retryLocalHistory()
                          : providerSupportsHistory && hasError
                          ? () => _loadSelectedHistory(forceRefresh: true)
                          : () => _retryLocalHistory(),
                    ),
            ),
          ),
          if (series != null) ...[
            const SizedBox(height: 6),
            if (display?.conversionStale == true ||
                display?.conversionUnavailable == true)
              Text(
                display?.conversionUnavailable == true
                    ? tr(
                        en: 'Exchange rate unavailable; chart remains in ${series.currency}.',
                        fa: 'نرخ تبدیل در دسترس نیست؛ نمودار به ${series.currency} نمایش داده می‌شود.',
                        ja: '為替レートを取得できないため、チャートは ${series.currency} のままです。',
                        ru: 'Курс недоступен; график остается в ${series.currency}.',
                      )
                    : tr(
                        en: 'Chart uses the last known exchange rate.',
                        fa: 'نمودار با آخرین نرخ تبدیل ثبت‌شده نمایش داده می‌شود.',
                        ja: 'チャートには最後に取得した為替レートを使用しています。',
                        ru: 'График использует последний известный курс.',
                      ),
                style: const TextStyle(color: Color(0xFFFFC857), fontSize: 10),
              ),
            Row(
              children: [
                Icon(
                  series.isStale
                      ? Icons.history_toggle_off_rounded
                      : series.isProxy
                      ? Icons.info_outline_rounded
                      : Icons.verified_rounded,
                  size: 13,
                  color: series.isStale || series.isProxy
                      ? const Color(0xFFFFC857)
                      : const Color(0xFF50E397),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    series.isLocalHistory || series.isPriceSample
                        ? series.isStale
                              ? tr(
                                  en: '${series.candles.length} verified samples from ${series.providerLabel} · ${_shortEvidenceTime(series.candles.first.time)} → ${_shortEvidenceTime(series.candles.last.time)} · stale · no interpolation',
                                  fa: '${series.candles.length} نمونهٔ واقعی از ${series.providerLabel} · ${_shortEvidenceTime(series.candles.first.time)} تا ${_shortEvidenceTime(series.candles.last.time)} · قدیمی · بدون نقطهٔ واسط',
                                  ja: '${series.providerLabel} の検証済みサンプル ${series.candles.length} 件 · ${_shortEvidenceTime(series.candles.first.time)} → ${_shortEvidenceTime(series.candles.last.time)} · 古い · 補間なし',
                                  ru: '${series.candles.length} проверенных точек ${series.providerLabel} · ${_shortEvidenceTime(series.candles.first.time)} → ${_shortEvidenceTime(series.candles.last.time)} · устарели · без интерполяции',
                                )
                              : tr(
                                  en: '${series.candles.length} verified same-source samples · actual window ${_formatDuration(series.observedSpan)} · ${series.providerLabel} · no interpolation',
                                  fa: '${series.candles.length} نمونهٔ واقعی هم‌منبع · بازهٔ واقعی ${_formatDuration(series.observedSpan)} · ${series.providerLabel} · بدون نقطهٔ واسط',
                                  ja: '同一ソースの検証済みサンプル ${series.candles.length} 件 · 実測期間 ${_formatDuration(series.observedSpan)} · ${series.providerLabel} · 補間なし',
                                  ru: '${series.candles.length} точек из одного источника · фактический период ${_formatDuration(series.observedSpan)} · ${series.providerLabel} · без интерполяции',
                                )
                        : series.isStale
                        ? tr(
                            en: 'The latest verified observation from ${series.providerLabel} is old; no newer value is being implied.',
                            fa: 'آخرین مشاهدهٔ تأییدشده از ${series.providerLabel} قدیمی است؛ مقدار جدیدتری القا نمی‌شود.',
                            ja: '${series.providerLabel} の最新の検証済み観測値は古いため、新しい値があるようには表示しません。',
                            ru: 'Последнее подтверждённое наблюдение ${series.providerLabel} устарело; более новое значение не подразумевается.',
                          )
                        : series.isProxy
                        ? tr(
                            en: '${series.providerLabel}; a real futures proxy, not the XAU/XAG spot quote.',
                            fa: '${series.providerLabel}؛ داده واقعی قرارداد آتی است، نه قیمت لحظه‌ای XAU/XAG.',
                            ja: '${series.providerLabel}。XAU/XAG現物ではなく実際の先物データです。',
                            ru: '${series.providerLabel}; реальные фьючерсы, а не спот XAU/XAG.',
                          )
                        : tr(
                            en: 'Source: ${series.providerLabel} · Hover for exact values · Click to enlarge',
                            fa: 'منبع: ${series.providerLabel} · برای مقدار دقیق نشانگر را حرکت دهید · برای بزرگ‌نمایی کلیک کنید',
                            ja: '出典: ${series.providerLabel} · ホバーで値を表示 · クリックで拡大',
                            ru: 'Источник: ${series.providerLabel} · Наведите для значения · Нажмите для увеличения',
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 9,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _shortEvidenceTime(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _formatDuration(Duration value) {
    if (value.inDays > 0) {
      final hours = value.inHours.remainder(24);
      return hours == 0 ? '${value.inDays}d' : '${value.inDays}d ${hours}h';
    }
    if (value.inHours > 0) {
      final minutes = value.inMinutes.remainder(60);
      return minutes == 0
          ? '${value.inHours}h'
          : '${value.inHours}h ${minutes}m';
    }
    return '${value.inMinutes}m';
  }

  Future<void> _showExpandedChart(
    _Asset asset,
    MarketHistorySeries initialSeries,
  ) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (context) => _ExpandedMarketChartDialog(
        assetName: assetName(asset),
        asset: asset,
        initialSeries: initialSeries,
        service: _historyService,
        marketStore: _marketStore,
        palette: palette,
        language: widget.selectedLanguage,
        currencyCode: widget.currencyCode,
      ),
    );
  }

  Widget _buildDetails() {
    final asset = selectedAsset;
    final selectedHistory = _historyByKey[_historyKey];
    final hasNavasanDomesticData =
        const {'USD', 'EUR', 'GOLD18'}.contains(asset.symbol) &&
        (asset.provider?.name == 'navasan' ||
            asset.upstreamSource?.trim().toLowerCase() == 'navasan' ||
            selectedHistory?.provider.name == 'navasan' ||
            selectedHistory?.providerLabel.toLowerCase().contains('navasan') ==
                true);
    final conversion = CurrencyService.conversionStatus(
      sourceCode: asset.currency,
      selectedCode: widget.currencyCode,
      language: widget.selectedLanguage,
    );
    final refreshFailed =
        asset.isStale ||
        _priceErrors.containsKey(asset.symbol) ||
        conversion.isStale;
    final delayed =
        asset.isDelayed &&
        !_priceErrors.containsKey(asset.symbol) &&
        !conversion.isStale;

    return Container(
      padding: const EdgeInsets.all(21),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.ltr,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: asset.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: asset.accent.withValues(alpha: 0.34),
                  ),
                ),
                child: Icon(asset.icon, color: asset.accent, size: 28),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        Flexible(
                          child: Text(
                            assetName(asset),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          asset.symbol,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: palette.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      textDirection: TextDirection.ltr,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatAssetPrice(asset),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 29,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (conversion.unavailable && asset.price != null)
                const _MarketSourceBadge(
                  text: 'FX N/A',
                  color: Color(0xFFFFC857),
                  large: true,
                )
              else if (refreshFailed && asset.price != null)
                _MarketSourceBadge(
                  text: delayed ? 'DELAYED' : 'STALE',
                  color: const Color(0xFFFFC857),
                  large: true,
                )
              else if (asset.change != null)
                _ChangeBadge(change: asset.change!, large: true)
              else
                _MarketSourceBadge(
                  text: asset.price == null
                      ? tr(
                          en: 'UNAVAILABLE',
                          fa: 'ناموجود',
                          ja: '取得不可',
                          ru: 'НЕТ ДАННЫХ',
                        )
                      : asset.sourceLabel,
                  color: asset.price == null
                      ? const Color(0xFFFF7182)
                      : const Color(0xFF50E397),
                  large: true,
                ),
              const SizedBox(width: 9),
              _FavoriteButton(
                palette: palette,
                active: _favorites.contains(asset.symbol),
                onTap: () => toggleFavorite(asset),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(child: _buildHistoryPanel(asset)),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final data = [
                _Stat(
                  tr(
                    en: 'PROVIDER',
                    fa: 'ارائه‌دهنده',
                    ja: 'データ提供元',
                    ru: 'ИСТОЧНИК',
                  ),
                  asset.sourceLabel,
                  Icons.dns_outlined,
                ),
                _Stat(
                  tr(
                    en: 'UPDATED',
                    fa: 'زمان به‌روزرسانی',
                    ja: '更新時刻',
                    ru: 'ОБНОВЛЕНО',
                  ),
                  formatUpdateTime(asset.updatedAt),
                  Icons.schedule_rounded,
                ),
                _Stat(
                  tr(
                    en: '24H CHANGE',
                    fa: 'تغییر ۲۴ ساعته',
                    ja: '24時間変動',
                    ru: 'ИЗМЕНЕНИЕ 24Ч',
                  ),
                  asset.change == null
                      ? tr(
                          en: 'Not provided',
                          fa: 'ارائه نشده',
                          ja: '提供なし',
                          ru: 'Нет данных',
                        )
                      : '${asset.change! >= 0 ? '+' : ''}${asset.change!.toStringAsFixed(2)}%',
                  Icons.percent_rounded,
                ),
              ];

              if (constraints.maxWidth < 650) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: data
                      .map(
                        (item) => SizedBox(
                          width: (constraints.maxWidth - 8) / 2,
                          child: _StatCard(data: item, palette: palette),
                        ),
                      )
                      .toList(),
                );
              }

              return Row(
                children: List.generate(data.length, (index) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index == data.length - 1 ? 0 : 8,
                      ),
                      child: _StatCard(data: data[index], palette: palette),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.primary.withValues(alpha: 0.08),
                  palette.secondary.withValues(alpha: 0.025),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: palette.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasNavasanDomesticData
                        ? tr(
                            en: 'Navasan free data refresh about every 2 hours; the app checks no more than once per 8 hours to protect the development quota. These prices are not live. Check source time and observed chart points.',
                            fa: 'دادهٔ رایگان نوسان حدود هر ۲ ساعت به‌روز می‌شود؛ برنامه برای حفظ سهمیهٔ توسعه بیش از یک بار در هر ۸ ساعت بررسی نمی‌کند. این قیمت‌ها لحظه‌ای نیستند؛ زمان منبع و نقاط واقعی نمودار را ببینید.',
                            ja: 'Navasanの無料データは約2時間ごとに更新されます。開発枠を守るため、アプリの確認は8時間に1回以下です。リアルタイムではありません。提供元の時刻と実測点をご確認ください。',
                            ru: 'Бесплатные данные Navasan обновляются примерно раз в 2 ч; приложение проверяет не чаще раза в 8 ч ради квоты разработки. Это не потоковая цена. Сверяйте время источника и точки графика.',
                          )
                        : tr(
                            en: 'Only fields returned by the named provider are shown. High, low, volume and market cap are intentionally omitted when unavailable.',
                            fa: 'فقط داده‌هایی نمایش داده می‌شوند که منبع نام‌برده برگردانده باشد؛ بیشترین، کمترین، حجم و ارزش بازار در صورت نبود منبع عمداً حذف شده‌اند.',
                            ja: '表示するのは提供元が返した項目だけです。高値・安値・出来高・時価総額がない場合は意図的に省略します。',
                            ru: 'Показаны только поля, полученные от указанного источника. Максимум, минимум, объём и капитализация скрыты, если их нет.',
                          ),
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration panelDecoration() {
    return BoxDecoration(
      color: palette.surface.withValues(alpha: 0.84),
      borderRadius: BorderRadius.circular(27),
      border: Border.all(color: palette.primary.withValues(alpha: 0.18)),
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 26, offset: Offset(0, 13)),
      ],
    );
  }
}

class _HistoryRangeButton extends StatelessWidget {
  const _HistoryRangeButton({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ThemePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: MotionPreferences.duration(180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: palette.primary.withValues(alpha: selected ? 0.18 : 0.035),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: palette.primary.withValues(alpha: selected ? 0.58 : 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.primary : palette.mutedText,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ChartUnavailable extends StatelessWidget {
  const _ChartUnavailable({
    super.key,
    required this.palette,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final ThemePalette palette;
  final String title;
  final String detail;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.query_stats_rounded, color: palette.mutedText, size: 37),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 10,
                height: 1.45,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              IconButton.filledTonal(
                tooltip: 'Retry chart',
                onPressed: () => unawaited(onRetry!()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InteractiveMarketChart extends StatefulWidget {
  const _InteractiveMarketChart({
    super.key,
    required this.series,
    required this.color,
    required this.textColor,
    required this.mutedColor,
    required this.backgroundColor,
    required this.openOnTap,
    this.onOpen,
  });

  final MarketHistorySeries series;
  final Color color;
  final Color textColor;
  final Color mutedColor;
  final Color backgroundColor;
  final bool openOnTap;
  final VoidCallback? onOpen;

  @override
  State<_InteractiveMarketChart> createState() =>
      _InteractiveMarketChartState();
}

class _InteractiveMarketChartState extends State<_InteractiveMarketChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MotionPreferences.controllerDuration(720),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _InteractiveMarketChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series != widget.series) {
      _hoveredIndex = null;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updatePointer(Offset localPosition, double width) {
    final usableWidth = math.max(1.0, width - 28);
    final normalized = ((localPosition.dx - 14) / usableWidth).clamp(0.0, 1.0);
    final candles = widget.series.candles;
    final (domainStart, domainEnd) = _timeDomain(widget.series);
    final firstMs = domainStart.millisecondsSinceEpoch;
    final lastMs = domainEnd.millisecondsSinceEpoch;
    final targetMs = firstMs + ((lastMs - firstMs) * normalized).round();
    var index = 0;
    var nearestDistance = (candles.first.time.millisecondsSinceEpoch - targetMs)
        .abs();
    for (var candidate = 1; candidate < candles.length; candidate++) {
      final distance =
          (candles[candidate].time.millisecondsSinceEpoch - targetMs).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        index = candidate;
      }
    }
    if (index != _hoveredIndex) setState(() => _hoveredIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.series.candles.first.close;
    final last = widget.series.candles.last.close;
    final percent = first == 0 ? 0.0 : ((last - first) / first) * 100;
    final semantics =
        '${widget.series.symbol} ${widget.series.range.name} chart, '
        '${widget.series.candles.length} real points, '
        '${percent >= 0 ? 'up' : 'down'} ${percent.abs().toStringAsFixed(2)} percent';

    return Semantics(
      label: semantics,
      button: widget.openOnTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return MouseRegion(
            cursor: widget.openOnTap
                ? SystemMouseCursors.click
                : SystemMouseCursors.precise,
            onExit: (_) => setState(() => _hoveredIndex = null),
            child: Listener(
              onPointerHover: (event) =>
                  _updatePointer(event.localPosition, constraints.maxWidth),
              onPointerDown: (event) =>
                  _updatePointer(event.localPosition, constraints.maxWidth),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.openOnTap ? widget.onOpen : null,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _MarketLineChartPainter(
                      candles: widget.series.candles,
                      lineColor: widget.color,
                      textColor: widget.textColor,
                      mutedColor: widget.mutedColor,
                      backgroundColor: widget.backgroundColor,
                      progress: Curves.easeOutCubic.transform(
                        _controller.value,
                      ),
                      highlightedIndex: _hoveredIndex,
                      currency: widget.series.currency,
                      domainStart: _timeDomain(widget.series).$1,
                      domainEnd: _timeDomain(widget.series).$2,
                      showSamplePoints:
                          widget.series.isLocalHistory ||
                          widget.series.isPriceSample,
                      showOhlcCandles:
                          widget.series.range == MarketHistoryRange.oneWeek &&
                          !widget.series.isLocalHistory &&
                          !widget.series.isPriceSample &&
                          widget.series.candles.any(
                            (candle) =>
                                candle.high != candle.low ||
                                candle.open != candle.close,
                          ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  (DateTime, DateTime) _timeDomain(MarketHistorySeries series) {
    final domain = series.actualTimeDomain;
    return (domain.start, domain.end);
  }
}

class _MarketLineChartPainter extends CustomPainter {
  const _MarketLineChartPainter({
    required this.candles,
    required this.lineColor,
    required this.textColor,
    required this.mutedColor,
    required this.backgroundColor,
    required this.progress,
    required this.highlightedIndex,
    required this.currency,
    required this.domainStart,
    required this.domainEnd,
    required this.showSamplePoints,
    required this.showOhlcCandles,
  });

  final List<MarketCandle> candles;
  final Color lineColor;
  final Color textColor;
  final Color mutedColor;
  final Color backgroundColor;
  final double progress;
  final int? highlightedIndex;
  final String currency;
  final DateTime domainStart;
  final DateTime domainEnd;
  final bool showSamplePoints;
  final bool showOhlcCandles;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.length < 2 || size.width <= 40 || size.height <= 40) return;
    const left = 14.0;
    const right = 14.0;
    const top = 18.0;
    const bottom = 24.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final values = showOhlcCandles
        ? candles.expand((point) => <double>[point.low, point.high])
        : candles.map((point) => point.close);
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    if ((maxValue - minValue).abs() < 0.0000001) {
      final padding = math.max(1.0, maxValue.abs() * 0.01);
      minValue -= padding;
      maxValue += padding;
    } else {
      final padding = (maxValue - minValue) * 0.08;
      minValue -= padding;
      maxValue += padding;
    }

    final firstTimeMs = domainStart.millisecondsSinceEpoch;
    final lastTimeMs = domainEnd.millisecondsSinceEpoch;
    final timeSpan = math.max(1, lastTimeMs - firstTimeMs);

    Offset pointAt(int index) {
      final elapsed = candles[index].time.millisecondsSinceEpoch - firstTimeMs;
      final x = left + chartWidth * elapsed / timeSpan;
      final ratio = (candles[index].close - minValue) / (maxValue - minValue);
      return Offset(x, top + chartHeight * (1 - ratio));
    }

    double yFor(double value) {
      final ratio = (value - minValue) / (maxValue - minValue);
      return top + chartHeight * (1 - ratio);
    }

    final gridPaint = Paint()
      ..color = mutedColor.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = top + chartHeight * index / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }
    for (var index = 0; index <= 6; index++) {
      final x = left + chartWidth * index / 6;
      canvas.drawLine(Offset(x, top), Offset(x, top + chartHeight), gridPaint);
    }

    final linePath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var index = 1; index < candles.length; index++) {
      final point = pointAt(index);
      // Sparse provider observations must not imply a price trajectory across
      // an interval where the source supplied no data.
      if (showSamplePoints &&
          candles[index].time.difference(candles[index - 1].time) >
              const Duration(hours: 4)) {
        linePath.moveTo(point.dx, point.dy);
      } else {
        linePath.lineTo(point.dx, point.dy);
      }
    }
    final areaPath = Path.from(linePath)
      ..lineTo(pointAt(candles.length - 1).dx, top + chartHeight)
      ..lineTo(left, top + chartHeight)
      ..close();

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(left, top, chartWidth * progress, chartHeight),
    );
    if (!showSamplePoints) {
      canvas.drawPath(
        areaPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              lineColor.withValues(alpha: 0.27),
              lineColor.withValues(alpha: 0.01),
            ],
          ).createShader(Rect.fromLTWH(left, top, chartWidth, chartHeight)),
      );
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = showOhlcCandles ? 1.35 : 2.3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (showOhlcCandles) {
      final bodyWidth = (chartWidth / math.max(10, candles.length * 1.7))
          .clamp(3.0, 11.0)
          .toDouble();
      for (var index = 0; index < candles.length; index++) {
        final candle = candles[index];
        final x = pointAt(index).dx;
        final rising = candle.close >= candle.open;
        final candleColor = rising
            ? lineColor
            : Color.lerp(lineColor, const Color(0xFFFF5D73), 0.66)!;
        canvas.drawLine(
          Offset(x, yFor(candle.high)),
          Offset(x, yFor(candle.low)),
          Paint()
            ..color = candleColor.withValues(alpha: 0.9)
            ..strokeWidth = 1.3,
        );
        final openY = yFor(candle.open);
        final closeY = yFor(candle.close);
        final bodyTop = math.min(openY, closeY);
        final bodyHeight = math.max(1.8, (openY - closeY).abs());
        final body = Rect.fromLTWH(
          x - (bodyWidth / 2),
          bodyTop,
          bodyWidth,
          bodyHeight,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(body, const Radius.circular(1.2)),
          Paint()
            ..color = rising
                ? candleColor.withValues(alpha: 0.8)
                : candleColor.withValues(alpha: 0.3)
            ..style = rising ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }
    if (showSamplePoints) {
      final pointPaint = Paint()..color = lineColor;
      for (var index = 0; index < candles.length; index++) {
        canvas.drawCircle(pointAt(index), 2.8, pointPaint);
      }
    }
    canvas.restore();

    final firstTime = domainStart;
    final lastTime = domainEnd;
    _paintText(
      canvas,
      _shortTime(firstTime),
      Offset(left, size.height - 18),
      mutedColor,
      9,
    );
    final endPainter = _textPainter(_shortTime(lastTime), mutedColor, 9);
    endPainter.paint(
      canvas,
      Offset(size.width - right - endPainter.width, size.height - 18),
    );

    final selected = highlightedIndex;
    if (selected != null && selected >= 0 && selected < candles.length) {
      final point = pointAt(selected);
      final candle = candles[selected];
      canvas.drawLine(
        Offset(point.dx, top),
        Offset(point.dx, top + chartHeight),
        Paint()
          ..color = lineColor.withValues(alpha: 0.38)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(point, 5, Paint()..color = backgroundColor);
      canvas.drawCircle(point, 3.2, Paint()..color = lineColor);
      final label = showOhlcCandles
          ? 'O ${_formatPrice(candle.open)}  H ${_formatPrice(candle.high)}  '
                'L ${_formatPrice(candle.low)}  C ${_formatPrice(candle.close)} '
                '$currency  ·  ${_fullTime(candle.time)}'
          : '${_formatPrice(candle.close)} $currency  ·  ${_fullTime(candle.time)}';
      final painter = _textPainter(label, textColor, 10, bold: true);
      final boxWidth = painter.width + 16;
      final boxHeight = painter.height + 10;
      final boxLeft = (point.dx - boxWidth / 2).clamp(
        left,
        size.width - right - boxWidth,
      );
      final boxTop = math.max(top, point.dy - boxHeight - 10);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(boxLeft, boxTop, boxWidth, boxHeight),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = backgroundColor.withValues(alpha: 0.94),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = lineColor.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke,
      );
      painter.paint(canvas, Offset(boxLeft + 8, boxTop + 5));
    }
  }

  String _formatPrice(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(3);
    return value.toStringAsFixed(6);
  }

  String _shortTime(DateTime value) =>
      '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:00';

  String _fullTime(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  TextPainter _textPainter(
    String text,
    Color color,
    double size, {
    bool bold = false,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double size,
  ) {
    _textPainter(text, color, size).paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _MarketLineChartPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.progress != progress ||
        oldDelegate.highlightedIndex != highlightedIndex ||
        oldDelegate.domainStart != domainStart ||
        oldDelegate.domainEnd != domainEnd ||
        oldDelegate.showSamplePoints != showSamplePoints ||
        oldDelegate.showOhlcCandles != showOhlcCandles ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.textColor != textColor;
  }
}

class _ExpandedMarketChartDialog extends StatefulWidget {
  const _ExpandedMarketChartDialog({
    required this.assetName,
    required this.asset,
    required this.initialSeries,
    required this.service,
    required this.marketStore,
    required this.palette,
    required this.language,
    required this.currencyCode,
  });

  final String assetName;
  final _Asset asset;
  final MarketHistorySeries initialSeries;
  final MarketHistoryService service;
  final LiveMarketStore marketStore;
  final ThemePalette palette;
  final GoldBrainLanguage language;
  final String currencyCode;

  @override
  State<_ExpandedMarketChartDialog> createState() =>
      _ExpandedMarketChartDialogState();
}

class _ExpandedMarketChartDialogState
    extends State<_ExpandedMarketChartDialog> {
  late MarketHistoryRange _range;
  late MarketHistorySeries _series;
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _range = widget.initialSeries.range;
    _series = widget.initialSeries;
  }

  String tr(String en, String fa, String ja, String ru, [String? zh]) =>
      switch (widget.language) {
        GoldBrainLanguage.persian => fa,
        GoldBrainLanguage.japanese => ja,
        GoldBrainLanguage.russian => ru,
        GoldBrainLanguage.chinese => zh ?? en,
        GoldBrainLanguage.arabic => AppTranslations.arabic(en),
        GoldBrainLanguage.turkish => AppTranslations.turkish(en),
        GoldBrainLanguage.french => AppTranslations.french(en),
        GoldBrainLanguage.english => en,
      };

  Future<void> _selectRange(MarketHistoryRange range) async {
    if (_range == range || _loading) return;
    final requestId = ++_requestId;
    final previousRange = _range;
    setState(() {
      _range = range;
      _loading = true;
      _error = null;
    });
    try {
      MarketHistorySeries? series;
      try {
        series = await widget.service.fetchHistory(
          widget.asset.symbol,
          range: range,
        );
      } on MarketHistoryException {
        series = await widget.marketStore.localHistoryFor(
          widget.asset.symbol,
          range: range,
        );
      }
      final resolved = series;
      if (resolved == null) {
        throw const MarketHistoryException(
          'Not enough verified local chart points.',
          unavailable: true,
        );
      }
      if (!mounted || requestId != _requestId) return;
      setState(() => _series = resolved);
    } on MarketHistoryException {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _range = previousRange;
        _error = tr(
          'Historical data is temporarily unavailable.',
          'داده تاریخی موقتاً در دسترس نیست.',
          '履歴データは一時的に利用できません。',
          'Исторические данные временно недоступны.',
        );
      });
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = _series.forDisplay(
      selectedCode: widget.currencyCode,
      language: widget.language,
    );
    return Dialog(
      key: const ValueKey('expanded-market-chart-dialog'),
      backgroundColor: widget.palette.surface,
      insetPadding: const EdgeInsets.all(28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: widget.palette.primary.withValues(alpha: 0.35)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(widget.asset.icon, color: widget.asset.accent, size: 27),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      '${widget.assetName} · ${widget.asset.symbol}',
                      style: TextStyle(
                        color: widget.palette.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _HistoryRangeButton(
                    label: tr('1H', '۱ ساعت', '1時間', '1Ч'),
                    selected: _range == MarketHistoryRange.oneHour,
                    palette: widget.palette,
                    onTap: () => _selectRange(MarketHistoryRange.oneHour),
                  ),
                  const SizedBox(width: 7),
                  _HistoryRangeButton(
                    label: tr('24H', '۲۴ ساعت', '24時間', '24Ч'),
                    selected: _range == MarketHistoryRange.oneDay,
                    palette: widget.palette,
                    onTap: () => _selectRange(MarketHistoryRange.oneDay),
                  ),
                  const SizedBox(width: 7),
                  _HistoryRangeButton(
                    label: tr('7D', '۷ روز', '7日', '7Д'),
                    selected: _range == MarketHistoryRange.oneWeek,
                    palette: widget.palette,
                    onTap: () => _selectRange(MarketHistoryRange.oneWeek),
                  ),
                  const SizedBox(width: 7),
                  _HistoryRangeButton(
                    label: tr('30D', '۳۰ روز', '30日', '30Д'),
                    selected: _range == MarketHistoryRange.oneMonth,
                    palette: widget.palette,
                    onTap: () => _selectRange(MarketHistoryRange.oneMonth),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: tr('Close', 'بستن', '閉じる', 'Закрыть'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _InteractiveMarketChart(
                        key: ValueKey(
                          'large-${_series.symbol}-${_series.range.name}-${_series.fetchedAt.millisecondsSinceEpoch}',
                        ),
                        series: display.series,
                        color: widget.asset.accent,
                        textColor: widget.palette.text,
                        mutedColor: widget.palette.mutedText,
                        backgroundColor: widget.palette.background,
                        openOnTap: false,
                      ),
                    ),
                    if (_loading)
                      Positioned.fill(
                        child: ColoredBox(
                          color: widget.palette.surface.withValues(alpha: 0.52),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: widget.palette.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF8290)),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                _series.isLocalHistory
                    ? _series.isStale
                          ? tr(
                              '${_series.candles.length} verified samples from ${_series.providerLabel}; actual window ${_formatDuration(_series.observedSpan)}; stale; no interpolation.',
                              '${_series.candles.length} نمونهٔ واقعی از ${_series.providerLabel}؛ بازهٔ واقعی ${_formatDuration(_series.observedSpan)}؛ قدیمی؛ بدون نقطهٔ واسط.',
                              '${_series.providerLabel} の検証済みサンプル ${_series.candles.length} 件。実測期間 ${_formatDuration(_series.observedSpan)}。古いデータ。補間なし。',
                              '${_series.candles.length} проверенных точек ${_series.providerLabel}; фактический период ${_formatDuration(_series.observedSpan)}; устарели; без интерполяции.',
                            )
                          : tr(
                              '${_series.candles.length} verified same-source samples from ${_formatEvidenceTime(_series.candles.first.time)} to ${_formatEvidenceTime(_series.candles.last.time)}; actual window ${_formatDuration(_series.observedSpan)}; no interpolation.',
                              '${_series.candles.length} نمونهٔ واقعی هم‌منبع از ${_formatEvidenceTime(_series.candles.first.time)} تا ${_formatEvidenceTime(_series.candles.last.time)}؛ بازهٔ واقعی ${_formatDuration(_series.observedSpan)}؛ بدون نقطهٔ واسط.',
                              '同一ソースの検証済みサンプル ${_series.candles.length} 件（${_formatEvidenceTime(_series.candles.first.time)}〜${_formatEvidenceTime(_series.candles.last.time)}）。実測期間 ${_formatDuration(_series.observedSpan)}。補間なし。',
                              '${_series.candles.length} проверенных точек из одного источника: ${_formatEvidenceTime(_series.candles.first.time)}–${_formatEvidenceTime(_series.candles.last.time)}; период ${_formatDuration(_series.observedSpan)}; без интерполяции.',
                            )
                    : _series.isStale
                    ? tr(
                        'The latest verified observation from ${_series.providerLabel} is old; no newer value is being implied.',
                        'آخرین مشاهدهٔ تأییدشده از ${_series.providerLabel} قدیمی است؛ مقدار جدیدتری القا نمی‌شود.',
                        '${_series.providerLabel} の最新の検証済み観測値は古いため、新しい値があるようには表示しません。',
                        'Последнее подтверждённое наблюдение ${_series.providerLabel} устарело; более новое значение не подразумевается.',
                      )
                    : _series.isProxy
                    ? tr(
                        'Source: ${_series.providerLabel}. This is a real futures proxy, not a spot quote.',
                        'منبع: ${_series.providerLabel}. این داده واقعی قرارداد آتی است، نه قیمت لحظه‌ای.',
                        '出典: ${_series.providerLabel}。現物価格ではなく実際の先物データです。',
                        'Источник: ${_series.providerLabel}. Это реальные фьючерсы, не спот.',
                      )
                    : tr(
                        'Source: ${_series.providerLabel} · Move the pointer for exact price and time.',
                        'منبع: ${_series.providerLabel} · نشانگر را برای قیمت و زمان دقیق حرکت دهید.',
                        '出典: ${_series.providerLabel} · ポインターで正確な価格と時刻を表示。',
                        'Источник: ${_series.providerLabel} · Наведите для точной цены и времени.',
                      ),
                style: TextStyle(color: widget.palette.mutedText, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatEvidenceTime(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _formatDuration(Duration value) {
    if (value.inDays > 0) {
      final hours = value.inHours.remainder(24);
      return hours == 0 ? '${value.inDays}d' : '${value.inDays}d ${hours}h';
    }
    if (value.inHours > 0) {
      final minutes = value.inMinutes.remainder(60);
      return minutes == 0
          ? '${value.inHours}h'
          : '${value.inHours}h ${minutes}m';
    }
    return '${value.inMinutes}m';
  }
}

class _Asset {
  const _Asset({
    required this.symbol,
    required this.en,
    required this.fa,
    required this.ja,
    required this.ru,
    required this.currency,
    required this.icon,
    required this.accent,
    this.price,
    this.change,
    this.updatedAt,
    this.provider,
    this.upstreamSource,
    this.isStale = false,
    this.isDelayed = false,
  });

  final String symbol;
  final String en;
  final String fa;
  final String ja;
  final String ru;
  final double? price;
  final String currency;
  final double? change;
  final IconData icon;
  final Color accent;
  final DateTime? updatedAt;
  final GlobalPriceProvider? provider;
  final String? upstreamSource;
  final bool isStale;
  final bool isDelayed;

  String get sourceLabel {
    final activeProvider = provider;
    if (activeProvider == null) return '—';
    final providerName = switch (activeProvider) {
      GlobalPriceProvider.navasan => 'Navasan',
      GlobalPriceProvider.zarix => 'ZARIX',
      GlobalPriceProvider.goldApi => 'Gold API',
      GlobalPriceProvider.backend => 'GoldBrain',
    };
    final upstream = upstreamSource?.trim();
    return upstream == null || upstream.isEmpty
        ? providerName
        : '$providerName · $upstream';
  }

  _Asset withQuote(GlobalPriceQuote quote) {
    return _Asset(
      symbol: symbol,
      en: en,
      fa: fa,
      ja: ja,
      ru: ru,
      price: quote.price,
      currency: quote.currency,
      change: quote.changePercent,
      icon: icon,
      accent: accent,
      updatedAt: quote.updatedAt,
      provider: quote.provider,
      upstreamSource: quote.upstreamSource,
      isStale: quote.isStale,
      isDelayed:
          quote.freshnessStatus?.toUpperCase() == 'DELAYED' &&
          quote.dataQualityStatus == 'VALID',
    );
  }
}

String formatAssetPrice(
  double? value,
  String nativeCurrencyCode,
  GoldBrainLanguage language,
  String displayCurrencyCode,
) {
  if (value == null) return '—';
  return CurrencyService.formatPrice(
    value: value,
    sourceCode: nativeCurrencyCode,
    selectedCode: displayCurrencyCode,
    language: language,
  );
}

class _AssetTile extends StatefulWidget {
  const _AssetTile({
    required this.asset,
    required this.name,
    required this.palette,
    required this.language,
    required this.displayCurrencyCode,
    required this.selected,
    required this.refreshFailed,
    required this.delayed,
    required this.conversionUnavailable,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
  });

  final _Asset asset;
  final String name;
  final ThemePalette palette;
  final GoldBrainLanguage language;
  final String displayCurrencyCode;
  final bool selected;
  final bool refreshFailed;
  final bool delayed;
  final bool conversionUnavailable;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  State<_AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<_AssetTile> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: MotionPreferences.duration(220),
          height: 75,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.palette.primary.withValues(alpha: 0.11)
                : Colors.white.withValues(alpha: hovered ? 0.045 : 0.012),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: widget.selected
                  ? widget.palette.primary.withValues(alpha: 0.50)
                  : hovered
                  ? widget.palette.primary.withValues(alpha: 0.19)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              Container(
                width: 41,
                height: 41,
                decoration: BoxDecoration(
                  color: widget.asset.accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  widget.asset.icon,
                  color: widget.asset.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.palette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        Text(
                          formatAssetPrice(
                            widget.asset.price,
                            widget.asset.currency,
                            widget.language,
                            widget.displayCurrencyCode,
                          ),
                          style: TextStyle(
                            color: widget.palette.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.conversionUnavailable &&
                      widget.asset.price != null)
                    const _MarketSourceBadge(
                      text: 'FX N/A',
                      color: Color(0xFFFFC857),
                    )
                  else if (widget.refreshFailed && widget.asset.price != null)
                    _MarketSourceBadge(
                      text: widget.delayed ? 'DELAYED' : 'STALE',
                      color: const Color(0xFFFFC857),
                    )
                  else if (widget.asset.change != null)
                    _ChangeBadge(change: widget.asset.change!)
                  else
                    _MarketSourceBadge(
                      text: widget.asset.price == null
                          ? 'NO DATA'
                          : widget.asset.sourceLabel,
                      color: widget.asset.price == null
                          ? const Color(0xFFFF7182)
                          : const Color(0xFF50E397),
                    ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: widget.onFavorite,
                    child: Icon(
                      widget.favorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: widget.favorite
                          ? widget.asset.accent
                          : widget.palette.mutedText,
                      size: 17,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatefulWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final ThemePalette palette;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<_FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<_FilterButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: MotionPreferences.duration(200),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.palette.primary.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: hovered ? 0.05 : 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected
                  ? widget.palette.primary.withValues(alpha: 0.60)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  color: widget.selected
                      ? widget.palette.secondary
                      : widget.palette.mutedText,
                  size: 13,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.selected
                      ? widget.palette.text
                      : widget.palette.mutedText,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change, this.large = false});

  final double change;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final positive = change >= 0;
    final color = positive ? const Color(0xFF50E397) : const Color(0xFFFF7182);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 11 : 7,
        vertical: large ? 8 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(large ? 12 : 9),
      ),
      child: Text(
        '${positive ? '+' : ''}${change.toStringAsFixed(2)}%',
        textDirection: TextDirection.ltr,
        style: TextStyle(
          color: color,
          fontSize: large ? 12 : 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MarketSourceBadge extends StatelessWidget {
  const _MarketSourceBadge({
    required this.text,
    required this.color,
    this.large = false,
  });

  final String text;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: large ? 190 : 96),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: large ? 11 : 7,
          vertical: large ? 8 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(large ? 12 : 9),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: color,
            fontSize: large ? 10 : 8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({
    required this.palette,
    required this.active,
    required this.onTap,
  });

  final ThemePalette palette;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: MotionPreferences.duration(200),
          width: 41,
          height: 41,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.palette.primary.withValues(
              alpha: widget.active || hovered ? 0.14 : 0.04,
            ),
            border: Border.all(
              color: widget.palette.primary.withValues(
                alpha: widget.active || hovered ? 0.42 : 0.11,
              ),
            ),
          ),
          child: Icon(
            widget.active ? Icons.star_rounded : Icons.star_outline_rounded,
            color: widget.active
                ? widget.palette.secondary
                : widget.palette.mutedText,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _FeedStatusChip extends StatelessWidget {
  const _FeedStatusChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodGauge extends StatelessWidget {
  const _MoodGauge({
    required this.palette,
    required this.progress,
    required this.label,
  });

  final ThemePalette palette;
  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: palette.primary.withValues(alpha: 0.09),
              valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: palette.mutedText,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat {
  const _Stat(this.title, this.value, this.icon);

  final String title;
  final String value;
  final IconData icon;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data, required this.palette});

  final _Stat data;
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.primary.withValues(alpha: 0.09)),
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Icon(data.icon, color: palette.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
