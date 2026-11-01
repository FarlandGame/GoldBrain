import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/backend_api_client.dart';
import 'package:goldbrain/core/backend_connection.dart';
import 'package:goldbrain/core/backend_session.dart';
import 'package:goldbrain/core/local_persistence_policy.dart';
import 'package:goldbrain/core/profile_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements RefreshTokenVault {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String token) async => this.token = token;
  @override
  Future<void> delete() async => token = null;
}

Map<String, dynamic> _user(String id, {String name = 'Server identity'}) => {
  'public_id': id,
  'display_name': name,
  'email': '$id@example.com',
  'role': 'user',
  'mfa_enabled': false,
  'email_verified': false,
};

Map<String, dynamic> _tokens(String id) => {
  'user': _user(id, name: 'Sign-in response'),
  'access_token': 'access-$id',
  'refresh_token': 'refresh-$id',
  'expires_in_seconds': 900,
  'session_id': 'session-$id',
};

BackendConnection _connection(
  _Vault vault,
  Future<http.Response> Function(http.Request) handler,
) => BackendConnection(
  api: GoldBrainBackendClient(
    config: GoldBrainBackendConfig(
      baseUri: Uri.parse('http://127.0.0.1:8000'),
      apiKey: '',
    ),
    client: MockClient(handler),
  ),
  vault: vault,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalPersistencePolicy.instance.setSuspended(false);
    await ProfileStore.instance.applyBackendUser(null);
  });

  for (final register in [false, true]) {
    test(
      '${register ? 'registration' : 'login'} uses GoldBrain and /auth/me',
      () async {
        final requests = <http.Request>[];
        final vault = _Vault();
        final connection = _connection(vault, (request) async {
          requests.add(request);
          if (request.url.path.endsWith('/me')) {
            expect(request.headers['authorization'], 'Bearer access-alice');
            return http.Response(jsonEncode(_user('alice')), 200);
          }
          if (request.url.path.endsWith('/logout'))
            return http.Response('', 204);
          if (request.url.path.endsWith('/register')) {
            return http.Response(
              jsonEncode({
                'email': 'alice@example.com',
                'verification_required': true,
                'expires_in': 900,
                'resend_after': 60,
              }),
              201,
            );
          }
          return http.Response(jsonEncode(_tokens('alice')), 200);
        });
        addTearDown(connection.dispose);

        final challenge = await connection.signIn(
          'alice@example.com',
          'Password1234',
          name: register ? 'Alice' : null,
        );
        expect(
          requests.first.url.path,
          '/api/v1/auth/${register ? 'register' : 'login'}',
        );
        expect(jsonDecode(requests.first.body)['password'], 'Password1234');
        if (register) {
          expect(challenge?.email, 'alice@example.com');
          expect(connection.session.authenticated, isFalse);
          expect(vault.token, isNull);
          expect(ProfileStore.instance.email, isEmpty);
          expect(requests, hasLength(1));
          await connection.verifyEmail(
            'alice@example.com',
            '123456',
            'Password1234',
          );
          expect(
            requests[1].url.path,
            '/api/v1/auth/email-verification/confirm',
          );
          expect(jsonDecode(requests[1].body)['code'], '123456');
          expect(jsonDecode(requests[1].body)['new_password'], 'Password1234');
        }
        expect(ProfileStore.instance.name, 'Server identity');
        expect(ProfileStore.instance.email, 'alice@example.com');
        expect(connection.session.authenticated, isTrue);
        expect(vault.token, 'refresh-alice');

        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getKeys().where((key) => key.contains('token')),
          isEmpty,
        );
        expect(
          preferences.getKeys().map(preferences.get).join(),
          isNot(contains('Password1234')),
        );
        expect(
          preferences.getKeys().map(preferences.get).join(),
          isNot(contains('access-alice')),
        );
        await connection.signOut();
        expect(connection.session.authenticated, isFalse);
        expect(vault.token, isNull);
        expect(ProfileStore.instance.email, isEmpty);
        expect(ProfileStore.instance.hasBackendIdentity, isFalse);
      },
    );
  }

  test(
    'a successful password reset clears secure session and returns no tokens',
    () async {
      final vault = _Vault();
      final connection = _connection(vault, (request) async {
        if (request.url.path.endsWith('/password-reset/request')) {
          expect(jsonDecode(request.body), {'email': 'alice@example.com'});
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response(
            jsonEncode({
              'accepted': true,
              'expires_in': 900,
              'resend_after': 60,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/password-reset/confirm')) {
          expect(jsonDecode(request.body), {
            'email': 'alice@example.com',
            'code': '123456',
            'new_password': 'NewPassword5678',
          });
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response('', 204);
        }
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/me')
                ? _user('alice')
                : _tokens('alice'),
          ),
          200,
        );
      });
      addTearDown(connection.dispose);
      await connection.signIn('alice@example.com', 'Password1234');
      final challenge = await connection.api.requestPasswordReset(
        'alice@example.com',
      );
      expect(challenge.expiresInSeconds, 900);
      expect(challenge.resendAfterSeconds, 60);
      await connection.resetPassword(
        'alice@example.com',
        '123456',
        'NewPassword5678',
      );
      expect(connection.session.authenticated, isFalse);
      expect(connection.api.accessToken, isEmpty);
      expect(vault.token, isNull);
      expect(ProfileStore.instance.email, isEmpty);
    },
  );

  test(
    'email errors retain HTTP compatibility, safe server code and resend cooldown',
    () async {
      final connection = _connection(
        _Vault(),
        (_) async => http.Response(
          jsonEncode({
            'detail': {
              'code': 'otp_resend_limited',
              'message': 'sensitive raw response',
            },
          }),
          429,
          headers: {'retry-after': '42'},
        ),
      );
      addTearDown(connection.dispose);
      await expectLater(
        connection.api.requestEmailVerification('alice@example.com'),
        throwsA(
          isA<GoldBrainBackendException>()
              .having((error) => error.code, 'HTTP code', 'http_429')
              .having(
                (error) => error.serverCode,
                'server code',
                'otp_resend_limited',
              )
              .having((error) => error.retryAfterSeconds, 'cooldown', 42)
              .having(
                (error) => error.message,
                'safe message',
                isNot(contains('sensitive')),
              ),
        ),
      );
    },
  );

  test(
    'registration rejects old token responses and never activates an unverified account',
    () async {
      final vault = _Vault();
      final connection = _connection(
        vault,
        (_) async => http.Response(jsonEncode(_tokens('alice')), 201),
      );
      addTearDown(connection.dispose);
      await expectLater(
        connection.signIn('alice@example.com', 'Password1234', name: 'Alice'),
        throwsA(
          isA<GoldBrainBackendException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );
      expect(connection.session.authenticated, isFalse);
      expect(vault.token, isNull);
    },
  );

  test(
    'startup rotates the secure refresh token once and obtains /auth/me',
    () async {
      final vault = _Vault()..token = 'previous-refresh';
      final paths = <String>[];
      final connection = _connection(vault, (request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/refresh')) {
          expect(jsonDecode(request.body)['refresh_token'], 'previous-refresh');
          return http.Response(jsonEncode(_tokens('alice')), 200);
        }
        return http.Response(jsonEncode(_user('alice')), 200);
      });
      addTearDown(connection.dispose);

      await Future.wait([connection.restore(), connection.restore()]);
      expect(paths, ['/api/v1/auth/refresh', '/api/v1/auth/me']);
      expect(ProfileStore.instance.name, 'Server identity');
      expect(vault.token, 'refresh-alice');
    },
  );

  test(
    'offline restore preserves secure token without showing an authenticated identity',
    () async {
      final vault = _Vault()..token = 'previous-refresh';
      final connection = _connection(vault, (_) async {
        throw http.ClientException('Offline');
      });
      addTearDown(connection.dispose);
      await connection.restore();
      expect(vault.token, 'previous-refresh');
      expect(connection.session.authenticated, isFalse);
      expect(connection.session.restoreError, 'restore_failed');
      expect(ProfileStore.instance.email, isEmpty);
    },
  );

  test(
    'local profile extras are isolated per account and cannot replace server identity',
    () async {
      final profile = ProfileStore.instance;
      await profile.applyBackendUser(_user('alice'));
      await profile.save(
        name: 'Local forged name',
        email: 'other@example.com',
        phone: 'alice-local-phone',
        imagePath: 'alice-avatar.png',
      );
      expect(profile.email, 'alice@example.com');
      expect(profile.name, 'Server identity');
      await profile.applyBackendUser(_user('bob'));
      expect(profile.phone, isEmpty);
      expect(profile.imagePath, isNull);
      await profile.applyBackendUser(_user('alice'));
      expect(profile.phone, 'alice-local-phone');
      expect(profile.imagePath, 'alice-avatar.png');
      await profile.applyBackendUser(null);
      expect(profile.email, isEmpty);
      expect(profile.phone, isEmpty);
      expect(profile.imagePath, isNull);
    },
  );

  test(
    'server logout failure keeps the session and does not pretend it was revoked',
    () async {
      final vault = _Vault();
      final connection = _connection(vault, (request) async {
        if (request.url.path.endsWith('/logout'))
          return http.Response('{}', 503);
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/me')
                ? _user('alice')
                : _tokens('alice'),
          ),
          200,
        );
      });
      addTearDown(connection.dispose);
      await connection.signIn('alice@example.com', 'Password1234');
      await expectLater(
        connection.signOut(),
        throwsA(isA<GoldBrainBackendException>()),
      );
      expect(connection.session.authenticated, isTrue);
      expect(vault.token, 'refresh-alice');
      expect(ProfileStore.instance.email, 'alice@example.com');
    },
  );
}
