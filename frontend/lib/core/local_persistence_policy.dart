import 'package:flutter/foundation.dart';

/// Process-wide write gate for GoldBrain-owned local preferences.
///
/// A finite retention policy is activated only after explicit confirmation.
/// Once its deadline is reached, stores may continue to work in memory but
/// must not recreate persistent keys until the user chooses Forever.
class LocalPersistencePolicy extends ChangeNotifier {
  LocalPersistencePolicy._();

  static final LocalPersistencePolicy instance = LocalPersistencePolicy._();

  bool _suspended = false;

  bool get isSuspended => _suspended;
  bool get canWrite => !_suspended;

  void setSuspended(bool value) {
    if (_suspended == value) return;
    _suspended = value;
    notifyListeners();
  }
}
