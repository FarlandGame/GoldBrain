import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/gapgpt_service.dart';
import 'package:goldbrain/core/market_intelligence_service.dart';
import 'package:goldbrain/core/news_ai_service.dart';
import 'package:goldbrain/core/news_service.dart';

void main() {
  final enabled = Platform.environment['RUN_GAPGPT_LIVE_SMOKE'] == '1';

  test(
    'OpenRouter free router returns a streamed Persian answer',
    () async {
      final service = GapGptService.fromEnvironment();
      addTearDown(service.close);

      expect(service.isConfigured, isTrue);
      expect(service.model, 'openrouter/free');

      final chunks = <String>[];
      await for (final chunk in service.createChatCompletionStream(
        messages: const <AiChatMessage>[
          AiChatMessage(
            role: 'user',
            content: 'فقط یک واژهٔ فارسی برای سلام بنویس.',
          ),
        ],
        systemPrompt:
            'Reply only in Persian. Keep the answer to one short word.',
        temperature: 0,
      )) {
        chunks.add(chunk);
      }

      expect(chunks, isNotEmpty);
      expect(chunks.join().trim(), isNotEmpty);
    },
    skip: enabled ? false : 'Set RUN_GAPGPT_LIVE_SMOKE=1 to call the live API.',
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'OpenRouter free router accepts the structured JSON path used by analysis',
    () async {
      final service = GapGptService.fromEnvironment();
      addTearDown(service.close);

      expect(service.isConfigured, isTrue);
      expect(service.model, 'openrouter/free');

      final response = await service.createChatCompletion(
        messages: const <AiChatMessage>[
          AiChatMessage(
            role: 'user',
            content: 'Return one JSON object with ok set to true.',
          ),
        ],
        systemPrompt: 'Return valid JSON only, without Markdown.',
        temperature: 0,
        responseFormat: const <String, Object?>{'type': 'json_object'},
      );

      final decoded = jsonDecode(response);
      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>)['ok'], isTrue);
    },
    skip: enabled ? false : 'Set RUN_GAPGPT_LIVE_SMOKE=1 to call the live API.',
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'OpenRouter produces a Persian summary through the production news adapter',
    () async {
      final service = GapGptService.fromEnvironment();
      final client = GapGptNewsAiClient(service: service);
      addTearDown(service.close);

      expect(service.isConfigured, isTrue);
      expect(service.model, 'openrouter/free');

      final article = NewsArticle(
        id: 'synthetic-live-news-summary',
        title: 'Synthetic gold market source briefing',
        summary:
            'A synthetic publisher note says the quoted gold price increased '
            'slightly during the observed session. It gives no cause, forecast, '
            'probability, or investment recommendation.',
        content:
            'This is synthetic test evidence, not live market news. The source '
            'only reports a small observed increase in the quoted gold price '
            'during one session and explicitly provides no explanation or '
            'forecast. No investment action is recommended.',
        source: 'GoldBrain synthetic smoke source',
        sourceCategory: 'financial test evidence',
        sourceLanguageCode: 'english',
        url: Uri.parse('https://example.invalid/goldbrain/synthetic-news'),
        publishedAt: DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        ),
      );

      final chunks = <String>[];
      await for (final chunk in client.summarizeArticle(
        article: article,
        languageCode: 'persian',
      )) {
        chunks.add(chunk);
      }

      final summary = chunks.join().trim();
      expect(summary, isNotEmpty);
      expect(
        NewsAiLanguagePolicy.isExpectedLanguage(summary, 'persian'),
        isTrue,
      );
    },
    skip: enabled ? false : 'Set RUN_GAPGPT_LIVE_SMOKE=1 to call the live API.',
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test(
    'OpenRouter response passes the full market intelligence JSON parser',
    () async {
      final service = MarketIntelligenceService();
      addTearDown(service.close);

      expect(service.isConfigured, isTrue);
      expect(service.usesRateLimitedFreeRouter, isTrue);

      final collectedAt = DateTime.now().toUtc();
      final historyStart = collectedAt.subtract(const Duration(hours: 23));
      final input = MarketIntelligenceInput(
        languageCode: 'persian',
        collectedAt: collectedAt,
        quotes: <IntelligenceQuoteEvidence>[
          IntelligenceQuoteEvidence(
            symbol: 'XAU',
            price: 2350,
            unit: 'USD',
            changePercent: 0.85,
            updatedAt: collectedAt.subtract(const Duration(minutes: 1)),
            source: 'synthetic-verified-quote',
          ),
        ],
        news: <IntelligenceNewsEvidence>[
          IntelligenceNewsEvidence(
            id: 'synthetic-xau-news',
            title: 'Synthetic XAU gold evidence update',
            summary:
                'This synthetic sourced item reports the observed move only '
                'and contains no prediction or instruction.',
            publishedAt: collectedAt.subtract(const Duration(minutes: 15)),
            source: 'synthetic-verified-news',
          ),
        ],
        histories: <IntelligenceHistoryEvidence>[
          IntelligenceHistoryEvidence(
            symbol: 'XAU',
            unit: 'USD',
            source: 'synthetic-verified-history',
            range: 'oneDay',
            points: List<IntelligenceHistoryPoint>.generate(
              24,
              (index) => IntelligenceHistoryPoint(
                time: historyStart.add(Duration(hours: index)),
                close: 2300 + (index * 2.15),
              ),
            ),
          ),
        ],
      );

      final report = await service.analyze(input);

      expect(report.symbol, 'XAU');
      expect(report.languageCode, 'persian');
      expect(report.historyPointCount, 24);
      expect(report.relevantNewsCount, 1);
      expect(report.summary.trim(), isNotEmpty);
      expect(report.reasons, isNotEmpty);
      expect(
        NewsAiLanguagePolicy.isExpectedLanguage(
          '${report.summary} ${report.reasons.join(' ')}',
          'persian',
        ),
        isTrue,
      );
      expect(
        report.direction,
        isIn(<MarketScenarioDirection>[
          MarketScenarioDirection.upward,
          MarketScenarioDirection.downward,
          MarketScenarioDirection.neutral,
          MarketScenarioDirection.insufficientData,
        ]),
      );
    },
    skip: enabled ? false : 'Set RUN_GAPGPT_LIVE_SMOKE=1 to call the live API.',
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
