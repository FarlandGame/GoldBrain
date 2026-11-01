import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/news_ai_service.dart';
import 'package:goldbrain/core/news_service.dart';
import 'package:goldbrain/core/news_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _singleArticleFeed = '''
<rss version="2.0">
  <channel>
    <item>
      <title>Tasnim publishes a gold market report</title>
      <link>https://www.tasnimnews.ir/fa/news/1405/05/13/3668001/gold-market-report</link>
      <guid>real-article</guid>
      <description>Official description.</description>
      <category>Economy</category>
      <pubDate>Tue, 4 Aug 2026 20:30:00 GMT</pubDate>
    </item>
  </channel>
</rss>
''';

const _persianArticleFeed = '''
<rss version="2.0">
  <channel>
    <item>
      <title>گزارش تازه بازار طلا</title>
      <link>https://www.tasnimnews.ir/fa/news/1405/05/13/3668002/gold-market-report</link>
      <guid>real-persian-article</guid>
      <description>این گزارش رسمی، وضعیت تازه بازار طلا را بررسی می‌کند.</description>
      <category>اقتصاد</category>
      <pubDate>Tue, 4 Aug 2026 20:30:00 GMT</pubDate>
    </item>
  </channel>
</rss>
''';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('keeps previously loaded real content when refresh fails', () async {
    var requests = 0;
    final service = NewsService(
      feedUri: NewsService.officialFeedUri,
      client: MockClient((_) async {
        requests++;
        if (requests == 1) {
          return http.Response.bytes(
            utf8.encode(_singleArticleFeed),
            200,
            headers: {'content-type': 'text/xml'},
          );
        }
        return http.Response('unavailable', 503);
      }),
    );
    final store = NewsStore(service: service);

    await store.load();
    expect(store.articles, hasLength(1));
    expect(store.errorMessage, isNull);
    expect(store.initialized, isTrue);

    await store.load(forceRefresh: true);
    expect(store.articles, hasLength(1));
    expect(store.articles.single.id, 'real-article');
    expect(store.errorMessage, contains('HTTP 503'));
    expect(store.isLoading, isFalse);

    store.dispose();
  });

  test('exposes an error with no fabricated fallback content', () async {
    final store = NewsStore(
      service: NewsService(
        feedUri: NewsService.officialFeedUri,
        client: MockClient((_) async => http.Response('failure', 500)),
      ),
    );

    await store.load();

    expect(store.articles, isEmpty);
    expect(store.errorMessage, contains('HTTP 500'));
    expect(store.isInitialLoading, isFalse);

    store.dispose();
  });

  test('persists actual read state and exposes a real unread count', () async {
    NewsStore createStore() => NewsStore(
      service: NewsService(
        feedUri: NewsService.officialFeedUri,
        client: MockClient(
          (_) async =>
              http.Response.bytes(utf8.encode(_singleArticleFeed), 200),
        ),
      ),
      aiClient: _FakeNewsAiClient(configured: false),
    );

    final first = createStore();
    await first.load();
    expect(first.unreadCount, 1);
    await first.markRead(first.articles.single);
    expect(first.unreadCount, 0);
    first.dispose();

    final restored = createStore();
    await restored.load();
    expect(restored.unreadCount, 0);
    expect(restored.isRead(restored.articles.single), isTrue);
    restored.dispose();
  });

  test(
    'translates through AI and reuses the bounded persistent cache',
    () async {
      final firstAi = _FakeNewsAiClient();
      final first = NewsStore(
        service: NewsService(
          feedUri: NewsService.officialFeedUri,
          client: MockClient(
            (_) async =>
                http.Response.bytes(utf8.encode(_singleArticleFeed), 200),
          ),
        ),
        aiClient: firstAi,
        translationBatchDelay: Duration.zero,
      );
      await first.load();
      await first.setLanguage('japanese');

      expect(firstAi.translationRequests, 1);
      expect(first.displayFor(first.articles.single).title, '翻訳された市場見出し');
      expect(first.displayFor(first.articles.single).isTranslated, isTrue);
      first.dispose();

      final secondAi = _FakeNewsAiClient();
      final restored = NewsStore(
        service: NewsService(
          feedUri: NewsService.officialFeedUri,
          client: MockClient(
            (_) async =>
                http.Response.bytes(utf8.encode(_singleArticleFeed), 200),
          ),
        ),
        aiClient: secondAi,
        translationBatchDelay: Duration.zero,
      );
      await restored.load();
      await restored.setLanguage('japanese');

      expect(secondAi.translationRequests, 0);
      expect(restored.displayFor(restored.articles.single).title, '翻訳された市場見出し');
      restored.dispose();
    },
  );

  test(
    'uses original Persian feed text without an unnecessary AI call',
    () async {
      final ai = _FakeNewsAiClient();
      final store = NewsStore(
        service: NewsService(
          feedUri: NewsService.officialFeedUri,
          client: MockClient(
            (_) async =>
                http.Response.bytes(utf8.encode(_singleArticleFeed), 200),
          ),
        ),
        aiClient: ai,
      );

      await store.load();
      await store.setLanguage('persian');

      expect(ai.translationRequests, 0);
      expect(store.displayFor(store.articles.single).isTranslated, isFalse);
      store.dispose();
    },
  );

  test('streams and caches an on-demand AI summary', () async {
    final ai = _FakeNewsAiClient();
    final store = NewsStore(
      service: NewsService(
        feedUri: NewsService.officialFeedUri,
        client: MockClient(
          (_) async =>
              http.Response.bytes(utf8.encode(_singleArticleFeed), 200),
        ),
      ),
      aiClient: ai,
    );
    await store.load();
    final article = store.articles.single;

    await store.generateAiSummary(article);

    expect(store.aiSummaryFor(article), 'Real source summary.');
    expect(store.aiSummaryErrorFor(article), isNull);
    expect(ai.summaryRequests, 1);
    await store.generateAiSummary(article);
    expect(ai.summaryRequests, 1);
    store.dispose();
  });

  test(
    'does not cache a wrong-language AI summary and uses Persian source fallback',
    () async {
      final ai = _FakeNewsAiClient(
        summaryText:
            'This English AI summary must never be cached for Persian.',
      );
      final store = NewsStore(
        service: NewsService(
          feedUri: NewsService.officialFeedUri,
          client: MockClient(
            (_) async =>
                http.Response.bytes(utf8.encode(_persianArticleFeed), 200),
          ),
        ),
        aiClient: ai,
      );
      await store.load();
      await store.setLanguage('persian');
      final article = store.articles.single;

      await store.generateAiSummary(article);

      expect(store.aiSummaryFor(article), article.bestAvailableBody);
      expect(store.aiSummaryFor(article), isNot(contains('This English')));
      expect(store.isSummarySourceFallback(article), isTrue);
      expect(store.aiSummaryErrorFor(article), contains('wrong language'));
      store.dispose();
    },
  );

  test(
    'reports missing AI configuration without inventing a translation',
    () async {
      final store = NewsStore(
        service: NewsService(
          feedUri: NewsService.officialFeedUri,
          client: MockClient(
            (_) async =>
                http.Response.bytes(utf8.encode(_singleArticleFeed), 200),
          ),
        ),
        aiClient: _FakeNewsAiClient(configured: false),
      );
      await store.load();
      await store.setLanguage('japanese');

      final display = store.displayFor(store.articles.single);
      expect(display.isTranslated, isFalse);
      expect(display.isPlaceholder, isTrue);
      expect(display.translationUnavailable, isTrue);
      expect(display.title, '翻訳を利用できません');
      expect(display.title, isNot(store.articles.single.title));
      expect(display.summary, isNot(store.articles.single.bestAvailableBody));
      expect(store.translationErrorMessage, contains('GAPGPT_API_KEY'));
      store.dispose();
    },
  );

  test(
    'uses exact target-language placeholders while translation is pending',
    () async {
      const expectedTitles = {
        'persian': 'ترجمه در حال آماده‌سازی است',
        'english': 'Translation is being prepared',
        'japanese': '翻訳を準備しています',
        'russian': 'Перевод подготавливается',
        'chinese': '正在准备翻译',
        'arabic': 'جارٍ إعداد الترجمة',
        'turkish': 'Çeviri hazırlanıyor',
        'french': 'Traduction en préparation',
      };

      for (final entry in expectedTitles.entries) {
        final ai = _ControlledNewsAiClient();
        final store = _emptyStore(ai);
        final article = _articleWithDifferentSource(entry.key);
        await store.setLanguage(entry.key);

        final translation = store.ensureTranslations([article]);
        await ai.started.future;
        final display = store.displayFor(article);

        expect(display.title, entry.value, reason: entry.key);
        expect(display.isPlaceholder, isTrue, reason: entry.key);
        expect(display.translationUnavailable, isFalse, reason: entry.key);
        expect(display.title, isNot(article.title), reason: entry.key);
        expect(
          display.summary,
          isNot(article.bestAvailableBody),
          reason: entry.key,
        );
        expect(
          display.category,
          isNot(article.sourceCategory),
          reason: entry.key,
        );

        ai.complete(const []);
        await translation;
        store.dispose();
      }
    },
  );

  test(
    'uses exact target-language failure placeholders without source leakage',
    () async {
      const expectedTitles = {
        'persian': 'ترجمه در دسترس نیست',
        'english': 'Translation unavailable',
        'japanese': '翻訳を利用できません',
        'russian': 'Перевод недоступен',
        'chinese': '翻译不可用',
        'arabic': 'الترجمة غير متاحة',
        'turkish': 'Çeviri kullanılamıyor',
        'french': 'Traduction indisponible',
      };

      for (final entry in expectedTitles.entries) {
        final store = _emptyStore(_FailingNewsAiClient());
        final article = _articleWithDifferentSource(entry.key);
        await store.setLanguage(entry.key);
        var notifications = 0;
        store.addListener(() => notifications++);

        await store.ensureTranslations([article]);
        final beforeReads = notifications;
        final display = store.displayFor(article);
        store.displayFor(article);

        expect(display.title, entry.value, reason: entry.key);
        expect(display.isPlaceholder, isTrue, reason: entry.key);
        expect(display.translationUnavailable, isTrue, reason: entry.key);
        expect(display.title, isNot(article.title), reason: entry.key);
        expect(
          display.summary,
          isNot(article.bestAvailableBody),
          reason: entry.key,
        );
        expect(
          display.category,
          isNot(article.sourceCategory),
          reason: entry.key,
        );
        expect(notifications, beforeReads, reason: 'displayFor must stay pure');
        store.dispose();
      }
    },
  );

  test(
    'reuses only the latest valid same-language translation while content refreshes',
    () async {
      final store = _emptyStore(_FakeNewsAiClient());
      await store.setLanguage('japanese');
      final original = NewsArticle(
        id: 'stable-publisher-id',
        title: 'Original headline',
        summary: 'Original publisher description.',
        source: 'Publisher',
        sourceCategory: 'Economy',
        url: Uri.parse('https://example.com/stable'),
        publishedAt: DateTime.utc(2026, 8, 11),
        sourceLanguageCode: 'english',
      );
      await store.ensureTranslations([original]);
      final refreshed = NewsArticle(
        id: original.id,
        title: 'Updated publisher headline',
        summary: 'Updated publisher description.',
        source: original.source,
        sourceCategory: original.sourceCategory,
        url: original.url,
        publishedAt: original.publishedAt,
        sourceLanguageCode: original.sourceLanguageCode,
      );

      final display = store.displayFor(refreshed);

      expect(display.title, '翻訳された市場見出し');
      expect(display.isTranslated, isTrue);
      expect(display.title, isNot(refreshed.title));
      store.dispose();
    },
  );

  test('auto refresh performs a real forced request every interval', () async {
    var requests = 0;
    final secondRequest = Completer<void>();
    final store = NewsStore(
      service: NewsService(
        feedUri: NewsService.officialFeedUri,
        client: MockClient((_) async {
          requests++;
          if (requests == 2 && !secondRequest.isCompleted) {
            secondRequest.complete();
          }
          return http.Response.bytes(utf8.encode(_singleArticleFeed), 200);
        }),
      ),
      aiClient: _FakeNewsAiClient(configured: false),
      autoRefreshInterval: const Duration(milliseconds: 15),
    );
    addTearDown(store.dispose);

    store.retainAutoRefresh();
    await secondRequest.future.timeout(const Duration(seconds: 2));
    store.releaseAutoRefresh();

    expect(requests, greaterThanOrEqualTo(2));
  });

  test('defaults to a five-minute automatic refresh interval', () {
    final store = NewsStore(
      service: NewsService(
        feedUri: NewsService.officialFeedUri,
        client: MockClient((_) async => http.Response('', 500)),
      ),
      aiClient: _FakeNewsAiClient(configured: false),
    );

    expect(store.autoRefreshInterval, const Duration(minutes: 5));
    store.dispose();
  });
}

NewsStore _emptyStore(NewsAiClient aiClient) {
  return NewsStore(
    service: NewsService(
      feedUri: NewsService.officialFeedUri,
      client: MockClient((_) async => http.Response('failure', 500)),
    ),
    aiClient: aiClient,
    translationBatchDelay: Duration.zero,
  );
}

NewsArticle _articleWithDifferentSource(String targetLanguage) {
  final sourceIsPersian = targetLanguage != 'persian';
  return NewsArticle(
    id: 'language-isolation-$targetLanguage',
    title: sourceIsPersian ? 'عنوان فارسی ناشر' : 'Publisher English title',
    summary: sourceIsPersian
        ? 'توضیح فارسی ناشر که نباید در زبان مقصد دیده شود.'
        : 'Publisher English description that must stay in Original.',
    source: 'Test publisher',
    sourceCategory: sourceIsPersian ? 'اقتصاد' : 'Economy',
    url: Uri.parse('https://example.com/news/$targetLanguage'),
    publishedAt: DateTime.utc(2026, 8, 11),
    sourceLanguageCode: sourceIsPersian ? 'persian' : 'english',
  );
}

class _ControlledNewsAiClient implements NewsAiClient {
  final Completer<void> started = Completer<void>();
  final Completer<List<NewsTranslation>> _result =
      Completer<List<NewsTranslation>>();

  @override
  bool get isConfigured => true;

  void complete(List<NewsTranslation> value) => _result.complete(value);

  @override
  Future<List<NewsTranslation>> translateArticles({
    required List<NewsArticle> articles,
    required String languageCode,
  }) {
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  @override
  Stream<String> summarizeArticle({
    required NewsArticle article,
    required String languageCode,
  }) => const Stream.empty();

  @override
  void close() {}
}

class _FailingNewsAiClient implements NewsAiClient {
  @override
  bool get isConfigured => true;

  @override
  Future<List<NewsTranslation>> translateArticles({
    required List<NewsArticle> articles,
    required String languageCode,
  }) => throw const NewsAiException('test_failure', 'Translation failed.');

  @override
  Stream<String> summarizeArticle({
    required NewsArticle article,
    required String languageCode,
  }) => const Stream.empty();

  @override
  void close() {}
}

class _FakeNewsAiClient implements NewsAiClient {
  _FakeNewsAiClient({
    this.configured = true,
    this.summaryText = 'Real source summary.',
  });

  final bool configured;
  final String summaryText;
  int translationRequests = 0;
  int summaryRequests = 0;

  @override
  bool get isConfigured => configured;

  @override
  Future<List<NewsTranslation>> translateArticles({
    required List<NewsArticle> articles,
    required String languageCode,
  }) async {
    translationRequests++;
    final translated = switch (languageCode) {
      'persian' => ('عنوان ترجمه‌شده', 'توضیح ترجمه‌شده', 'سیاست پولی'),
      'japanese' => ('翻訳された市場見出し', 'これは市場ニュースの翻訳された説明です。', '経済ニュース'),
      'russian' => (
        'Переведённый заголовок рынка',
        'Это переведённое описание новости о рынке.',
        'Экономика',
      ),
      'chinese' => ('已翻译的市场标题', '这是市场新闻的翻译说明。', '财经新闻'),
      'arabic' => (
        'عنوان السوق المترجم',
        'هذا وصف مترجم لأخبار السوق.',
        'أخبار اقتصادية',
      ),
      'turkish' => (
        'Çevrilmiş piyasa başlığı',
        'Bu, piyasa haberinin çevrilmiş açıklamasıdır.',
        'Ekonomi haberi',
      ),
      'french' => (
        'Titre traduit du marché',
        'Cette description présente les nouvelles du marché.',
        'Actualité économique',
      ),
      _ => (
        'Translated market headline',
        'This is the translated market news description.',
        'Economic news',
      ),
    };
    return [
      for (final article in articles)
        NewsTranslation(
          articleId: article.id,
          languageCode: languageCode,
          title: translated.$1,
          summary: translated.$2,
          category: translated.$3,
        ),
    ];
  }

  @override
  Stream<String> summarizeArticle({
    required NewsArticle article,
    required String languageCode,
  }) async* {
    summaryRequests++;
    final midpoint = summaryText.length ~/ 2;
    yield summaryText.substring(0, midpoint);
    yield summaryText.substring(midpoint);
  }

  @override
  void close() {}
}
