import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpHeaders, Platform;

import 'package:http/http.dart' as http;

import 'backend_types.dart';

class GoldBrainBackendConfig {
  const GoldBrainBackendConfig({required this.baseUri, required this.apiKey});

  factory GoldBrainBackendConfig.fromEnvironment() {
    const compiledBase = String.fromEnvironment('GOLDBRAIN_API_BASE_URL');
    final rawBase =
        (Platform.environment['GOLDBRAIN_API_BASE_URL'] ?? compiledBase).trim();
    final uri = Uri.tryParse(
      rawBase.isNotEmpty ? rawBase : 'http://127.0.0.1:8000',
    );
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme == 'http' &&
            !['localhost', '127.0.0.1', '::1'].contains(uri.host))) {
      throw const GoldBrainBackendException(
        'invalid_configuration',
        'GOLDBRAIN_API_BASE_URL is invalid.',
      );
    }
    return GoldBrainBackendConfig(
      baseUri: uri,
      // User builds never carry the owner key. Explicit test/research clients
      // may still supply one through the constructor.
      apiKey: '',
    );
  }

  final Uri baseUri;
  final String apiKey;
}

class GoldBrainBackendException implements Exception {
  const GoldBrainBackendException(
    this.code,
    this.message, {
    this.serverCode,
    this.retryAfterSeconds,
  });

  final String code;
  final String message;
  final String? serverCode;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

/// An email challenge is not a session and can never activate authentication.
class BackendEmailChallenge {
  const BackendEmailChallenge({
    required this.email,
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
  });

  final String email;
  final int expiresInSeconds;
  final int resendAfterSeconds;

  static BackendEmailChallenge fromJson(
    Map<String, dynamic> value, {
    required String email,
    bool registration = false,
  }) {
    final expires = value['expires_in'];
    final resend = value['resend_after'];
    final address = value['email']?.toString() ?? email.trim();
    if ((registration
            ? value['verification_required'] != true
            : value['accepted'] != true) ||
        expires is! int ||
        expires <= 0 ||
        resend is! int ||
        resend < 0 ||
        address.isEmpty ||
        value.containsKey('access_token') ||
        value.containsKey('refresh_token')) {
      throw const GoldBrainBackendException(
        'invalid_response',
        'GoldBrain returned invalid email challenge data.',
      );
    }
    return BackendEmailChallenge(
      email: address,
      expiresInSeconds: expires,
      resendAfterSeconds: resend,
    );
  }
}

class BackendHealth {
  const BackendHealth({
    required this.status,
    required this.version,
    required this.environment,
  });

  final String status;
  final String version;
  final String environment;
}

class BackendMarketQuote {
  const BackendMarketQuote({
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
  });

  final String symbol;
  final String name;
  final String currency;
  final double price;
  final DateTime updatedAt;
  final String provider;
  final double? changePercent;
  final String? upstreamSource;
  final String? unit;
  final String? market;
  final String? freshnessStatus;
  final String? dataQualityStatus;
  final DateTime? providerTimestamp;
  final DateTime? receivedAt;
  final String? fallbackFrom;

  static BackendMarketQuote? fromJson(Object? value) {
    if (value is! Map) return null;
    final symbol = value['symbol']?.toString().trim().toUpperCase() ?? '';
    final name = value['name']?.toString().trim() ?? '';
    final currency = value['currency']?.toString().trim().toUpperCase() ?? '';
    final rawPrice = value['price'];
    final price = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse('$rawPrice');
    final updatedAt = DateTime.tryParse(value['updated_at']?.toString() ?? '');
    final provider = value['provider']?.toString().trim() ?? '';
    final rawChange = value['change_percent'];
    final changePercent = rawChange is num
        ? rawChange.toDouble()
        : double.tryParse('$rawChange');
    if (symbol.isEmpty ||
        name.isEmpty ||
        currency.isEmpty ||
        price == null ||
        !price.isFinite ||
        price <= 0 ||
        updatedAt == null ||
        provider.isEmpty) {
      return null;
    }
    return BackendMarketQuote(
      symbol: symbol,
      name: name,
      currency: currency,
      price: price,
      updatedAt: updatedAt.toUtc(),
      provider: provider,
      changePercent: changePercent?.isFinite == true ? changePercent : null,
      upstreamSource: value['upstream_source']?.toString().trim(),
      unit: value['unit']?.toString().trim(),
      market: value['market']?.toString().trim(),
      freshnessStatus: (value['freshness'] ?? value['freshness_status'])
          ?.toString()
          .trim()
          .toUpperCase(),
      dataQualityStatus: value['data_quality_status']
          ?.toString()
          .trim()
          .toUpperCase(),
      providerTimestamp: DateTime.tryParse(
        value['provider_timestamp']?.toString() ?? '',
      )?.toUtc(),
      receivedAt: DateTime.tryParse(
        value['received_at']?.toString() ?? '',
      )?.toUtc(),
      fallbackFrom: value['fallback_from']?.toString().trim(),
    );
  }
}

class BackendMarketAsset {
  const BackendMarketAsset({
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

  static BackendMarketAsset? fromJson(Object? value) {
    if (value is! Map) return null;
    final symbol = value['symbol']?.toString().trim().toUpperCase() ?? '';
    final name = value['name']?.toString().trim() ?? '';
    final assetClass = value['asset_class']?.toString().trim() ?? '';
    final quoteCurrency =
        value['quote_currency']?.toString().trim().toUpperCase() ?? '';
    if (!RegExp(r'^[A-Z0-9]{2,15}$').hasMatch(symbol) ||
        name.isEmpty ||
        assetClass.isEmpty ||
        quoteCurrency.isEmpty ||
        value['live_quote'] is! bool ||
        value['forecast'] is! bool) {
      return null;
    }
    return BackendMarketAsset(
      symbol: symbol,
      name: name,
      assetClass: assetClass,
      quoteCurrency: quoteCurrency,
      liveQuote: value['live_quote'] as bool,
      forecast: value['forecast'] as bool,
    );
  }
}

class BackendAuthSession {
  const BackendAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.sessionId,
    required this.expiresInSeconds,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final String sessionId;
  final int expiresInSeconds;
  final Map<String, dynamic> user;

  static BackendAuthSession? fromJson(Object? value) {
    if (value is! Map) return null;
    final access = value['access_token']?.toString().trim() ?? '';
    final refresh = value['refresh_token']?.toString().trim() ?? '';
    final sessionId = value['session_id']?.toString().trim() ?? '';
    final expiresRaw = value['expires_in_seconds'];
    final expires = expiresRaw is num
        ? expiresRaw.toInt()
        : int.tryParse('$expiresRaw');
    final rawUser = value['user'];
    if (access.isEmpty ||
        refresh.isEmpty ||
        sessionId.isEmpty ||
        expires == null ||
        expires <= 0 ||
        rawUser is! Map ||
        rawUser['public_id'] is! String ||
        (rawUser['public_id'] as String).isEmpty) {
      return null;
    }
    return BackendAuthSession(
      accessToken: access,
      refreshToken: refresh,
      sessionId: sessionId,
      expiresInSeconds: expires,
      user: Map<String, dynamic>.from(rawUser),
    );
  }
}

class BackendForecast {
  const BackendForecast({
    required this.forecastId,
    required this.symbol,
    required this.horizon,
    required this.direction,
    required this.anchorPrice,
    required this.pointEstimate,
    required this.lowerBound,
    required this.upperBound,
    required this.confidenceScore,
    required this.probabilityUp,
    required this.calibrationStatus,
    required this.generatedAt,
    required this.targetAt,
    required this.reasons,
    this.timeframe = '1h',
    this.dataQuality = 0,
    this.signal = 'no_trade',
    this.signalQuality = 'unverified',
    this.tradeAllowed = false,
    this.decisionReasons = const [],
    this.modelVersion = '',
    this.modelBreakdown = const {},
  });

  final String forecastId;
  final String symbol;
  final String horizon;
  final String direction;
  final double anchorPrice;
  final double pointEstimate;
  final double lowerBound;
  final double upperBound;
  final int confidenceScore;
  final double probabilityUp;
  final String calibrationStatus;
  final DateTime generatedAt;
  final DateTime targetAt;
  final List<String> reasons;
  final String timeframe, signal, signalQuality, modelVersion;
  final int dataQuality;
  final bool tradeAllowed;
  final List<String> decisionReasons;
  final Map<String, dynamic> modelBreakdown;
  bool get paperEligible =>
      ['buy', 'sell'].contains(signal) &&
      (signalQuality == 'paper_only' || tradeAllowed) &&
      ['validation-based', 'calibrated'].contains(calibrationStatus);

  static BackendForecast? fromJson(Object? value) {
    if (value is! Map) return null;
    double? number(String key) {
      final raw = value[key];
      return raw is num ? raw.toDouble() : double.tryParse('$raw');
    }

    final id = value['forecast_id']?.toString().trim() ?? '';
    final symbol = value['symbol']?.toString().trim().toUpperCase() ?? '';
    final horizon = value['horizon']?.toString().trim() ?? '';
    final direction = value['direction']?.toString().trim() ?? '';
    final anchor = number('anchor_price');
    final point = number('point_estimate');
    final lower = number('lower_bound');
    final upper = number('upper_bound');
    final probability = number('probability_up');
    final confidenceRaw = value['confidence_score'];
    final confidence = confidenceRaw is num
        ? confidenceRaw.toInt()
        : int.tryParse('$confidenceRaw');
    final generatedAt = DateTime.tryParse(
      value['generated_at']?.toString() ?? '',
    );
    final targetAt = DateTime.tryParse(value['target_at']?.toString() ?? '');
    if (id.isEmpty ||
        symbol.isEmpty ||
        horizon.isEmpty ||
        !['upward', 'downward', 'neutral'].contains(direction) ||
        anchor == null ||
        point == null ||
        lower == null ||
        upper == null ||
        probability == null ||
        confidence == null ||
        generatedAt == null ||
        targetAt == null) {
      return null;
    }
    if ([anchor, point, lower, upper, probability].any((n) => !n.isFinite) ||
        anchor <= 0 ||
        lower <= 0 ||
        lower > point ||
        point > upper ||
        probability < 0 ||
        probability > 1 ||
        confidence < 0 ||
        confidence > 100 ||
        !generatedAt.isUtc ||
        !targetAt.isUtc ||
        !targetAt.isAfter(generatedAt))
      return null;
    return BackendForecast(
      forecastId: id,
      symbol: symbol,
      horizon: horizon,
      direction: direction,
      anchorPrice: anchor,
      pointEstimate: point,
      lowerBound: lower,
      upperBound: upper,
      confidenceScore: confidence,
      probabilityUp: probability,
      calibrationStatus:
          value['calibration_status']?.toString().trim() ?? 'provisional',
      generatedAt: generatedAt.toUtc(),
      targetAt: targetAt.toUtc(),
      reasons: value['reasons'] is List
          ? (value['reasons'] as List)
                .map((item) => item.toString())
                .toList(growable: false)
          : const <String>[],
      timeframe: value['timeframe']?.toString() ?? '1h',
      dataQuality: value['data_quality'] is num
          ? (value['data_quality'] as num).toInt()
          : 0,
      signal: ['buy', 'sell', 'no_trade'].contains(value['signal'])
          ? value['signal'] as String
          : 'no_trade',
      signalQuality: value['signal_quality']?.toString() ?? 'unverified',
      tradeAllowed: value['trade_allowed'] == true,
      decisionReasons: value['decision_reasons'] is List
          ? (value['decision_reasons'] as List)
                .map((v) => v.toString())
                .toList()
          : const [],
      modelVersion: value['model_version']?.toString() ?? '',
      modelBreakdown: value['model_breakdown'] is Map
          ? Map<String, dynamic>.from(value['model_breakdown'] as Map)
          : const {},
    );
  }
}

class BackendQuoteBatch {
  const BackendQuoteBatch({
    required this.requestedSymbols,
    required this.quotes,
    required this.issues,
    required this.partial,
  });

  final List<String> requestedSymbols;
  final Map<String, BackendMarketQuote> quotes;
  final Map<String, String> issues;
  final bool partial;
}

/// Shared transport for the private-beta UI. Provider keys stay server-side.
class GoldBrainBackendClient {
  GoldBrainBackendClient({
    GoldBrainBackendConfig? config,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.emailDeliveryTimeout = const Duration(seconds: 60),
  }) : config = config ?? GoldBrainBackendConfig.fromEnvironment(),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final GoldBrainBackendConfig config;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  // SMTP delivery takes multiple network round trips before the API responds.
  final Duration emailDeliveryTimeout;
  String _accessToken = '';
  Future<bool> Function()? renewSession;
  void Function()? sessionExpired;
  String get accessToken => _accessToken;

  void setAccessToken(String? value) {
    _accessToken = value?.trim() ?? '';
  }

  Future<BackendEmailChallenge> register({
    required String email,
    required String password,
    required String displayName,
    String deviceName = 'GoldBrain Flutter',
  }) async {
    final body = await _postObject(
      '/api/v1/auth/register',
      <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'display_name': displayName.trim(),
        'device_name': deviceName,
      },
      authenticated: false,
      requestTimeout: emailDeliveryTimeout,
    );
    return BackendEmailChallenge.fromJson(
      body,
      email: email,
      registration: true,
    );
  }

  Future<BackendEmailChallenge> requestEmailVerification(String email) async =>
      BackendEmailChallenge.fromJson(
        await _postObject(
          '/api/v1/auth/email-verification/request',
          {'email': email.trim()},
          authenticated: false,
          requestTimeout: emailDeliveryTimeout,
        ),
        email: email,
      );

  Future<BackendAuthSession> confirmEmailVerification({
    required String email,
    required String code,
    required String newPassword,
    String deviceName = 'GoldBrain Flutter',
  }) async {
    final session = BackendAuthSession.fromJson(
      await _postObject('/api/v1/auth/email-verification/confirm', {
        'email': email.trim(),
        'code': code.trim(),
        'new_password': newPassword,
        'device_name': deviceName,
      }, authenticated: false),
    );
    if (session == null) {
      throw const GoldBrainBackendException(
        'invalid_response',
        'GoldBrain backend returned invalid auth data.',
      );
    }
    return session;
  }

  Future<BackendAuthSession> login({
    required String email,
    required String password,
    String deviceName = 'GoldBrain Flutter',
    bool activate = true,
  }) async {
    final body = await _postObject('/api/v1/auth/login', <String, dynamic>{
      'email': email.trim(),
      'password': password,
      'device_name': deviceName,
    }, authenticated: false);
    final session = BackendAuthSession.fromJson(body);
    if (session == null) {
      throw const GoldBrainBackendException(
        'invalid_response',
        'GoldBrain backend returned invalid auth data.',
      );
    }
    if (activate) setAccessToken(session.accessToken);
    return session;
  }

  Future<BackendAuthSession> refreshAuth(
    String refreshToken, {
    bool activate = true,
  }) async {
    final body = await _postObject('/api/v1/auth/refresh', <String, dynamic>{
      'refresh_token': refreshToken,
    }, authenticated: false);
    final session = BackendAuthSession.fromJson(body);
    if (session == null) {
      throw const GoldBrainBackendException(
        'invalid_response',
        'GoldBrain backend returned invalid auth data.',
      );
    }
    if (activate) setAccessToken(session.accessToken);
    return session;
  }

  Future<Map<String, dynamic>> currentUser() {
    return _getObject('/api/v1/auth/me', authenticated: true);
  }

  Future<Map<String, dynamic>> countryPulseEvidence(
    String country,
    String window,
  ) => _getObjectUri(
    _resolve(
      '/api/v1/pulse/countries/${Uri.encodeComponent(country)}',
    ).replace(queryParameters: {'window': window}),
    authenticated: true,
  );

  Future<BackendHealth> health() async {
    final body = await _getObject('/api/v1/health', authenticated: false);
    final status = body['status']?.toString().trim() ?? '';
    final version = body['version']?.toString().trim() ?? '';
    final environment = body['environment']?.toString().trim() ?? '';
    if (status.isEmpty || version.isEmpty || environment.isEmpty) {
      throw const GoldBrainBackendException(
        'invalid_response',
        'GoldBrain backend returned an invalid health response.',
      );
    }
    return BackendHealth(
      status: status,
      version: version,
      environment: environment,
    );
  }

  Future<BackendQuoteBatch> fetchQuotes(
    Iterable<String> symbols, {
    bool forceRefresh = false,
  }) async {
    final normalized = symbols
        .map((item) => item.trim().toUpperCase())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final uri = _resolve('/api/v1/market/quotes').replace(
      queryParameters: <String, dynamic>{
        if (normalized.isNotEmpty) 'symbols': normalized,
        if (forceRefresh) 'force_refresh': 'true',
      },
    );
    final body = await _getObjectUri(uri, authenticated: true);
    final requested = (body['requested_symbols'] is List)
        ? (body['requested_symbols'] as List)
              .map((item) => item.toString().trim().toUpperCase())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final quotes = <String, BackendMarketQuote>{};
    final rawQuotes = body['quotes'];
    if (rawQuotes is List) {
      for (final item in rawQuotes) {
        final quote = BackendMarketQuote.fromJson(item);
        if (quote != null) quotes[quote.symbol] = quote;
      }
    }
    final issues = <String, String>{};
    final rawIssues = body['issues'];
    if (rawIssues is List) {
      for (final item in rawIssues) {
        if (item is! Map) continue;
        final symbol = item['symbol']?.toString().trim().toUpperCase() ?? '';
        final message = item['message']?.toString().trim() ?? '';
        if (symbol.isNotEmpty && message.isNotEmpty) issues[symbol] = message;
      }
    }
    return BackendQuoteBatch(
      requestedSymbols: requested,
      quotes: Map.unmodifiable(quotes),
      issues: Map.unmodifiable(issues),
      partial: body['partial'] == true,
    );
  }

  Future<List<BackendMarketAsset>> marketAssets() async {
    final body = await _getObject('/api/v1/market/assets', authenticated: true);
    final raw = body['assets'];
    if (raw is! List) throw const FormatException('Missing market assets');
    final assets = <BackendMarketAsset>[];
    final seen = <String>{};
    for (final item in raw) {
      final asset = BackendMarketAsset.fromJson(item);
      if (asset == null || !seen.add(asset.symbol)) {
        throw const FormatException('Invalid or duplicate market asset');
      }
      assets.add(asset);
    }
    if (assets.isEmpty) throw const FormatException('Empty market assets');
    return List.unmodifiable(assets);
  }

  Future<BackendForecast> generateForecast({
    required String symbol,
    String horizon = '1h',
    String timeframe = '1h',
    bool persist = true,
  }) async {
    final body = await _postObject('/api/v1/forecast', <String, dynamic>{
      'symbol': symbol.trim().toUpperCase(),
      'horizon': horizon,
      'timeframe': timeframe,
      'persist': persist,
    }, authenticated: true);
    final forecast = BackendForecast.fromJson(body);
    if (forecast == null) {
      throw const GoldBrainBackendException(
        'invalid_response',
        'GoldBrain backend returned an invalid forecast.',
      );
    }
    return forecast;
  }

  Future<Map<String, dynamic>> runBacktest({
    required String symbol,
    String horizon = '1h',
    String timeframe = '1h',
  }) {
    return _postObject('/api/v1/forecast/backtest', <String, dynamic>{
      'symbol': symbol.trim().toUpperCase(),
      'horizon': horizon,
      'timeframe': timeframe,
    }, authenticated: true);
  }

  Future<Map<String, dynamic>> deepAnalysis({
    required String symbol,
    String horizon = '1h',
    String timeframe = '1h',
    String language = 'fa',
  }) {
    return _postObject('/api/v1/intelligence/deep-analysis', <String, dynamic>{
      'symbol': symbol.trim().toUpperCase(),
      'horizon': horizon,
      'timeframe': timeframe,
      'language': language,
    }, authenticated: true);
  }

  Future<Map<String, dynamic>> createPaperAccount({
    required String name,
    double initialBalance = 10000,
    String baseCurrency = 'USDT',
  }) {
    return _postObject('/api/v1/paper/accounts', <String, dynamic>{
      'name': name,
      'initial_balance': initialBalance,
      'base_currency': baseCurrency,
    }, authenticated: true);
  }

  Future<Map<String, dynamic>> placePaperOrder({
    required String symbol,
    required String side,
    required double quantity,
    required double price,
    double feeRate = 0,
    String? reason,
    String? forecastId,
  }) {
    return _postObject('/api/v1/paper/orders', <String, dynamic>{
      'symbol': symbol.trim().toUpperCase(),
      'side': side,
      'quantity': quantity,
      'price': price,
      'fee_rate': feeRate,
      if (reason != null) 'reason': reason,
      if (forecastId != null) 'forecast_id': forecastId,
    }, authenticated: true);
  }

  Future<Map<String, dynamic>> paperPortfolio() {
    return _getObject('/api/v1/paper/portfolio/me', authenticated: true);
  }

  Future<List<BackendCandle>> candles(
    String symbol,
    String timeframe, {
    String? provider,
    int? limit,
  }) async {
    final body = await _getObjectUri(
      _resolve('/api/v1/market/${Uri.encodeComponent(symbol)}/candles').replace(
        queryParameters: {
          'timeframe': timeframe,
          if (provider != null) 'provider': provider,
          if (limit != null) 'limit': '$limit',
        },
      ),
      authenticated: true,
    );
    final rows = listField(body['candles'], BackendCandle.fromJson);
    final now = DateTime.now().toUtc();
    DateTime? previous;
    String? currency;
    String? candleProvider;
    for (final row in rows) {
      if (row.symbol != symbol ||
          row.timeframe != timeframe ||
          row.closedAt.isAfter(now) ||
          (previous != null && !row.openedAt.isAfter(previous)) ||
          (currency != null && row.currency != currency) ||
          (provider != null && row.provider != provider) ||
          (candleProvider != null && row.provider != candleProvider)) {
        throw const FormatException(
          'Unordered, mixed-source or future history',
        );
      }
      previous = row.openedAt;
      currency = row.currency;
      candleProvider = row.provider;
    }
    return rows;
  }

  Future<List<BackendPriceSample>> priceSamples24h(String symbol) async {
    final normalized = symbol.trim().toUpperCase();
    final body = await _getObjectUri(
      _resolve(
        '/api/v1/market/${Uri.encodeComponent(normalized)}/samples',
      ).replace(queryParameters: const {'range': '24h'}),
      authenticated: true,
    );
    if (body['symbol'] != normalized || body['range'] != '24h') {
      throw const FormatException('Invalid price sample response');
    }
    final rows = listField(body['samples'], BackendPriceSample.fromJson);
    DateTime? previous;
    String? currency;
    String? provider;
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(const Duration(hours: 24));
    for (final row in rows) {
      if (row.symbol != normalized ||
          row.provider != 'navasan' ||
          row.market != 'IRAN' ||
          row.dataQualityStatus != 'VALID' ||
          !const {
            'LIVE',
            'FRESH',
            'DELAYED',
            'STALE',
          }.contains(row.freshnessStatus) ||
          !['IRT', 'IRR'].contains(row.currency) ||
          row.unit != (normalized == 'GOLD18' ? 'gram_18k' : 'currency_unit') ||
          row.providerTimestamp.isBefore(cutoff) ||
          row.providerTimestamp.isAfter(now.add(const Duration(seconds: 30))) ||
          (previous != null && !row.providerTimestamp.isAfter(previous)) ||
          (currency != null && row.currency != currency) ||
          (provider != null && row.provider != provider) ||
          !row.qualityFlags.contains('price_sample_not_ohlc')) {
        throw const FormatException(
          'Invalid, mixed or unordered price samples',
        );
      }
      previous = row.providerTimestamp;
      currency = row.currency;
      provider = row.provider;
    }
    return rows;
  }

  Future<BackendMetrics> metrics(String symbol, String horizon) async {
    final result = BackendMetrics.fromJson(
      await _getObjectUri(
        _resolve(
          '/api/v1/forecast/metrics',
        ).replace(queryParameters: {'symbol': symbol, 'horizon': horizon}),
        authenticated: true,
      ),
    );
    if (result.symbol != symbol || result.horizon != horizon)
      throw const FormatException('Metrics identity mismatch');
    return result;
  }

  Future<BackendOverview> overview() async => BackendOverview.fromJson(
    await _getObject('/api/v1/market/overview', authenticated: true),
  );

  Future<BackendForecast?> latestForecast(String symbol, String horizon) async {
    try {
      final body = await _getObjectUri(
        _resolve('/api/v1/forecast/latest').replace(
          queryParameters: {
            'symbol': symbol,
            'horizon': horizon,
            'timeframe': timeframeFor(horizon),
          },
        ),
        authenticated: true,
      );
      final forecast = BackendForecast.fromJson(body);
      if (forecast == null ||
          forecast.symbol != symbol ||
          forecast.horizon != horizon ||
          forecast.timeframe != timeframeFor(horizon)) {
        throw const FormatException('Forecast identity mismatch');
      }
      return forecast;
    } on GoldBrainBackendException catch (error) {
      if (error.code == 'http_404') return null;
      rethrow;
    }
  }

  Future<BackendGoldContext> goldContext() async => BackendGoldContext.fromJson(
    await _getObject('/api/v1/market/gold18-context', authenticated: true),
  );

  Future<BackendNews> news({bool refresh = false}) async =>
      BackendNews.fromJson(
        await _getObjectUri(
          _resolve(
            '/api/v1/intelligence/news',
          ).replace(queryParameters: {'refresh': '$refresh'}),
          authenticated: true,
        ),
      );

  Future<List<BackendDevice>> sessions() async => listField(
    await _request('GET', _resolve('/api/v1/auth/sessions')),
    BackendDevice.fromJson,
  );
  Future<void> revokeSession(String id) async {
    await _request(
      'DELETE',
      _resolve('/api/v1/auth/sessions/${Uri.encodeComponent(id)}'),
    );
  }

  Future<void> logout() async {
    await _request('POST', _resolve('/api/v1/auth/logout'), body: {});
  }

  Future<BackendEmailChallenge> requestPasswordReset(String email) async =>
      BackendEmailChallenge.fromJson(
        await _postObject(
          '/api/v1/auth/password-reset/request',
          {'email': email.trim()},
          authenticated: false,
          requestTimeout: emailDeliveryTimeout,
        ),
        email: email,
      );

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _request(
      'POST',
      _resolve('/api/v1/auth/password-reset/confirm'),
      body: {
        'email': email.trim(),
        'code': code.trim(),
        'new_password': newPassword,
      },
      authenticated: false,
    );
  }

  Future<List<BackendAlert>> alerts() async => listField(
    await _request('GET', _resolve('/api/v1/alerts')),
    BackendAlert.fromJson,
  );
  Future<void> createAlert(
    String symbol,
    String condition,
    double threshold,
  ) async {
    await _request(
      'POST',
      _resolve('/api/v1/alerts'),
      body: {'symbol': symbol, 'condition': condition, 'threshold': threshold},
    );
  }

  Future<void> deleteAlert(String id) async {
    await _request(
      'DELETE',
      _resolve('/api/v1/alerts/${Uri.encodeComponent(id)}'),
    );
  }

  Future<List<BackendAlert>> evaluateAlerts() async => listField(
    await _request('POST', _resolve('/api/v1/alerts/evaluate'), body: {}),
    BackendAlert.fromJson,
  );

  Future<Map<String, dynamic>> _getObject(
    String path, {
    required bool authenticated,
  }) => _getObjectUri(_resolve(path), authenticated: authenticated);

  Future<Map<String, dynamic>> assistantChat(Map<String, dynamic> payload) =>
      _postObject(
        '/api/v1/assistant/chat',
        payload,
        authenticated: true,
        requestTimeout: const Duration(seconds: 95),
      );

  Future<Map<String, dynamic>> newsFeed({bool refresh = false}) async => object(
    await _request(
      'GET',
      _resolve(
        '/api/v1/intelligence/news',
      ).replace(queryParameters: {'refresh': refresh.toString()}),
      requestTimeout: const Duration(seconds: 25),
    ),
  );

  Future<Map<String, dynamic>> newsSummary(String articleId, String language) =>
      _postObject(
        '/api/v1/intelligence/news/${Uri.encodeComponent(articleId)}/summary',
        {'language': language},
        authenticated: true,
        requestTimeout: const Duration(seconds: 95),
      );

  Future<Map<String, dynamic>> newsTranslations(
    List<String> articleIds,
    String language,
  ) => _postObject(
    '/api/v1/intelligence/news/translations',
    {'article_ids': articleIds, 'language': language},
    authenticated: true,
    requestTimeout: const Duration(seconds: 95),
  );

  Future<Map<String, dynamic>> _getObjectUri(
    Uri uri, {
    required bool authenticated,
  }) async => object(await _request('GET', uri, authenticated: authenticated));

  Future<Map<String, dynamic>> _postObject(
    String path,
    Map<String, dynamic> payload, {
    required bool authenticated,
    Duration? requestTimeout,
  }) async => object(
    await _request(
      'POST',
      _resolve(path),
      body: payload,
      authenticated: authenticated,
      requestTimeout: requestTimeout,
    ),
  );

  Future<Object?> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool retried = false,
    Duration? requestTimeout,
  }) async {
    final sentToken = _accessToken;
    late http.Response response;
    try {
      final request = http.Request(method, uri)
        ..headers.addAll(_headers(authenticated: authenticated));
      if (body != null) {
        request.headers[HttpHeaders.contentTypeHeader] = 'application/json';
        request.body = jsonEncode(body);
      }
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout ?? timeout);
    } on TimeoutException {
      throw const GoldBrainBackendException(
        'timeout',
        'GoldBrain backend request timed out.',
      );
    } on http.ClientException {
      throw const GoldBrainBackendException(
        'network_error',
        'Could not connect to GoldBrain.',
      );
    }
    if (response.statusCode == 401 &&
        authenticated &&
        !retried &&
        renewSession != null) {
      final renewed =
          _accessToken.isNotEmpty && sentToken != _accessToken ||
          await renewSession!();
      if (renewed)
        return _request(
          method,
          uri,
          body: body,
          authenticated: true,
          retried: true,
          requestTimeout: requestTimeout,
        );
    }
    if (response.statusCode == 401 && authenticated) sessionExpired?.call();
    if (response.statusCode == 204 && method != 'GET') return null;
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw const GoldBrainBackendException(
          'invalid_response',
          'Invalid JSON from GoldBrain.',
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Never expose raw server tracebacks, request bodies or credentials in UI.
      final detail = decoded is Map
          ? (decoded['error'] is Map ? decoded['error'] : decoded['detail'])
          : null;
      final rawCode = detail is Map ? detail['code'] : null;
      final serverCode =
          rawCode is String &&
              RegExp(r'^[a-z][a-z0-9_]{0,79}$').hasMatch(rawCode)
          ? rawCode
          : null;
      final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
      throw GoldBrainBackendException(
        'http_${response.statusCode}',
        'GoldBrain request failed (HTTP ${response.statusCode}).',
        serverCode: serverCode,
        retryAfterSeconds: retryAfter != null && retryAfter >= 0
            ? retryAfter
            : null,
      );
    }
    return decoded;
  }

  Uri _resolve(String path) {
    final base = config.baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final suffix = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$suffix');
  }

  Map<String, String> _headers({required bool authenticated}) =>
      <String, String>{
        HttpHeaders.acceptHeader: 'application/json',
        if (authenticated && _accessToken.isNotEmpty)
          HttpHeaders.authorizationHeader: 'Bearer $_accessToken'
        else if (authenticated && config.apiKey.isNotEmpty)
          'X-GoldBrain-Key': config.apiKey,
      };

  void close() {
    if (_ownsClient) _client.close();
  }
}
