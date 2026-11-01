import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/supabase_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'signs in with Supabase password auth without persisting secrets',
    () async {
      late http.Request captured;
      final service = SupabaseAuthService(
        projectUrl: 'https://example.supabase.co/',
        publishableKey: 'publishable-test-key',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'access_token': 'session-token',
              'user': {
                'email': 'person@example.com',
                'user_metadata': {'display_name': 'Person'},
              },
            }),
            200,
          );
        }),
      );

      final result = await service.signIn(
        email: 'person@example.com',
        password: 'password123',
      );

      expect(
        captured.url.toString(),
        'https://example.supabase.co/auth/v1/token?grant_type=password',
      );
      expect(captured.headers['apikey'], 'publishable-test-key');
      expect(result.authenticated, isTrue);
      expect(result.displayName, 'Person');
    },
  );

  test('reports email confirmation after sign-up without a session', () async {
    final service = SupabaseAuthService(
      projectUrl: 'https://example.supabase.co',
      publishableKey: 'publishable-test-key',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode({
            'user': {
              'email': 'new@example.com',
              'user_metadata': {'display_name': 'New User'},
            },
          }),
          200,
        );
      }),
    );

    final result = await service.signUp(
      email: 'new@example.com',
      password: 'password123',
      displayName: 'New User',
    );

    expect(result.authenticated, isFalse);
    expect(result.requiresEmailConfirmation, isTrue);
  });

  test('rejects fake login when Supabase is not configured', () async {
    final service = SupabaseAuthService(
      projectUrl: '',
      publishableKey: '',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      () => service.signIn(email: 'person@example.com', password: 'password'),
      throwsA(
        isA<AuthServiceException>().having(
          (error) => error.code,
          'code',
          'not_configured',
        ),
      ),
    );
  });
}
