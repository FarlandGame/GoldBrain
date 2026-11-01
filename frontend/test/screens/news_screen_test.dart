import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/news_ai_service.dart';
import 'package:goldbrain/core/news_service.dart';
import 'package:goldbrain/core/news_store.dart';
import 'package:goldbrain/screens/news_screen.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _widgetFeed = '''
<rss version="2.0">
  <channel>
    <item>
      <title>Tasnim publishes a gold market report</title>
      <link>https://www.tasnimnews.ir/fa/news/1405/05/13/3668001/gold-market-report</link>
      <guid>widget-real-article</guid>
      <description>Official policy statement from the source.</description>
      <category>Economy</category>
      <pubDate>Tue, 4 Aug 2026 20:30:00 GMT</pubDate>
    </item>
  </channel>
</rss>
''';

const _persianWidgetFeed = '''
<rss version="2.0">
  <channel>
    <item>
      <title>عنوان فارسی ناشر</title>
      <link>https://www.tasnimnews.ir/fa/news/1405/05/13/3668002/gold-market-report</link>
      <guid>widget-persian-article</guid>
      <description>توضیح فارسی ناشر فقط باید در بخش متن اصلی باشد.</description>
      <category>اقتصاد</category>
      <pubDate>Tue, 4 Aug 2026 20:30:00 GMT</pubDate>
    </item>
  </channel>
</rss>
''';

Widget _appFor(
  NewsStore store, {
  bool disableAnimations = false,
  GoldBrainLanguage language = GoldBrainLanguage.english,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 1200,
          child: NewsScreen(
            palette: themePalettes[GoldBrainTheme.gold]!,
            selectedLanguage: language,
            newsStore: store,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows real RSS fields and no fabricated analysis or impact', (
    tester,
  ) async {
    final store = NewsStore(
      service: NewsService(
        sources: [
          NewsFeedSource(
            id: 'english-widget-feed',
            name: NewsService.officialSourceName,
            feedUri: NewsService.officialFeedUri,
            informationUri: NewsService.officialFeedInformationUri,
            allowedArticleHosts: const {'tasnimnews.ir', 'www.tasnimnews.ir'},
            defaultCategory: 'Economy',
            languageCode: 'english',
          ),
        ],
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(_widgetFeed),
            200,
            headers: {'content-type': 'text/xml'},
          ),
        ),
      ),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(_appFor(store));
    expect(find.byKey(const ValueKey('news-loading')), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Financial News'), findsOneWidget);
    expect(find.text('Tasnim publishes a gold market report'), findsWidgets);
    expect(
      find.text('Official policy statement from the source.'),
      findsOneWidget,
    );
    expect(find.text('Economy'), findsWidgets);
    expect(find.byKey(const ValueKey('open-original-news')), findsOneWidget);
    expect(find.text('GOLDBRAIN AI ANALYSIS'), findsNothing);
    expect(find.text('AI ANALYZED'), findsNothing);
    expect(find.text('8.7'), findsNothing);
    expect(find.text('BREAKING'), findsNothing);
  });

  testWidgets('shows an honest unavailable state on feed failure', (
    tester,
  ) async {
    final store = NewsStore(
      service: NewsService(
        feedUri: NewsService.officialFeedUri,
        client: MockClient((_) async => http.Response('failure', 503)),
      ),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(_appFor(store));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('news-error')), findsOneWidget);
    expect(find.text('Official news is currently unavailable'), findsOneWidget);
    expect(find.textContaining('fabricated content'), findsOneWidget);
    expect(find.text('Gold advances as markets reassess'), findsNothing);
  });

  testWidgets('one unavailable source does not label the entire feed failed', (
    tester,
  ) async {
    final store = NewsStore(
      service: NewsService(
        sources: [
          NewsFeedSource(
            id: 'available-feed',
            name: 'Available publisher',
            feedUri: Uri.parse('https://www.tasnimnews.ir/available-feed'),
            informationUri: NewsService.officialFeedInformationUri,
            allowedArticleHosts: const {'www.tasnimnews.ir'},
            defaultCategory: 'Economy',
            languageCode: 'english',
          ),
          NewsFeedSource(
            id: 'unavailable-feed',
            name: 'Unavailable publisher',
            feedUri: Uri.parse('https://www.tasnimnews.ir/unavailable-feed'),
            informationUri: NewsService.officialFeedInformationUri,
            allowedArticleHosts: const {'www.tasnimnews.ir'},
            defaultCategory: 'Economy',
            languageCode: 'english',
          ),
        ],
        client: MockClient(
          (request) async => request.url.path == '/available-feed'
              ? http.Response.bytes(utf8.encode(_widgetFeed), 200)
              : http.Response('failure', 503),
        ),
      ),
      aiClient: _UnconfiguredNewsAiClient(),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(_appFor(store));
    await tester.pumpAndSettle();

    expect(find.text('Tasnim publishes a gold market report'), findsWidgets);
    expect(
      find.textContaining(
        'Some news sources are unavailable. Available articles remain visible.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('The latest refresh failed'), findsNothing);
    expect(find.byKey(const ValueKey('news-error')), findsNothing);
    expect(find.text('NEWS FEED'), findsOneWidget);
  });

  testWidgets('honors platform reduced-motion for the news entrance', (
    tester,
  ) async {
    final store = NewsStore(
      service: NewsService(
        feedUri: NewsService.officialFeedUri,
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(_widgetFeed), 200),
        ),
      ),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(_appFor(store, disableAnimations: true));

    expect(find.byKey(const ValueKey('news-entrance-header')), findsNothing);
    expect(find.byKey(const ValueKey('news-entrance-filters')), findsNothing);
    expect(find.byKey(const ValueKey('news-entrance-content')), findsNothing);
  });

  testWidgets('localizes the news shell for Chinese', (tester) async {
    final store = NewsStore(
      service: NewsService(
        feedUri: NewsService.officialFeedUri,
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(_widgetFeed), 200),
        ),
      ),
    );
    addTearDown(store.dispose);

    await tester.pumpWidget(
      _appFor(store, language: GoldBrainLanguage.chinese),
    );
    await tester.pumpAndSettle();

    expect(find.text('财经新闻'), findsOneWidget);
    expect(find.textContaining('每 5 分钟自动刷新'), findsOneWidget);
  });

  testWidgets(
    'hides Persian publisher fields until Chinese translation exists',
    (tester) async {
      final store = NewsStore(
        service: NewsService(
          feedUri: NewsService.officialFeedUri,
          client: MockClient(
            (_) async =>
                http.Response.bytes(utf8.encode(_persianWidgetFeed), 200),
          ),
        ),
        aiClient: _UnconfiguredNewsAiClient(),
      );
      addTearDown(store.dispose);

      await tester.pumpWidget(
        _appFor(store, language: GoldBrainLanguage.chinese),
      );
      await tester.pumpAndSettle();

      expect(find.text('翻译不可用'), findsWidgets);
      expect(find.text('标题 فارسی ناشر'), findsNothing);
      expect(find.text('عنوان فارسی ناشر'), findsNothing);
      expect(
        find.text('توضیح فارسی ناشر فقط باید در بخش متن اصلی باشد.'),
        findsNothing,
      );
      expect(find.text('查看发布者原文'), findsOneWidget);

      await tester.ensureVisible(find.text('查看发布者原文'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看发布者原文'));
      await tester.pumpAndSettle();

      expect(find.textContaining('عنوان فارسی ناشر'), findsOneWidget);
      expect(
        find.textContaining('توضیح فارسی ناشر فقط باید در بخش متن اصلی باشد.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('localizes the AI summary label for every new language', (
    tester,
  ) async {
    const expectedLabels = {
      GoldBrainLanguage.arabic: 'ملخص اختياري بالذكاء الاصطناعي',
      GoldBrainLanguage.turkish: 'İSTEĞE BAĞLI YAPAY ZEKÂ ÖZETİ',
      GoldBrainLanguage.french: 'RÉSUMÉ IA FACULTATIF',
    };

    for (final entry in expectedLabels.entries) {
      final store = NewsStore(
        service: NewsService(
          feedUri: NewsService.officialFeedUri,
          client: MockClient(
            (_) async => http.Response.bytes(utf8.encode(_widgetFeed), 200),
          ),
        ),
      );
      await tester.pumpWidget(_appFor(store, language: entry.key));
      await tester.pumpAndSettle();

      expect(find.text(entry.value), findsOneWidget, reason: entry.key.name);

      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    }
  });
}

class _UnconfiguredNewsAiClient implements NewsAiClient {
  @override
  bool get isConfigured => false;

  @override
  Future<List<NewsTranslation>> translateArticles({
    required List<NewsArticle> articles,
    required String languageCode,
  }) => Future.value(const []);

  @override
  Stream<String> summarizeArticle({
    required NewsArticle article,
    required String languageCode,
  }) => const Stream.empty();

  @override
  void close() {}
}
