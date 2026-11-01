import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/currency_service.dart';
import '../core/market_forecast.dart';
import '../core/market_intelligence_service.dart';
import '../core/market_intelligence_store.dart';
import '../core/settings_store.dart';
import '../screens/selection_screen.dart';

class DeepMarketAnalysisCard extends StatefulWidget {
  const DeepMarketAnalysisCard({
    super.key,
    required this.palette,
    required this.language,
    this.store,
    this.densityScale = 1,
  });

  final ThemePalette palette;
  final GoldBrainLanguage language;
  final MarketIntelligenceStore? store;
  final double densityScale;

  @override
  State<DeepMarketAnalysisCard> createState() => _DeepMarketAnalysisCardState();
}

class _DeepMarketAnalysisCardState extends State<DeepMarketAnalysisCard> {
  late MarketIntelligenceStore _store;
  MarketForecastHorizon _selectedForecastHorizon =
      MarketForecastHorizon.twelveHours;

  ThemePalette get palette => widget.palette;

  @override
  void initState() {
    super.initState();
    _attach(widget.store ?? MarketIntelligenceStore.instance);
  }

  @override
  void didUpdateWidget(covariant DeepMarketAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.store ?? MarketIntelligenceStore.instance;
    if (!identical(next, _store)) {
      _store.removeListener(_onChanged);
      _attach(next);
    } else if (oldWidget.language != widget.language) {
      _store.updateLanguage(widget.language.name, refresh: true);
    }
  }

  void _attach(MarketIntelligenceStore store) {
    _store = store..addListener(_onChanged);
    unawaited(
      _store.start(
        languageCode: widget.language.name,
        refreshImmediately: false,
      ),
    );
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  String _t({
    required String en,
    required String fa,
    required String ja,
    required String ru,
    required String zh,
    required String ar,
    required String tr,
    required String fr,
  }) {
    return switch (widget.language) {
      GoldBrainLanguage.english => en,
      GoldBrainLanguage.persian => fa,
      GoldBrainLanguage.japanese => ja,
      GoldBrainLanguage.russian => ru,
      GoldBrainLanguage.chinese => zh,
      GoldBrainLanguage.arabic => ar,
      GoldBrainLanguage.turkish => tr,
      GoldBrainLanguage.french => fr,
    };
  }

  String _assetName(String symbol) => switch (symbol) {
    'GOLD18' => _t(
      en: '18K Gold',
      fa: 'طلای ۱۸ عیار',
      ja: '18金',
      ru: 'Золото 18К',
      zh: '18K 金',
      ar: 'ذهب عيار 18',
      tr: '18 Ayar Altın',
      fr: 'Or 18 carats',
    ),
    'XAU' => _t(
      en: 'Global Gold',
      fa: 'اونس جهانی طلا',
      ja: '金現物',
      ru: 'Мировое золото',
      zh: '国际黄金',
      ar: 'الذهب العالمي',
      tr: 'Küresel Altın',
      fr: 'Or mondial',
    ),
    'XAG' => _t(
      en: 'Silver',
      fa: 'نقره',
      ja: '銀',
      ru: 'Серебро',
      zh: '白银',
      ar: 'الفضة',
      tr: 'Gümüş',
      fr: 'Argent',
    ),
    'USD' => _t(
      en: 'US Dollar',
      fa: 'دلار آمریکا',
      ja: '米ドル',
      ru: 'Доллар США',
      zh: '美元',
      ar: 'الدولار الأمريكي',
      tr: 'ABD Doları',
      fr: 'Dollar américain',
    ),
    'BTC' => _t(
      en: 'Bitcoin',
      fa: 'بیت‌کوین',
      ja: 'ビットコイン',
      ru: 'Биткоин',
      zh: '比特币',
      ar: 'بيتكوين',
      tr: 'Bitcoin',
      fr: 'Bitcoin',
    ),
    'USDT' => _t(
      en: 'Tether',
      fa: 'تتر',
      ja: 'テザー',
      ru: 'Тетер',
      zh: '泰达币',
      ar: 'تيثر',
      tr: 'Tether',
      fr: 'Tether',
    ),
    'ETH' => _t(
      en: 'Ethereum',
      fa: 'اتریوم',
      ja: 'イーサリアム',
      ru: 'Эфириум',
      zh: '以太坊',
      ar: 'إيثريوم',
      tr: 'Ethereum',
      fr: 'Ethereum',
    ),
    _ => symbol,
  };

  IconData _assetIcon(String symbol) => switch (symbol) {
    'GOLD18' => Icons.auto_awesome_rounded,
    'XAU' => Icons.circle_outlined,
    'XAG' => Icons.brightness_1_outlined,
    'USD' => Icons.attach_money_rounded,
    'BTC' => Icons.currency_bitcoin_rounded,
    'USDT' => Icons.currency_exchange_rounded,
    'ETH' => Icons.diamond_outlined,
    _ => Icons.query_stats_rounded,
  };

  Color _directionColor(MarketIntelligenceReport? report) =>
      switch (report?.direction) {
        MarketScenarioDirection.upward => const Color(0xFF38D98B),
        MarketScenarioDirection.downward => const Color(0xFFFF6678),
        MarketScenarioDirection.neutral => const Color(0xFFF5C84C),
        MarketScenarioDirection.insufficientData || null => palette.mutedText,
      };

  IconData _directionIcon(MarketIntelligenceReport? report) =>
      switch (report?.direction) {
        MarketScenarioDirection.upward => Icons.trending_up_rounded,
        MarketScenarioDirection.downward => Icons.trending_down_rounded,
        MarketScenarioDirection.neutral => Icons.horizontal_rule_rounded,
        MarketScenarioDirection.insufficientData || null => Icons.query_stats,
      };

  String _directionLabel(MarketIntelligenceReport? report) =>
      switch (report?.direction) {
        MarketScenarioDirection.upward => _t(
          en: 'UPWARD SCENARIO',
          fa: 'سناریوی صعودی',
          ja: '上昇シナリオ',
          ru: 'СЦЕНАРИЙ РОСТА',
          zh: '上行情景',
          ar: 'سيناريو صاعد',
          tr: 'YÜKSELİŞ SENARYOSU',
          fr: 'SCÉNARIO HAUSSIER',
        ),
        MarketScenarioDirection.downward => _t(
          en: 'DOWNWARD SCENARIO',
          fa: 'سناریوی نزولی',
          ja: '下降シナリオ',
          ru: 'СЦЕНАРИЙ СНИЖЕНИЯ',
          zh: '下行情景',
          ar: 'سيناريو هابط',
          tr: 'DÜŞÜŞ SENARYOSU',
          fr: 'SCÉNARIO BAISSIER',
        ),
        MarketScenarioDirection.neutral => _t(
          en: 'MIXED SCENARIO',
          fa: 'سناریوی خنثی',
          ja: '中立シナリオ',
          ru: 'НЕЙТРАЛЬНЫЙ СЦЕНАРИЙ',
          zh: '中性情景',
          ar: 'سيناريو محايد',
          tr: 'NÖTR SENARYO',
          fr: 'SCÉNARIO NEUTRE',
        ),
        MarketScenarioDirection.insufficientData || null => _t(
          en: 'NO VERIFIED SCENARIO',
          fa: 'سناریوی تأییدشده‌ای موجود نیست',
          ja: '検証済みシナリオなし',
          ru: 'НЕТ ПРОВЕРЕННОГО СЦЕНАРИЯ',
          zh: '暂无已验证情景',
          ar: 'لا يوجد سيناريو موثّق',
          tr: 'DOĞRULANMIŞ SENARYO YOK',
          fr: 'AUCUN SCÉNARIO VÉRIFIÉ',
        ),
      };

  String _emptyOrErrorMessage(String symbol) {
    return switch (_store.errorCode) {
      'missing_api_key' => _t(
        en: 'Configure the AI API key for the news narrative. The local numerical model remains separate.',
        fa: 'برای روایت خبری، کلید API هوش مصنوعی را تنظیم کنید؛ مدل عددی محلی جداگانه کار می‌کند.',
        ja: 'ニュース解説用のAI APIキーを設定してください。ローカル数値モデルは別に動作します。',
        ru: 'Настройте API-ключ ИИ для новостного обзора. Локальная числовая модель работает отдельно.',
        zh: '请为新闻解读配置 AI API 密钥；本地数值模型独立运行。',
        ar: 'اضبط مفتاح API لسرد الأخبار؛ يعمل النموذج الرقمي المحلي بشكل منفصل.',
        tr: 'Haber anlatımı için AI API anahtarını ayarlayın; yerel sayısal model ayrıdır.',
        fr: 'Configurez la clé API pour le récit d’actualité ; le modèle numérique local est distinct.',
      ),
      'disabled' => _t(
        en: 'AI market analysis is disabled in Settings.',
        fa: 'تحلیل هوشمند بازار در تنظیمات غیرفعال است.',
        ja: '設定でAI市場分析が無効です。',
        ru: 'Анализ рынка ИИ отключён в настройках.',
        zh: '设置中已关闭 AI 市场分析。',
        ar: 'تحليل السوق بالذكاء الاصطناعي معطّل في الإعدادات.',
        tr: 'AI piyasa analizi Ayarlar’da devre dışı.',
        fr: 'L’analyse IA du marché est désactivée.',
      ),
      'ai_unavailable' => _t(
        en: 'The AI news narrative did not refresh. Any local numerical scenario below is separate and appears only when exact history passes its data gates.',
        fa: 'روایت خبری هوش مصنوعی به‌روز نشد. سناریوی عددی محلیِ پایین مستقل است و فقط با عبور تاریخچهٔ دقیق از معیارهای داده نمایش داده می‌شود.',
        ja: 'AIニュース解説は更新されませんでした。下のローカル数値シナリオは独立しており、実履歴が基準を満たす場合のみ表示されます。',
        ru: 'Новостной обзор ИИ не обновился. Локальный числовой сценарий ниже независим и виден только при прохождении проверок точной истории.',
        zh: 'AI 新闻解读未更新。下方本地数值情景独立运行，只有精确历史通过数据门槛时才显示。',
        ar: 'لم يتحدث سرد الأخبار بالذكاء الاصطناعي. السيناريو الرقمي المحلي أدناه مستقل ولا يظهر إلا بعد اجتياز السجل الدقيق لمعايير البيانات.',
        tr: 'AI haber anlatımı yenilenmedi. Aşağıdaki yerel sayısal senaryo ayrıdır ve yalnızca kesin geçmiş veri eşiklerini geçerse görünür.',
        fr: 'Le récit IA n’a pas été actualisé. Le scénario numérique local ci-dessous est distinct et n’apparaît qu’après validation de l’historique exact.',
      ),
      'incomplete_history' => _t(
        en: 'Deep analysis needs enough recent, verified history or directly relevant news. The available evidence is still incomplete.',
        fa: 'تحلیل عمیق به تاریخچهٔ معتبر و تازه یا خبر مستقیمِ مرتبط نیاز دارد؛ شواهد موجود هنوز کافی نیست.',
        ja: '詳細分析には、十分な最新の検証済み履歴または直接関連するニュースが必要です。利用可能な根拠はまだ不十分です。',
        ru: 'Для глубокого анализа нужна достаточная свежая подтверждённая история или непосредственно связанная новость. Доступных данных пока недостаточно.',
        zh: '深度分析需要足够且最新的可靠历史，或直接相关的新闻；当前证据仍不完整。',
        ar: 'يتطلب التحليل العميق سجلاً حديثاً وموثوقاً كافياً أو أخباراً مرتبطة مباشرة؛ الأدلة المتاحة ما زالت غير كافية.',
        tr: 'Derin analiz için yeterli ve güncel doğrulanmış geçmiş ya da doğrudan ilgili haber gerekir; mevcut kanıt hâlâ yetersiz.',
        fr: 'L’analyse approfondie nécessite un historique récent et vérifié suffisant, ou une actualité directement liée. Les éléments disponibles restent incomplets.',
      ),
      'insufficient_evidence' => _t(
        en: 'There is not enough verified price, history and news data yet.',
        fa: 'هنوز قیمت، تاریخچه و خبر معتبر کافی برای تحلیل وجود ندارد.',
        ja: '検証済みの価格・履歴・ニュースがまだ不足しています。',
        ru: 'Пока недостаточно проверенных цен, истории и новостей.',
        zh: '目前没有足够的可靠价格、历史和新闻数据。',
        ar: 'لا تتوفر بعد بيانات موثّقة كافية من الأسعار والتاريخ والأخبار.',
        tr: 'Henüz yeterli doğrulanmış fiyat, geçmiş ve haber verisi yok.',
        fr: 'Les prix, historiques et actualités vérifiés sont insuffisants.',
      ),
      null => _t(
        en: 'No analysis for $symbol yet. Run it now or wait for auto refresh.',
        fa: 'هنوز تحلیلی برای $symbol نیست؛ اکنون اجرا کنید یا منتظر به‌روزرسانی خودکار بمانید.',
        ja: '$symbol の分析はまだありません。今すぐ実行するか自動更新をお待ちください。',
        ru: 'Для $symbol анализа пока нет. Запустите его или дождитесь автообновления.',
        zh: '$symbol 暂无分析。请立即运行或等待自动更新。',
        ar: 'لا يوجد تحليل لـ $symbol بعد؛ شغّله الآن أو انتظر التحديث التلقائي.',
        tr: '$symbol için henüz analiz yok. Şimdi çalıştırın veya otomatik yenilemeyi bekleyin.',
        fr: 'Aucune analyse pour $symbol. Lancez-la ou attendez l’actualisation.',
      ),
      _ => _t(
        en: 'The latest update failed. Check the network and retry.',
        fa: 'آخرین به‌روزرسانی ناموفق بود؛ اینترنت را بررسی و دوباره تلاش کنید.',
        ja: '最新の更新に失敗しました。接続を確認して再試行してください。',
        ru: 'Последнее обновление не удалось. Проверьте сеть и повторите.',
        zh: '最新更新失败，请检查网络后重试。',
        ar: 'فشل آخر تحديث؛ تحقق من الشبكة وأعد المحاولة.',
        tr: 'Son güncelleme başarısız. Ağı kontrol edip yeniden deneyin.',
        fr: 'La dernière actualisation a échoué. Vérifiez le réseau.',
      ),
    };
  }

  String _staleErrorLabel() => _t(
    en: 'Latest refresh failed; showing the previous report.',
    fa: 'به‌روزرسانی آخر ناموفق بود؛ گزارش قبلی نمایش داده می‌شود.',
    ja: '最新の更新に失敗したため、前回のレポートを表示しています。',
    ru: 'Обновление не удалось; показан предыдущий отчёт.',
    zh: '最新更新失败，正在显示上一份报告。',
    ar: 'فشل آخر تحديث؛ يتم عرض التقرير السابق.',
    tr: 'Son yenileme başarısız; önceki rapor gösteriliyor.',
    fr: 'Échec de l’actualisation ; le rapport précédent est affiché.',
  );

  Future<void> _runAnalysis() async {
    await _store.start(
      languageCode: widget.language.name,
      refreshImmediately: false,
    );
    await _store.refresh(force: true, symbols: <String>{_store.selectedSymbol});
  }

  String _formatForecastPrice(MarketForecast forecast, double value) {
    return CurrencyService.formatPrice(
      value: value,
      sourceCode: forecast.unit,
      selectedCode: SettingsStore.instance.currencyCode,
      language: widget.language,
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _horizonLabel(MarketForecastHorizon horizon) => switch (horizon) {
    MarketForecastHorizon.oneHour => '1H',
    MarketForecastHorizon.twelveHours => '12H',
    MarketForecastHorizon.twentyFourHours => '24H',
  };

  String _forecastTitle(MarketForecast? forecast) {
    final targetAt = forecast == null
        ? null
        : _formatDateTime(forecast.targetFor);
    return switch (_selectedForecastHorizon) {
      MarketForecastHorizon.oneHour => _t(
        en: targetAt == null
            ? '1-hour model scenario'
            : '1-hour scenario at $targetAt',
        fa: targetAt == null
            ? 'سناریوی مدل برای ۱ ساعت'
            : 'سناریوی ۱ ساعته در $targetAt',
        ja: targetAt == null ? '1時間モデルシナリオ' : '$targetAt の1時間シナリオ',
        ru: targetAt == null
            ? 'Сценарий модели на 1 час'
            : 'Сценарий на 1 час к $targetAt',
        zh: targetAt == null ? '1 小时模型情景' : '$targetAt 的 1 小时情景',
        ar: targetAt == null
            ? 'سيناريو النموذج لساعة'
            : 'سيناريو ساعة واحدة عند $targetAt',
        tr: targetAt == null
            ? '1 saatlik model senaryosu'
            : '$targetAt için 1 saatlik senaryo',
        fr: targetAt == null
            ? 'Scénario modèle à 1 h'
            : 'Scénario à 1 h vers $targetAt',
      ),
      MarketForecastHorizon.twelveHours => _t(
        en: targetAt == null
            ? '12-hour model scenario'
            : '12-hour scenario at $targetAt',
        fa: targetAt == null
            ? 'سناریوی مدل برای ۱۲ ساعت'
            : 'سناریوی ۱۲ ساعته در $targetAt',
        ja: targetAt == null ? '12時間モデルシナリオ' : '$targetAt の12時間シナリオ',
        ru: targetAt == null
            ? 'Сценарий модели на 12 часов'
            : 'Сценарий на 12 часов к $targetAt',
        zh: targetAt == null ? '12 小时模型情景' : '$targetAt 的 12 小时情景',
        ar: targetAt == null
            ? 'سيناريو النموذج لـ12 ساعة'
            : 'سيناريو 12 ساعة عند $targetAt',
        tr: targetAt == null
            ? '12 saatlik model senaryosu'
            : '$targetAt için 12 saatlik senaryo',
        fr: targetAt == null
            ? 'Scénario modèle à 12 h'
            : 'Scénario à 12 h vers $targetAt',
      ),
      MarketForecastHorizon.twentyFourHours => _t(
        en: targetAt == null
            ? '24-hour observed-price scenario'
            : '24-hour scenario near the observation at $targetAt',
        fa: targetAt == null
            ? 'سناریوی قیمت مشاهده‌شده در ۲۴ ساعت'
            : 'سناریوی ۲۴ ساعته نزدیک مشاهدهٔ $targetAt',
        ja: targetAt == null ? '24時間の観測価格シナリオ' : '$targetAt 付近の24時間観測シナリオ',
        ru: targetAt == null
            ? 'Сценарий наблюдаемой цены на 24 часа'
            : '24-часовой сценарий около наблюдения $targetAt',
        zh: targetAt == null ? '24 小时观测价格情景' : '$targetAt 附近的 24 小时观测情景',
        ar: targetAt == null
            ? 'سيناريو السعر المرصود خلال 24 ساعة'
            : 'سيناريو 24 ساعة قرب رصد $targetAt',
        tr: targetAt == null
            ? '24 saatlik gözlenen fiyat senaryosu'
            : '$targetAt gözlemine yakın 24 saatlik senaryo',
        fr: targetAt == null
            ? 'Scénario du prix observé à 24 h'
            : 'Scénario à 24 h près de l’observation $targetAt',
      ),
    };
  }

  String _forecastUnavailableLabel() => _t(
    en: 'Unavailable: this horizon does not have enough fresh, exact history.',
    fa: 'در دسترس نیست: برای این افق، تاریخچهٔ دقیق و تازه کافی نیست.',
    ja: '利用不可：この期間には十分な最新の実履歴がありません。',
    ru: 'Недоступно: для этого горизонта недостаточно свежей точной истории.',
    zh: '不可用：此周期没有足够的新鲜、精确历史数据。',
    ar: 'غير متاح: لا يوجد سجل حديث ودقيق كافٍ لهذا الأفق.',
    tr: 'Kullanılamıyor: bu ufuk için yeterli güncel ve kesin geçmiş yok.',
    fr: 'Indisponible : historique exact et récent insuffisant pour cet horizon.',
  );

  String _forecastIntervalLabel(MarketForecast forecast) {
    final lower = _formatForecastPrice(forecast, forecast.lowerBound);
    final upper = _formatForecastPrice(forecast, forecast.upperBound);
    return _t(
      en: 'Uncalibrated 80% model range: $lower – $upper',
      fa: 'بازهٔ ۸۰٪ کالیبره‌نشدهٔ مدل: $lower تا $upper',
      ja: '未校正のモデル80%範囲：$lower～$upper',
      ru: 'Некалиброванный 80% диапазон модели: $lower — $upper',
      zh: '未校准的模型 80% 区间：$lower – $upper',
      ar: 'نطاق النموذج غير المعاير 80٪: $lower – $upper',
      tr: 'Kalibre edilmemiş model %80 aralığı: $lower – $upper',
      fr: 'Plage modèle 80 % non calibrée : $lower – $upper',
    );
  }

  String _forecastEvidenceLabel(MarketForecast forecast) {
    final source = forecast.sources.first;
    final sourceAt = _formatDateTime(forecast.sourceLatestAt);
    return _t(
      en: 'Data quality ${forecast.dataQualityPercent}% · ${forecast.evidencePointCount} points · $source · through $sourceAt',
      fa: 'کیفیت داده ${forecast.dataQualityPercent}٪ · ${forecast.evidencePointCount} نقطه · $source · تا $sourceAt',
      ja: 'データ品質 ${forecast.dataQualityPercent}%・${forecast.evidencePointCount}点・$source・$sourceAt まで',
      ru: 'Качество ${forecast.dataQualityPercent}% · ${forecast.evidencePointCount} точек · $source · до $sourceAt',
      zh: '数据质量 ${forecast.dataQualityPercent}% · ${forecast.evidencePointCount} 点 · $source · 截至 $sourceAt',
      ar: 'جودة البيانات ${forecast.dataQualityPercent}٪ · ${forecast.evidencePointCount} نقطة · $source · حتى $sourceAt',
      tr: 'Veri kalitesi %${forecast.dataQualityPercent} · ${forecast.evidencePointCount} nokta · $source · $sourceAt',
      fr: 'Qualité ${forecast.dataQualityPercent} % · ${forecast.evidencePointCount} points · $source · jusqu’au $sourceAt',
    );
  }

  String _forecastDirectionLabel(MarketForecast forecast) {
    final rawChange = (forecast.pointEstimate / forecast.anchorPrice - 1) * 100;
    final change = rawChange.isFinite ? rawChange.clamp(-99.0, 999.0) : 0.0;
    final signedChange =
        '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
    return switch (forecast.direction) {
      MarketForecastDirection.upward => _t(
        en: 'UP model scenario · $signedChange from the observed anchor',
        fa: 'سناریوی صعودی مدل · $signedChange نسبت به قیمت مبنا',
        ja: 'モデル上昇シナリオ・観測基準比 $signedChange',
        ru: 'Сценарий модели: рост · $signedChange от опорной цены',
        zh: '模型上行情景 · 较观测基准 $signedChange',
        ar: 'سيناريو نموذج صاعد · $signedChange من سعر الارتكاز',
        tr: 'Model yükseliş senaryosu · gözlenen çıpaya göre $signedChange',
        fr: 'Scénario modèle haussier · $signedChange depuis l’ancrage observé',
      ),
      MarketForecastDirection.downward => _t(
        en: 'DOWN model scenario · $signedChange from the observed anchor',
        fa: 'سناریوی نزولی مدل · $signedChange نسبت به قیمت مبنا',
        ja: 'モデル下降シナリオ・観測基準比 $signedChange',
        ru: 'Сценарий модели: снижение · $signedChange от опорной цены',
        zh: '模型下行情景 · 较观测基准 $signedChange',
        ar: 'سيناريو نموذج هابط · $signedChange من سعر الارتكاز',
        tr: 'Model düşüş senaryosu · gözlenen çıpaya göre $signedChange',
        fr: 'Scénario modèle baissier · $signedChange depuis l’ancrage observé',
      ),
      MarketForecastDirection.neutral => _t(
        en: 'MIXED model scenario · $signedChange from the observed anchor',
        fa: 'سناریوی خنثی مدل · $signedChange نسبت به قیمت مبنا',
        ja: 'モデル中立シナリオ・観測基準比 $signedChange',
        ru: 'Смешанный сценарий модели · $signedChange от опорной цены',
        zh: '模型中性情景 · 较观测基准 $signedChange',
        ar: 'سيناريو نموذج محايد · $signedChange من سعر الارتكاز',
        tr: 'Model nötr senaryosu · gözlenen çıpaya göre $signedChange',
        fr: 'Scénario modèle mixte · $signedChange depuis l’ancrage observé',
      ),
    };
  }

  String? _forecastMetricsLabel(MarketForecastMetrics? metrics) {
    if (metrics == null || !metrics.isDisplayReady) return null;
    final mae = CurrencyService.formatPrice(
      value: metrics.meanAbsoluteError,
      sourceCode: metrics.unit,
      selectedCode: SettingsStore.instance.currencyCode,
      language: widget.language,
    );
    final mape = metrics.meanAbsolutePercentageError;
    final direction = metrics.directionalHitRate;
    final interval = metrics.intervalHitRate;
    return _t(
      en: 'Past n=${metrics.sampleCount} · MAE $mae · MAPE ${mape.toStringAsFixed(1)}% · direction hit ${direction.toStringAsFixed(0)}% · range hit ${interval.toStringAsFixed(0)}%',
      fa: 'گذشته n=${metrics.sampleCount} · MAE $mae · MAPE ${mape.toStringAsFixed(1)}٪ · جهت درست ${direction.toStringAsFixed(0)}٪ · اصابت بازه ${interval.toStringAsFixed(0)}٪',
      ja: '過去 n=${metrics.sampleCount}・MAE $mae・MAPE ${mape.toStringAsFixed(1)}%・方向 ${direction.toStringAsFixed(0)}%・範囲 ${interval.toStringAsFixed(0)}%',
      ru: 'Прошлые n=${metrics.sampleCount} · MAE $mae · MAPE ${mape.toStringAsFixed(1)}% · направление ${direction.toStringAsFixed(0)}% · диапазон ${interval.toStringAsFixed(0)}%',
      zh: '历史 n=${metrics.sampleCount} · MAE $mae · MAPE ${mape.toStringAsFixed(1)}% · 方向 ${direction.toStringAsFixed(0)}% · 区间 ${interval.toStringAsFixed(0)}%',
      ar: 'السابق n=${metrics.sampleCount} · MAE $mae · MAPE ${mape.toStringAsFixed(1)}٪ · الاتجاه ${direction.toStringAsFixed(0)}٪ · النطاق ${interval.toStringAsFixed(0)}٪',
      tr: 'Geçmiş n=${metrics.sampleCount} · MAE $mae · MAPE %${mape.toStringAsFixed(1)} · yön %${direction.toStringAsFixed(0)} · aralık %${interval.toStringAsFixed(0)}',
      fr: 'Passé n=${metrics.sampleCount} · MAE $mae · MAPE ${mape.toStringAsFixed(1)} % · direction ${direction.toStringAsFixed(0)} % · plage ${interval.toStringAsFixed(0)} %',
    );
  }

  String _analysisExplanation(MarketIntelligenceReport? report) {
    if (report == null) {
      return _t(
        en: 'GoldBrain checks the live price, every verified history range currently available, technical indicators and relevant market news. A 12-hour scenario is shown only after the AI analysis succeeds.',
        fa: 'GoldBrain قیمت زنده، همهٔ بازه‌های تاریخچهٔ معتبرِ در دسترس، شاخص‌های تکنیکال و اخبار مرتبط را بررسی می‌کند؛ سناریوی ۱۲ ساعته فقط پس از موفقیت تحلیل هوش مصنوعی نمایش داده می‌شود.',
        ja: 'GoldBrain はライブ価格、検証済み履歴、テクニカル指標、利用可能な市場ニュースを確認し、AI と組み合わせて12時間シナリオを作成します。',
        ru: 'GoldBrain проверяет текущую цену, подтверждённую историю, технические индикаторы и доступные новости, а затем объединяет их с ИИ для 12-часового сценария.',
        zh: 'GoldBrain 会检查实时价格、可靠历史、技术指标和可用市场新闻，并结合 AI 生成 12 小时情景。',
        ar: 'يفحص GoldBrain السعر المباشر والسجل الموثوق والمؤشرات الفنية والأخبار المتاحة، ثم يدمجها مع الذكاء الاصطناعي لبناء سيناريو 12 ساعة.',
        tr: 'GoldBrain canlı fiyatı, doğrulanmış geçmişi, teknik göstergeleri ve mevcut piyasa haberlerini inceler; ardından 12 saatlik senaryo için AI ile birleştirir.',
        fr: 'GoldBrain vérifie le prix en direct, l’historique validé, les indicateurs techniques et les actualités disponibles, puis les combine avec l’IA pour construire le scénario à 12 h.',
      );
    }
    final newsCount = report.relevantNewsCount;
    return _t(
      en: 'GoldBrain analyzed the live price, the verified history ranges that were actually available, technical indicators and $newsCount relevant news item(s) from the app, then completed this 12-hour scenario with AI.',
      fa: 'GoldBrain قیمت زنده، بازه‌های تاریخچه‌ای را که واقعاً معتبر و در دسترس بوده‌اند، شاخص‌های تکنیکال و $newsCount خبر مرتبط از برنامه بررسی کرده و سپس این سناریوی ۱۲ ساعته را با هوش مصنوعی ساخته است.',
      ja: 'GoldBrain はライブ価格、検証済み履歴、テクニカル指標、関連ニュース $newsCount 件を分析し、AI と組み合わせてこの12時間シナリオを作成しました。',
      ru: 'GoldBrain проанализировал текущую цену, подтверждённую историю, технические индикаторы и $newsCount связанных новостей, затем объединил данные с ИИ для этого 12-часового сценария.',
      zh: 'GoldBrain 分析了实时价格、可靠历史、技术指标和 $newsCount 条相关新闻，并结合 AI 生成此 12 小时情景。',
      ar: 'حلّل GoldBrain السعر المباشر والسجل الموثوق والمؤشرات الفنية و$newsCount خبر/أخبار مرتبطة، ثم دمج الأدلة مع الذكاء الاصطناعي لهذا السيناريو لمدة 12 ساعة.',
      tr: 'GoldBrain canlı fiyatı, doğrulanmış geçmişi, teknik göstergeleri ve $newsCount ilgili haberi analiz etti; ardından bu 12 saatlik senaryo için kanıtları AI ile birleştirdi.',
      fr: 'GoldBrain a analysé le prix en direct, l’historique validé, les indicateurs techniques et $newsCount actualité(s) directement liée(s), puis a combiné les éléments avec l’IA pour ce scénario à 12 h.',
    );
  }

  String _colorLegend() => _t(
    en: 'Green = price-up scenario  •  Red = price-down scenario',
    fa: 'سبز = سناریوی افزایش قیمت  •  قرمز = سناریوی کاهش قیمت',
    ja: '緑 = 上昇シナリオ  •  赤 = 下落シナリオ',
    ru: 'Зелёный = рост цены  •  Красный = снижение цены',
    zh: '绿色 = 上涨情景  •  红色 = 下跌情景',
    ar: 'الأخضر = سيناريو صعود السعر  •  الأحمر = سيناريو هبوط السعر',
    tr: 'Yeşil = fiyat yükseliş senaryosu  •  Kırmızı = fiyat düşüş senaryosu',
    fr: 'Vert = scénario de hausse  •  Rouge = scénario de baisse',
  );

  String _formatTime(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _logo(double size) {
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(64, 256)
        .toInt();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: palette.primary.withValues(alpha: 0.45)),
      ),
      child: Image.asset(
        'assets/images/goldbrain_deep_analyzer_logo.png',
        fit: BoxFit.cover,
        cacheWidth: decodeSize,
        cacheHeight: decodeSize,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/images/goldbrain_ai_logo.png',
          fit: BoxFit.cover,
          cacheWidth: decodeSize,
          cacheHeight: decodeSize,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.insights_rounded, color: palette.primary),
        ),
      ),
    );
  }

  Widget _assetSelector() {
    final selected = _store.selectedSymbol;
    return PopupMenuButton<String>(
      key: const ValueKey('deep-analysis-asset-menu'),
      initialValue: selected,
      tooltip: _t(
        en: 'Choose market',
        fa: 'انتخاب بازار',
        ja: '市場を選択',
        ru: 'Выбрать рынок',
        zh: '选择市场',
        ar: 'اختر السوق',
        tr: 'Piyasa seç',
        fr: 'Choisir le marché',
      ),
      onSelected: _store.selectSymbol,
      itemBuilder: (context) => MarketIntelligenceStore.supportedSymbols
          .map((symbol) {
            final candidate = _store.reportFor(symbol);
            final report = candidate?.languageCode == widget.language.name
                ? candidate
                : null;
            final score = report?.scenarioEstimatePercent;
            final statusColor = _directionColor(report);
            return PopupMenuItem<String>(
              value: symbol,
              child: Row(
                children: [
                  Icon(_assetIcon(symbol), size: 18, color: palette.primary),
                  const SizedBox(width: 9),
                  Expanded(child: Text(_assetName(symbol))),
                  const SizedBox(width: 8),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      symbol,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    constraints: const BoxConstraints(minWidth: 30),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      score == null ? '—' : '$score%',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
      child: _ControlPill(
        palette: palette,
        icon: _assetIcon(selected),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _assetName(selected),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                selected,
                style: TextStyle(color: palette.mutedText, fontSize: 8),
              ),
            ),
          ],
        ),
        trailing: Icons.expand_more_rounded,
      ),
    );
  }

  Widget _intervalSelector() {
    final minutes = _store.analysisInterval.inMinutes;
    final freePlan = _store.usesRateLimitedFreeRouter;
    return PopupMenuButton<Duration>(
      key: const ValueKey('deep-analysis-interval-menu'),
      initialValue: _store.analysisInterval,
      tooltip: _t(
        en: 'Automatic refresh interval',
        fa: 'فاصلهٔ به‌روزرسانی خودکار',
        ja: '自動更新間隔',
        ru: 'Интервал автообновления',
        zh: '自动更新间隔',
        ar: 'فاصل التحديث التلقائي',
        tr: 'Otomatik yenileme aralığı',
        fr: 'Intervalle d’actualisation',
      ),
      onSelected: _store.setAnalysisInterval,
      itemBuilder: (context) => _store.availableAnalysisIntervals
          .map(
            (interval) => PopupMenuItem<Duration>(
              value: interval,
              child: Text(
                _t(
                  en: 'Every ${interval.inMinutes} minutes',
                  fa: 'هر ${interval.inMinutes} دقیقه',
                  ja: '${interval.inMinutes}分ごと',
                  ru: 'Каждые ${interval.inMinutes} мин.',
                  zh: '每 ${interval.inMinutes} 分钟',
                  ar: 'كل ${interval.inMinutes} دقائق',
                  tr: '${interval.inMinutes} dakikada bir',
                  fr: 'Toutes les ${interval.inMinutes} min',
                ),
              ),
            ),
          )
          .toList(growable: false),
      child: _ControlPill(
        palette: palette,
        icon: Icons.autorenew_rounded,
        child: Text(
          _t(
            en: freePlan ? '${minutes}m auto · free plan' : '${minutes}m auto',
            fa: freePlan
                ? 'خودکار ${minutes}د · پلن رایگان'
                : 'خودکار ${minutes}د',
            ja: freePlan ? '自動 ${minutes}分 · 無料プラン' : '自動 ${minutes}分',
            ru: freePlan
                ? 'Авто ${minutes}м · бесплатный план'
                : 'Авто ${minutes}м',
            zh: freePlan ? '自动 ${minutes}分 · 免费方案' : '自动 ${minutes}分',
            ar: freePlan
                ? 'تلقائي ${minutes}د · الخطة المجانية'
                : 'تلقائي ${minutes}د',
            tr: freePlan
                ? 'Oto ${minutes}dk · ücretsiz plan'
                : 'Oto ${minutes}dk',
            fr: freePlan
                ? 'Auto ${minutes}min · offre gratuite'
                : 'Auto ${minutes}min',
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: palette.text,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        trailing: Icons.expand_more_rounded,
      ),
    );
  }

  Widget _forecastHorizonSelector() {
    return PopupMenuButton<MarketForecastHorizon>(
      key: const ValueKey('deep-analysis-forecast-horizon-menu'),
      initialValue: _selectedForecastHorizon,
      tooltip: _t(
        en: 'Choose forecast horizon',
        fa: 'انتخاب افق سناریو',
        ja: '予測期間を選択',
        ru: 'Выбрать горизонт прогноза',
        zh: '选择预测周期',
        ar: 'اختر أفق السيناريو',
        tr: 'Tahmin ufkunu seç',
        fr: 'Choisir l’horizon',
      ),
      onSelected: (value) {
        if (_selectedForecastHorizon == value) return;
        setState(() => _selectedForecastHorizon = value);
      },
      itemBuilder: (context) => MarketForecastHorizon.values
          .map(
            (horizon) => PopupMenuItem<MarketForecastHorizon>(
              value: horizon,
              child: Text(switch (horizon) {
                MarketForecastHorizon.oneHour => _t(
                  en: '1 hour',
                  fa: '۱ ساعت',
                  ja: '1時間',
                  ru: '1 час',
                  zh: '1 小时',
                  ar: 'ساعة واحدة',
                  tr: '1 saat',
                  fr: '1 heure',
                ),
                MarketForecastHorizon.twelveHours => _t(
                  en: '12 hours',
                  fa: '۱۲ ساعت',
                  ja: '12時間',
                  ru: '12 часов',
                  zh: '12 小时',
                  ar: '12 ساعة',
                  tr: '12 saat',
                  fr: '12 heures',
                ),
                MarketForecastHorizon.twentyFourHours => _t(
                  en: '24-hour observed-price scenario',
                  fa: 'سناریوی مشاهدهٔ ۲۴ ساعته',
                  ja: '24時間観測シナリオ',
                  ru: '24-часовой сценарий наблюдения',
                  zh: '24 小时观测情景',
                  ar: 'سيناريو الرصد خلال 24 ساعة',
                  tr: '24 saatlik gözlem senaryosu',
                  fr: 'Scénario observé à 24 h',
                ),
              }),
            ),
          )
          .toList(growable: false),
      child: Container(
        key: const ValueKey('deep-analysis-forecast-horizon-value'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: palette.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.primary.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _horizonLabel(_selectedForecastHorizon),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: palette.primary,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 12, color: palette.primary),
          ],
        ),
      ),
    );
  }

  Widget _timeStrip(MarketIntelligenceReport? report) {
    final last = _formatTime(report?.generatedAt);
    final next = _formatTime(_store.nextForecastRefreshAt);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 13, color: palette.mutedText),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${_t(en: 'Last', fa: 'آخرین', ja: '最終', ru: 'Последний', zh: '上次', ar: 'الأخير', tr: 'Son', fr: 'Dernière')} $last',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.mutedText, fontSize: 8.5),
            ),
          ),
          Container(
            height: 14,
            width: 1,
            color: palette.primary.withValues(alpha: 0.16),
          ),
          const SizedBox(width: 7),
          Icon(Icons.schedule_rounded, size: 13, color: palette.primary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${_t(en: 'Local model next', fa: 'مدل محلی بعدی', ja: '次のローカルモデル', ru: 'Следующая локальная модель', zh: '下次本地模型', ar: 'النموذج المحلي التالي', tr: 'Sonraki yerel model', fr: 'Prochain modèle local')} $next',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.mutedText, fontSize: 8.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final symbol = _store.selectedSymbol;
    final storedReport = _store.reportFor(symbol);
    final report = storedReport?.languageCode == widget.language.name
        ? storedReport
        : null;
    final forecast = _store.forecastFor(symbol, _selectedForecastHorizon);
    final metrics = _store.forecastMetricsFor(symbol, _selectedForecastHorizon);
    final forecastColor = switch (forecast?.direction) {
      MarketForecastDirection.upward => const Color(0xFF38D98B),
      MarketForecastDirection.downward => const Color(0xFFFF6678),
      MarketForecastDirection.neutral => const Color(0xFFF5C84C),
      null => palette.mutedText,
    };
    final color = report == null ? forecastColor : _directionColor(report);
    final score = report?.scenarioEstimatePercent;
    final target = forecast == null
        ? ''
        : _formatForecastPrice(forecast, forecast.pointEstimate);
    final metricsLabel = _forecastMetricsLabel(metrics);
    final density = widget.densityScale.clamp(0.78, 1.12);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Container(
      height: 500 * density,
      padding: EdgeInsets.all(16 * density),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 30,
            spreadRadius: 1,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 370;
          final gaugeWidth = (narrow ? 100.0 : 126.0) * density;
          return Column(
            children: [
              Row(
                children: [
                  _logo(46 * density),
                  SizedBox(width: 10 * density),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(
                            en: 'GOLDBRAIN DEEP ANALYST',
                            fa: 'تحلیل‌گر عمیق GOLDBRAIN',
                            ja: 'GOLDBRAIN 深層分析',
                            ru: 'ГЛУБОКИЙ АНАЛИТИК GOLDBRAIN',
                            zh: 'GOLDBRAIN 深度分析器',
                            ar: 'محلّل GOLDBRAIN العميق',
                            tr: 'GOLDBRAIN DERİN ANALİZ',
                            fr: 'ANALYSTE PROFOND GOLDBRAIN',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 13 * density,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t(
                            en: 'Verified prices, history and news',
                            fa: 'بر پایهٔ قیمت، تاریخچه و اخبار معتبر',
                            ja: '検証済み価格・履歴・ニュース',
                            ru: 'Цены, история и новости с источниками',
                            zh: '基于可靠价格、历史和新闻',
                            ar: 'أسعار وتاريخ وأخبار موثّقة',
                            tr: 'Doğrulanmış fiyat, geçmiş ve haberler',
                            fr: 'Prix, historique et actualités vérifiés',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 8.5 * density,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_store.loading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.primary,
                      ),
                    )
                  else
                    Icon(_directionIcon(report), color: color, size: 24),
                ],
              ),
              SizedBox(height: 8 * density),
              SizedBox(
                height: 39 * density,
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _assetSelector()),
                    SizedBox(width: 7 * density),
                    Expanded(flex: 2, child: _intervalSelector()),
                  ],
                ),
              ),
              SizedBox(height: 7 * density),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: gaugeWidth,
                      child: TweenAnimationBuilder<double>(
                        key: const ValueKey('analysis-gauge-animation'),
                        tween: Tween<double>(end: (score ?? 0).toDouble()),
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 750),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => CustomPaint(
                          painter: _AnalysisGaugePainter(
                            value: value / 100,
                            color: color,
                            trackColor: palette.mutedText.withValues(
                              alpha: 0.15,
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  score == null ? '—' : '${value.round()}%',
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: (narrow ? 24 : 28) * density,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  _t(
                                    en: 'AI scenario',
                                    fa: 'سناریوی AI',
                                    ja: 'AIシナリオ',
                                    ru: 'Сценарий ИИ',
                                    zh: 'AI 情景',
                                    ar: 'سيناريو AI',
                                    tr: 'AI senaryosu',
                                    fr: 'Scénario IA',
                                  ),
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: palette.mutedText,
                                    fontSize: 8 * density,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10 * density),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _directionLabel(report),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                              fontSize: 10 * density,
                            ),
                          ),
                          SizedBox(height: 5 * density),
                          Text(
                            report == null
                                ? _emptyOrErrorMessage(symbol)
                                : _analysisExplanation(report),
                            maxLines: report == null ? 4 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 9.5 * density,
                              height: 1.4,
                            ),
                          ),
                          if (report != null) ...[
                            SizedBox(height: 5 * density),
                            Text(
                              _colorLegend(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: color,
                                fontSize: 8.5 * density,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                          SizedBox(height: 7 * density),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: 8 * density,
                              vertical: 6 * density,
                            ),
                            decoration: BoxDecoration(
                              color: forecastColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: forecastColor.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _forecastTitle(forecast),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.mutedText,
                                          fontSize: 7.5 * density,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    _forecastHorizonSelector(),
                                  ],
                                ),
                                SizedBox(height: 2 * density),
                                if (forecast == null)
                                  Text(
                                    _forecastUnavailableLabel(),
                                    key: const ValueKey(
                                      'deep-analysis-forecast-unavailable',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.mutedText,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 7.5 * density,
                                      height: 1.2,
                                    ),
                                  )
                                else ...[
                                  Directionality(
                                    textDirection: TextDirection.ltr,
                                    child: Text(
                                      '$symbol  $target',
                                      key: const ValueKey(
                                        'deep-analysis-forecast-point',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: forecastColor,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10.5 * density,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _forecastDirectionLabel(forecast),
                                    key: const ValueKey(
                                      'deep-analysis-forecast-direction',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: forecastColor,
                                      fontSize: 6.8 * density,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    _forecastIntervalLabel(forecast),
                                    key: const ValueKey(
                                      'deep-analysis-forecast-interval',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.mutedText,
                                      fontSize: 6.8 * density,
                                    ),
                                  ),
                                  Text(
                                    _forecastEvidenceLabel(forecast),
                                    key: const ValueKey(
                                      'deep-analysis-forecast-provenance',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.mutedText,
                                      fontSize: 6.5 * density,
                                    ),
                                  ),
                                  if (metricsLabel != null)
                                    Text(
                                      metricsLabel,
                                      key: const ValueKey(
                                        'deep-analysis-forecast-metrics',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: forecastColor,
                                        fontSize: 6.5 * density,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (report != null && _store.errorCode != null) ...[
                SizedBox(height: 4 * density),
                Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 12,
                      color: Color(0xFFFFA968),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _staleErrorLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFFA968),
                          fontSize: 7.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 5 * density),
              _timeStrip(report),
              SizedBox(height: 6 * density),
              SizedBox(
                width: double.infinity,
                height: 39 * density,
                child: FilledButton.icon(
                  key: const ValueKey('start-deep-analysis'),
                  onPressed: _store.loading ? null : _runAnalysis,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: palette.isLight
                        ? Colors.white
                        : Colors.black,
                    padding: EdgeInsets.symmetric(vertical: 8 * density),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: _store.loading
                      ? SizedBox(
                          width: 15 * density,
                          height: 15 * density,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 17),
                  label: Text(
                    _store.loading
                        ? _t(
                            en: 'Analyzing verified data…',
                            fa: 'در حال تحلیل داده‌های معتبر…',
                            ja: '検証済みデータを分析中…',
                            ru: 'Анализ проверенных данных…',
                            zh: '正在分析可靠数据…',
                            ar: 'جارٍ تحليل البيانات الموثّقة…',
                            tr: 'Doğrulanmış veriler analiz ediliyor…',
                            fr: 'Analyse des données vérifiées…',
                          )
                        : _t(
                            en: 'ANALYZE $symbol NOW',
                            fa: 'تحلیل دوبارهٔ $symbol',
                            ja: '$symbol を今すぐ分析',
                            ru: 'АНАЛИЗИРОВАТЬ $symbol',
                            zh: '立即分析 $symbol',
                            ar: 'حلّل $symbol الآن',
                            tr: '$symbol ŞİMDİ ANALİZ ET',
                            fr: 'ANALYSER $symbol',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5 * density,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 5 * density),
              Text(
                _t(
                  en: 'AI scenario, not financial advice. It may be wrong and loss is possible; you make the final decision.',
                  fa: 'این فقط سناریوی هوش مصنوعی است، نه توصیهٔ مالی؛ ممکن است اشتباه باشد و زیان رخ دهد. تصمیم نهایی با شماست.',
                  ja: 'AIシナリオであり投資助言ではありません。誤りや損失の可能性があり、最終判断はご自身で行ってください。',
                  ru: 'Это сценарий ИИ, а не финансовый совет. Возможны ошибки и убытки; решение принимаете вы.',
                  zh: '这是 AI 情景分析，不是投资建议；可能出错并造成损失，最终决定由您作出。',
                  ar: 'هذا سيناريو ذكاء اصطناعي وليس نصيحة مالية؛ قد يخطئ وقد تحدث خسارة، والقرار النهائي لك.',
                  tr: 'Bu bir AI senaryosudur, yatırım tavsiyesi değildir; hata ve kayıp mümkündür, son karar sizindir.',
                  fr: 'Scénario IA, pas un conseil financier. Il peut être erroné et causer des pertes ; vous décidez.',
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: const Color(0xFFFFA968),
                  fontSize: 7.5 * density,
                  height: 1.25,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ControlPill extends StatelessWidget {
  const _ControlPill({
    required this.palette,
    required this.icon,
    required this.child,
    required this.trailing,
  });

  final ThemePalette palette;
  final IconData icon;
  final Widget child;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      constraints: const BoxConstraints(minWidth: 94),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(icon, size: 16, color: palette.primary),
          const SizedBox(width: 6),
          Expanded(child: child),
          const SizedBox(width: 4),
          Icon(trailing, size: 15, color: palette.mutedText),
        ],
      ),
    );
  }
}

class _AnalysisGaugePainter extends CustomPainter {
  const _AnalysisGaugePainter({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  final double value;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.37;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final stroke = math.min(9.0, radius * 0.16);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        colors: <Color>[color.withValues(alpha: 0.30), color],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);
    canvas.drawArc(rect, start, sweep * value.clamp(0, 1), false, progress);
  }

  @override
  bool shouldRepaint(covariant _AnalysisGaugePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
