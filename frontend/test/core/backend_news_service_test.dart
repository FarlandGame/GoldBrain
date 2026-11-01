import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/backend_api_client.dart';
import 'package:goldbrain/core/backend_news_service.dart';
import 'package:goldbrain/core/news_ai_service.dart';
import 'package:goldbrain/core/news_service.dart';
import 'package:goldbrain/core/news_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _id = 'a' * 64;
Map<String, dynamic> _row({String? id, int score = 4}) => {
  'article_id': id ?? _id,
  'title': 'Bitcoin regulation advances',
  'summary': 'The committee approved a proposal.',
  'source': 'Cointelegraph',
  'category': 'crypto',
  'language': 'english',
  'url': 'https://cointelegraph.com/news/example',
  'published_at': '2026-10-04T10:00:00Z',
  'relevance_score': score,
  'source_information_url': 'https://cointelegraph.com/rss',
};

GoldBrainBackendClient _api(
  Future<http.Response> Function(http.Request) handler,
) => GoldBrainBackendClient(
  config: GoldBrainBackendConfig(
    baseUri: Uri.parse('http://127.0.0.1:8000'),
    apiKey: '',
  ),
  client: MockClient(handler),
)..setAccessToken('synthetic-news-session');

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'news uses only authenticated GoldBrain with honest cache/time/source metadata',
    () async {
      final api = _api((request) async {
        expect(request.url.host, '127.0.0.1');
        expect(request.url.path, '/api/v1/intelligence/news');
        expect(request.url.queryParameters['refresh'], 'true');
        expect(
          request.headers['authorization'],
          'Bearer synthetic-news-session',
        );
        return _json({
          'articles': [_row()],
          'fetched_at': '2026-10-04T10:01:00Z',
          'from_cache': true,
          'source_errors': {'Tasnim': 'Source temporarily unavailable.'},
        });
      });
      final service = BackendNewsService(api: api);
      addTearDown(service.close);
      addTearDown(api.close);
      final result = await service.fetchArticles(forceRefresh: true);
      expect(result.fromCache, isTrue);
      expect(result.fetchedAt, DateTime.utc(2026, 10, 4, 10, 1));
      expect(result.articles.single.source, 'Cointelegraph');
      expect(result.articles.single.relevanceScore, 4);
      expect(result.sourceErrors.keys, contains('Tasnim'));
    },
  );

  for (final kind in ['duplicate', 'bad_uri', 'bad_date', 'bad_language']) {
    test(
      'invalid feed $kind is rejected instead of being fabricated',
      () async {
        final row = _row();
        if (kind == 'bad_uri') row['url'] = 'file:///private';
        if (kind == 'bad_date') row['published_at'] = 'unknown';
        if (kind == 'bad_language') row['language'] = 'unknown';
        final api = _api(
          (_) async => _json({
            'articles': [row, if (kind == 'duplicate') row],
            'fetched_at': '2026-10-04T10:01:00Z',
          }),
        );
        final service = BackendNewsService(api: api);
        addTearDown(service.close);
        addTearDown(api.close);
        await expectLater(
          service.fetchArticles(),
          throwsA(isA<NewsServiceException>()),
        );
      },
    );
  }

  test(
    'store preserves relevance ranking and content after transport failure',
    () async {
      var requests = 0;
      final api = _api((_) async {
        if (++requests > 1) return _json({'detail': 'synthetic-secret'}, 503);
        return _json({
          'articles': [_row(score: 0), _row(id: 'b' * 64, score: 8)],
          'fetched_at': '2026-10-04T10:01:00Z',
        });
      });
      final service = BackendNewsService(api: api);
      final store = NewsStore(service: service);
      addTearDown(store.dispose);
      addTearDown(service.close);
      addTearDown(api.close);
      await store.load();
      expect(store.articles.first.id, 'b' * 64);
      await store.load(forceRefresh: true);
      expect(store.articles.length, 2);
      expect(store.errorMessage, isNot(contains('synthetic-secret')));
    },
  );

  test(
    'summary sends only stored article ID and language, no client text/key/prompt',
    () async {
      final api = _api((request) async {
        expect(request.url.path, '/api/v1/intelligence/news/$_id/summary');
        expect(jsonDecode(request.body), {'language': 'persian'});
        expect(
          request.headers['authorization'],
          'Bearer synthetic-news-session',
        );
        return _json({
          'article_id': _id,
          'language': 'persian',
          'text':
              'این خبر دربارهٔ بررسی پیشنهاد تازهٔ قانون‌گذاری بیت کوین است.',
        });
      });
      addTearDown(api.close);
      final article = NewsArticle(
        id: _id,
        title: 'untrusted client instruction',
        summary: '',
        source: 'publisher',
        sourceCategory: 'crypto',
        url: Uri.parse('https://cointelegraph.com/news/example'),
        publishedAt: DateTime.utc(2026, 10, 4),
      );
      final answer = await BackendNewsAiClient(
        api: api,
      ).summarizeArticle(article: article, languageCode: 'persian').join();
      expect(answer, contains('بیت کوین'));
    },
  );

  for (final status in [401, 429, 503]) {
    test('summary HTTP $status is a safe error', () async {
      final api = _api(
        (_) async => _json({'detail': 'synthetic-upstream-secret'}, status),
      );
      addTearDown(api.close);
      final article = NewsArticle(
        id: _id,
        title: 'Bitcoin',
        summary: '',
        source: 'publisher',
        sourceCategory: 'crypto',
        url: Uri.parse('https://cointelegraph.com/news/example'),
        publishedAt: DateTime.utc(2026, 10, 4),
      );
      await expectLater(
        BackendNewsAiClient(
          api: api,
        ).summarizeArticle(article: article, languageCode: 'persian').join(),
        throwsA(
          isA<NewsAiException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('synthetic-upstream-secret')),
          ),
        ),
      );
    });
  }

  test(
    'translation rejects a returned ID outside the requested article set',
    () async {
      final api = _api((request) async {
        expect(request.url.path, '/api/v1/intelligence/news/translations');
        expect(jsonDecode(request.body), {
          'article_ids': [_id],
          'language': 'persian',
        });
        return _json({
          'translations': [
            {
              'article_id': 'b' * 64,
              'language': 'persian',
              'title': 'عنوان خبر',
              'summary': 'خلاصهٔ خبر ناشر',
              'category': 'رمزارز',
            },
          ],
        });
      });
      addTearDown(api.close);
      final article = NewsArticle(
        id: _id,
        title: 'Bitcoin',
        summary: '',
        source: 'publisher',
        sourceCategory: 'crypto',
        url: Uri.parse('https://cointelegraph.com/news/example'),
        publishedAt: DateTime.utc(2026, 10, 4),
      );
      await expectLater(
        BackendNewsAiClient(
          api: api,
        ).translateArticles(articles: [article], languageCode: 'persian'),
        throwsA(isA<NewsAiException>()),
      );
    },
  );
}
