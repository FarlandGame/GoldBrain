import 'package:flutter/foundation.dart';

import '../screens/selection_screen.dart';

class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.decimalDigits,
    required this.englishName,
    required this.persianName,
    required this.japaneseName,
    required this.russianName,
  });

  final String code;
  final String symbol;
  final int decimalDigits;
  final String englishName;
  final String persianName;
  final String japaneseName;
  final String russianName;
}

typedef CurrencyDisplayConversion = ({
  double value,
  String currencyCode,
  bool isStale,
  bool unavailable,
});

class CurrencyService {
  CurrencyService._();

  /// Number of units of each currency equal to one US dollar.
  ///
  /// No estimated market rates are seeded. Until a sourced rate is available,
  /// formatPrice retains the actual source currency and its correct label.
  static final Map<String, double> _unitsPerUsd = <String, double>{'USD': 1};
  static final Map<String, DateTime> _rateTimes = {};
  static double? _tomanPerUsdt;
  static DateTime? _tomanPerUsdtAt;

  static const Map<String, String> _chineseNames = {
    'IRT': '伊朗土曼',
    'IRR': '伊朗里亚尔',
    'USD': '美元',
    'USDT': '泰达币',
    'EUR': '欧元',
    'GBP': '英镑',
    'JPY': '日元',
    'RUB': '俄罗斯卢布',
    'CNY': '人民币',
    'AED': '阿联酋迪拉姆',
    'TRY': '土耳其里拉',
    'CAD': '加拿大元',
    'AUD': '澳大利亚元',
    'CHF': '瑞士法郎',
    'INR': '印度卢比',
    'SAR': '沙特里亚尔',
  };

  static const Map<String, String> _arabicNames = {
    'IRT': 'التومان الإيراني',
    'IRR': 'الريال الإيراني',
    'USD': 'الدولار الأمريكي',
    'USDT': 'تيثر',
    'EUR': 'اليورو',
    'GBP': 'الجنيه الإسترليني',
    'JPY': 'الين الياباني',
    'RUB': 'الروبل الروسي',
    'CNY': 'اليوان الصيني',
    'AED': 'الدرهم الإماراتي',
    'TRY': 'الليرة التركية',
    'CAD': 'الدولار الكندي',
    'AUD': 'الدولار الأسترالي',
    'CHF': 'الفرنك السويسري',
    'INR': 'الروبية الهندية',
    'SAR': 'الريال السعودي',
  };

  static const Map<String, String> _turkishNames = {
    'IRT': 'İran Tümeni',
    'IRR': 'İran Riyali',
    'USD': 'ABD Doları',
    'USDT': 'Tether',
    'EUR': 'Euro',
    'GBP': 'İngiliz Sterlini',
    'JPY': 'Japon Yeni',
    'RUB': 'Rus Rublesi',
    'CNY': 'Çin Yuanı',
    'AED': 'BAE Dirhemi',
    'TRY': 'Türk Lirası',
    'CAD': 'Kanada Doları',
    'AUD': 'Avustralya Doları',
    'CHF': 'İsviçre Frangı',
    'INR': 'Hindistan Rupisi',
    'SAR': 'Suudi Riyali',
  };

  static const Map<String, String> _frenchNames = {
    'IRT': 'Toman iranien',
    'IRR': 'Rial iranien',
    'USD': 'Dollar américain',
    'USDT': 'Tether',
    'EUR': 'Euro',
    'GBP': 'Livre sterling',
    'JPY': 'Yen japonais',
    'RUB': 'Rouble russe',
    'CNY': 'Yuan chinois',
    'AED': 'Dirham des EAU',
    'TRY': 'Livre turque',
    'CAD': 'Dollar canadien',
    'AUD': 'Dollar australien',
    'CHF': 'Franc suisse',
    'INR': 'Roupie indienne',
    'SAR': 'Riyal saoudien',
  };

  static const Map<String, CurrencyInfo> currencies = {
    'IRT': CurrencyInfo(
      code: 'IRT',
      symbol: 'تومان',
      decimalDigits: 0,
      englishName: 'Iranian Toman',
      persianName: 'تومان ایران',
      japaneseName: 'イラン・トマン',
      russianName: 'Иранский туман',
    ),
    'IRR': CurrencyInfo(
      code: 'IRR',
      symbol: '﷼',
      decimalDigits: 0,
      englishName: 'Iranian Rial',
      persianName: 'ریال ایران',
      japaneseName: 'イラン・リアル',
      russianName: 'Иранский риал',
    ),
    'USD': CurrencyInfo(
      code: 'USD',
      symbol: r'$',
      decimalDigits: 2,
      englishName: 'US Dollar',
      persianName: 'دلار آمریکا',
      japaneseName: '米ドル',
      russianName: 'Доллар США',
    ),
    'USDT': CurrencyInfo(
      code: 'USDT',
      symbol: 'USDT',
      decimalDigits: 2,
      englishName: 'Tether',
      persianName: 'تتر',
      japaneseName: 'テザー',
      russianName: 'Tether',
    ),
    'EUR': CurrencyInfo(
      code: 'EUR',
      symbol: '€',
      decimalDigits: 2,
      englishName: 'Euro',
      persianName: 'یورو',
      japaneseName: 'ユーロ',
      russianName: 'Евро',
    ),
    'GBP': CurrencyInfo(
      code: 'GBP',
      symbol: '£',
      decimalDigits: 2,
      englishName: 'British Pound',
      persianName: 'پوند بریتانیا',
      japaneseName: '英ポンド',
      russianName: 'Британский фунт',
    ),
    'JPY': CurrencyInfo(
      code: 'JPY',
      symbol: '¥',
      decimalDigits: 0,
      englishName: 'Japanese Yen',
      persianName: 'ین ژاپن',
      japaneseName: '日本円',
      russianName: 'Японская иена',
    ),
    'RUB': CurrencyInfo(
      code: 'RUB',
      symbol: '₽',
      decimalDigits: 2,
      englishName: 'Russian Ruble',
      persianName: 'روبل روسیه',
      japaneseName: 'ロシアルーブル',
      russianName: 'Российский рубль',
    ),
    'CNY': CurrencyInfo(
      code: 'CNY',
      symbol: '¥',
      decimalDigits: 2,
      englishName: 'Chinese Yuan',
      persianName: 'یوان چین',
      japaneseName: '中国元',
      russianName: 'Китайский юань',
    ),
    'AED': CurrencyInfo(
      code: 'AED',
      symbol: 'د.إ',
      decimalDigits: 2,
      englishName: 'UAE Dirham',
      persianName: 'درهم امارات',
      japaneseName: 'UAEディルハム',
      russianName: 'Дирхам ОАЭ',
    ),
    'TRY': CurrencyInfo(
      code: 'TRY',
      symbol: '₺',
      decimalDigits: 2,
      englishName: 'Turkish Lira',
      persianName: 'لیر ترکیه',
      japaneseName: 'トルコリラ',
      russianName: 'Турецкая лира',
    ),
    'CAD': CurrencyInfo(
      code: 'CAD',
      symbol: r'C$',
      decimalDigits: 2,
      englishName: 'Canadian Dollar',
      persianName: 'دلار کانادا',
      japaneseName: 'カナダドル',
      russianName: 'Канадский доллар',
    ),
    'AUD': CurrencyInfo(
      code: 'AUD',
      symbol: r'A$',
      decimalDigits: 2,
      englishName: 'Australian Dollar',
      persianName: 'دلار استرالیا',
      japaneseName: '豪ドル',
      russianName: 'Австралийский доллар',
    ),
    'CHF': CurrencyInfo(
      code: 'CHF',
      symbol: 'CHF',
      decimalDigits: 2,
      englishName: 'Swiss Franc',
      persianName: 'فرانک سوئیس',
      japaneseName: 'スイスフラン',
      russianName: 'Швейцарский франк',
    ),
    'INR': CurrencyInfo(
      code: 'INR',
      symbol: '₹',
      decimalDigits: 2,
      englishName: 'Indian Rupee',
      persianName: 'روپیه هند',
      japaneseName: 'インドルピー',
      russianName: 'Индийская рупия',
    ),
    'SAR': CurrencyInfo(
      code: 'SAR',
      symbol: 'ر.س',
      decimalDigits: 2,
      englishName: 'Saudi Riyal',
      persianName: 'ریال عربستان',
      japaneseName: 'サウジアラビア・リヤル',
      russianName: 'Саудовский риял',
    ),
  };

  static String resolveCurrencyCode({
    required String selectedCode,
    required GoldBrainLanguage language,
  }) {
    if (selectedCode != 'auto' && currencies.containsKey(selectedCode)) {
      return selectedCode;
    }

    switch (language) {
      case GoldBrainLanguage.persian:
        return 'IRT';
      case GoldBrainLanguage.english:
        return 'USD';
      case GoldBrainLanguage.japanese:
        return 'JPY';
      case GoldBrainLanguage.russian:
        return 'RUB';
      case GoldBrainLanguage.chinese:
        return 'CNY';
      case GoldBrainLanguage.arabic:
        return 'SAR';
      case GoldBrainLanguage.turkish:
        return 'TRY';
      case GoldBrainLanguage.french:
        return 'EUR';
    }
  }

  static CurrencyInfo currencyInfo({
    required String selectedCode,
    required GoldBrainLanguage language,
  }) {
    final resolvedCode = resolveCurrencyCode(
      selectedCode: selectedCode,
      language: language,
    );

    return currencies[resolvedCode]!;
  }

  static String localizedName({
    required String code,
    required GoldBrainLanguage language,
  }) {
    final info = currencies[code] ?? currencies['USD']!;

    switch (language) {
      case GoldBrainLanguage.persian:
        return info.persianName;
      case GoldBrainLanguage.japanese:
        return info.japaneseName;
      case GoldBrainLanguage.russian:
        return info.russianName;
      case GoldBrainLanguage.chinese:
        return _chineseNames[code] ?? info.englishName;
      case GoldBrainLanguage.arabic:
        return _arabicNames[code] ?? info.englishName;
      case GoldBrainLanguage.turkish:
        return _turkishNames[code] ?? info.englishName;
      case GoldBrainLanguage.french:
        return _frenchNames[code] ?? info.englishName;
      case GoldBrainLanguage.english:
        return info.englishName;
    }
  }

  static String formatNumber(double value, {required int decimalDigits}) {
    final fixed = value.toStringAsFixed(decimalDigits);
    final parts = fixed.split('.');
    final integerPart = parts.first;
    final buffer = StringBuffer();

    for (var index = 0; index < integerPart.length; index++) {
      final positionFromEnd = integerPart.length - index;

      buffer.write(integerPart[index]);

      if (positionFromEnd > 1 && positionFromEnd % 3 == 1) {
        buffer.write(',');
      }
    }

    if (parts.length == 2 && decimalDigits > 0) {
      buffer
        ..write('.')
        ..write(parts[1]);
    }

    return buffer.toString();
  }

  static String formatPrice({
    required double value,
    required String selectedCode,
    required GoldBrainLanguage language,
    String? sourceCode,
  }) {
    final targetCode = resolveCurrencyCode(
      selectedCode: selectedCode,
      language: language,
    );
    final normalizedSource = (sourceCode ?? targetCode).trim().toUpperCase();
    final result = convertForDisplay(
      value: value,
      sourceCode: normalizedSource,
      selectedCode: selectedCode,
      language: language,
    );
    final info = currencies[result.currencyCode];
    if (info == null) {
      return '${formatNumber(value, decimalDigits: 2)} $normalizedSource';
    }

    var decimalDigits = info.decimalDigits;
    var number = formatNumber(result.value, decimalDigits: decimalDigits);
    // Small token prices must never become a displayed zero merely because
    // their quote currency normally uses two decimal places.
    while (result.value.isFinite &&
        result.value != 0 &&
        double.tryParse(number.replaceAll(',', '')) == 0 &&
        decimalDigits < 12) {
      decimalDigits++;
      number = formatNumber(result.value, decimalDigits: decimalDigits);
    }
    if (decimalDigits > info.decimalDigits) {
      decimalDigits = (decimalDigits + 2).clamp(0, 12);
      number = formatNumber(result.value, decimalDigits: decimalDigits);
    }

    return '$number ${info.symbol}';
  }

  /// Converts [value] between supported currencies using units-per-USD rates.
  /// Returns `null` instead of presenting a value under a false unit when a
  /// future/unknown currency has no validated conversion rate.
  static CurrencyDisplayConversion convertForDisplay({
    required double value,
    required String sourceCode,
    required String selectedCode,
    required GoldBrainLanguage language,
  }) {
    final source = sourceCode.trim().toUpperCase();
    final target = resolveCurrencyCode(
      selectedCode: selectedCode,
      language: language,
    );
    final converted = _convertWithStatus(value, source, target);
    if (converted.value == null) {
      return (
        value: value,
        currencyCode: source,
        isStale: false,
        unavailable: true,
      );
    }
    return (
      value: converted.value!,
      currencyCode: target,
      isStale: converted.isStale,
      unavailable: false,
    );
  }

  static ({bool isStale, bool unavailable, String currencyCode})
  conversionStatus({
    required String sourceCode,
    required String selectedCode,
    required GoldBrainLanguage language,
  }) {
    final result = convertForDisplay(
      value: 1,
      sourceCode: sourceCode,
      selectedCode: selectedCode,
      language: language,
    );
    return (
      isStale: result.isStale,
      unavailable: result.unavailable,
      currencyCode: result.currencyCode,
    );
  }

  static double? convert({
    required double value,
    required String sourceCode,
    required String targetCode,
  }) {
    final result = _convertWithStatus(value, sourceCode, targetCode);
    return result.isStale ? null : result.value;
  }

  static ({double? value, bool isStale}) _convertWithStatus(
    double value,
    String sourceCode,
    String targetCode,
  ) {
    if (!value.isFinite) return (value: null, isStale: false);
    final source = sourceCode.trim().toUpperCase();
    final target = targetCode.trim().toUpperCase();
    if (source == target) return (value: value, isStale: false);
    if (source == 'IRR' && target == 'IRT') {
      return (value: value / 10, isStale: false);
    }
    if (source == 'IRT' && target == 'IRR') {
      return (value: value * 10, isStale: false);
    }
    bool stale(String code) {
      if (code == 'USD') return false;
      final at = _rateTimes[code];
      if (at == null) return true;
      final age = DateTime.now().difference(at);
      return age.isNegative ||
          age >
              (code == 'IRT' || code == 'IRR' || code == 'USDT'
                  ? const Duration(minutes: 5)
                  : const Duration(hours: 6));
    }

    final sourceRate = _unitsPerUsd[source];
    final targetRate = _unitsPerUsd[target];
    if (sourceRate == null ||
        targetRate == null ||
        !sourceRate.isFinite ||
        !targetRate.isFinite ||
        sourceRate <= 0 ||
        targetRate <= 0) {
      return (value: null, isStale: false);
    }
    return (
      value: value / sourceRate * targetRate,
      isStale: stale(source) || stale(target),
    );
  }

  /// Applies a validated USD-base FX snapshot. Iranian market currencies are
  /// deliberately excluded because their free-market rate comes from the live
  /// USD/IRT quote already used by GoldBrain.
  static void updateInternationalRates(
    Map<String, double> unitsPerUsd, {
    DateTime? observedAt,
  }) {
    final asOf = observedAt ?? DateTime.now();
    if (asOf.isAfter(DateTime.now().add(const Duration(minutes: 5)))) return;
    for (final entry in unitsPerUsd.entries) {
      final code = entry.key.trim().toUpperCase();
      final value = entry.value;
      if (code == 'IRT' || code == 'IRR' || code == 'USDT') continue;
      if (!currencies.containsKey(code) || !value.isFinite || value <= 0) {
        continue;
      }
      _unitsPerUsd[code] = value;
      _rateTimes[code] = asOf;
    }
    _unitsPerUsd['USD'] = 1;
  }

  /// Updates both Toman and Rial from one sourced free-market USD quote.
  static void updateIranianTomanPerUsd(
    double tomanPerUsd, {
    DateTime? observedAt,
  }) {
    if (!tomanPerUsd.isFinite || tomanPerUsd <= 0) return;
    final asOf = observedAt ?? DateTime.now();
    if (asOf.isAfter(DateTime.now().add(const Duration(minutes: 5)))) return;
    if (_rateTimes['IRT']?.isAfter(asOf) == true) return;
    _unitsPerUsd['IRT'] = tomanPerUsd;
    _unitsPerUsd['IRR'] = tomanPerUsd * 10;
    _rateTimes['IRT'] = _rateTimes['IRR'] = asOf;
    _recomputeUsdtRate();
  }

  static void updateUsdtTomanPrice(
    double tomanPerUsdt, {
    DateTime? observedAt,
  }) {
    if (!tomanPerUsdt.isFinite || tomanPerUsdt <= 0) return;
    final asOf = observedAt ?? DateTime.now();
    if (asOf.isAfter(DateTime.now().add(const Duration(minutes: 5)))) return;
    if (_tomanPerUsdtAt?.isAfter(asOf) == true) return;
    _tomanPerUsdt = tomanPerUsdt;
    _tomanPerUsdtAt = asOf;
    _recomputeUsdtRate();
  }

  static void _recomputeUsdtRate() {
    final tomanPerUsd = _unitsPerUsd['IRT'];
    final usdAt = _rateTimes['IRT'];
    final tetherPrice = _tomanPerUsdt;
    final tetherAt = _tomanPerUsdtAt;
    if (tomanPerUsd == null ||
        usdAt == null ||
        tetherPrice == null ||
        tetherAt == null ||
        tetherPrice <= 0) {
      return;
    }
    _unitsPerUsd['USDT'] = tomanPerUsd / tetherPrice;
    _rateTimes['USDT'] = usdAt.isBefore(tetherAt) ? usdAt : tetherAt;
  }

  @visibleForTesting
  static double? unitsPerUsdFor(String code) =>
      _unitsPerUsd[code.trim().toUpperCase()];
}
