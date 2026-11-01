import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'global_price_service.dart';
import 'local_persistence_policy.dart';

/// Last sourced observations for a cold start. Restored values are always stale.
class MarketQuotePersistentCache {
  MarketQuotePersistentCache({
    Future<SharedPreferences> Function()? preferencesLoader,
    this.maxAge = const Duration(days: 7),
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _storageKey = 'goldbrain_last_market_quotes_v1';
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Duration maxAge;

  Future<Map<String, GlobalPriceQuote>> load(Iterable<String> symbols) async {
    final allowed = symbols.map((s) => s.trim().toUpperCase()).toSet();
    final preferences = await _preferencesLoader();
    final root = _read(preferences.getString(_storageKey));
    final quotes = <String, GlobalPriceQuote>{};
    final now = DateTime.now();
    for (final symbol in allowed) {
      final raw = root[symbol];
      if (raw is! Map) continue;
      final price = raw['price'];
      final parsedPrice = price is num
          ? price.toDouble()
          : double.tryParse('$price');
      final updatedAt = DateTime.tryParse(raw['updatedAt']?.toString() ?? '');
      final providerName = raw['provider']?.toString() ?? '';
      final providers = GlobalPriceProvider.values.where(
        (provider) => provider.name == providerName,
      );
      final name = raw['name']?.toString().trim() ?? '';
      final currency = raw['currency']?.toString().trim().toUpperCase() ?? '';
      if (parsedPrice == null ||
          !parsedPrice.isFinite ||
          parsedPrice <= 0 ||
          updatedAt == null ||
          updatedAt.isAfter(now.add(const Duration(minutes: 5))) ||
          now.difference(updatedAt) > maxAge ||
          providers.isEmpty ||
          name.isEmpty ||
          currency.isEmpty ||
          raw['dataQualityStatus'] == 'INVALID') {
        continue;
      }
      final change = raw['changePercent'];
      final changePercent = change is num ? change.toDouble() : null;
      final quote = GlobalPriceQuote(
        symbol: symbol,
        name: name,
        currency: currency,
        price: parsedPrice,
        updatedAt: updatedAt,
        provider: providers.first,
        changePercent: changePercent?.isFinite == true ? changePercent : null,
        upstreamSource: raw['upstreamSource']?.toString(),
        unit: raw['unit']?.toString(),
        market: raw['market']?.toString(),
        freshnessStatus: raw['freshnessStatus']?.toString(),
        dataQualityStatus: raw['dataQualityStatus']?.toString(),
        providerTimestamp: DateTime.tryParse(
          raw['providerTimestamp']?.toString() ?? '',
        ),
        receivedAt: DateTime.tryParse(raw['receivedAt']?.toString() ?? ''),
        fallbackFrom: raw['fallbackFrom']?.toString(),
        wasCached: true,
      );
      if (!quote.hasDisallowedDomesticSource) quotes[symbol] = quote;
    }
    return Map.unmodifiable(quotes);
  }

  Future<void> put(Map<String, GlobalPriceQuote> quotes) async {
    if (!LocalPersistencePolicy.instance.canWrite || quotes.isEmpty) return;
    final preferences = await _preferencesLoader();
    final root = _read(preferences.getString(_storageKey));
    final now = DateTime.now();
    for (final quote in quotes.values) {
      if (!quote.price.isFinite ||
          quote.price <= 0 ||
          quote.updatedAt.isAfter(now.add(const Duration(minutes: 5))) ||
          quote.hasDisallowedDomesticSource ||
          quote.dataQualityStatus == 'INVALID') {
        continue;
      }
      root[quote.symbol.trim().toUpperCase()] = {
        'name': quote.name,
        'currency': quote.currency,
        'price': quote.price,
        'updatedAt': quote.updatedAt.toUtc().toIso8601String(),
        'provider': quote.provider.name,
        'changePercent': quote.changePercent,
        'upstreamSource': quote.upstreamSource,
        'unit': quote.unit,
        'market': quote.market,
        'freshnessStatus': quote.freshnessStatus,
        'dataQualityStatus': quote.dataQualityStatus,
        'providerTimestamp': quote.providerTimestamp?.toUtc().toIso8601String(),
        'receivedAt': quote.receivedAt?.toUtc().toIso8601String(),
        'fallbackFrom': quote.fallbackFrom,
      };
    }
    await preferences.setString(_storageKey, jsonEncode(root));
  }

  Map<String, dynamic> _read(String? value) {
    if (value == null || value.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      // A damaged cache is never presented as a quote.
    }
    return <String, dynamic>{};
  }
}
