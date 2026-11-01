import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/news_service.dart';

const _runLiveNewsSmoke = bool.fromEnvironment('GOLDBRAIN_NEWS_SMOKE');

void main() {
  test(
    'configured public RSS feeds return attributed newest-first articles',
    () async {
      final service = NewsService(timeout: const Duration(seconds: 20));
      addTearDown(service.close);

      final snapshot = await service.fetchArticles(forceRefresh: true);

      expect(snapshot.articles, isNotEmpty);
      final publishers = snapshot.articles
          .map((article) => article.source)
          .toSet();
      expect(publishers, contains(NewsService.officialSourceName));
      expect(publishers, contains('Mehr News Agency — Economy'));
      expect(publishers, contains('Mehr News Agency — Gold & Coin'));
      for (var index = 1; index < snapshot.articles.length; index++) {
        expect(
          snapshot.articles[index - 1].publishedAt.isBefore(
            snapshot.articles[index].publishedAt,
          ),
          isFalse,
        );
      }
      for (final article in snapshot.articles) {
        expect(article.source, isNotEmpty);
        expect(article.url.scheme, 'https');
        expect(article.publishedAt.isUtc, isTrue);
        expect(article.sourceLanguageCode, 'persian');
      }
    },
    skip: _runLiveNewsSmoke
        ? false
        : 'Set GOLDBRAIN_NEWS_SMOKE=true to call the public RSS feeds.',
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
