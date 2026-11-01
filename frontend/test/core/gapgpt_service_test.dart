import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/gapgpt_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fromEnvironment accepts mobile compile-time configuration', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: const <String, String>{'content-type': 'text/event-stream'},
      );
    });
    final service = GapGptService.fromEnvironment(
      client: client,
      compileTimeEnvironment: const <String, String>{
        'GAPGPT_API_KEY': 'compiled-test-key',
        'GAPGPT_BASE_URL': 'https://openrouter.ai/api/v1',
        'GAPGPT_MODEL': 'openrouter/free',
      },
      processEnvironment: const <String, String>{},
      isWindows: false,
    );

    final answer = await service.createChatCompletion(
      messages: const <AiChatMessage>[
        AiChatMessage(role: 'user', content: 'Hello'),
      ],
      systemPrompt: 'Be brief.',
    );

    expect(answer, 'ok');
    expect(
      capturedRequest.headers['authorization'],
      'Bearer compiled-test-key',
    );
    expect(
      capturedRequest.url.toString(),
      'https://openrouter.ai/api/v1/chat/completions',
    );
  });

  test(
    'fromEnvironment prefers current Windows User OpenRouter configuration',
    () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: const <String, String>{'content-type': 'text/event-stream'},
        );
      });
      final service = GapGptService.fromEnvironment(
        client: client,
        processEnvironment: const <String, String>{
          'GAPGPT_API_KEY': 'stale-key',
          'GAPGPT_BASE_URL': 'https://api.gapgpt.app/v1',
          'GAPGPT_MODEL': 'gpt-4o-mini',
        },
        isWindows: true,
        windowsUserEnvironmentLoader: (_) => const <String, String>{
          'GAPGPT_API_KEY': 'fresh-key',
          'GAPGPT_BASE_URL': 'https://openrouter.ai/api/v1',
          'GAPGPT_MODEL': 'openrouter/free',
        },
      );

      final answer = await service.createChatCompletion(
        messages: const <AiChatMessage>[
          AiChatMessage(role: 'user', content: 'Hello'),
        ],
        systemPrompt: 'Be brief.',
      );

      expect(answer, 'ok');
      expect(service.model, 'openrouter/free');
      expect(service.isOpenRouterFreeRouter, isTrue);
      expect(
        capturedRequest.url.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
      expect(capturedRequest.headers['authorization'], 'Bearer fresh-key');
    },
  );

  test('configuration readiness rejects a non-HTTPS endpoint', () {
    final service = GapGptService(
      apiKey: 'test-key',
      baseUrl: 'http://example.test/v1',
    );
    addTearDown(service.close);

    expect(service.isConfigured, isFalse);
  });

  test('sends an OpenAI-compatible chat completion request', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': 'Test '},
            },
          ],
        })}\n\n'
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': 'answer'},
            },
          ],
        })}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream; charset=utf-8'},
      );
    });
    final service = GapGptService(apiKey: 'test-key', client: client);

    final answer = await service.createChatCompletion(
      messages: const [AiChatMessage(role: 'user', content: 'Hello')],
      systemPrompt: 'Be helpful.',
    );

    expect(answer, 'Test answer');
    expect(
      capturedRequest.url.toString(),
      'https://api.gapgpt.app/v1/chat/completions',
    );
    expect(capturedRequest.headers['authorization'], 'Bearer test-key');
    final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(payload['model'], 'gpt-4o');
    expect(payload['stream'], isTrue);
    expect((payload['messages'] as List), hasLength(2));
  });

  test('exposes streamed content incrementally', () async {
    final client = MockClient((_) async {
      return http.Response(
        'data: {"choices":[{"delta":{"content":"one"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":" two"}}]}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final service = GapGptService(apiKey: 'test-key', client: client);

    final chunks = await service
        .createChatCompletionStream(
          messages: const [AiChatMessage(role: 'user', content: 'Hello')],
          systemPrompt: 'Be helpful.',
          temperature: 0.8,
        )
        .toList();

    expect(chunks, ['one', ' two']);
  });

  test(
    'passes an optional JSON response format to compatible providers',
    () async {
      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"choices":[{"message":{"content":"{\\"ok\\":true}"}}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = GapGptService(apiKey: 'test-key', client: client);

      await service.createChatCompletion(
        messages: const [AiChatMessage(role: 'user', content: 'Return JSON')],
        systemPrompt: 'Return JSON.',
        responseFormat: const <String, Object?>{'type': 'json_object'},
      );

      expect(payload['response_format'], <String, Object?>{
        'type': 'json_object',
      });
      expect(payload['provider'], isNull);
    },
  );

  test(
    'requires structured-output support from OpenRouter providers',
    () async {
      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"choices":[{"message":{"content":"{\\"ok\\":true}"}}]}',
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final service = GapGptService(
        apiKey: 'test-key',
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'openrouter/free',
        client: client,
      );

      await service.createChatCompletion(
        messages: const <AiChatMessage>[
          AiChatMessage(role: 'user', content: 'Return JSON'),
        ],
        systemPrompt: 'Return JSON.',
        responseFormat: const <String, Object?>{'type': 'json_object'},
      );

      expect(payload['provider'], <String, Object?>{
        'require_parameters': true,
      });
      expect(payload['stream'], isFalse);
    },
  );

  test(
    'validates json_schema completions locally before exposing them',
    () async {
      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          '{"choices":[{"message":{"content":"not json"}}]}',
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final service = GapGptService(
        apiKey: 'test-key',
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'openrouter/free',
        client: client,
        maxAttempts: 1,
      );

      await expectLater(
        service.createChatCompletion(
          messages: const <AiChatMessage>[
            AiChatMessage(role: 'user', content: 'Return schema JSON'),
          ],
          systemPrompt: 'Return JSON only.',
          responseFormat: const <String, Object?>{
            'type': 'json_schema',
            'json_schema': <String, Object?>{
              'name': 'result',
              'strict': true,
              'schema': <String, Object?>{
                'type': 'object',
                'additionalProperties': false,
                'properties': <String, Object?>{
                  'ok': <String, Object?>{'type': 'boolean'},
                },
                'required': <String>['ok'],
              },
            },
          },
        ),
        throwsA(
          isA<GapGptException>().having(
            (error) => error.code,
            'code',
            'invalid_response',
          ),
        ),
      );

      expect(payload['stream'], isFalse);
      expect(payload['provider'], <String, Object?>{
        'require_parameters': true,
      });
      expect(
        (payload['response_format'] as Map<String, dynamic>)['type'],
        'json_schema',
      );
    },
  );

  test(
    'free router retries unsupported structured output with locally validated JSON',
    () async {
      final payloads = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        payloads.add(payload);
        if (payloads.length == 1) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 400,
                'message': 'Provider returned error',
                'metadata': {
                  'raw':
                      'response_format is not supported; diagnostic sk-never-expose-this',
                },
              },
            }),
            400,
          );
        }
        return http.Response(
          '{"choices":[{"message":{"content":"{\\"ok\\":true}"}}]}',
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });
      final service = GapGptService(
        apiKey: 'test-key',
        baseUrl: 'https://openrouter.ai/api/v1',
        model: 'openrouter/free',
        client: client,
        retryDelay: Duration.zero,
      );

      final answer = await service.createChatCompletion(
        messages: const <AiChatMessage>[
          AiChatMessage(role: 'user', content: 'Return JSON'),
        ],
        systemPrompt: 'Return JSON only.',
        responseFormat: const <String, Object?>{'type': 'json_object'},
      );

      expect(jsonDecode(answer), <String, dynamic>{'ok': true});
      expect(payloads, hasLength(2));
      expect(payloads.first['stream'], isFalse);
      expect(payloads.first['response_format'], isNotNull);
      expect(payloads.first['provider'], isNotNull);
      expect(payloads.last['stream'], isFalse);
      expect(payloads.last['response_format'], isNull);
      expect(payloads.last['provider'], isNull);
    },
  );

  test('never exposes nested provider diagnostics for a JSON error', () async {
    final client = MockClient((_) async {
      return http.Response(
        jsonEncode({
          'error': {
            'code': 400,
            'message': 'Provider returned error',
            'metadata': {
              'raw': 'response_format is unsupported for sk-private-diagnostic',
            },
          },
        }),
        400,
      );
    });
    final service = GapGptService(
      apiKey: 'test-key',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'openrouter/free',
      client: client,
      retryDelay: Duration.zero,
      maxAttempts: 1,
    );

    await expectLater(
      service.createChatCompletion(
        messages: const <AiChatMessage>[
          AiChatMessage(role: 'user', content: 'Return JSON'),
        ],
        systemPrompt: 'Return JSON only.',
        responseFormat: const <String, Object?>{'type': 'json_object'},
      ),
      throwsA(
        isA<GapGptException>()
            .having(
              (error) => error.code,
              'code',
              'unsupported_response_format',
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('sk-')),
            ),
      ),
    );
  });

  test('maps a top-level OpenRouter SSE rate-limit error', () async {
    final client = MockClient((_) async {
      return http.Response(
        'data: ${jsonEncode({
          'error': {
            'code': 429,
            'message': 'Rate limit exceeded for sk-secret-value',
            'metadata': {'error_type': 'rate_limit_exceeded'},
          },
          'choices': const [],
        })}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final service = GapGptService(apiKey: 'test-key', client: client);

    await expectLater(
      service
          .createChatCompletionStream(
            messages: const [AiChatMessage(role: 'user', content: 'Hello')],
            systemPrompt: 'Be helpful.',
          )
          .drain<void>(),
      throwsA(
        isA<GapGptException>()
            .having((error) => error.code, 'code', 'rate_limited')
            .having(
              (error) => error.message,
              'message',
              isNot(contains('sk-')),
            ),
      ),
    );
  });

  test(
    'rejects a non-stream completion with an embedded choice error',
    () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'partial answer'},
                'finish_reason': 'error',
                'error': {
                  'code': 502,
                  'message': 'Provider disconnected',
                  'metadata': {'error_type': 'provider_unavailable'},
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = GapGptService(
        apiKey: 'test-key',
        client: client,
        retryDelay: Duration.zero,
        maxAttempts: 1,
      );

      await expectLater(
        service.createChatCompletion(
          messages: const [AiChatMessage(role: 'user', content: 'Hello')],
          systemPrompt: 'Be helpful.',
        ),
        throwsA(
          isA<GapGptException>().having(
            (error) => error.code,
            'code',
            'service_unavailable',
          ),
        ),
      );
    },
  );

  test('returns the provider error without exposing a secret', () async {
    final client = MockClient((_) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'invalid key sk-secret-value'},
        }),
        401,
      );
    });
    final service = GapGptService(apiKey: 'test-key', client: client);

    expect(
      () => service
          .createChatCompletionStream(
            messages: const [AiChatMessage(role: 'user', content: 'Hello')],
            systemPrompt: 'Be helpful.',
          )
          .drain<void>(),
      throwsA(
        isA<GapGptException>()
            .having((error) => error.code, 'code', 'authentication_failed')
            .having(
              (error) => error.message,
              'message',
              isNot(contains('sk-')),
            ),
      ),
    );
  });

  test('refuses to send when the API key is missing', () async {
    final service = GapGptService(
      apiKey: '',
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(
      () => service.createChatCompletion(
        messages: const [AiChatMessage(role: 'user', content: 'Hello')],
        systemPrompt: 'Be helpful.',
      ),
      throwsA(
        isA<GapGptException>().having(
          (error) => error.code,
          'code',
          'missing_api_key',
        ),
      ),
    );
  });

  test('retries one transport failure before the first token', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts++;
      if (attempts == 1) {
        throw http.ClientException('temporary connection failure');
      }
      return http.Response(
        'data: {"choices":[{"delta":{"content":"recovered"}}]}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final service = GapGptService(
      apiKey: 'test-key',
      client: client,
      retryDelay: Duration.zero,
    );

    final answer = await service.createChatCompletion(
      messages: const [AiChatMessage(role: 'user', content: 'Hello')],
      systemPrompt: 'Be helpful.',
    );

    expect(answer, 'recovered');
    expect(attempts, 2);
  });

  test(
    'uses an explicitly configured fallback model after a provider outage',
    () async {
      final models = <String>[];
      final client = MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        models.add(payload['model'] as String);
        if (models.length == 1) {
          return http.Response('{"error":{"message":"temporarily down"}}', 503);
        }
        return http.Response(
          'data: {"choices":[{"delta":{"content":"fallback"}}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final service = GapGptService(
        apiKey: 'test-key',
        model: 'primary-model',
        fallbackModels: const ['fallback-model'],
        client: client,
        retryDelay: Duration.zero,
      );

      final answer = await service.createChatCompletion(
        messages: const [AiChatMessage(role: 'user', content: 'Hello')],
        systemPrompt: 'Be helpful.',
      );

      expect(answer, 'fallback');
      expect(models, ['primary-model', 'fallback-model']);
    },
  );

  test(
    'falls back once to a non-stream response after an empty SSE answer',
    () async {
      final streamingFlags = <bool>[];
      final client = MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        streamingFlags.add(payload['stream'] as bool);
        if (streamingFlags.length == 1) {
          return http.Response(
            'data: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        return http.Response(
          '{"choices":[{"message":{"content":"complete answer"}}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = GapGptService(
        apiKey: 'test-key',
        client: client,
        retryDelay: Duration.zero,
      );

      final answer = await service.createChatCompletion(
        messages: const [AiChatMessage(role: 'user', content: 'Hello')],
        systemPrompt: 'Be helpful.',
      );

      expect(answer, 'complete answer');
      expect(streamingFlags, [true, false]);
    },
  );

  test('does not retry a timed-out request automatically', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response('{}', 200);
    });
    final service = GapGptService(
      apiKey: 'test-key',
      client: client,
      timeout: const Duration(milliseconds: 2),
      retryDelay: Duration.zero,
    );

    await expectLater(
      service
          .createChatCompletionStream(
            messages: const [AiChatMessage(role: 'user', content: 'Hello')],
            systemPrompt: 'Be helpful.',
          )
          .drain<void>(),
      throwsA(
        isA<GapGptException>().having((error) => error.code, 'code', 'timeout'),
      ),
    );
    expect(attempts, 1);
  });
}
