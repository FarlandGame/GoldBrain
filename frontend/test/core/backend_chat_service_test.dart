import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/backend_api_client.dart';
import 'package:goldbrain/core/backend_chat_service.dart';
import 'package:goldbrain/core/gapgpt_service.dart';
import 'package:goldbrain/core/settings_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'chat uses GoldBrain bearer transport, never a client prompt or provider key',
    () async {
      http.Request? captured;
      final api = GoldBrainBackendClient(
        config: GoldBrainBackendConfig(
          baseUri: Uri.parse('http://127.0.0.1:8000'),
          apiKey: '',
        ),
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'text': 'این پاسخ از سرور آمده است.',
              'model': 'free/model',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      api.setAccessToken('synthetic-session-token');
      final service = BackendChatService(api: api)..languageCode = 'persian';
      final answer = await service.createChatCompletion(
        messages: const [AiChatMessage(role: 'user', content: 'سلام')],
        systemPrompt: 'Untrusted client instruction must not be sent.',
        temperature: 0.7,
      );
      expect(answer, contains('از سرور'));
      expect(captured!.url.path, '/api/v1/assistant/chat');
      expect(
        captured!.headers['authorization'],
        'Bearer synthetic-session-token',
      );
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['language'], 'persian');
      expect(body['temperature'], 0.7);
      expect(body['display_currency'], 'IRT');
      expect(body.containsKey('systemPrompt'), isFalse);
      expect(body.containsKey('api_key'), isFalse);
      expect(captured!.body, isNot(contains('Untrusted client instruction')));
      service.close();
      api.close();
    },
  );

  for (final status in [401, 429, 503]) {
    test('HTTP $status stays a sanitized chat error', () async {
      final api = GoldBrainBackendClient(
        config: GoldBrainBackendConfig(
          baseUri: Uri.parse('http://127.0.0.1:8000'),
          apiKey: '',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'synthetic-secret-never-display'}),
            status,
          ),
        ),
      );
      final service = BackendChatService(api: api);
      await expectLater(
        service.createChatCompletion(
          messages: const [AiChatMessage(role: 'user', content: 'سلام')],
          systemPrompt: '',
        ),
        throwsA(
          isA<GapGptException>()
              .having(
                (e) => e.code,
                'code',
                status == 401
                    ? 'session_required'
                    : status == 429
                    ? 'rate_limited'
                    : 'service_unavailable',
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains('synthetic-secret')),
              ),
        ),
      );
      service.close();
      api.close();
    });

    for (final currency in ['IRT', 'USD']) {
      test('chat forwards resolved $currency display preference', () async {
        final settings = SettingsStore.instance;
        final oldCurrency = settings.currencyCode;
        settings.currencyCode = currency;
        addTearDown(() => settings.currencyCode = oldCurrency);
        final api = GoldBrainBackendClient(
          config: GoldBrainBackendConfig(
            baseUri: Uri.parse('http://127.0.0.1:8000'),
            apiKey: '',
          ),
          client: MockClient((request) async {
            expect(jsonDecode(request.body)['display_currency'], currency);
            return http.Response('{"text":"OK"}', 200);
          }),
        );
        final service = BackendChatService(api: api);
        await service.createChatCompletion(
          messages: const [AiChatMessage(role: 'user', content: 'Hi')],
          systemPrompt: '',
        );
        service.close();
        api.close();
      });
    }
  }
}
