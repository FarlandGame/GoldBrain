import 'gapgpt_service.dart';
import 'news_ai_service.dart';

abstract final class GoldBrainAiPolicy {
  static const Map<String, String> languageNames = {
    'english': 'English',
    'persian': 'Persian (Farsi)',
    'japanese': 'Japanese',
    'russian': 'Russian',
    'chinese': 'Simplified Chinese',
    'arabic': 'Arabic',
    'turkish': 'Turkish',
    'french': 'French',
  };

  static String languageName(String languageCode) =>
      languageNames[languageCode] ?? languageNames['english']!;

  static bool isExpectedResponseLanguage(String value, String languageCode) =>
      NewsAiLanguagePolicy.isExpectedLanguage(value, languageCode);

  /// Keeps user-authored history intact while preventing assistant answers in
  /// a previously selected language from steering the next response.
  static List<AiChatMessage> historyForLanguage(
    Iterable<AiChatMessage> messages,
    String languageCode,
  ) => List<AiChatMessage>.unmodifiable(
    messages.where(
      (message) =>
          message.role != 'assistant' ||
          isExpectedResponseLanguage(message.content, languageCode),
    ),
  );

  static String languageRepairSystemPrompt(String languageCode) {
    final language = languageName(languageCode);
    return 'You are a strict language repair step. Rewrite the supplied '
        'assistant answer entirely in $language ($languageCode). Preserve its '
        'facts, numbers, uncertainty, warnings, code and URLs. Do not answer '
        'the original question again, add new facts, or mention this repair. '
        'Return only the repaired answer.';
  }

  /// Market/news payloads are useful for financial questions, but sending
  /// them for writing, editing or general questions adds latency and distracts
  /// the model. This lightweight classifier only decides whether app context
  /// should be attached; it never restricts what the assistant can answer.
  static bool requiresMarketContext(String userText) {
    final normalized = userText.toLowerCase();
    return _marketTerms.any(normalized.contains);
  }

  static String baseSystemPrompt({
    required String languageCode,
    required String tone,
  }) {
    final language = languageName(languageCode);
    final prompt = StringBuffer(
      'You are GoldBrain, a high-quality general-purpose assistant with deep '
      'specialization in gold, precious metals, currencies, crypto assets, '
      'financial news, and the GoldBrain application. GoldBrain is a desktop '
      'market-intelligence application that combines sourced prices, financial '
      'news, watchlists, charts, and AI-assisted analysis. According to the '
      'project owner, its creators are Bardiya Alizadeh, known as Kabir, and '
      'Ermia Alizadeh, known as Kabir. If asked about the application or its '
      'creators, state only these supplied facts and never invent biographies, '
      'credentials, or achievements. '
      'LANGUAGE REQUIREMENT: the application language is $language '
      '($languageCode). Write the entire answer in $language, including '
      'headings, summaries, explanations, warnings, and closing sentences. '
      'Do not switch to English merely because the user or a source uses '
      'English. Keep only unavoidable proper names, market symbols, URLs, code, '
      'and exact quotations in their original form. This language requirement '
      'has priority over the language of conversation history and source data. '
      'When the user asks about gold, currencies, markets, financial news, or '
      'GoldBrain, answer directly and use supplied app evidence when relevant. '
      'When a sourced GoldBrain market/news snapshot is supplied in this prompt, '
      'treat it as the application context available for this turn and do not '
      'claim that you cannot access GoldBrain or its news section. Clearly say '
      'that the information comes from the app-provided snapshot. '
      'Do not pretend to have live access when no sourced snapshot is supplied. '
      'Clearly distinguish sourced facts from your analysis and uncertainty. '
      'You are also fully capable of non-financial work such as rewriting, '
      'proofreading, drafting sentences and documents, summarization, '
      'translation, brainstorming, explanations, and general questions. Do the '
      'requested task helpfully instead of refusing merely because it is '
      'outside finance. Answer the request first; add caveats only when they '
      'are genuinely relevant. Never invent live prices, news, portfolio data, '
      'or sources. Never present educational content as guaranteed investment '
      'advice. A directional probability is allowed only as an explicitly '
      'labelled AI scenario estimate backed by supplied price/news evidence; '
      'if evidence is insufficient, do not output a percentage. Never instruct '
      'the user to buy all or sell all. Use conditional, risk-managed language. '
      'Whenever discussing a possible trade, include a clear warning in '
      '$language that forecasts can be wrong, capital can be lost, and the '
      'final decision and responsibility belong to the user.',
    );
    switch (tone) {
      case 'concise':
        prompt.write(' Keep answers concise, direct, and action-oriented.');
        break;
      case 'detailed':
        prompt.write(
          ' Give a well-structured, detailed explanation and make assumptions explicit.',
        );
        break;
      case 'balanced':
      default:
        prompt.write(' Balance brevity with enough explanation to be useful.');
    }
    return prompt.toString();
  }

  static const List<String> _marketTerms = [
    'gold',
    'xau',
    'currency',
    'forex',
    'dollar',
    'usd',
    'euro',
    'bitcoin',
    'btc',
    'crypto',
    'market',
    'price',
    'financial news',
    'news',
    'goldbrain',
    'app news',
    'economy',
    'inflation',
    'طلا',
    'سکه',
    'نقره',
    'ارز',
    'دلار',
    'یورو',
    'بیت کوین',
    'رمزارز',
    'بازار',
    'قیمت',
    'اخبار مالی',
    'اخبار',
    'خبر',
    'گلدبرین',
    'برنامه',
    'اقتصاد',
    'تورم',
    'ذهب',
    'عملة',
    'دولار',
    'سوق',
    'سعر',
    'altın',
    'döviz',
    'dolar',
    'piyasa',
    'fiyat',
    'devise',
    'marché',
    'prix',
    '金融',
    '黄金',
    '金価格',
    '通貨',
    '市場',
    'золото',
    'валют',
    'доллар',
    'рынок',
    'цен',
  ];
}
