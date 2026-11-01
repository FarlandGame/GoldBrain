import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'currency_service.dart';
import 'local_persistence_policy.dart';

/// Keeps a validated, cached USD-base FX snapshot for display conversion.
/// Iranian Toman/Rial are intentionally updated by [LiveMarketStore] from the
/// sourced Iranian USD quote, not from an official IRR rate.
class CurrencyRateStore extends ChangeNotifier {
  CurrencyRateStore({
    http.Client? client,
    Uri? endpoint,
    this.cacheDuration = const Duration(hours: 6),
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       endpoint =
           endpoint ??
           Uri.parse('https://api.exchangerate.fun/latest?base=USD');

  static final CurrencyRateStore instance = CurrencyRateStore();

  static const _ratesKey = 'currency.usd_reference_rates_v1';
  static const _fetchedAtKey = 'currency.usd_reference_fetched_at_v1';
  static const _supportedInternationalCodes = <String>{
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'RUB',
    'CNY',
    'AED',
    'TRY',
    'CAD',
    'AUD',
    'CHF',
    'INR',
    'SAR',
  };

  final http.Client _client;
  final bool _ownsClient;
  final Uri endpoint;
  final Duration cacheDuration;
  final Duration timeout;

  DateTime? _fetchedAt;
  Future<bool>? _inFlight;
  bool _loading = false;
  String? _lastError;

  bool get loading => _loading;
  DateTime? get fetchedAt => _fetchedAt;
  String? get lastError => _lastError;
  String get providerLabel => 'ExchangeRate.fun';

  Future<void> loadCached() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_ratesKey);
    final fetchedAtText = preferences.getString(_fetchedAtKey);
    final parsedTime = DateTime.tryParse(fetchedAtText ?? '');
    if (encoded == null || parsedTime == null) return;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return;
      final rates = _validatedRates(decoded);
      if (!_hasRequiredRates(rates)) return;
      CurrencyService.updateInternationalRates(rates, observedAt: parsedTime);
      _fetchedAt = parsedTime.toLocal();
      notifyListeners();
    } on FormatException {
      // Ignore a damaged cache and keep the conservative offline bootstrap.
    }
  }

  Future<bool> refresh({bool force = false}) {
    final active = _inFlight;
    if (active != null) return active;
    final fetchedAt = _fetchedAt;
    if (!force &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < cacheDuration) {
      return Future.value(true);
    }

    final request = _refresh();
    _inFlight = request;
    return request.whenComplete(() => _inFlight = null);
  }

  Future<bool> _refresh() async {
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final response = await _client.get(endpoint).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FormatException('FX provider returned a non-success code');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map ||
          decoded['base']?.toString().toUpperCase() != 'USD') {
        throw const FormatException('FX provider returned an invalid base');
      }
      final rawRates = decoded['rates'];
      if (rawRates is! Map) {
        throw const FormatException('FX provider returned no rates');
      }
      final rates = _validatedRates(rawRates);
      if (!_hasRequiredRates(rates)) {
        throw const FormatException('FX provider omitted required rates');
      }

      CurrencyService.updateInternationalRates(rates);
      _fetchedAt = DateTime.now();
      if (LocalPersistencePolicy.instance.canWrite) {
        final preferences = await SharedPreferences.getInstance();
        await Future.wait([
          preferences.setString(_ratesKey, jsonEncode(rates)),
          preferences.setString(_fetchedAtKey, _fetchedAt!.toIso8601String()),
        ]);
      }
      _loading = false;
      notifyListeners();
      return true;
    } on TimeoutException {
      _lastError = 'Currency rate request timed out.';
    } on http.ClientException {
      _lastError = 'Currency rate provider is unreachable.';
    } on FormatException {
      _lastError = 'Currency rate provider returned invalid data.';
    } catch (_) {
      _lastError = 'Currency rates could not be updated.';
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  Map<String, double> _validatedRates(Map<dynamic, dynamic> rawRates) {
    final rates = <String, double>{};
    for (final entry in rawRates.entries) {
      final code = entry.key.toString().trim().toUpperCase();
      final value = entry.value;
      if (!_supportedInternationalCodes.contains(code) || value is! num) {
        continue;
      }
      final rate = value.toDouble();
      if (rate.isFinite && rate > 0) rates[code] = rate;
    }
    rates['USD'] = 1;
    return rates;
  }

  bool _hasRequiredRates(Map<String, double> rates) =>
      _supportedInternationalCodes.every(rates.containsKey);

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
