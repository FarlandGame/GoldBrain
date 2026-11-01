import 'backend_api_client.dart';
import 'backend_connection.dart';
import 'news_ai_service.dart';
import 'news_service.dart';

/// Existing NewsService/NewsArticle interfaces, with Backend-only production IO.
class BackendNewsService extends NewsService {
  BackendNewsService({GoldBrainBackendClient? api})
    : _api = api ?? BackendConnection.instance.api;

  final GoldBrainBackendClient _api;

  @override
  Future<NewsFeedSnapshot> fetchArticles({bool forceRefresh = false}) async {
    try {
      final body = await _api.newsFeed(refresh: forceRefresh);
      final rows = body['articles'];
      final received = DateTime.tryParse(body['fetched_at']?.toString() ?? '');
      if (rows is! List || received == null) {
        throw const FormatException('Invalid news snapshot');
      }
      final articles = <NewsArticle>[];
      final seen = <String>{};
      for (final row in rows) {
        if (row is! Map) throw const FormatException('Invalid article');
        final id = row['article_id'];
        final title = row['title'];
        final summary = row['summary'];
        final source = row['source'];
        final category = row['category'];
        final language = row['language'];
        final uri = Uri.tryParse(row['url']?.toString() ?? '');
        final published = DateTime.tryParse(
          row['published_at']?.toString() ?? '',
        );
        final information = Uri.tryParse(
          row['source_information_url']?.toString() ?? '',
        );
        if (id is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
            !seen.add(id) ||
            title is! String ||
            title.trim().isEmpty ||
            summary is! String ||
            source is! String ||
            source.isEmpty ||
            category is! String ||
            !NewsAiLanguagePolicy.supportedLanguages.contains(language) ||
            uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            published == null) {
          throw const FormatException('Invalid news evidence');
        }
        articles.add(
          NewsArticle(
            id: id,
            title: title,
            summary: summary,
            source: source,
            sourceCategory: category,
            url: uri,
            publishedAt: published.toUtc(),
            sourceLanguageCode: language as String,
            sourceInformationUri:
                information != null &&
                    {'http', 'https'}.contains(information.scheme) &&
                    information.host.isNotEmpty &&
                    information.userInfo.isEmpty
                ? information
                : null,
            relevanceScore: row['relevance_score'] is int
                ? row['relevance_score'] as int
                : 0,
          ),
        );
      }
      final errors = body['source_errors'];
      return NewsFeedSnapshot(
        articles: List.unmodifiable(articles),
        fetchedAt: received.toUtc(),
        fromCache: body['from_cache'] == true,
        sourceErrors: errors is Map
            ? {
                for (final entry in errors.entries)
                  entry.key.toString(): entry.value.toString(),
              }
            : const {},
      );
    } on GoldBrainBackendException {
      throw const NewsServiceException(
        'News is temporarily unavailable. Please try again later.',
      );
    } on FormatException {
      throw const NewsServiceException(
        'The news service returned invalid data.',
      );
    }
  }
}

class BackendNewsAiClient implements NewsAiClient {
  BackendNewsAiClient({GoldBrainBackendClient? api})
    : _api = api ?? BackendConnection.instance.api;

  final GoldBrainBackendClient _api;
  @override
  bool get isConfigured => true; // Configuration/credentials belong to Backend.
  @override
  void close() {} // Shared authenticated transport belongs to BackendConnection.

  @override
  Stream<String> summarizeArticle({
    required NewsArticle article,
    required String languageCode,
  }) async* {
    try {
      final body = await _api.newsSummary(article.id, languageCode);
      final text = body['text'];
      if (body['article_id'] != article.id ||
          body['language'] != languageCode ||
          text is! String ||
          text.trim().isEmpty ||
          text.length > 5000 ||
          !NewsAiLanguagePolicy.isExpectedLanguage(text, languageCode)) {
        throw const NewsAiException(
          'invalid_summary',
          'The summary response was invalid.',
        );
      }
      yield text;
    } on GoldBrainBackendException catch (error) {
      throw _error(error);
    }
  }

  @override
  Future<List<NewsTranslation>> translateArticles({
    required List<NewsArticle> articles,
    required String languageCode,
  }) async {
    try {
      final ids = articles.map((article) => article.id).toList();
      final body = await _api.newsTranslations(ids, languageCode);
      final rows = body['translations'];
      if (rows is! List || rows.length != ids.length) {
        throw const NewsAiException(
          'invalid_translation',
          'The translation response was invalid.',
        );
      }
      final seen = <String>{};
      final translations = <NewsTranslation>[];
      for (final row in rows) {
        if (row is! Map ||
            row['article_id'] is! String ||
            !ids.contains(row['article_id']) ||
            !seen.add(row['article_id'] as String) ||
            row['language'] != languageCode ||
            row['title'] is! String ||
            row['summary'] is! String ||
            row['category'] is! String ||
            !NewsAiLanguagePolicy.isExpectedLanguage(
              '${row['title']} ${row['summary']} ${row['category']}',
              languageCode,
            )) {
          throw const NewsAiException(
            'invalid_translation',
            'The translation response was invalid.',
          );
        }
        translations.add(
          NewsTranslation(
            articleId: row['article_id'] as String,
            languageCode: languageCode,
            title: row['title'] as String,
            summary: row['summary'] as String,
            category: row['category'] as String,
          ),
        );
      }
      return translations;
    } on GoldBrainBackendException catch (error) {
      throw _error(error);
    }
  }

  NewsAiException _error(GoldBrainBackendException error) => NewsAiException(
    error.serverCode == 'assistant_wrong_language'
        ? 'wrong_language'
        : error.code,
    error.code == 'http_429'
        ? 'The free AI request limit has been reached. Please try again later.'
        : 'News AI is temporarily unavailable. Please try again later.',
  );
}
