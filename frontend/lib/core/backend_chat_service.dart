import 'backend_api_client.dart';
import 'backend_connection.dart';
import 'currency_service.dart';
import 'gapgpt_service.dart';
import 'settings_store.dart';
import '../screens/selection_screen.dart';

/// Retains the existing chat service interface and test injection. Production
/// chat uses the authenticated GoldBrain transport, never a client provider key.
class BackendChatService extends GapGptService {
  BackendChatService({GoldBrainBackendClient? api})
    : _api = api ?? BackendConnection.instance.api,
      super(apiKey: '', model: 'GoldBrain API');

  final GoldBrainBackendClient _api;
  String languageCode = 'persian';

  @override
  bool get isConfigured => true;

  @override
  Stream<String> createChatCompletionStream({
    required List<AiChatMessage> messages,
    required String systemPrompt,
    double temperature = 0.35,
    Map<String, Object?>? responseFormat,
  }) async* {
    final settings = SettingsStore.instance;
    try {
      final response = await _api.assistantChat(<String, dynamic>{
        'messages': messages
            .take(24)
            .map(
              (message) => <String, String>{
                'role': message.role,
                'content': message.content.length > 4000
                    ? message.content.substring(0, 4000)
                    : message.content,
              },
            )
            .toList(),
        'language': languageCode,
        'tone': settings.personalizedAiEnabled ? settings.aiTone : 'balanced',
        'temperature': temperature.clamp(0.0, 1.0),
        'market_context': settings.marketContextEnabled,
        'display_currency': CurrencyService.resolveCurrencyCode(
          selectedCode: settings.currencyCode,
          language: GoldBrainLanguage.values.firstWhere(
            (value) => value.name == languageCode,
            orElse: () => GoldBrainLanguage.english,
          ),
        ),
      });
      final text = response['text'];
      if (text is! String || text.trim().isEmpty) {
        throw const GapGptException(
          'invalid_response',
          'Empty assistant answer.',
        );
      }
      // Backend finishes the bounded tool loop before returning the answer.
      // The existing composer keeps its loading state until then.
      yield text;
    } on GoldBrainBackendException catch (error) {
      final code = error.serverCode;
      throw GapGptException(
        error.code == 'http_401'
            ? 'session_required'
            : code == 'assistant_rate_limited' || error.code == 'http_429'
            ? 'rate_limited'
            : code == 'assistant_timeout' || error.code == 'timeout'
            ? 'timeout'
            : code == 'assistant_not_configured'
            ? 'backend_not_configured'
            : 'service_unavailable',
        'The assistant is temporarily unavailable.',
      );
    }
  }
}
