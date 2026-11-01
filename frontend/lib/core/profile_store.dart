import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_persistence_policy.dart';

class ProfileStore extends ChangeNotifier {
  ProfileStore._();

  static final ProfileStore instance = ProfileStore._();

  static const _nameKey = 'profile_name';
  static const _emailKey = 'profile_email';
  static const _phoneKey = 'profile_phone';
  static const _imagePathKey = 'profile_image_path';

  // These values shipped as visual placeholders in an early prototype. They
  // must never be presented as real user data in production.
  static const _legacyPlaceholderEmail = 'user@goldbrain.app';
  static const _legacyPlaceholderPhone = '+98 912 000 0000';

  String name = 'GoldBrain User';
  String email = '';
  String phone = '';
  String? imagePath;

  bool isLoaded = false;
  Map<String, dynamic>? _backendUser;
  bool _backendManaged = false;
  int _loadRevision = 0;

  bool get hasBackendIdentity => _backendUser != null;
  String? get backendUserId => _backendUser?['public_id']?.toString();
  String _preferenceKey(String suffix) => !_backendManaged
      ? 'profile_$suffix'
      : 'profile.${backendUserId ?? 'guest'}.$suffix';

  /// Server identity stays in memory. Local avatar/contact preferences belong
  /// to one account and cannot leak into the next account after logout.
  Future<void> applyBackendUser(Map<String, dynamic>? user) async {
    _backendManaged = true;
    _backendUser = user == null ? null : Map.unmodifiable(user);
    name = user?['display_name']?.toString().trim() ?? 'GoldBrain User';
    email = user?['email']?.toString().trim() ?? '';
    phone = '';
    imagePath = null;
    notifyListeners();
    await load();
  }

  bool get hasValidImage {
    final path = imagePath;
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  Future<void> load() async {
    final revision = ++_loadRevision;
    final preferences = await SharedPreferences.getInstance();
    if (revision != _loadRevision) return;

    if (_backendManaged) {
      name =
          _backendUser?['display_name']?.toString().trim() ??
          preferences.getString(_preferenceKey('name')) ??
          'GoldBrain User';
      email =
          _backendUser?['email']?.toString().trim() ??
          preferences.getString(_preferenceKey('email')) ??
          '';
      phone = preferences.getString(_preferenceKey('phone')) ?? '';
      imagePath = preferences.getString(_preferenceKey('image_path'));
      isLoaded = true;
      notifyListeners();
      return;
    }

    name = preferences.getString(_nameKey) ?? 'GoldBrain User';
    final storedEmail = preferences.getString(_emailKey)?.trim() ?? '';
    final storedPhone = preferences.getString(_phoneKey)?.trim() ?? '';
    email = storedEmail == _legacyPlaceholderEmail ? '' : storedEmail;
    phone = storedPhone == _legacyPlaceholderPhone ? '' : storedPhone;
    imagePath = preferences.getString(_imagePathKey);

    if (LocalPersistencePolicy.instance.canWrite &&
        storedEmail == _legacyPlaceholderEmail) {
      await preferences.remove(_emailKey);
    }
    if (LocalPersistencePolicy.instance.canWrite &&
        storedPhone == _legacyPlaceholderPhone) {
      await preferences.remove(_phoneKey);
    }

    isLoaded = true;
    notifyListeners();
  }

  Future<void> save({
    required String name,
    required String email,
    required String phone,
    String? imagePath,
  }) async {
    final preferences = await SharedPreferences.getInstance();

    this.name =
        _backendUser?['display_name']?.toString() ??
        (name.trim().isEmpty ? 'GoldBrain User' : name.trim());
    this.email = _backendUser?['email']?.toString() ?? email.trim();
    this.phone = phone.trim();

    if (imagePath != null) {
      this.imagePath = imagePath;
    }

    if (!LocalPersistencePolicy.instance.canWrite) {
      notifyListeners();
      return;
    }
    if (!hasBackendIdentity) {
      await preferences.setString(_preferenceKey('name'), this.name);
      await preferences.setString(_preferenceKey('email'), this.email);
    }
    await preferences.setString(_preferenceKey('phone'), this.phone);

    if (this.imagePath != null && this.imagePath!.isNotEmpty) {
      await preferences.setString(
        _preferenceKey('image_path'),
        this.imagePath!,
      );
    }

    notifyListeners();
  }

  Future<void> removeImage() async {
    final preferences = await SharedPreferences.getInstance();

    imagePath = null;
    if (LocalPersistencePolicy.instance.canWrite) {
      await preferences.remove(_preferenceKey('image_path'));
    }

    notifyListeners();
  }
}
