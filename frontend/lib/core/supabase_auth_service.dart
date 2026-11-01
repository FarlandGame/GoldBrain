import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AuthResult {
  const AuthResult({
    required this.email,
    required this.displayName,
    required this.authenticated,
    required this.requiresEmailConfirmation,
  });

  final String email;
  final String displayName;
  final bool authenticated;
  final bool requiresEmailConfirmation;
}

class AuthServiceException implements Exception {
  const AuthServiceException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Minimal Supabase Auth client for email/password sign-up and sign-in.
///
/// Passwords and access tokens are deliberately never persisted here. A later
/// session-restoration feature must use OS-backed secure storage, not
/// SharedPreferences.
class SupabaseAuthService {
  SupabaseAuthService({
    required String projectUrl,
    required String publishableKey,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _projectUrl = projectUrl.replaceFirst(RegExp(r'/+$'), ''),
       _publishableKey = publishableKey.trim(),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  factory SupabaseAuthService.fromEnvironment({http.Client? client}) {
    return SupabaseAuthService(
      projectUrl: Platform.environment['SUPABASE_URL'] ?? '',
      publishableKey:
          Platform.environment['SUPABASE_PUBLISHABLE_KEY'] ??
          Platform.environment['SUPABASE_ANON_KEY'] ??
          '',
      client: client,
    );
  }

  final String _projectUrl;
  final String _publishableKey;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  bool get isConfigured => _projectUrl.isNotEmpty && _publishableKey.isNotEmpty;

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final body = await _post('/auth/v1/token?grant_type=password', {
      'email': email.trim(),
      'password': password,
    });

    final accessToken = body['access_token'];
    final user = body['user'];
    if (accessToken is! String || accessToken.isEmpty || user is! Map) {
      throw const AuthServiceException(
        'invalid_response',
        'The authentication service returned an invalid session.',
      );
    }

    return AuthResult(
      email: _userEmail(user, email),
      displayName: _userName(user),
      authenticated: true,
      requiresEmailConfirmation: false,
    );
  }

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final body = await _post('/auth/v1/signup', {
      'email': email.trim(),
      'password': password,
      'data': {'display_name': displayName.trim()},
    });

    final user = body['user'];
    if (user is! Map) {
      throw const AuthServiceException(
        'invalid_response',
        'The authentication service returned an invalid user.',
      );
    }
    final accessToken = body['access_token'];
    final authenticated = accessToken is String && accessToken.isNotEmpty;

    return AuthResult(
      email: _userEmail(user, email),
      displayName: _userName(user, fallback: displayName),
      authenticated: authenticated,
      requiresEmailConfirmation: !authenticated,
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    if (!isConfigured) {
      throw const AuthServiceException(
        'not_configured',
        'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are not configured.',
      );
    }

    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_projectUrl$path'),
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
              'apikey': _publishableKey,
              HttpHeaders.authorizationHeader: 'Bearer $_publishableKey',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AuthServiceException(
        'timeout',
        'The authentication request timed out.',
      );
    } on http.ClientException {
      throw const AuthServiceException(
        'network_error',
        'Could not connect to the authentication service.',
      );
    }

    final body = _decodeObject(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthServiceException(
        _statusCode(response.statusCode),
        _safeError(body, response.statusCode),
      );
    }
    return body;
  }

  Map<String, dynamic> _decodeObject(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // A sanitized invalid-response error is returned by the caller.
    }
    return const {};
  }

  String _statusCode(int status) {
    if (status == 400 || status == 401) return 'invalid_credentials';
    if (status == 422) return 'invalid_registration';
    if (status == 429) return 'rate_limited';
    if (status >= 500) return 'service_unavailable';
    return 'request_failed';
  }

  String _safeError(Map<String, dynamic> body, int status) {
    final raw =
        body['msg'] ??
        body['message'] ??
        body['error_description'] ??
        body['error'];
    if (raw is String && raw.trim().isNotEmpty) {
      final message = raw
          .replaceAll(
            RegExp(r'Bearer\s+\S+', caseSensitive: false),
            '[redacted]',
          )
          .trim();
      return message.length <= 240 ? message : '${message.substring(0, 240)}…';
    }
    return 'Authentication failed (HTTP $status).';
  }

  String _userEmail(Map user, String fallback) {
    final value = user['email'];
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : fallback.trim();
  }

  String _userName(Map user, {String fallback = ''}) {
    final metadata = user['user_metadata'];
    final value = metadata is Map ? metadata['display_name'] : null;
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : fallback.trim();
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
