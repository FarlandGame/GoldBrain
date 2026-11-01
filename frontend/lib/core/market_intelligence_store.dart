import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_market_store.dart';
import 'market_forecast.dart';
import 'market_forecast_engine.dart';
import 'market_forecast_ledger.dart';
import 'market_history_service.dart';
import 'market_intelligence_service.dart';
import 'news_store.dart';
import 'local_persistence_policy.dart';
import 'backend_connection.dart';
import 'backend_intelligence_adapter.dart';
import 'backend_api_client.dart';

typedef MarketIntelligenceInputLoader =
    Future<MarketIntelligenceInput> Function(String languageCode);

class MarketIntelligenceStore extends ChangeNotifier {
  MarketIntelligenceStore({
    MarketIntelligenceService? service,
    MarketIntelligenceInputLoader? inputLoader,
    MarketHistoryService? historyService,
    MarketForecastEngine forecastEngine = const MarketForecastEngine(),
    MarketForecastLedger? forecastLedger,
    BackendIntelligenceAdapter? backendAdapter,
    Duration analysisInterval = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _service = service ?? MarketIntelligenceService(),
       _ownsService = service == null,
       _historyService = historyService ?? MarketHistoryService(),
       _ownsHistoryService = historyService == null,
       _forecastEngine = forecastEngine,
       _forecastLedger = forecastLedger ?? MarketForecastLedger(),
       _backendAdapter =
           backendAdapter ??
           (service == null &&
                   inputLoader == null &&
                   BackendConnection.instance.session.authenticated
               ? BackendIntelligenceAdapter(
                   BackendConnection.instance.api,
                   clock: clock,
                 )
               : null),
       _inputLoader = inputLoader,
       _clock = clock ?? DateTime.now,
       _analysisInterval =
           analysisInterval.isNegative || analysisInterval == Duration.zero
           ? const Duration(minutes: 10)
           : analysisInterval {
    _analysisInterval = _providerAwareInterval(_analysisInterval);
  }

  static final MarketIntelligenceStore instance = MarketIntelligenceStore();

  static const List<String> supportedSymbols = <String>[
    'GOLD18',
    'XAU',
    'XAG',
    'USD',
    'USDT',
    'BTC',
    'ETH',
  ];
  static const List<Duration> supportedAnalysisIntervals = <Duration>[
    Duration(minutes: 5),
    Duration(minutes: 10),
  ];
  static const Duration freeRouterMinimumAnalysisInterval = Duration(
    minutes: 60,
  );
  static const Duration deterministicForecastInterval = Duration(minutes: 5);

  static const _reportsKey = 'market_intelligence.reports_v2';
  static const _legacyReportKey = 'market_intelligence.latest_report_v1';
  static const _selectedSymbolKey = 'market_intelligence.selected_symbol_v1';
  static const _intervalMinutesKey = 'market_intelligence.interval_minutes_v1';
  static const _activeForecastsKey = 'market_forecast.active_v1';
  static const _forecastLedgerKey = 'market_forecast.ledger_v1';

  final MarketIntelligenceService _service;
  final bool _ownsService;
  final MarketHistoryService _historyService;
  final bool _ownsHistoryService;
  final MarketForecastEngine _forecastEngine;
  final BackendIntelligenceAdapter? _backendAdapter;
  final Map<String, MarketForecastMetrics> _backendMetrics = {};
  int _backendEpoch = 0;
  bool get usesBackend => _backendAdapter != null;
  MarketForecastLedger _forecastLedger;
  final MarketIntelligenceInputLoader? _inputLoader;
  final DateTime Function() _clock;

  Duration _analysisInterval;
  SharedPreferences? _preferences;
  Timer? _timer;
  Timer? _forecastTimer;
  Future<void>? _inFlight;
  Future<void>? _forecastInFlight;
  Future<void> _forecastUpdateQueue = Future<void>.value();
  final Map<String, MarketIntelligenceReport> _reports =
      <String, MarketIntelligenceReport>{};
  final Map<String, String> _errorCodes = <String, String>{};
  final Map<String, String> _errorMessages = <String, String>{};
  final Map<String, Map<MarketForecastHorizon, MarketForecast>> _forecasts =
      <String, Map<MarketForecastHorizon, MarketForecast>>{};
  Set<String> _loadingSymbols = const <String>{};
  String _languageCode = 'english';
  String _selectedSymbol = 'GOLD18';
  bool _started = false;
  bool _disposed = false;
  DateTime? _nextRefreshAt;
  DateTime? _lastAnalysisAttemptAt;
  DateTime? _nextForecastRefreshAt;
  DateTime? _lastForecastEvidenceAt;

  Map<String, MarketIntelligenceReport> get reportsBySymbol =>
      Map.unmodifiable(<String, MarketIntelligenceReport>{
        for (final entry in _reports.entries)
          if (entry.value.languageCode == _languageCode) entry.key: entry.value,
      });
  Map<String, String> get errorCodesBySymbol => Map.unmodifiable(_errorCodes);
  Map<String, String> get errorMessagesBySymbol =>
      Map.unmodifiable(_errorMessages);
  Set<String> get loadingSymbols => Set.unmodifiable(_loadingSymbols);
  Map<MarketForecastHorizon, MarketForecast> forecastsFor(String symbol) =>
      Map.unmodifiable(
        _forecasts[_normalizeSymbol(symbol)] ??
            const <MarketForecastHorizon, MarketForecast>{},
      );

  MarketForecast? forecastFor(String symbol, MarketForecastHorizon horizon) {
    final forecast = _forecasts[_normalizeSymbol(symbol)]?[horizon];
    if (forecast == null ||
        !forecast.targetFor.toUtc().isAfter(_clock().toUtc())) {
      return null;
    }
    return forecast;
  }

  MarketForecastMetrics? forecastMetricsFor(
    String symbol,
    MarketForecastHorizon horizon,
  ) {
    final active = forecastFor(symbol, horizon);
    if (usesBackend) {
      return active == null
          ? null
          : _backendMetrics['${_normalizeSymbol(symbol)}:${horizon.wireName}'];
    }
    return _forecastLedger.metricsFor(
      _normalizeSymbol(symbol),
      horizon,
      unit: active?.unit,
    );
  }

  /// Compatibility getter used by the assistant screen and the original card.
  MarketIntelligenceReport? get report =>
      reportFor(_selectedSymbol) ??
      reportFor('GOLD18') ??
      reportsBySymbol.values.firstOrNull;

  MarketIntelligenceReport? reportFor(String symbol) {
    final report = _reports[_normalizeSymbol(symbol)];
    return report?.languageCode == _languageCode ? report : null;
  }

  String? errorCodeFor(String symbol) => _errorCodes[_normalizeSymbol(symbol)];
  String? errorMessageFor(String symbol) =>
      _errorMessages[_normalizeSymbol(symbol)];
  bool isLoadingSymbol(String symbol) =>
      _loadingSymbols.contains(_normalizeSymbol(symbol));

  String? get errorCode => errorCodeFor(_selectedSymbol);
  String? get errorMessage => errorMessageFor(_selectedSymbol);
  bool get loading => _loadingSymbols.isNotEmpty;
  bool get started => _started;
  bool get isConfigured => _service.isConfigured;
  bool get usesRateLimitedFreeRouter => _service.usesRateLimitedFreeRouter;
  DateTime? get nextRefreshAt => _nextRefreshAt;
  DateTime? get lastAnalysisAttemptAt => _lastAnalysisAttemptAt;
  DateTime? get nextForecastRefreshAt => _nextForecastRefreshAt;
  String get selectedSymbol => _selectedSymbol;
  Duration get analysisInterval => _analysisInterval;
  List<Duration> get availableAnalysisIntervals =>
      _service.usesRateLimitedFreeRouter
      ? const <Duration>[freeRouterMinimumAnalysisInterval]
      : supportedAnalysisIntervals;

  Future<void> start({
    required String languageCode,
    bool refreshImmediately = true,
  }) async {
    if (_disposed) return;
    final languageChanged = _languageCode != languageCode;
    _preferences ??= await SharedPreferences.getInstance();
    if (_started) {
      if (languageChanged) {
        _languageCode = languageCode;
        unawaited(refreshAll(force: true));
      }
      if (refreshImmediately && _reports.isEmpty) await refreshAll();
      return;
    }
    _languageCode = languageCode;
    _restoreState();
    final needsBackgroundRefresh =
        supportedSymbols.any((symbol) => !_reports.containsKey(symbol)) ||
        _reports.values.any((report) => report.languageCode != languageCode);
    final needsImmediateForecastRefresh =
        _forecasts.isEmpty && !needsBackgroundRefresh;
    _started = true;
    _scheduleNextRefresh();
    _scheduleForecastRefresh();
    _notifySafely();
    if (refreshImmediately) {
      await refreshAll();
    } else if (needsBackgroundRefresh) {
      unawaited(refreshAll());
    } else if (needsImmediateForecastRefresh) {
      // A reports_v2 cache may predate the deterministic forecast schema.
      // Populate its first source-backed checkpoint immediately instead of
      // leaving the card empty until the first five-minute timer fires.
      unawaited(refreshForecasts());
    }
  }

  void updateLanguage(String languageCode, {bool refresh = true}) {
    if (_languageCode == languageCode) return;
    _languageCode = languageCode;
    if (refresh) unawaited(refreshAll(force: true));
  }

  void selectSymbol(String symbol) {
    final normalized = _normalizeSymbol(symbol);
    if (!supportedSymbols.contains(normalized) ||
        normalized == _selectedSymbol) {
      return;
    }
    _selectedSymbol = normalized;
    if (LocalPersistencePolicy.instance.canWrite) {
      unawaited(_preferences?.setString(_selectedSymbolKey, normalized));
    }
    _notifySafely();
  }

  void setAnalysisInterval(Duration interval) {
    final requested = interval == const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : const Duration(minutes: 10);
    final normalized = _providerAwareInterval(requested);
    if (_analysisInterval == normalized) return;
    _analysisInterval = normalized;
    if (LocalPersistencePolicy.instance.canWrite) {
      unawaited(
        _preferences?.setInt(_intervalMinutesKey, normalized.inMinutes),
      );
    }
    if (_started) _scheduleNextRefresh();
    _notifySafely();
  }

  Future<void> refreshAll({bool force = false}) =>
      refresh(force: force, symbols: supportedSymbols.toSet());

  Future<void> refresh({bool force = false, Set<String>? symbols}) {
    final active = _inFlight;
    if (active != null) return active;
    final requested = (symbols ?? supportedSymbols.toSet())
        .map(_normalizeSymbol)
        .where(supportedSymbols.contains)
        .toSet();
    if (requested.isEmpty || _disposed) return Future<void>.value();
    final operation = _performRefresh(requested, force: force);
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
      if (_started) _scheduleNextRefresh();
    });
  }

  Future<void> _performRefresh(
    Set<String> requested, {
    required bool force,
  }) async {
    if (_disposed) return;
    if (usesBackend) {
      await _performBackendRefresh(requested, force: force);
      return;
    }
    final now = _clock();
    final dueSymbols = force
        ? requested
        : requested.where((symbol) {
            final current = _reports[symbol];
            return current == null ||
                current.languageCode != _languageCode ||
                now.difference(current.generatedAt.toLocal()) >=
                    _analysisInterval;
          }).toSet();
    if (dueSymbols.isEmpty) return;

    _loadingSymbols = Set.unmodifiable(dueSymbols);
    for (final symbol in dueSymbols) {
      _errorCodes.remove(symbol);
      _errorMessages.remove(symbol);
    }
    _notifySafely();
    try {
      final loader = _inputLoader;
      final input = loader != null
          ? await loader(_languageCode)
          : await _loadEvidence(_languageCode);
      await _updateForecasts(input);
      final analysisSymbols = force
          ? dueSymbols
          : dueSymbols.where((symbol) {
              final current = _reports[symbol];
              return current == null ||
                  current.languageCode != _languageCode ||
                  current.evidenceFingerprint !=
                      input.evidenceFingerprintFor(symbol);
            }).toSet();
      if (analysisSymbols.isEmpty) {
        _lastAnalysisAttemptAt = _clock();
        return;
      }
      _loadingSymbols = Set.unmodifiable(analysisSymbols);
      _notifySafely();
      final result = await _service.analyzeBatch(
        input,
        symbols: analysisSymbols,
      );
      _reports.addAll(result.reports);
      for (final entry in result.issues.entries) {
        _errorCodes[entry.key] = entry.value.code;
        _errorMessages[entry.key] = entry.value.message;
        // Never leave a previous forecast visible when the current deep-analysis
        // run failed its AI/history/news evidence gate.
        _reports.remove(entry.key);
      }
      for (final symbol in result.reports.keys) {
        _errorCodes.remove(symbol);
        _errorMessages.remove(symbol);
      }
      _lastAnalysisAttemptAt = _clock();
      await _persistReports();
    } on MarketIntelligenceException catch (error) {
      _setIssues(dueSymbols, code: error.code, message: error.message);
      _lastAnalysisAttemptAt = _clock();
    } catch (_) {
      _setIssues(
        dueSymbols,
        code: 'unexpected_error',
        message: 'Automatic market analysis could not be updated.',
      );
      _lastAnalysisAttemptAt = _clock();
    } finally {
      _loadingSymbols = const <String>{};
      _notifySafely();
    }
  }

  void _setIssues(
    Iterable<String> symbols, {
    required String code,
    required String message,
  }) {
    for (final symbol in symbols) {
      _errorCodes[symbol] = code;
      _errorMessages[symbol] = message;
    }
  }

  Future<void> _performBackendRefresh(
    Set<String> requested, {
    required bool force,
  }) async {
    final epoch = _backendEpoch;
    final language = _languageCode;
    final due = requested.where((symbol) {
      final existing = _reports[symbol];
      return force ||
          existing == null ||
          existing.languageCode != language ||
          _clock().difference(existing.generatedAt) >= _analysisInterval;
    }).toSet();
    if (due.isEmpty) return;
    final hadReports = <String, bool>{
      for (final symbol in due) symbol: _reports.containsKey(symbol),
    };
    _loadingSymbols = Set.unmodifiable(due);
    _notifySafely();
    try {
      // Scheduled refreshes read persisted worker forecasts. A user-triggered
      // refresh may generate missing horizons and run deep analysis.
      await _refreshBackendForecasts(due, generateIfMissing: force);
      for (final symbol in due) {
        if (_disposed || epoch != _backendEpoch) return;
        if (!force && hadReports[symbol] != true) continue;
        try {
          final report = await _backendAdapter!.analyze(symbol, language);
          if (_disposed || epoch != _backendEpoch) return;
          _reports[symbol] = report;
          _errorCodes.remove(symbol);
          _errorMessages.remove(symbol);
        } on MarketIntelligenceException catch (error) {
          if (epoch != _backendEpoch) return;
          _reports.remove(symbol);
          _setIssues([symbol], code: error.code, message: error.message);
        } on GoldBrainBackendException catch (error) {
          if (epoch != _backendEpoch) return;
          _reports.remove(symbol);
          _setIssues([symbol], code: error.code, message: error.message);
        } catch (_) {
          if (epoch != _backendEpoch) return;
          _reports.remove(symbol);
          _setIssues(
            [symbol],
            code: 'invalid_response',
            message: 'The server analysis could not be verified.',
          );
        }
        _notifySafely();
      }
    } finally {
      if (epoch == _backendEpoch) {
        _lastAnalysisAttemptAt = _clock();
        _loadingSymbols = const {};
        _notifySafely();
      }
    }
  }

  Future<void> _refreshBackendForecasts(
    Iterable<String> symbols, {
    bool generateIfMissing = false,
  }) async {
    final epoch = _backendEpoch;
    for (final symbol in symbols) {
      for (final horizon in MarketForecastHorizon.values) {
        if (_disposed || epoch != _backendEpoch) return;
        final metricsKey = '$symbol:${horizon.wireName}';
        try {
          final evidence = await _backendAdapter!.forecast(
            symbol,
            horizon,
            generateIfMissing: generateIfMissing,
          );
          if (_disposed || epoch != _backendEpoch) return;
          final forecast = evidence.displayForecast;
          if (forecast == null) {
            _forecasts[symbol]?.remove(horizon);
            _backendMetrics.remove(metricsKey);
          } else {
            (_forecasts[symbol] ??= {})[horizon] = forecast;
            try {
              final metrics = await _backendAdapter.metrics(
                symbol,
                horizon,
                evidence.unit,
              );
              if (_disposed || epoch != _backendEpoch) return;
              if (metrics == null) {
                _backendMetrics.remove(metricsKey);
              } else {
                _backendMetrics[metricsKey] = metrics;
              }
            } catch (_) {
              _backendMetrics.remove(metricsKey);
            }
          }
        } catch (_) {
          // A failed validation must hide an old directional card immediately.
          if (_disposed || epoch != _backendEpoch) return;
          _forecasts[symbol]?.remove(horizon);
          _backendMetrics.remove(metricsKey);
        }
      }
      _notifySafely();
    }
  }

  /// Called on logout so a late request cannot populate the next user's view.
  void clearSessionState() {
    _backendEpoch++;
    stop();
    _reports.clear();
    _forecasts.clear();
    _backendMetrics.clear();
    _errorCodes.clear();
    _errorMessages.clear();
    _loadingSymbols = const {};
    _notifySafely();
  }

  void _scheduleNextRefresh() {
    _timer?.cancel();
    if (_disposed || !_started) return;
    final now = _clock();
    final latestReportAt = _reports.values
        .map((report) => report.generatedAt.toLocal())
        .fold<DateTime?>(null, (latest, value) {
          if (latest == null || value.isAfter(latest)) return value;
          return latest;
        });
    final anchor = _lastAnalysisAttemptAt ?? latestReportAt ?? now;
    final dueAt = anchor.add(_analysisInterval);
    final delay = dueAt.isAfter(now)
        ? dueAt.difference(now)
        : const Duration(milliseconds: 250);
    _nextRefreshAt = now.add(delay);
    _timer = Timer(delay, () => unawaited(refreshAll()));
  }

  Future<void> refreshForecasts() {
    final active = _forecastInFlight;
    if (active != null) return active;
    if (_disposed) return Future<void>.value();
    final operation = _performForecastRefresh();
    _forecastInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_forecastInFlight, operation)) _forecastInFlight = null;
      if (_started) _scheduleForecastRefresh();
    });
  }

  Future<void> _performForecastRefresh() async {
    if (usesBackend) {
      await _refreshBackendForecasts(supportedSymbols);
      _notifySafely();
      return;
    }
    try {
      final loader = _inputLoader;
      final input = loader != null
          ? await loader(_languageCode)
          : await _loadEvidence(_languageCode);
      if (_disposed) return;
      await _updateForecasts(input);
      _notifySafely();
    } catch (_) {
      // Local deterministic forecasts fail closed per horizon. A temporary
      // evidence/network failure does not trigger an AI call or fabricate a
      // replacement value; the last still-active checkpoint remains visible.
    }
  }

  Future<void> _updateForecasts(MarketIntelligenceInput input) async {
    final operation = _forecastUpdateQueue.then<void>(
      (_) => _applyForecastUpdate(input),
    );
    _forecastUpdateQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _applyForecastUpdate(MarketIntelligenceInput input) async {
    if (_disposed) return;
    final evidenceAt = input.collectedAt.toUtc();
    final lastAppliedAt = _lastForecastEvidenceAt;
    if (lastAppliedAt != null && evidenceAt.isBefore(lastAppliedAt)) {
      // Evidence loads can complete out of order when the hourly AI refresh
      // overlaps the five-minute deterministic refresh. Never let an older
      // snapshot replace forecasts (or evaluate outcomes) produced from a
      // newer snapshot.
      return;
    }
    _forecastLedger.evaluate(input);
    final generated = _forecastEngine.generateAll(
      input,
      symbols: supportedSymbols,
    );
    final now = input.collectedAt.toUtc();
    for (final symbol in supportedSymbols) {
      final current =
          _forecasts[symbol] ?? <MarketForecastHorizon, MarketForecast>{};
      current.removeWhere((_, forecast) => !forecast.targetFor.isAfter(now));
      final next = generated[symbol];
      if (next != null) {
        for (final entry in next.entries) {
          final existing = current[entry.key];
          if (existing != null &&
              existing.evidenceFingerprint == entry.value.evidenceFingerprint &&
              existing.targetFor.isAfter(now)) {
            continue;
          }
          current[entry.key] = entry.value;
          _forecastLedger.add(entry.value);
        }
      }
      if (current.isEmpty) {
        _forecasts.remove(symbol);
      } else {
        _forecasts[symbol] = current;
      }
    }
    _lastForecastEvidenceAt = evidenceAt;
    await _persistForecastState();
  }

  void _scheduleForecastRefresh() {
    _forecastTimer?.cancel();
    if (_disposed || !_started) return;
    final now = _clock();
    _nextForecastRefreshAt = now.add(deterministicForecastInterval);
    _forecastTimer = Timer(
      deterministicForecastInterval,
      () => unawaited(refreshForecasts()),
    );
  }

  Future<MarketIntelligenceInput> _loadEvidence(String languageCode) async {
    final marketFuture = LiveMarketStore.instance.load();
    final newsFuture = NewsStore.instance.load();
    await Future.wait<void>(<Future<void>>[
      marketFuture.then<void>((_) {}),
      newsFuture,
    ]);
    final quotes = LiveMarketStore.instance.quotes.values
        .map(
          (quote) => IntelligenceQuoteEvidence(
            symbol: quote.symbol,
            price: quote.price,
            unit: quote.currency,
            changePercent: quote.changePercent,
            updatedAt: quote.updatedAt,
            source: quote.upstreamSource ?? quote.providerLabel,
          ),
        )
        .toList(growable: false);
    // Scan the full loaded news feed for relevance. The intelligence service
    // will only send a bounded set of the most relevant items to the AI, so
    // prompt size stays controlled while no loaded article is skipped here.
    final news = NewsStore.instance.articles
        .take(80)
        .map(
          (article) => IntelligenceNewsEvidence(
            id: article.id,
            title: article.title,
            summary: article.bestAvailableBody,
            publishedAt: article.publishedAt,
            source: article.source,
          ),
        )
        .toList(growable: false);
    final histories = await _loadHistories();
    return MarketIntelligenceInput(
      languageCode: languageCode,
      quotes: quotes,
      news: news,
      histories: histories,
      collectedAt: _clock(),
    );
  }

  Future<List<IntelligenceHistoryEvidence>> _loadHistories() async {
    const ranges = <MarketHistoryRange>[
      MarketHistoryRange.oneHour,
      MarketHistoryRange.oneDay,
      MarketHistoryRange.oneWeek,
    ];
    final requests = <Future<IntelligenceHistoryEvidence?>>[];
    for (final symbol in supportedSymbols) {
      for (final range in ranges) {
        requests.add(() async {
          MarketHistorySeries? series;
          if (MarketHistoryService.supportedSymbols.contains(symbol)) {
            try {
              series = await _historyService.fetchHistory(symbol, range: range);
            } catch (_) {
              series = null;
            }
          }
          if (series == null) {
            try {
              series = await LiveMarketStore.instance.localHistoryFor(
                symbol,
                range: range,
              );
            } catch (_) {
              series = null;
            }
          }
          if (series == null || series.candles.length < 2) return null;
          final maximum = switch (range) {
            MarketHistoryRange.oneHour => 120,
            MarketHistoryRange.oneDay => 144,
            MarketHistoryRange.oneWeek => 168,
            MarketHistoryRange.oneMonth => 720,
          };
          final candles = _sampleCandles(series.candles, maximum: maximum);
          return IntelligenceHistoryEvidence(
            symbol: series.symbol,
            unit: series.currency,
            source: series.providerLabel,
            range: range.name,
            isProxy: series.isProxy,
            points: candles
                .map(
                  (candle) => IntelligenceHistoryPoint(
                    time: candle.time,
                    close: candle.close,
                  ),
                )
                .toList(growable: false),
          );
        }());
      }
    }
    return (await Future.wait<IntelligenceHistoryEvidence?>(
      requests,
    )).whereType<IntelligenceHistoryEvidence>().toList(growable: false);
  }

  List<MarketCandle> _sampleCandles(
    List<MarketCandle> candles, {
    required int maximum,
  }) {
    if (candles.length <= maximum) return List.unmodifiable(candles);
    final sampled = <MarketCandle>[];
    for (var index = 0; index < maximum; index++) {
      final sourceIndex = (index * (candles.length - 1) / (maximum - 1))
          .round();
      sampled.add(candles[sourceIndex]);
    }
    return List.unmodifiable(sampled);
  }

  void _restoreState() {
    if (!usesBackend) _restoreForecastState();
    final storedSelected = _preferences?.getString(_selectedSymbolKey);
    if (storedSelected != null && supportedSymbols.contains(storedSelected)) {
      _selectedSymbol = storedSelected;
    }
    final intervalMinutes = _preferences?.getInt(_intervalMinutesKey);
    if (intervalMinutes == 5 ||
        intervalMinutes == 10 ||
        intervalMinutes == 30 ||
        intervalMinutes == 60) {
      _analysisInterval = Duration(minutes: intervalMinutes!);
    }
    final providerAwareInterval = _providerAwareInterval(_analysisInterval);
    if (providerAwareInterval != _analysisInterval) {
      _analysisInterval = providerAwareInterval;
      if (LocalPersistencePolicy.instance.canWrite) {
        unawaited(
          _preferences?.setInt(
            _intervalMinutesKey,
            providerAwareInterval.inMinutes,
          ),
        );
      }
    }
    // Do not restore local-engine predictions into the server-backed product.
    // Forecasts and evaluations are read from the server ledger after login.
    if (usesBackend) return;
    final raw = _preferences?.getString(_reportsKey);
    if (raw != null && raw.length <= 1024 * 1024) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final symbol = _normalizeSymbol(entry.key.toString());
            final report = MarketIntelligenceReport.fromJson(entry.value);
            if (supportedSymbols.contains(symbol) &&
                report != null &&
                report.symbol == symbol &&
                report.engineVersion == marketIntelligenceEngineVersion) {
              _reports[symbol] = report;
            }
          }
        }
      } on FormatException {
        _reports.clear();
      }
    }
    if (_reports.isEmpty) _restoreLegacyReport();
  }

  void _restoreForecastState() {
    final now = _clock().toUtc();
    final rawActive = _preferences?.getString(_activeForecastsKey);
    if (rawActive != null && rawActive.length <= 1024 * 1024) {
      try {
        final decoded = jsonDecode(rawActive);
        if (decoded is Map) {
          for (final symbolEntry in decoded.entries) {
            final symbol = _normalizeSymbol(symbolEntry.key.toString());
            if (!supportedSymbols.contains(symbol) ||
                symbolEntry.value is! Map) {
              continue;
            }
            final restored = <MarketForecastHorizon, MarketForecast>{};
            for (final horizonEntry in (symbolEntry.value as Map).entries) {
              final horizon = MarketForecastHorizonX.parse(
                horizonEntry.key.toString(),
              );
              final forecast = MarketForecast.fromJson(horizonEntry.value);
              if (horizon != null &&
                  forecast != null &&
                  forecast.symbol == symbol &&
                  forecast.horizon == horizon &&
                  !forecast.generatedAt.toUtc().isAfter(
                    now.add(const Duration(minutes: 1)),
                  ) &&
                  forecast.targetFor.isAfter(now)) {
                restored[horizon] = forecast;
              }
            }
            if (restored.isNotEmpty) {
              _forecasts[symbol] = restored;
              for (final forecast in restored.values) {
                final generatedAt = forecast.generatedAt.toUtc();
                final lastAppliedAt = _lastForecastEvidenceAt;
                if (lastAppliedAt == null ||
                    generatedAt.isAfter(lastAppliedAt)) {
                  _lastForecastEvidenceAt = generatedAt;
                }
              }
            }
          }
        }
      } on FormatException {
        _forecasts.clear();
      }
    }
    final rawLedger = _preferences?.getString(_forecastLedgerKey);
    if (rawLedger != null && rawLedger.length <= 4 * 1024 * 1024) {
      try {
        _forecastLedger = MarketForecastLedger.fromJson(jsonDecode(rawLedger));
      } on FormatException {
        _forecastLedger = MarketForecastLedger();
      }
    }
  }

  void _restoreLegacyReport() {
    final raw = _preferences?.getString(_legacyReportKey);
    if (raw == null || raw.length > 256 * 1024) return;
    try {
      final report = MarketIntelligenceReport.fromJson(jsonDecode(raw));
      if (report != null &&
          report.engineVersion == marketIntelligenceEngineVersion) {
        _reports[report.symbol] = report;
      }
    } on FormatException {
      // Ignore corrupt legacy cache.
    }
  }

  Future<void> _persistReports() async {
    if (usesBackend) return;
    if (!LocalPersistencePolicy.instance.canWrite) return;
    final preferences = _preferences;
    if (preferences == null) return;
    final encoded = jsonEncode(<String, Object?>{
      for (final entry in _reports.entries) entry.key: entry.value.toJson(),
    });
    await preferences.setString(_reportsKey, encoded);
  }

  Future<void> _persistForecastState() async {
    if (usesBackend) return;
    if (!LocalPersistencePolicy.instance.canWrite) return;
    final preferences = _preferences;
    if (preferences == null) return;
    final active = jsonEncode(<String, Object?>{
      for (final symbolEntry in _forecasts.entries)
        symbolEntry.key: <String, Object?>{
          for (final forecastEntry in symbolEntry.value.entries)
            forecastEntry.key.wireName: forecastEntry.value.toJson(),
        },
    });
    final ledger = jsonEncode(_forecastLedger.toJson());
    try {
      await preferences.setString(_activeForecastsKey, active);
      await preferences.setString(_forecastLedgerKey, ledger);
    } catch (_) {
      // Persistence is only an evaluation aid. In-memory forecasts remain
      // usable and no network/AI behavior is changed when a disk write fails.
    }
  }

  String _normalizeSymbol(String symbol) => symbol.trim().toUpperCase();

  Duration _providerAwareInterval(Duration requested) {
    if (_service.usesRateLimitedFreeRouter &&
        requested < freeRouterMinimumAnalysisInterval) {
      return freeRouterMinimumAnalysisInterval;
    }
    return requested;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _forecastTimer?.cancel();
    _forecastTimer = null;
    _started = false;
    _nextRefreshAt = null;
    _nextForecastRefreshAt = null;
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _forecastTimer?.cancel();
    if (_ownsService) _service.close();
    if (_ownsHistoryService) _historyService.close();
    super.dispose();
  }
}
