import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'child_process_environment.dart';
import 'runtime_environment.dart';

class AiChatMessage {
  const AiChatMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class GapGptException implements Exception {
  const GapGptException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class GapGptService {
  GapGptService({
    required String apiKey,
    String baseUrl = 'https://api.gapgpt.app/v1',
    String model = 'gpt-4o',
    List<String> fallbackModels = const [],
    http.Client? client,
    bool? ownsClient,
    Duration timeout = const Duration(seconds: 45),
    Duration retryDelay = const Duration(milliseconds: 250),
    int maxAttempts = 2,
  }) : _apiKey = apiKey.trim(),
       _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       model = _normalizedModel(model),
       _fallbackModels = _normalizedFallbackModels(model, fallbackModels),
       _client = client ?? http.Client(),
       _ownsClient = ownsClient ?? client == null,
       _timeout = timeout,
       _retryDelay = retryDelay,
       _maxAttempts = maxAttempts.clamp(1, 3);

  factory GapGptService.fromEnvironment({
    http.Client? client,
    Map<String, String>? processEnvironment,
    Map<String, String>? compileTimeEnvironment,
    bool? isWindows,
    WindowsUserEnvironmentLoader? windowsUserEnvironmentLoader,
  }) {
    final environment = RuntimeEnvironment.resolve(
      allowedNames: _environmentNames,
      processEnvironment: processEnvironment,
      compileTimeEnvironment: compileTimeEnvironment,
      isWindows: isWindows,
      windowsUserEnvironmentLoader: windowsUserEnvironmentLoader,
    );
    final ownedClient = client ?? _proxyAwareClient(environment);
    return GapGptService(
      apiKey: environment['GAPGPT_API_KEY'] ?? '',
      baseUrl: environment['GAPGPT_BASE_URL'] ?? 'https://api.gapgpt.app/v1',
      model: environment['GAPGPT_MODEL'] ?? 'gpt-4o',
      fallbackModels: _environmentList(
        environment['GAPGPT_FALLBACK_MODELS'] ?? '',
      ),
      client: ownedClient,
      ownsClient: client == null,
    );
  }

  static const Set<String> _environmentNames = <String>{
    'GAPGPT_API_KEY',
    'GAPGPT_BASE_URL',
    'GAPGPT_MODEL',
    'GAPGPT_FALLBACK_MODELS',
    'GAPGPT_PROXY_URL',
  };

  final String _apiKey;
  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  final Duration _retryDelay;
  final int _maxAttempts;
  final List<String> _fallbackModels;

  final String model;

  bool get isConfigured {
    final uri = Uri.tryParse(_baseUrl);
    return _apiKey.isNotEmpty &&
        model.trim().isNotEmpty &&
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty;
  }

  bool get isOpenRouter {
    final uri = Uri.tryParse(_baseUrl);
    final host = uri?.host.toLowerCase();
    return host == 'openrouter.ai' || host?.endsWith('.openrouter.ai') == true;
  }

  bool get isOpenRouterFreeRouter {
    final normalizedModel = model.toLowerCase();
    return isOpenRouter &&
        (normalizedModel == 'openrouter/free' ||
            normalizedModel.endsWith(':free'));
  }

  /// Uses standard HTTP_PROXY/HTTPS_PROXY/NO_PROXY variables and also accepts
  /// a dedicated GAPGPT_PROXY_URL such as http://127.0.0.1:7890. Transparent
  /// VPNs need no setting; this only helps VPN clients exposing a local proxy.
  static http.Client _proxyAwareClient(Map<String, String> environment) {
    final ioClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    final dedicatedProxy = environment['GAPGPT_PROXY_URL']?.trim();
    if (dedicatedProxy != null && dedicatedProxy.isNotEmpty) {
      final directive = _proxyDirectiveFromAddress(dedicatedProxy);
      if (directive != null) {
        // Explicit proxy configuration is fail-closed: if that proxy is down,
        // do not silently send the API request over the direct connection.
        ioClient.findProxy = (_) => directive;
      } else {
        ioClient.findProxy = HttpClient.findProxyFromEnvironment;
      }
    } else if (_hasEnvironmentProxy()) {
      ioClient.findProxy = HttpClient.findProxyFromEnvironment;
    } else if (_windowsSystemProxyDirective() case final directive?) {
      // Dart's environment proxy lookup does not read the WinINET settings
      // used by many Windows VPN clients. Respect an enabled manual system
      // proxy when no explicit application/environment proxy was supplied.
      ioClient.findProxy = (_) => directive;
    } else {
      ioClient.findProxy = HttpClient.findProxyFromEnvironment;
    }
    return IOClient(ioClient);
  }

  static bool _hasEnvironmentProxy() {
    const proxyNames = {'http_proxy', 'https_proxy', 'all_proxy'};
    return Platform.environment.entries.any(
      (entry) =>
          proxyNames.contains(entry.key.toLowerCase()) &&
          entry.value.trim().isNotEmpty,
    );
  }

  static String? _windowsSystemProxyDirective() {
    return _cachedWindowsSystemProxyDirective;
  }

  static final String? _cachedWindowsSystemProxyDirective =
      _readWindowsSystemProxyDirective();

  static String? _readWindowsSystemProxyDirective() {
    if (!Platform.isWindows) return null;
    const key =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    try {
      final childEnvironment = sanitizedWindowsChildEnvironment(
        parent: Platform.environment,
      );
      final enabledResult = Process.runSync(
        'reg.exe',
        const ['query', key, '/v', 'ProxyEnable'],
        environment: childEnvironment,
        includeParentEnvironment: false,
        runInShell: false,
      );
      if (enabledResult.exitCode != 0) return null;
      final enabledText = enabledResult.stdout.toString().toLowerCase();
      if (!RegExp(r'0x0*1(?:\s|$)').hasMatch(enabledText)) return null;

      final serverResult = Process.runSync(
        'reg.exe',
        const ['query', key, '/v', 'ProxyServer'],
        environment: childEnvironment,
        includeParentEnvironment: false,
        runInShell: false,
      );
      if (serverResult.exitCode != 0) return null;
      final match = RegExp(
        r'ProxyServer\s+REG_\w+\s+(.+)',
        caseSensitive: false,
      ).firstMatch(serverResult.stdout.toString());
      final rawServer = match?.group(1)?.trim();
      if (rawServer == null || rawServer.isEmpty) return null;
      final protocols = <String, String>{};
      for (final part in rawServer.split(';')) {
        final separator = part.indexOf('=');
        if (separator <= 0) continue;
        protocols[part.substring(0, separator).trim().toLowerCase()] = part
            .substring(separator + 1)
            .trim();
      }
      return _proxyDirectiveFromAddress(
        protocols['https'] ?? protocols['http'] ?? rawServer,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _proxyDirectiveFromAddress(String address) {
    final normalized = address.trim();
    if (normalized.isEmpty) return null;
    final withScheme = normalized.contains('://')
        ? normalized
        : 'http://$normalized';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final port = uri.hasPort
        ? uri.port
        : uri.scheme == 'https'
        ? 443
        : 8080;
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return 'PROXY $host:$port';
  }

  static String _normalizedModel(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? 'gpt-4o' : normalized;
  }

  static List<String> _normalizedFallbackModels(
    String primaryModel,
    Iterable<String> values,
  ) {
    final primary = _normalizedModel(primaryModel);
    final seen = <String>{primary};
    return List<String>.unmodifiable(
      values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty && seen.add(value)),
    );
  }

  static List<String> _environmentList(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  Future<String> createChatCompletion({
    required List<AiChatMessage> messages,
    required String systemPrompt,
    double temperature = 0.35,
    Map<String, Object?>? responseFormat,
  }) async {
    final answer = StringBuffer();
    await for (final chunk in createChatCompletionStream(
      messages: messages,
      systemPrompt: systemPrompt,
      temperature: temperature,
      responseFormat: responseFormat,
    )) {
      answer.write(chunk);
    }
    return answer.toString().trim();
  }

  Stream<String> createChatCompletionStream({
    required List<AiChatMessage> messages,
    required String systemPrompt,
    double temperature = 0.35,
    Map<String, Object?>? responseFormat,
  }) async* {
    if (!isConfigured) {
      throw const GapGptException(
        'missing_api_key',
        'GAPGPT_API_KEY is not configured.',
      );
    }
    if (messages.isEmpty) {
      throw const GapGptException(
        'empty_conversation',
        'The conversation is empty.',
      );
    }

    var attemptModel = model;
    // Structured OpenRouter calls are consumed as one JSON document. Starting
    // them as non-streaming requests avoids provider-specific SSE wrappers and
    // matches OpenRouter's documented structured-output request shape.
    var requestStreaming = !(isOpenRouter && responseFormat != null);
    var attemptResponseFormat = responseFormat;
    final responseFormatType = responseFormat?['type'];
    final validateJsonObject =
        responseFormatType == 'json_object' ||
        responseFormatType == 'json_schema';
    GapGptException? lastError;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      var emittedContent = false;
      try {
        await for (final chunk in _createChatCompletionAttempt(
          messages: messages,
          systemPrompt: systemPrompt,
          temperature: temperature,
          requestModel: attemptModel,
          streaming: requestStreaming,
          responseFormat: attemptResponseFormat,
          validateJsonObject: validateJsonObject,
        )) {
          emittedContent = true;
          yield chunk;
        }
        return;
      } on GapGptException catch (error) {
        // Never retry after a visible token: doing so could duplicate or mix
        // two different answers in the same chat bubble.
        final retryWithoutNativeFormat =
            isOpenRouterFreeRouter &&
            attemptResponseFormat != null &&
            (error.code == 'unsupported_response_format' ||
                error.code == 'provider_error' ||
                (error.code == 'request_failed' &&
                    error.message.toLowerCase().contains(
                      'provider returned error',
                    )));
        if (emittedContent ||
            attempt + 1 >= _maxAttempts ||
            (!retryWithoutNativeFormat &&
                !_canRetryBeforeFirstToken(error.code))) {
          rethrow;
        }
        lastError = error;
        if (retryWithoutNativeFormat) {
          // The free router can temporarily have no structured-output-capable
          // provider. Retry once without the native hint; JSON is still
          // required by the prompt and validated locally before it is exposed.
          attemptResponseFormat = null;
          requestStreaming = false;
        } else if (error.code == 'invalid_response' ||
            error.code == 'provider_forbidden') {
          // Some compatible gateways reject or mishandle SSE streaming for a
          // request that succeeds as a normal JSON completion. Retry once
          // without streaming before declaring the provider unavailable.
          requestStreaming = false;
        } else if ((error.code == 'model_unavailable' ||
                error.code == 'service_unavailable') &&
            _fallbackModels.isNotEmpty) {
          attemptModel = _fallbackModels.first;
        }
        if (_retryDelay > Duration.zero)
          await Future<void>.delayed(_retryDelay);
      }
    }
    throw lastError ??
        const GapGptException(
          'request_failed',
          'The AI request could not be completed.',
        );
  }

  Stream<String> _createChatCompletionAttempt({
    required List<AiChatMessage> messages,
    required String systemPrompt,
    required double temperature,
    required String requestModel,
    required bool streaming,
    required Map<String, Object?>? responseFormat,
    required bool validateJsonObject,
  }) async* {
    final uri = Uri.parse('$_baseUrl/chat/completions');
    final request = http.Request('POST', uri)
      ..headers.addAll({
        HttpHeaders.authorizationHeader: 'Bearer $_apiKey',
        HttpHeaders.contentTypeHeader: 'application/json',
        if (isOpenRouter) 'X-Title': 'GoldBrain',
        HttpHeaders.acceptHeader: streaming
            ? 'text/event-stream, application/json'
            : 'application/json',
      })
      ..body = jsonEncode({
        'model': requestModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...messages.map((message) => message.toJson()),
        ],
        'temperature': temperature.clamp(0.0, 1.0),
        'stream': streaming,
        if (responseFormat != null) 'response_format': responseFormat,
        if (isOpenRouter && responseFormat != null)
          // The free router otherwise may randomly select a model/provider
          // which silently ignores response_format and returns prose. Ask
          // OpenRouter to route only to providers supporting the requested
          // structured-output parameter.
          'provider': const <String, Object?>{'require_parameters': true},
      });

    late final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_timeout);
    } on TimeoutException {
      throw const GapGptException(
        'timeout',
        'The AI service did not respond in time.',
      );
    } on http.ClientException {
      throw const GapGptException(
        'network_error',
        'Could not connect to the AI service.',
      );
    } on IOException {
      throw const GapGptException(
        'network_error',
        'Could not connect to the AI service.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      late final List<int> bytes;
      try {
        bytes = await response.stream.toBytes().timeout(_timeout);
      } on TimeoutException {
        throw const GapGptException(
          'timeout',
          'The AI provider did not finish its error response.',
        );
      }
      final body = _decodeObject(bytes);
      throw _httpResponseException(
        body,
        response.statusCode,
        responseFormatRequested: responseFormat != null,
      );
    }

    final contentType = response.headers[HttpHeaders.contentTypeHeader] ?? '';
    if (!streaming ||
        !contentType.toLowerCase().contains('text/event-stream')) {
      late final List<int> bytes;
      try {
        bytes = await response.stream.toBytes().timeout(_timeout);
      } on TimeoutException {
        throw const GapGptException(
          'timeout',
          'The AI service did not finish its answer in time.',
        );
      } on http.ClientException {
        throw const GapGptException(
          'network_error',
          'The AI connection ended before an answer arrived.',
        );
      } on IOException {
        throw const GapGptException(
          'network_error',
          'The AI connection ended before an answer arrived.',
        );
      }
      final body = _decodeObject(bytes);
      final error = body['error'];
      if (error is Map) {
        throw _providerEventException(error);
      }
      final choiceError = _firstChoiceError(body);
      if (choiceError != null) {
        throw _providerEventException(choiceError);
      }
      final content = _completionContent(body);
      if (content.isEmpty) {
        throw const GapGptException(
          'invalid_response',
          'The AI service returned no answer.',
        );
      }
      if (validateJsonObject && !_isJsonObject(content)) {
        throw const GapGptException(
          'invalid_response',
          'The AI service did not return the required JSON object.',
        );
      }
      yield content;
      return;
    }

    var receivedContent = false;
    try {
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_timeout);

      await for (final line in lines) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;

        final payload = trimmed.substring(5).trimLeft();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') break;

        final event = _decodeTextObject(payload);
        final error = event['error'];
        if (error is Map) {
          throw _providerEventException(error);
        }
        final choiceError = _firstChoiceError(event);
        if (choiceError != null) {
          throw _providerEventException(choiceError);
        }
        final content = _completionContent(event, streamingDelta: true);
        if (content.isNotEmpty) {
          receivedContent = true;
          yield content;
        }
      }
    } on TimeoutException {
      throw const GapGptException(
        'timeout',
        'The AI stream stopped responding.',
      );
    } on FormatException {
      throw const GapGptException(
        'invalid_response',
        'The AI service returned an invalid stream.',
      );
    } on http.ClientException {
      throw const GapGptException(
        'network_error',
        'The AI stream ended unexpectedly.',
      );
    } on IOException {
      throw const GapGptException(
        'network_error',
        'The AI stream ended unexpectedly.',
      );
    }

    if (!receivedContent) {
      throw const GapGptException(
        'invalid_response',
        'The AI service returned no answer.',
      );
    }
  }

  bool _canRetryBeforeFirstToken(String code) =>
      code == 'network_error' ||
      code == 'service_unavailable' ||
      code == 'provider_forbidden' ||
      code == 'unsupported_response_format' ||
      (code == 'model_unavailable' && _fallbackModels.isNotEmpty) ||
      code == 'invalid_response';

  GapGptException _httpResponseException(
    Map<String, dynamic> body,
    int status, {
    required bool responseFormatRequested,
  }) {
    final error = body['error'];
    if (error is Map) {
      if (responseFormatRequested && _isUnsupportedResponseFormatError(error)) {
        return const GapGptException(
          'unsupported_response_format',
          'The selected AI provider does not support structured JSON for this request.',
        );
      }
      final providerError = _providerEventException(error);
      if (providerError.code != 'provider_error' &&
          providerError.code != 'request_failed') {
        return providerError;
      }
    }
    return GapGptException(
      _statusCode(status, body),
      _safeErrorMessage(body, status),
    );
  }

  bool _isUnsupportedResponseFormatError(Map error) {
    final metadata = error['metadata'];
    final fragments = <Object?>[
      error['message'],
      if (metadata is Map) metadata['message'],
      if (metadata is Map) metadata['error'],
      if (metadata is Map) metadata['raw'],
    ];
    final normalized = fragments
        .where((value) => value != null)
        .map((value) => value.toString().toLowerCase())
        .join(' ');
    final mentionsFormat =
        normalized.contains('response_format') ||
        normalized.contains('response format') ||
        normalized.contains('json_object') ||
        normalized.contains('structured output');
    final rejectsParameter =
        normalized.contains('not support') ||
        normalized.contains('unsupported') ||
        normalized.contains('invalid parameter') ||
        normalized.contains('invalid_parameter') ||
        normalized.contains('unknown parameter') ||
        normalized.contains('unrecognized parameter');
    final noCompatibleEndpoint =
        normalized.contains('no endpoint') &&
        normalized.contains('support') &&
        normalized.contains('parameter');
    return (mentionsFormat && rejectsParameter) || noCompatibleEndpoint;
  }

  bool _isJsonObject(String content) {
    try {
      return jsonDecode(content) is Map;
    } on FormatException {
      return false;
    }
  }

  Map<String, dynamic> _decodeObject(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // The caller receives a sanitized error below.
    }
    return const {};
  }

  Map<String, dynamic> _decodeTextObject(String text) {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException();
  }

  Map? _firstChoiceError(Map<String, dynamic> body) {
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return null;
    }
    final error = (choices.first as Map)['error'];
    return error is Map ? error : null;
  }

  GapGptException _providerEventException(Map error) {
    final message = error['message'] is String
        ? error['message'] as String
        : 'The AI provider returned an error.';
    final metadata = error['metadata'];
    final errorType = metadata is Map
        ? metadata['error_type']?.toString().toLowerCase()
        : error['error_type']?.toString().toLowerCase();
    final rawCode = error['code'];
    final numericCode = rawCode is num
        ? rawCode.toInt()
        : int.tryParse(rawCode?.toString() ?? '');
    return GapGptException(
      _providerEventCode(numericCode, errorType, message),
      _sanitizeProviderMessage(message),
    );
  }

  String _providerEventCode(
    int? numericCode,
    String? errorType,
    String message,
  ) {
    switch (errorType) {
      case 'authentication':
        return 'authentication_failed';
      case 'rate_limit_exceeded':
        return 'rate_limited';
      case 'timeout':
        return 'timeout';
      case 'provider_overloaded':
      case 'provider_unavailable':
      case 'server':
        return 'service_unavailable';
      case 'context_length_exceeded':
      case 'max_tokens_exceeded':
      case 'token_limit_exceeded':
        return 'context_too_large';
      case 'content_policy_violation':
        return 'provider_forbidden';
    }
    if (numericCode != null) {
      return _statusCode(numericCode, <String, dynamic>{
        'error': <String, Object?>{'message': message},
      });
    }
    return 'provider_error';
  }

  String _completionContent(
    Map<String, dynamic> body, {
    bool streamingDelta = false,
  }) {
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return '';
    final choice = choices.first as Map;
    final container = streamingDelta ? choice['delta'] : choice['message'];
    final rawContent = container is Map ? container['content'] : choice['text'];
    if (rawContent is String) return rawContent;
    if (rawContent is List) {
      return rawContent
          .whereType<Map>()
          .map((part) => part['text'] ?? part['content'])
          .whereType<String>()
          .join();
    }
    return '';
  }

  String _statusCode(int status, Map<String, dynamic> body) {
    if (status == 401) return 'authentication_failed';
    if (status == 402) return 'insufficient_credits';
    if (status == 403) return 'provider_forbidden';
    if (status == 408 || status == 504) return 'timeout';
    if (status == 429) return 'rate_limited';
    if (status >= 500) return 'service_unavailable';
    final error = body['error'];
    final providerMessage = error is Map ? error['message'] : null;
    final normalized = providerMessage?.toString().toLowerCase() ?? '';
    if ((status == 400 || status == 404 || status == 422) &&
        (normalized.contains('model') || normalized.contains('deployment'))) {
      return 'model_unavailable';
    }
    return 'request_failed';
  }

  String _safeErrorMessage(Map<String, dynamic> body, int status) {
    final error = body['error'];
    final providerMessage = error is Map ? error['message'] : null;
    if (providerMessage is String && providerMessage.trim().isNotEmpty) {
      return _sanitizeProviderMessage(providerMessage);
    }
    return 'AI request failed (HTTP $status).';
  }

  String _sanitizeProviderMessage(String message) {
    final redacted = message
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]+'), '[redacted]')
        .replaceAll(
          RegExp(r'Bearer\s+\S+', caseSensitive: false),
          'Bearer [redacted]',
        )
        .trim();
    if (redacted.length <= 280) return redacted;
    return '${redacted.substring(0, 280)}…';
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
