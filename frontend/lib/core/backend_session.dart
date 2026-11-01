import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'backend_api_client.dart';

abstract class RefreshTokenVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureRefreshTokenVault implements RefreshTokenVault {
  SecureRefreshTokenVault(String backend)
    : key = 'goldbrain.refresh.v1.${Uri.encodeComponent(backend)}';
  final String key;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String token) => storage.write(key: key, value: token);
  @override
  Future<void> delete() => storage.delete(key: key);
}

class BackendSession extends ChangeNotifier {
  BackendSession(this.api, {RefreshTokenVault? vault})
    : vault = vault ?? SecureRefreshTokenVault(api.config.baseUri.toString()) {
    api.renewSession = renew;
    api.sessionExpired = () {
      unawaited(expire());
    };
  }
  final GoldBrainBackendClient api;
  final RefreshTokenVault vault;
  Map<String, dynamic>? user;
  String? restoreError;
  String? _refresh;
  Future<bool>? _renewing;
  Future<void> _vaultQueue = Future<void>.value();
  bool restoring = true;
  bool _disposed = false;
  int _generation = 0;
  bool get authenticated => user != null && api.accessToken.isNotEmpty;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    final epoch = _generation;
    restoring = true;
    restoreError = null;
    _changed();
    try {
      final token = await vault.read();
      if (_disposed || epoch != _generation) return;
      _refresh = token;
      if (_refresh != null && _refresh!.isNotEmpty) await renew();
    } catch (_) {
      restoreError = 'restore_failed';
    } finally {
      restoring = false;
      _changed();
    }
  }

  Future<void> signIn(String email, String password) async {
    final epoch = ++_generation;
    final session = await api.login(
      email: email,
      password: password,
      activate: false,
    );
    if (_disposed || epoch != _generation) return;
    await _accept(session, epoch);
  }

  Future<void> verifyEmail(
    String email,
    String code,
    String newPassword,
  ) async {
    final epoch = ++_generation;
    final session = await api.confirmEmailVerification(
      email: email,
      code: code,
      newPassword: newPassword,
    );
    if (_disposed || epoch != _generation) return;
    await _accept(session, epoch);
  }

  Future<void> _store(Future<void> Function() action) {
    final operation = _vaultQueue.then((_) => action());
    _vaultQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<bool> _accept(BackendAuthSession session, int epoch) async {
    try {
      // A storage failure must not silently downgrade to plaintext persistence.
      // Serialize writes/deletes so a late rotation cannot resurrect logout.
      await _store(() async {
        if (!_disposed && epoch == _generation) {
          await vault.write(session.refreshToken);
        }
      });
    } catch (_) {
      if (_disposed || epoch != _generation) return false;
      api.setAccessToken(null);
      user = null;
      throw const GoldBrainBackendException(
        'secure_storage',
        'Secure storage unavailable.',
      );
    }
    if (_disposed || epoch != _generation) return false;
    _refresh = session.refreshToken;
    user = Map.unmodifiable(session.user);
    api.setAccessToken(session.accessToken);
    _changed();
    return true;
  }

  Future<bool> renew() {
    final active = _renewing;
    if (active != null) return active;
    return _renewing = _refreshOnce().whenComplete(() => _renewing = null);
  }

  Future<bool> _refreshOnce() async {
    final token = _refresh;
    if (token == null) return false;
    final epoch = _generation;
    try {
      final session = await api.refreshAuth(token, activate: false);
      if (_disposed || epoch != _generation) {
        return false;
      }
      return await _accept(session, epoch);
    } on GoldBrainBackendException catch (error) {
      if (_disposed || epoch != _generation) return false;
      if (['http_401', 'http_403', 'http_422'].contains(error.code)) {
        await expire();
        return false;
      }
      rethrow;
    }
  }

  Future<void> loadProfile() async {
    final epoch = _generation;
    final profile = await api.currentUser();
    if (!_disposed && epoch == _generation && authenticated) {
      user = Map.unmodifiable(profile);
      _changed();
    }
  }

  Future<void> signOut() async {
    // Do not report server logout as successful when the backend is offline.
    await api.logout();
    await expire();
  }

  Future<void> expire() async {
    ++_generation;
    _refresh = null;
    user = null;
    api.setAccessToken(null);
    _changed();
    try {
      await _store(vault.delete);
    } catch (_) {
      restoreError = 'secure_storage';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    api.renewSession = null;
    api.sessionExpired = null;
    super.dispose();
  }
}
