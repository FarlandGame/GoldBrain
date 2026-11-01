import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/backend_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final flow in ['register', 'verification', 'reset']) {
    testWidgets('$flow waits for an email response beyond 15 seconds', (
      tester,
    ) async {
      var requests = 0;
      String? requestedPath;
      final client = GoldBrainBackendClient(
        config: GoldBrainBackendConfig(
          baseUri: Uri.parse('http://127.0.0.1:8000'),
          apiKey: '',
        ),
        client: MockClient((request) async {
          requests++;
          requestedPath = request.url.path;
          await Future<void>.delayed(const Duration(seconds: 16));
          return _emailResponse(flow);
        }),
      );
      BackendEmailChallenge? challenge;
      Object? failure;
      _requestEmail(client, flow).then<void>(
        (value) {
          challenge = value;
        },
        onError: (Object error) {
          failure = error;
        },
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      final waitingAt15Seconds = challenge == null && failure == null;
      await tester.pump(const Duration(seconds: 1));
      expect(waitingAt15Seconds, isTrue);
      expect(requestedPath, _emailPath(flow));
      expect(failure, isNull);
      expect(challenge?.email, 'alice@example.com');
      expect(challenge?.resendAfterSeconds, 60);
      expect(requests, 1);
      client.close();
    });
  }

  testWidgets('email wait is bounded at 60 seconds without automatic resend', (
    tester,
  ) async {
    var requests = 0;
    final client = GoldBrainBackendClient(
      config: GoldBrainBackendConfig(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        apiKey: '',
      ),
      client: MockClient((request) async {
        requests++;
        await Future<void>.delayed(const Duration(seconds: 70));
        return _emailResponse('verification');
      }),
    );
    Object? failure;
    client
        .requestEmailVerification('alice@example.com')
        .then<void>(
          (_) {},
          onError: (Object error) {
            failure = error;
          },
        );
    await tester.pump();
    await tester.pump(const Duration(seconds: 59));
    final failureBeforeDeadline = failure;
    await tester.pump(const Duration(seconds: 1));
    final failureAtDeadline = failure;
    await tester.pump(const Duration(seconds: 10));
    expect(failureBeforeDeadline, isNull);
    expect(
      failureAtDeadline,
      isA<GoldBrainBackendException>().having(
        (error) => error.code,
        'code',
        'timeout',
      ),
    );
    expect(requests, 1);
    client.close();
  });

  for (final route in ['health', 'login']) {
    testWidgets('$route retains the ordinary 15-second timeout', (
      tester,
    ) async {
      var requests = 0;
      final client = GoldBrainBackendClient(
        config: GoldBrainBackendConfig(
          baseUri: Uri.parse('http://127.0.0.1:8000'),
          apiKey: '',
        ),
        client: MockClient((request) async {
          requests++;
          await Future<void>.delayed(const Duration(seconds: 16));
          return http.Response('{}', 200);
        }),
      );
      Object? failure;
      final Future<Object?> pending = route == 'health'
          ? client.health()
          : client.login(email: 'alice@example.com', password: 'Synthetic1234');
      pending.then<void>(
        (_) {},
        onError: (Object error) {
          failure = error;
        },
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 14));
      expect(failure, isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(
        failure,
        isA<GoldBrainBackendException>().having(
          (error) => error.code,
          'code',
          'timeout',
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(requests, 1);
      client.close();
    });
  }

  test('health parses backend contract', () async {
    final client = GoldBrainBackendClient(
      config: GoldBrainBackendConfig(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        apiKey: 'private-alpha-key',
      ),
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/health');
        expect(request.headers.containsKey('X-GoldBrain-Key'), isFalse);
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'version': '0.1.0-phase1',
            'environment': 'test',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.health();
    expect(result.status, 'ok');
    expect(result.version, '0.1.0-phase1');
  });

  test('quote request sends private key and parses partial batches', () async {
    final client = GoldBrainBackendClient(
      config: GoldBrainBackendConfig(
        baseUri: Uri.parse('http://127.0.0.1:8000'),
        apiKey: 'private-alpha-key',
      ),
      client: MockClient((request) async {
        expect(request.headers['X-GoldBrain-Key'], 'private-alpha-key');
        expect(
          request.url.queryParametersAll['symbols'],
          containsAll(['XAU', 'BTC']),
        );
        return http.Response(
          jsonEncode({
            'requested_symbols': ['XAU', 'BTC'],
            'quotes': [
              {
                'symbol': 'XAU',
                'name': 'Gold',
                'currency': 'USD',
                'price': 3600.5,
                'updated_at': '2026-09-08T08:00:00Z',
                'provider': 'gold-api',
                'change_percent': null,
                'upstream_source': 'gold-api.com',
              },
            ],
            'issues': [
              {'symbol': 'BTC', 'message': 'Provider unavailable'},
            ],
            'partial': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.fetchQuotes(['xau', 'btc']);
    expect(result.partial, isTrue);
    expect(result.quotes['XAU']?.price, 3600.5);
    expect(result.issues['BTC'], 'Provider unavailable');
  });
}

String _emailPath(String flow) => switch (flow) {
  'register' => '/api/v1/auth/register',
  'verification' => '/api/v1/auth/email-verification/request',
  _ => '/api/v1/auth/password-reset/request',
};

Future<BackendEmailChallenge> _requestEmail(
  GoldBrainBackendClient client,
  String flow,
) => switch (flow) {
  'register' => client.register(
    email: 'alice@example.com',
    password: 'Synthetic1234',
    displayName: 'Alice',
  ),
  'verification' => client.requestEmailVerification('alice@example.com'),
  _ => client.requestPasswordReset('alice@example.com'),
};

http.Response _emailResponse(String flow) => http.Response(
  jsonEncode({
    'email': 'alice@example.com',
    'verification_required': true,
    'accepted': true,
    'expires_in': 900,
    'resend_after': 60,
  }),
  flow == 'register' ? 201 : 200,
);
