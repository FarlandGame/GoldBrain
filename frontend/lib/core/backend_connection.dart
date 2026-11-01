import 'dart:async';

import 'backend_api_client.dart';
import 'backend_session.dart';
import 'profile_store.dart';

/// The original screens share one authenticated transport and secure session.
/// Only the refresh token enters the OS vault; profile preferences are separate.
class BackendConnection {
  BackendConnection({
    GoldBrainBackendClient? api,
    RefreshTokenVault? vault,
    ProfileStore? profileStore,
  }) : api = api ?? GoldBrainBackendClient(),
       profile = profileStore ?? ProfileStore.instance {
    session = BackendSession(this.api, vault: vault);
    session.addListener(_sessionChanged);
  }

  static final BackendConnection instance = BackendConnection();

  final GoldBrainBackendClient api;
  late final BackendSession session;
  final ProfileStore profile;
  Future<void>? _restoration;
  bool _disposed = false;

  void _sessionChanged() {
    // Identity changes immediately; a preferences failure never downgrades
    // authentication to locally stored account details.
    unawaited(_syncProfile().catchError((Object _) {}));
  }

  Future<void> _syncProfile() =>
      profile.applyBackendUser(session.authenticated ? session.user : null);

  Future<void> restore() => _restoration ??= _restore();

  Future<void> _restore() async {
    await session.restore();
    if (session.authenticated) {
      try {
        await session.loadProfile();
      } catch (_) {
        // A transient /me failure does not discard a successfully rotated
        // secure session. The next account refresh can retry it.
      }
    }
    try {
      await _syncProfile();
    } catch (_) {
      // Storage errors are handled by the secure session; local extras are
      // optional and must not prevent the original startup screens opening.
    }
  }

  Future<BackendEmailChallenge?> signIn(
    String email,
    String password, {
    String? name,
  }) async {
    if (name != null) {
      return api.register(email: email, password: password, displayName: name);
    }
    await session.signIn(email, password);
    if (!session.authenticated) return null;
    await session.loadProfile();
    await _syncProfile();
    return null;
  }

  Future<void> verifyEmail(
    String email,
    String code,
    String newPassword,
  ) async {
    await session.verifyEmail(email, code, newPassword);
    if (!session.authenticated) return;
    await session.loadProfile();
    await _syncProfile();
  }

  Future<void> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    await api.confirmPasswordReset(
      email: email,
      code: code,
      newPassword: newPassword,
    );
    await session.expire();
    await _syncProfile();
  }

  Future<void> refreshProfile() async {
    if (!session.authenticated) return;
    await session.loadProfile();
    await _syncProfile();
  }

  Future<void> signOut() async {
    if (session.authenticated) {
      await session.signOut();
    } else {
      await session.expire();
    }
    await _syncProfile();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    session.removeListener(_sessionChanged);
    session.dispose();
    api.close();
  }
}
