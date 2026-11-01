import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/news_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _rssFixture = '''
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>Tasnim Economy</title>
    <item>
      <title>بازار طلا به‌روز شد</title>
      <link><![CDATA[https://www.tasnimnews.ir/fa/news/1405/05/13/3668001/test-one]]></link>
      <guid>tasnim-3668001</guid>
      <description><![CDATA[گزارش رسمی بازار &amp; طلا.]]></description>
      <category>اقتصادی</category>
      <pubDate>Tue, 4 Aug 2026 20:30:00 GMT</pubDate>
    </item>
    <item>
      <title>گزارش ارز</title>
      <link>https://www.tasnimnews.ir/fa/news/1405/05/12/3667999/test-two</link>
      <description>داده منتشرشده در خوراک رسمی.</description>
      <category>پول و ارز</category>
      <pubDate>Mon, 3 Aug 2026 18:00:00 +0330</pubDate>
    </item>
    <item>
      <title>Duplicate release</title>
      <link>https://www.tasnimnews.ir/fa/news/1405/05/12/3667999/test-two</link>
      <description>Duplicate URL must be ignored.</description>
      <category>Other Announcements</category>
      <pubDate>Mon, 3 Aug 2026 17:00:00 GMT</pubDate>
    </item>
    <item>
      <title>Untrusted link</title>
      <link>https://malicious.example/article</link>
      <description>This must never be exposed.</description>
      <category>Other</category>
      <pubDate>Mon, 3 Aug 2026 16:00:00 GMT</pubDate>
    </item>
    <item>
      <title>Invalid date</title>
      <link>https://www.tasnimnews.ir/fa/news/1405/05/11/3667998/test-three</link>
      <description>This record must be ignored.</description>
      <category>Other</category>
      <pubDate>Mon, 99 Aug 2026 16:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>
''';

http.Response _rssResponse(String source, {int statusCode = 200}) {
  return http.Response.bytes(
    utf8.encode(source),
    statusCode,
    headers: {'content-type': 'text/xml'},
  );
}

void main() {
  test('parses, validates, sorts and caches official RSS articles', () async {
    var requests = 0;
    var now = DateTime.utc(2026, 8, 10, 10);
    final service = NewsService(
      feedUri: NewsService.officialFeedUri,
      client: MockClient((request) async {
        requests++;
        expect(request.url, NewsService.officialFeedUri);
        expect(request.headers['accept'], contains('application/rss+xml'));
        return _rssResponse(_rssFixture);
      }),
      cacheDuration: const Duration(minutes: 10),
      clock: () => now,
    );

    final first = await service.fetchArticles();
    now = now.add(const Duration(minutes: 5));
    final cached = await service.fetchArticles();

    expect(first.fromCache, isFalse);
    expect(cached.fromCache, isTrue);
    expect(requests, 1);
    expect(first.articles, hasLength(2));

    final firstArticle = first.articles.first;
    expect(firstArticle.id, 'tasnim-3668001');
    expect(firstArticle.title, 'بازار طلا به‌روز شد');
    expect(firstArticle.summary, 'گزارش رسمی بازار & طلا.');
    expect(firstArticle.source, NewsService.officialSourceName);
    expect(firstArticle.sourceCategory, 'اقتصادی');
    expect(firstArticle.sourceLanguageCode, 'persian');
    expect(
      firstArticle.url.toString(),
      'https://www.tasnimnews.ir/fa/news/1405/05/13/3668001/test-one',
    );
    expect(firstArticle.publishedAt, DateTime.utc(2026, 8, 4, 20, 30));
    expect(first.articles.last.publishedAt, DateTime.utc(2026, 8, 3, 14, 30));

    await service.fetchArticles(forceRefresh: true);
    expect(requests, 2);
  });

  test('coalesces concurrent network requests', () async {
    var requests = 0;
    final completer = Completer<http.Response>();
    final service = NewsService(
      feedUri: NewsService.officialFeedUri,
      client: MockClient((_) {
        requests++;
        return completer.future;
      }),
    );

    final first = service.fetchArticles();
    final second = service.fetchArticles();
    completer.complete(_rssResponse(_rssFixture));

    final results = await Future.wait([first, second]);
    expect(requests, 1);
    expect(results.first.articles, hasLength(2));
    expect(results.last.articles, hasLength(2));
  });

  test('reports timeout without inserting fallback articles', () async {
    final service = NewsService(
      feedUri: NewsService.officialFeedUri,
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _rssResponse(_rssFixture);
      }),
      timeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      service.fetchArticles(),
      throwsA(
        isA<NewsServiceException>().having(
          (error) => error.message,
          'message',
          contains('did not respond in time'),
        ),
      ),
    );
  });

  test('rejects an invalid XML response', () async {
    final service = NewsService(
      feedUri: NewsService.officialFeedUri,
      client: MockClient((_) async => _rssResponse('<rss><broken>')),
    );

    await expectLater(
      service.fetchArticles(),
      throwsA(
        isA<NewsServiceException>().having(
          (error) => error.message,
          'message',
          contains('invalid XML'),
        ),
      ),
    );
  });

  test('returns an honest empty list when no valid item exists', () async {
    const emptyFeed = '''
      <rss><channel><item><title>Missing fields</title></item></channel></rss>
    ''';
    final service = NewsService(
      feedUri: NewsService.officialFeedUri,
      client: MockClient((_) async => _rssResponse(emptyFeed)),
    );

    final snapshot = await service.fetchArticles();

    expect(snapshot.articles, isEmpty);
  });

  test('uses HTTP validators and accepts a not-modified response', () async {
    var requests = 0;
    final service = NewsService(
      feedUri: NewsService.officialFeedUri,
      client: MockClient((request) async {
        requests++;
        if (requests == 1) {
          return http.Response.bytes(
            utf8.encode(_rssFixture),
            200,
            headers: {
              'content-type': 'text/xml',
              'etag': '"feed-v1"',
              'last-modified': 'Mon, 10 Aug 2026 10:00:00 GMT',
            },
          );
        }
        expect(request.headers['if-none-match'], '"feed-v1"');
        expect(
          request.headers['if-modified-since'],
          'Mon, 10 Aug 2026 10:00:00 GMT',
        );
        return http.Response('', 304);
      }),
    );

    final first = await service.fetchArticles();
    final second = await service.fetchArticles(forceRefresh: true);

    expect(first.articles, hasLength(2));
    expect(second.articles, hasLength(2));
    expect(second.fromCache, isTrue);
    expect(requests, 2);
  });

  test(
    'keeps the longest publisher body supplied in content:encoded',
    () async {
      const feedWithBody = '''
      <rss xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel><item>
          <title>Release title</title>
          <link>https://www.tasnimnews.ir/fa/news/1405/05/19/3668111/release</link>
          <description>Short description.</description>
          <content:encoded><![CDATA[<p>A longer body supplied by the official publisher.</p>]]></content:encoded>
          <pubDate>Mon, 10 Aug 2026 10:00:00 GMT</pubDate>
        </item></channel>
      </rss>
    ''';
      final service = NewsService(
        feedUri: NewsService.officialFeedUri,
        client: MockClient((_) async => _rssResponse(feedWithBody)),
      );

      final snapshot = await service.fetchArticles();

      expect(
        snapshot.articles.single.bestAvailableBody,
        'A longer body supplied by the official publisher.',
      );
    },
  );

  test(
    'merges attributed sources newest-first and reports partial failure',
    () async {
      const mehrFeed = '''
      <rss><channel><item>
        <title>گزارش اقتصادی مهر</title>
        <link>https://www.mehrnews.com/news/6914000/test-economic-report</link>
        <description>خلاصه منتشرشده در RSS مهر.</description>
        <pubDate>Wed, 5 Aug 2026 10:00:00 +0200</pubDate>
      </item></channel></rss>
    ''';
      final service = NewsService(
        sources: [
          NewsService.tasnimEconomySource,
          NewsService.mehrEconomySource,
          NewsService.mehrGoldSource,
        ],
        client: MockClient((request) async {
          if (request.url == NewsService.tasnimEconomySource.feedUri) {
            return _rssResponse('\uFEFF$_rssFixture');
          }
          if (request.url == NewsService.mehrEconomySource.feedUri) {
            return _rssResponse(mehrFeed);
          }
          return http.Response('temporarily unavailable', 503);
        }),
      );

      final snapshot = await service.fetchArticles();

      expect(snapshot.articles.first.source, 'Mehr News Agency — Economy');
      expect(snapshot.articles.first.sourceCategory, 'اقتصاد');
      expect(
        snapshot.sourceErrors['Mehr News Agency — Gold & Coin'],
        contains('HTTP 503'),
      );
      expect(
        snapshot.articles.map((article) => article.source),
        contains(NewsService.officialSourceName),
      );
    },
  );
}
