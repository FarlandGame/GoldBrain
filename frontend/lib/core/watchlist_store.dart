import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_persistence_policy.dart';

class WatchlistStore extends ChangeNotifier {
  WatchlistStore._();

  static final WatchlistStore instance = WatchlistStore._();

  static const _favoriteSymbolsKey = 'watchlist.favorite_symbols';

  static const Set<String> _defaultSymbols = {'GOLD18', 'XAUUSD', 'USD', 'BTC'};

  SharedPreferences? _preferences;
  bool _loaded = false;

  final Set<String> _favoriteSymbols = {..._defaultSymbols};

  bool get loaded => _loaded;

  Set<String> get favoriteSymbols => Set.unmodifiable(_favoriteSymbols);

  bool isFavorite(String symbol) {
    return _favoriteSymbols.contains(symbol);
  }

  Future<void> load() async {
    _preferences ??= await SharedPreferences.getInstance();
    final prefs = _preferences!;

    final savedSymbols = prefs.getStringList(_favoriteSymbolsKey);

    _favoriteSymbols
      ..clear()
      ..addAll(savedSymbols ?? _defaultSymbols);

    _loaded = true;
    notifyListeners();
  }

  Future<bool> toggleFavorite(String symbol) async {
    _preferences ??= await SharedPreferences.getInstance();

    final added = !_favoriteSymbols.contains(symbol);

    if (added) {
      _favoriteSymbols.add(symbol);
    } else {
      _favoriteSymbols.remove(symbol);
    }

    await _save();
    notifyListeners();

    return added;
  }

  Future<void> addFavorite(String symbol) async {
    if (_favoriteSymbols.add(symbol)) {
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeFavorite(String symbol) async {
    if (_favoriteSymbols.remove(symbol)) {
      await _save();
      notifyListeners();
    }
  }

  Future<void> resetDefaults() async {
    _favoriteSymbols
      ..clear()
      ..addAll(_defaultSymbols);

    await _save();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _favoriteSymbols.clear();

    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    if (!LocalPersistencePolicy.instance.canWrite) return;
    _preferences ??= await SharedPreferences.getInstance();

    final symbols = _favoriteSymbols.toList()..sort();

    await _preferences!.setStringList(_favoriteSymbolsKey, symbols);
  }
}
