import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/gapgpt_service.dart';
import 'package:goldbrain/core/news_ai_service.dart';
import 'package:goldbrain/core/news_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

NewsArticle _article({String id = 'article-1', String? body}) {
  return NewsArticle(
    id: id,
    title: 'گزارش رسمی بازار طلا',
    summary: body ?? 'توضیح رسمی منبع.',
    source: NewsService.officialSourceName,
    sourceCategory: 'اقتصادی',
    url: Uri.parse(
      'https://www.tasnimnews.ir/fa/news/1405/05/19/3668111/report',
    ),
    publishedAt: DateTime.utc(2026, 8, 10),
    sourceLanguageCode: 'persian',
  );
}

http.Response _sseAnswer(String answer) {
  final source =
      'data: ${jsonEncode({
        'choices': [
          {
            'delta': {'content': answer},
          },
        ],
      })}\n\ndata: [DONE]\n\n';
  return http.Response.bytes(
    utf8.encode(source),
    200,
    headers: {'content-type': 'text/event-stream; charset=utf-8'},
  );
}

void main() {
  test('parses a constrained factual translation response', () async {
    late http.Request request;
    final gap = GapGptService(
      apiKey: 'test-key',
      client: MockClient((captured) async {
        request = captured;
        return _sseAnswer(
          jsonEncode({
            'translations': [
              {
                'id': 'article-1',
                'title': '黄金市场官方报告',
                'summary': '来源的官方说明。',
                'category': '经济',
              },
            ],
          }),
        );
      }),
    );
    final client = GapGptNewsAiClient(service: gap);

    final result = await client.translateArticles(
      articles: [_article()],
      languageCode: 'chinese',
    );

    expect(result.single.articleId, 'article-1');
    expect(result.single.title, '黄金市场官方报告');
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    expect(payload['temperature'], 0.0);
    expect(request.body, contains('untrusted'));
  });

  test('limits source size before sending public text to AI', () async {
    late http.Request request;
    final gap = GapGptService(
      apiKey: 'test-key',
      client: MockClient((captured) async {
        request = captured;
        return _sseAnswer(
          '{"translations":[{"id":"article-1","title":"黄金报告",'
          '"summary":"这是来自官方来源的摘要。","category":"财经"}]}',
        );
      }),
    );
    final client = GapGptNewsAiClient(service: gap);

    await client.translateArticles(
      articles: [_article(body: 'x' * 50000)],
      languageCode: 'chinese',
    );

    expect(request.body.length, lessThan(16000));
  });

  test('retries a translation returned in the wrong language', () async {
    var requests = 0;
    final gap = GapGptService(
      apiKey: 'test-key',
      client: MockClient((_) async {
        requests++;
        if (requests == 1) {
          return _sseAnswer(
            '{"translations":[{"id":"article-1",'
            '"title":"Gold market report",'
            '"summary":"This response is incorrectly in English.",'
            '"category":"Economy"}]}',
          );
        }
        return _sseAnswer(
          '{"translations":[{"id":"article-1","title":"黄金市场报告",'
          '"summary":"这是一份来自官方来源的市场摘要。","category":"财经新闻"}]}',
        );
      }),
    );
    final client = GapGptNewsAiClient(service: gap);

    final result = await client.translateArticles(
      articles: [_article()],
      languageCode: 'chinese',
    );

    expect(requests, 2);
    expect(result.single.summary, contains('官方来源'));
  });

  test('rejects malformed translation instead of displaying invented data', () {
    final gap = GapGptService(
      apiKey: 'test-key',
      client: MockClient((_) async => _sseAnswer('not-json')),
    );
    final client = GapGptNewsAiClient(service: gap);

    expect(
      () => client.translateArticles(
        articles: [_article()],
        languageCode: 'chinese',
      ),
      throwsA(
        isA<NewsAiException>().having(
          (error) => error.code,
          'code',
          'invalid_translation',
        ),
      ),
    );
  });

  test('streams an on-demand summary in the selected language', () async {
    final gap = GapGptService(
      apiKey: 'test-key',
      client: MockClient((_) async => _sseAnswer('خلاصه واقعی منبع')),
    );
    final client = GapGptNewsAiClient(service: gap);

    final answer = await client
        .summarizeArticle(article: _article(), languageCode: 'persian')
        .join();

    expect(answer, 'خلاصه واقعی منبع');
  });

  test('retries a summary that is not in the selected language', () async {
    var requests = 0;
    late http.Request retryRequest;
    final gap = GapGptService(
      apiKey: 'test-key',
      client: MockClient((request) async {
        requests++;
        if (requests == 1) {
          return _sseAnswer(
            'A recent report discusses the gold market in English.',
          );
        }
        retryRequest = request;
        return _sseAnswer('این گزارش تازه وضعیت بازار طلا را بررسی می‌کند.');
      }),
    );
    final client = GapGptNewsAiClient(service: gap);

    final answer = await client
        .summarizeArticle(article: _article(), languageCode: 'persian')
        .join();

    expect(requests, 2);
    expect(answer, contains('بازار طلا'));
    expect(retryRequest.body, contains('previous result was rejected'));
  });

  test('never returns or caches a repeatedly wrong-language summary', () async {
    var requests = 0;
    final gap = GapGptService(
      apiKey: 'test-key',
      client: MockClient((_) async {
        requests++;
        return _sseAnswer(
          'This English response must not be shown for Persian.',
        );
      }),
    );
    final client = GapGptNewsAiClient(service: gap);

    await expectLater(
      client
          .summarizeArticle(article: _article(), languageCode: 'persian')
          .drain<void>(),
      throwsA(
        isA<NewsAiException>().having(
          (error) => error.code,
          'code',
          'wrong_language',
        ),
      ),
    );
    expect(requests, 2);
  });

  test('recognizes all supported selected-language scripts', () {
    const samples = {
      'english': 'This report explains the latest gold market movement.',
      'persian': 'این گزارش تازه وضعیت بازار طلا را بررسی می‌کند.',
      'japanese': 'この報告書は金市場の最新動向を説明しています。',
      'russian': 'Этот отчёт объясняет последние изменения рынка золота.',
      'chinese': '这份报告说明了黄金市场的最新变化。',
      'arabic': 'يشرح هذا التقرير أحدث التغيرات في سوق الذهب.',
      'turkish': 'Bu rapor, altın piyasasındaki son değişimleri açıklıyor.',
      'french': 'Ce rapport décrit les dernières évolutions du marché de l’or.',
    };

    for (final entry in samples.entries) {
      expect(
        NewsAiLanguagePolicy.isExpectedLanguage(entry.value, entry.key),
        isTrue,
        reason: entry.key,
      );
    }
    expect(
      NewsAiLanguagePolicy.isExpectedLanguage(samples['english']!, 'persian'),
      isFalse,
    );
  });
}
