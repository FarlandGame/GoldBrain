import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_translations.dart';
import '../core/notification_service.dart';
import '../core/currency_service.dart';
import '../core/global_price_service.dart';
import '../core/live_market_store.dart';
import '../core/watchlist_store.dart';
import '../core/motion_preferences.dart';

import 'selection_screen.dart';

enum WatchlistCategory { all, metals, currency, crypto }

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({
    super.key,
    required this.palette,
    required this.selectedLanguage,
    required this.currencyCode,
    this.marketStore,
  });

  final ThemePalette palette;
  final GoldBrainLanguage selectedLanguage;
  final String currencyCode;
  final LiveMarketStore? marketStore;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final TextEditingController _searchController = TextEditingController();
  final NotificationService _notificationService = NotificationService.instance;
  final WatchlistStore _watchlistStore = WatchlistStore.instance;
  late final LiveMarketStore _marketStore;

  WatchlistCategory _selectedCategory = WatchlistCategory.all;

  static const List<_WatchlistAsset> _originalAssets = [
    const _WatchlistAsset(
      symbol: 'GOLD18',
      nameEn: '18K Gold',
      nameFa: 'طلای ۱۸ عیار',
      nameJa: '18金',
      nameRu: 'Золото 18К',
      category: WatchlistCategory.metals,
      priceSymbol: 'GOLD18',
      icon: Icons.auto_awesome_rounded,
    ),
    const _WatchlistAsset(
      symbol: 'XAUUSD',
      nameEn: 'Global Gold Ounce',
      nameFa: 'اونس جهانی طلا',
      nameJa: '世界の金価格',
      nameRu: 'Мировое золото',
      category: WatchlistCategory.metals,
      priceSymbol: 'XAU',
      icon: Icons.public_rounded,
    ),
    const _WatchlistAsset(
      symbol: 'USD',
      nameEn: 'US Dollar',
      nameFa: 'دلار آمریکا',
      nameJa: '米ドル',
      nameRu: 'Доллар США',
      category: WatchlistCategory.currency,
      priceSymbol: 'USD',
      icon: Icons.attach_money_rounded,
    ),
    const _WatchlistAsset(
      symbol: 'BTC',
      nameEn: 'Bitcoin',
      nameFa: 'بیت‌کوین',
      nameJa: 'ビットコイン',
      nameRu: 'Биткоин',
      category: WatchlistCategory.crypto,
      priceSymbol: 'BTC',
      icon: Icons.currency_bitcoin_rounded,
    ),
    const _WatchlistAsset(
      symbol: 'USDT',
      nameEn: 'Tether',
      nameFa: 'تتر',
      nameJa: 'テザー',
      nameRu: 'Тетер',
      category: WatchlistCategory.crypto,
      priceSymbol: 'USDT',
      icon: Icons.currency_exchange_rounded,
    ),
    const _WatchlistAsset(
      symbol: 'ETH',
      nameEn: 'Ethereum',
      nameFa: 'اتریوم',
      nameJa: 'イーサリアム',
      nameRu: 'Эфириум',
      category: WatchlistCategory.crypto,
      priceSymbol: 'ETH',
      icon: Icons.token_rounded,
    ),
    const _WatchlistAsset(
      symbol: 'XAGUSD',
      nameEn: 'Global Silver Ounce',
      nameFa: 'اونس جهانی نقره',
      nameJa: '世界の銀価格',
      nameRu: 'Мировое серебро',
      category: WatchlistCategory.metals,
      priceSymbol: 'XAG',
      icon: Icons.brightness_7_rounded,
    ),
  ];
  List<_WatchlistAsset> get _assets {
    final catalog = _marketStore.assets;
    if (catalog.isEmpty) return _originalAssets;
    return [
      for (final market in catalog.where((asset) => asset.liveQuote))
        _assetFromCatalog(market),
    ];
  }

  _WatchlistAsset _assetFromCatalog(MarketAssetMetadata market) {
    for (final original in _originalAssets) {
      if (original.priceSymbol == market.symbol) {
        return original.withQuoteCurrency(market.quoteCurrency);
      }
    }
    final category = switch (market.assetClass.toLowerCase()) {
      'metal' || 'metals' || 'gold' => WatchlistCategory.metals,
      'fiat' || 'currency' || 'forex' || 'fx' => WatchlistCategory.currency,
      _ => WatchlistCategory.crypto,
    };
    return _WatchlistAsset(
      symbol: market.symbol,
      nameEn: market.name,
      nameFa: market.name,
      nameJa: market.name,
      nameRu: market.name,
      category: category,
      priceSymbol: market.symbol,
      quoteCurrency: market.quoteCurrency,
      icon: category == WatchlistCategory.currency
          ? Icons.currency_exchange_rounded
          : category == WatchlistCategory.metals
          ? Icons.auto_awesome_rounded
          : Icons.token_rounded,
    );
  }

  Set<String> get _favoriteSymbols => _watchlistStore.favoriteSymbols;

  ThemePalette get palette => widget.palette;

  bool get isPersian =>
      widget.selectedLanguage == GoldBrainLanguage.persian ||
      widget.selectedLanguage == GoldBrainLanguage.arabic;

  @override
  void initState() {
    super.initState();
    _marketStore = widget.marketStore ?? LiveMarketStore.instance;
    _loadWatchlist();
    _marketStore.addListener(_onMarketChanged);
    _marketStore.load();
  }

  void _onMarketChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadWatchlist() async {
    await _watchlistStore.load();

    if (!mounted) return;

    setState(() {});
  }

  @override
  void dispose() {
    _marketStore.removeListener(_onMarketChanged);
    _searchController.dispose();
    super.dispose();
  }

  String tr({
    required String en,
    required String fa,
    required String ja,
    required String ru,
  }) {
    switch (widget.selectedLanguage) {
      case GoldBrainLanguage.persian:
        return fa;
      case GoldBrainLanguage.japanese:
        return ja;
      case GoldBrainLanguage.russian:
        return ru;
      case GoldBrainLanguage.chinese:
        return AppTranslations.simplifiedChinese(en);
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic(en);
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish(en);
      case GoldBrainLanguage.french:
        return AppTranslations.french(en);
      case GoldBrainLanguage.english:
        return en;
    }
  }

  String assetName(_WatchlistAsset asset) {
    return tr(
      en: asset.nameEn,
      fa: asset.nameFa,
      ja: asset.nameJa,
      ru: asset.nameRu,
    );
  }

  String _formatQuote(GlobalPriceQuote quote) {
    return CurrencyService.formatPrice(
      value: quote.price,
      sourceCode: quote.currency,
      selectedCode: widget.currencyCode,
      language: widget.selectedLanguage,
    );
  }

  String _quoteStatus(String symbol, GlobalPriceQuote? quote) {
    if (quote == null) return 'UNAVAILABLE';
    if (_marketStore.batch?.errors.containsKey(symbol) == true ||
        quote.wasCached) {
      return 'STALE';
    }
    if (quote.freshnessStatus?.toUpperCase() == 'DELAYED' &&
        (quote.dataQualityStatus == null ||
            quote.dataQualityStatus == 'VALID')) {
      return 'DELAYED';
    }
    if (quote.isStale) return 'STALE';
    return switch (quote.freshnessStatus?.toUpperCase()) {
      'LIVE' => 'LIVE',
      'FRESH' => 'FRESH',
      'DELAYED' => 'DELAYED',
      'STALE' || 'UNAVAILABLE' => 'STALE',
      _ => 'SOURCED',
    };
  }

  bool _hasCurrentQuote(String symbol) {
    final state = _quoteStatus(symbol, _marketStore.quoteFor(symbol));
    return state == 'LIVE' || state == 'FRESH';
  }

  String _quoteEvidence(GlobalPriceQuote? quote) {
    if (quote == null) return '';
    final local = (quote.providerTimestamp ?? quote.updatedAt).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${quote.providerLabel} · ${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String categoryLabel(WatchlistCategory category) {
    switch (category) {
      case WatchlistCategory.all:
        return tr(en: 'All', fa: 'همه', ja: 'すべて', ru: 'Все');
      case WatchlistCategory.metals:
        return tr(en: 'Metals', fa: 'فلزات', ja: '金属', ru: 'Металлы');
      case WatchlistCategory.currency:
        return tr(en: 'Currency', fa: 'ارز', ja: '通貨', ru: 'Валюты');
      case WatchlistCategory.crypto:
        return tr(en: 'Crypto', fa: 'رمزارز', ja: '暗号資産', ru: 'Крипто');
    }
  }

  List<_WatchlistAsset> get visibleAssets {
    final query = _searchController.text.trim().toLowerCase();

    return _assets.where((asset) {
      final categoryMatches =
          _selectedCategory == WatchlistCategory.all ||
          asset.category == _selectedCategory;

      final searchMatches =
          query.isEmpty ||
          asset.symbol.toLowerCase().contains(query) ||
          asset.nameEn.toLowerCase().contains(query) ||
          asset.nameFa.contains(query) ||
          asset.nameJa.contains(query) ||
          asset.nameRu.toLowerCase().contains(query);

      return categoryMatches && searchMatches;
    }).toList();
  }

  Future<void> toggleFavorite(_WatchlistAsset asset) async {
    SystemSound.play(SystemSoundType.click);

    final wasFavorite = _watchlistStore.isFavorite(asset.symbol);

    await _watchlistStore.toggleFavorite(asset.symbol);

    if (!mounted) return;

    setState(() {});

    _notificationService.addNotification(
      title: wasFavorite
          ? tr(
              en: 'Removed from Watchlist',
              fa: 'حذف از دیده‌بان',
              ja: 'ウォッチリストから削除しました',
              ru: 'Удалено из списка наблюдения',
            )
          : tr(
              en: 'Added to Watchlist',
              fa: 'اضافه‌شدن به دیده‌بان',
              ja: 'ウォッチリストに追加しました',
              ru: 'Добавлено в список наблюдения',
            ),
      message: wasFavorite
          ? tr(
              en: '${assetName(asset)} was removed from your watchlist.',
              fa: '${assetName(asset)} از دیده‌بان شما حذف شد.',
              ja: '${assetName(asset)}をウォッチリストから削除しました。',
              ru: '${assetName(asset)} удалён из списка наблюдения.',
            )
          : tr(
              en: '${assetName(asset)} was added to your watchlist.',
              fa: '${assetName(asset)} به دیده‌بان شما اضافه شد.',
              ja: '${assetName(asset)}をウォッチリストに追加しました。',
              ru: '${assetName(asset)} добавлен в список наблюдения.',
            ),
      type: AppNotificationType.system,
    );
  }

  void showAiAnalysis(_WatchlistAsset asset) {
    SystemSound.play(SystemSoundType.click);

    showDialog<void>(
      context: context,
      builder: (context) {
        final quote = _marketStore.quoteFor(asset.priceSymbol);
        final quoteStatus = _quoteStatus(asset.priceSymbol, quote);
        final signalColor = switch (quoteStatus) {
          'LIVE' || 'FRESH' => const Color(0xFF50E397),
          'DELAYED' || 'STALE' => const Color(0xFFFFC857),
          'UNAVAILABLE' => const Color(0xFFFF7182),
          _ => palette.primary,
        };

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.30),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 30,
                  offset: Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: palette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(asset.icon, color: palette.primary),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assetName(asset),
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            asset.symbol,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              color: palette.mutedText,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: signalColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        quoteStatus,
                        style: TextStyle(
                          color: signalColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: palette.background.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    quote == null
                        ? tr(
                            en: 'No sourced quote is currently available. GoldBrain will not manufacture an AI score or price.',
                            fa: 'اکنون قیمت منبع‌داری در دسترس نیست؛ GoldBrain امتیاز AI یا قیمت ساختگی تولید نمی‌کند.',
                            ja: '現在、出典付き価格はありません。AIスコアや価格を捏造しません。',
                            ru: 'Сейчас нет цены с источником. GoldBrain не выдумывает цену или балл ИИ.',
                          )
                        : tr(
                            en: '${_formatQuote(quote)}\nSource: ${quote.providerLabel}${quote.fallbackFrom == null ? '' : ' (fallback from ${quote.fallbackFrom})'}\nProvider time: ${quote.providerTimestamp?.toLocal() ?? 'not supplied'}\nBackend received: ${quote.receivedAt?.toLocal() ?? 'not supplied'}\nStatus: $quoteStatus\n\nThis is a sourced reference quote, not an AI prediction or investment signal.',
                            fa: '${_formatQuote(quote)}\nمنبع: ${quote.providerLabel}${quote.fallbackFrom == null ? '' : ' (جایگزین ${quote.fallbackFrom})'}\nزمان منبع: ${quote.providerTimestamp?.toLocal() ?? 'ارائه نشده'}\nدریافت سرور: ${quote.receivedAt?.toLocal() ?? 'ارائه نشده'}\nوضعیت: $quoteStatus\n\nاین فقط قیمت مرجع منبع‌دار است و پیش‌بینی AI یا سیگنال سرمایه‌گذاری نیست.',
                            ja: '${_formatQuote(quote)}\n出典: ${quote.providerLabel}\n提供元の時刻: ${quote.providerTimestamp?.toLocal() ?? '提供なし'}\nサーバー受信: ${quote.receivedAt?.toLocal() ?? '提供なし'}\n状態: $quoteStatus\n\n出典付き参考価格であり、AI予測や投資シグナルではありません。',
                            ru: '${_formatQuote(quote)}\nИсточник: ${quote.providerLabel}\nВремя источника: ${quote.providerTimestamp?.toLocal() ?? 'не указано'}\nПолучено сервером: ${quote.receivedAt?.toLocal() ?? 'не указано'}\nСтатус: $quoteStatus\n\nЭто справочная цена, не прогноз ИИ и не инвестиционный сигнал.',
                          ),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 13,
                      height: 1.7,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      tr(en: 'Close', fa: 'بستن', ja: '閉じる', ru: 'Закрыть'),
                      style: TextStyle(
                        color: palette.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: SizedBox(
        height: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                textDirection: TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildAssetList()),
                  const SizedBox(width: 16),
                  SizedBox(width: 290, child: _buildOverviewPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(21),
      decoration: _panelDecoration(),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.30),
              ),
            ),
            child: Icon(Icons.star_rounded, color: palette.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    en: 'Smart Watchlist',
                    fa: 'دیده‌بان هوشمند',
                    ja: 'スマートウォッチリスト',
                    ru: 'Умный список наблюдения',
                  ),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _marketStore.catalogIsFallback
                      ? tr(
                          en: 'Saved asset list · availability and ranking are not live.',
                          fa: 'فهرست ذخیره‌شدهٔ دارایی‌ها · دسترسی و رتبه‌بندی آن لحظه‌ای نیست.',
                          ja: '保存済み資産リスト・利用可否と順位はライブではありません。',
                          ru: 'Сохранённый список активов · доступность и рейтинг не в реальном времени.',
                        )
                      : tr(
                          en: 'Track selected assets and prepare them for GoldBrain AI analysis.',
                          fa: 'دارایی‌های مهم را دنبال کنید و برای تحلیل هوش مصنوعی GoldBrain آماده سازید.',
                          ja: '重要な資産を追跡し、GoldBrain AI分析に備えます。',
                          ru: 'Отслеживайте активы и готовьте их для анализа GoldBrain AI.',
                        ),
                  style: TextStyle(color: palette.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          _HeaderMetric(
            palette: palette,
            label: tr(
              en: 'FAVORITES',
              fa: 'علاقه‌مندی‌ها',
              ja: 'お気に入り',
              ru: 'ИЗБРАННОЕ',
            ),
            value: '${_favoriteSymbols.length}',
            icon: Icons.star_rounded,
          ),
          const SizedBox(width: 10),
          _HeaderMetric(
            palette: palette,
            label: tr(
              en: 'CURRENT QUOTES',
              fa: 'قیمت‌های به‌روز',
              ja: '新しい価格',
              ru: 'АКТУАЛЬНЫЕ ЦЕНЫ',
            ),
            value:
                '${_assets.where((asset) => _hasCurrentQuote(asset.priceSymbol)).length}',
            icon: Icons.cloud_done_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildAssetList() {
    final assets = visibleAssets;

    return Container(
      decoration: _panelDecoration(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: palette.text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: tr(
                      en: 'Search an asset...',
                      fa: 'جست‌وجوی دارایی...',
                      ja: '資産を検索...',
                      ru: 'Поиск актива...',
                    ),
                    hintStyle: TextStyle(color: palette.mutedText),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: palette.primary,
                    ),
                    filled: true,
                    fillColor: palette.background.withValues(alpha: 0.42),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                        color: palette.primary.withValues(alpha: 0.13),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: palette.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: WatchlistCategory.values.map((category) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: _CategoryButton(
                          label: categoryLabel(category),
                          selected: category == _selectedCategory,
                          palette: palette,
                          onTap: () {
                            SystemSound.play(SystemSoundType.click);

                            setState(() {
                              _selectedCategory = category;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.primary.withValues(alpha: 0.11)),
          Expanded(
            child: assets.isEmpty
                ? Center(
                    child: Text(
                      tr(
                        en: 'No asset found',
                        fa: 'دارایی‌ای پیدا نشد',
                        ja: '資産が見つかりません',
                        ru: 'Актив не найден',
                      ),
                      style: TextStyle(color: palette.mutedText),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: assets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final asset = assets[index];

                      return _AssetTile(
                        asset: asset,
                        quote: _marketStore.quoteFor(asset.priceSymbol),
                        status: _quoteStatus(
                          asset.priceSymbol,
                          _marketStore.quoteFor(asset.priceSymbol),
                        ),
                        evidence: _quoteEvidence(
                          _marketStore.quoteFor(asset.priceSymbol),
                        ),
                        name: assetName(asset),
                        palette: palette,
                        language: widget.selectedLanguage,
                        displayCurrencyCode: widget.currencyCode,
                        favorite: _favoriteSymbols.contains(asset.symbol),
                        onFavorite: () => toggleFavorite(asset),
                        onAnalyze: () => showAiAnalysis(asset),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewPanel() {
    final availableQuotes = _assets
        .map((asset) => _marketStore.quoteFor(asset.priceSymbol))
        .whereType<GlobalPriceQuote>()
        .toList();
    final positiveAssets = availableQuotes
        .where((quote) => _hasCurrentQuote(quote.symbol))
        .where(
          (quote) => quote.changePercent != null && quote.changePercent! >= 0,
        )
        .length;
    final currentQuoteCount = _assets
        .where((asset) => _hasCurrentQuote(asset.priceSymbol))
        .length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              en: 'WATCHLIST OVERVIEW',
              fa: 'نمای کلی دیده‌بان',
              ja: 'ウォッチリスト概要',
              ru: 'ОБЗОР СПИСКА',
            ),
            style: TextStyle(
              color: palette.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 18),
          _OverviewCard(
            palette: palette,
            icon: Icons.show_chart_rounded,
            title: tr(
              en: 'Positive movement',
              fa: 'حرکت مثبت',
              ja: '上昇',
              ru: 'Рост',
            ),
            value:
                '$positiveAssets / ${_assets.where((asset) => _hasCurrentQuote(asset.priceSymbol)).length}',
          ),
          const SizedBox(height: 10),
          _OverviewCard(
            palette: palette,
            icon: Icons.cloud_done_outlined,
            title: tr(
              en: 'Current sourced quotes',
              fa: 'قیمت‌های به‌روز و منبع‌دار',
              ja: '出典付きの新しい価格',
              ru: 'Актуальные цены с источником',
            ),
            value: '$currentQuoteCount / ${_assets.length}',
          ),
          const SizedBox(height: 10),
          _OverviewCard(
            palette: palette,
            icon: Icons.notifications_off_outlined,
            title: tr(
              en: 'Price alerts',
              fa: 'هشدارهای قیمت',
              ja: '価格アラート',
              ru: 'Ценовые уведомления',
            ),
            value: tr(
              en: 'Planned with portfolio · Off',
              fa: 'همراه سبد دارایی · غیرفعال',
              ja: 'ポートフォリオと追加予定・オフ',
              ru: 'Вместе с портфелем · Выключено',
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.primary.withValues(alpha: 0.12),
                  palette.secondary.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.20),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: palette.primary,
                  size: 28,
                ),
                const SizedBox(height: 10),
                Text(
                  tr(
                    en: 'GoldBrain Analysis Pipeline',
                    fa: 'مسیر تحلیل GoldBrain',
                    ja: 'GoldBrain分析パイプライン',
                    ru: 'Система анализа GoldBrain',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    en: 'Live prices, charts, news and prediction models will later analyze every favorite asset here.',
                    fa: 'بعداً قیمت زنده، نمودار، اخبار و مدل‌های پیش‌بینی تمام دارایی‌های منتخب را در این بخش تحلیل می‌کنند.',
                    ja: '将来、価格、チャート、ニュース、予測モデルが資産を分析します。',
                    ru: 'Позже цены, графики, новости и модели прогнозирования будут анализировать активы.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: palette.surface.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(27),
      border: Border.all(color: palette.primary.withValues(alpha: 0.18)),
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 25, offset: Offset(0, 12)),
      ],
    );
  }
}

class _WatchlistAsset {
  const _WatchlistAsset({
    required this.symbol,
    required this.nameEn,
    required this.nameFa,
    required this.nameJa,
    required this.nameRu,
    required this.category,
    required this.priceSymbol,
    required this.icon,
    this.quoteCurrency,
  });

  final String symbol;
  final String nameEn;
  final String nameFa;
  final String nameJa;
  final String nameRu;
  final WatchlistCategory category;
  final String priceSymbol;
  final IconData icon;
  final String? quoteCurrency;

  _WatchlistAsset withQuoteCurrency(String value) => _WatchlistAsset(
    symbol: symbol,
    nameEn: nameEn,
    nameFa: nameFa,
    nameJa: nameJa,
    nameRu: nameRu,
    category: category,
    priceSymbol: priceSymbol,
    icon: icon,
    quoteCurrency: value,
  );
}

class _AssetTile extends StatefulWidget {
  const _AssetTile({
    required this.asset,
    required this.quote,
    required this.status,
    required this.evidence,
    required this.name,
    required this.palette,
    required this.language,
    required this.displayCurrencyCode,
    required this.favorite,
    required this.onFavorite,
    required this.onAnalyze,
  });

  final _WatchlistAsset asset;
  final GlobalPriceQuote? quote;
  final String status;
  final String evidence;
  final String name;
  final ThemePalette palette;
  final GoldBrainLanguage language;
  final String displayCurrencyCode;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onAnalyze;

  @override
  State<_AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<_AssetTile> {
  bool hovered = false;

  String _formatTileQuote(GlobalPriceQuote? quote) {
    if (quote == null) {
      final expectedCurrency = widget.asset.quoteCurrency;
      return expectedCurrency == null ? '—' : '— $expectedCurrency';
    }
    return CurrencyService.formatPrice(
      value: quote.price,
      sourceCode: quote.currency,
      selectedCode: widget.displayCurrencyCode,
      language: widget.language,
    );
  }

  @override
  Widget build(BuildContext context) {
    final change = widget.quote?.changePercent;
    final positive = change != null && change >= 0;
    final color = change == null
        ? widget.palette.mutedText
        : positive
        ? const Color(0xFF50E397)
        : const Color(0xFFFF7182);

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: MotionPreferences.duration(220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.palette.text.withValues(alpha: hovered ? 0.050 : 0.018),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hovered
                ? widget.palette.primary.withValues(alpha: 0.35)
                : widget.palette.primary.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: widget.palette.primary.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(widget.asset.icon, color: widget.palette.primary),
            ),
            const SizedBox(width: 13),
            SizedBox(
              width: 145,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.palette.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.asset.symbol,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: widget.palette.mutedText,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatTileQuote(widget.quote),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: widget.palette.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (widget.evidence.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.evidence,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: widget.palette.mutedText,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 72,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                change == null
                    ? '—'
                    : '${positive ? '+' : ''}${change.toStringAsFixed(2)}%',
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: widget.onAnalyze,
              icon: Icon(
                Icons.info_outline_rounded,
                size: 17,
                color: widget.palette.primary,
              ),
              label: Text(
                widget.status,
                style: TextStyle(
                  color: widget.status == 'STALE' || widget.status == 'DELAYED'
                      ? const Color(0xFFFFC857)
                      : widget.status == 'UNAVAILABLE'
                      ? const Color(0xFFFF7182)
                      : widget.palette.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: widget.palette.primary.withValues(alpha: 0.30),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: widget.onFavorite,
              icon: Icon(
                widget.favorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: widget.favorite
                    ? widget.palette.primary
                    : widget.palette.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
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
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? palette.primary.withValues(alpha: 0.15)
              : palette.text.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? palette.primary
                : palette.text.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.text : palette.mutedText,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.palette,
    required this.label,
    required this.value,
    required this.icon,
  });

  final ThemePalette palette;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.primary, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: palette.mutedText, fontSize: 8),
              ),
              Text(
                value,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 12,
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

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.palette,
    required this.icon,
    required this.title,
    required this.value,
  });

  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.primary.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: palette.mutedText, fontSize: 9),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
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
