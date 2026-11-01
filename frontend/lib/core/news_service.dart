import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class NewsFeedSource {
  const NewsFeedSource({
    required this.id,
    required this.name,
    required this.feedUri,
    required this.informationUri,
    required this.allowedArticleHosts,
    required this.defaultCategory,
    this.languageCode = 'english',
  });

  final String id;
  final String name;
  final Uri feedUri;
  final Uri informationUri;
  final Set<String> allowedArticleHosts;
  final String defaultCategory;
  final String languageCode;
}

class NewsArticle {
  const NewsArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.source,
    required this.sourceCategory,
    required this.url,
    required this.publishedAt,
    this.content = '',
    this.sourceInformationUri,
    this.sourceLanguageCode = 'english',
    this.relevanceScore = 0,
  });

  final String id;
  final String title;
  final String summary;
  final String source;
  final String sourceCategory;
  final Uri url;
  final DateTime publishedAt;
  final String content;
  final Uri? sourceInformationUri;
  final String sourceLanguageCode;
  final int relevanceScore;

  /// Longest text that the publisher itself supplied in RSS.
  /// It is never generated or expanded by the application.
  String get bestAvailableBody {
    final body = content.trim();
    if (body.isNotEmpty) return body;
    final description = summary.trim();
    return description.isEmpty ? title : description;
  }
}

class NewsFeedSnapshot {
  const NewsFeedSnapshot({
    required this.articles,
    required this.fetchedAt,
    required this.fromCache,
    this.sourceErrors = const {},
  });

  final List<NewsArticle> articles;
  final DateTime fetchedAt;
  final bool fromCache;
  final Map<String, String> sourceErrors;

  NewsFeedSnapshot asCached() {
    return NewsFeedSnapshot(
      articles: articles,
      fetchedAt: fetchedAt,
      fromCache: true,
      sourceErrors: sourceErrors,
    );
  }
}

class NewsServiceException implements Exception {
  const NewsServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NewsService {
  NewsService({
    http.Client? client,
    Uri? feedUri,
    List<NewsFeedSource>? sources,
    this.timeout = const Duration(seconds: 12),
    this.cacheDuration = const Duration(seconds: 45),
    this.maxArticles = 30,
    this.maxArticlesPerSource = 12,
    DateTime Function()? clock,
  }) : assert(feedUri == null || sources == null),
       assert(maxArticles > 0),
       assert(maxArticlesPerSource > 0),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       sources = List.unmodifiable(
         sources ??
             (feedUri == null
                 ? defaultSources
                 : [
                     NewsFeedSource(
                       id: 'tasnim-economy-test-feed',
                       name: officialSourceName,
                       feedUri: feedUri,
                       informationUri: officialFeedInformationUri,
                       allowedArticleHosts:
                           tasnimEconomySource.allowedArticleHosts,
                       defaultCategory: 'اقتصادی',
                       languageCode: 'persian',
                     ),
                   ]),
       ),
       feedUri = feedUri ?? (sources?.firstOrNull?.feedUri ?? officialFeedUri),
       _clock = clock ?? DateTime.now;

  static final Uri officialFeedUri = Uri.parse(
    'https://www.tasnimnews.ir/fa/rss/feeds/7/0/0/0',
  );
  static final Uri officialFeedInformationUri = Uri.parse(
    'https://www.tasnimnews.ir/fa/rss',
  );
  static const String officialSourceName = 'Tasnim News Agency — Economy';

  /// Tasnim publishes this endpoint on its official RSS catalogue and states
  /// that its content is available under CC BY 4.0 on that same page.
  static final NewsFeedSource tasnimEconomySource = NewsFeedSource(
    id: 'tasnim-economy',
    name: officialSourceName,
    feedUri: officialFeedUri,
    informationUri: officialFeedInformationUri,
    allowedArticleHosts: const {'tasnimnews.ir', 'www.tasnimnews.ir'},
    defaultCategory: 'اقتصادی',
    languageCode: 'persian',
  );

  /// Mehr exposes these publisher-authored RSS feeds publicly. GoldBrain only
  /// displays their attributed headline/description and links to the original.
  static final NewsFeedSource mehrEconomySource = NewsFeedSource(
    id: 'mehr-economy',
    name: 'Mehr News Agency — Economy',
    feedUri: Uri.parse('https://www.mehrnews.com/rss/tp/25'),
    informationUri: Uri.parse('https://www.mehrnews.com/service/Economy'),
    allowedArticleHosts: const {'mehrnews.com', 'www.mehrnews.com'},
    defaultCategory: 'اقتصاد',
    languageCode: 'persian',
  );

  static final NewsFeedSource mehrGoldSource = NewsFeedSource(
    id: 'mehr-gold',
    name: 'Mehr News Agency — Gold & Coin',
    feedUri: Uri.parse('https://www.mehrnews.com/rss/tp/672'),
    informationUri: Uri.parse(
      'https://www.mehrnews.com/service/markets/Gold-coins',
    ),
    allowedArticleHosts: const {'mehrnews.com', 'www.mehrnews.com'},
    defaultCategory: 'طلا و سکه',
    languageCode: 'persian',
  );

  static final List<NewsFeedSource> defaultSources = List.unmodifiable([
    tasnimEconomySource,
    mehrEconomySource,
    mehrGoldSource,
  ]);

  static const int _maximumResponseBytes = 2 * 1024 * 1024;
  static const int _maximumTitleCharacters = 1000;
  static const int _maximumBodyCharacters = 12000;
  static const int _maximumIdCharacters = 600;

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;
  final Uri feedUri;
  final List<NewsFeedSource> sources;
  final Duration timeout;
  final Duration cacheDuration;
  final int maxArticles;
  final int maxArticlesPerSource;

  NewsFeedSnapshot? _cachedSnapshot;
  Future<NewsFeedSnapshot>? _inFlightRequest;
  final Map<String, String> _etags = {};
  final Map<String, String> _lastModifiedValues = {};
  final Map<String, List<NewsArticle>> _sourceCaches = {};

  Future<NewsFeedSnapshot> fetchArticles({bool forceRefresh = false}) {
    final cached = _cachedSnapshot;
    final now = _clock();
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.fetchedAt) < cacheDuration) {
      return Future.value(cached.asCached());
    }

    final activeRequest = _inFlightRequest;
    if (activeRequest != null) return activeRequest;

    final request = _fetchFromNetwork();
    _inFlightRequest = request;
    return request.whenComplete(() {
      if (identical(_inFlightRequest, request)) _inFlightRequest = null;
    });
  }

  Future<NewsFeedSnapshot> _fetchFromNetwork() async {
    final outcomes = await Future.wait([
      for (final source in sources) _fetchSourceSafely(source),
    ]);
    final articles = <NewsArticle>[];
    final seenUrls = <String>{};
    final sourceErrors = <String, String>{};
    var successfulSources = 0;
    var usedNetworkResponse = false;

    for (final outcome in outcomes) {
      if (outcome.error != null) {
        sourceErrors[outcome.source.name] = outcome.error!;
        final previous = _sourceCaches[outcome.source.id];
        if (previous != null) {
          for (final article in previous) {
            if (seenUrls.add(article.url.toString())) articles.add(article);
          }
        }
        continue;
      }
      successfulSources++;
      usedNetworkResponse = usedNetworkResponse || !outcome.fromCache;
      for (final article in outcome.articles) {
        if (seenUrls.add(article.url.toString())) articles.add(article);
      }
    }

    if (successfulSources == 0) {
      final details = sourceErrors.values.toSet().join(' ');
      throw NewsServiceException(
        details.isEmpty
            ? 'Could not connect to any configured news source.'
            : details,
      );
    }

    articles.sort(
      (left, right) => right.publishedAt.compareTo(left.publishedAt),
    );
    final limited = articles.take(maxArticles).toList(growable: false);
    final snapshot = NewsFeedSnapshot(
      articles: List.unmodifiable(limited),
      fetchedAt: _clock(),
      fromCache: !usedNetworkResponse,
      sourceErrors: Map.unmodifiable(sourceErrors),
    );
    _cachedSnapshot = snapshot;
    return snapshot;
  }

  Future<_SourceOutcome> _fetchSourceSafely(NewsFeedSource source) async {
    try {
      return await _fetchSource(source);
    } on NewsServiceException catch (error) {
      return _SourceOutcome(source: source, error: error.message);
    } catch (_) {
      return _SourceOutcome(
        source: source,
        error: '${source.name} returned an unexpected error.',
      );
    }
  }

  Future<_SourceOutcome> _fetchSource(NewsFeedSource source) async {
    late final http.Response response;
    try {
      final headers = <String, String>{
        'accept': 'application/rss+xml, application/xml, text/xml',
        'user-agent': 'GoldBrain/1.0 (financial news reader)',
      };
      if (_etags[source.id] case final etag?) {
        headers['if-none-match'] = etag;
      }
      if (_lastModifiedValues[source.id] case final value?) {
        headers['if-modified-since'] = value;
      }
      response = await _client
          .get(source.feedUri, headers: headers)
          .timeout(timeout);
    } on TimeoutException {
      throw NewsServiceException('${source.name} did not respond in time.');
    } on http.ClientException {
      throw NewsServiceException('Could not connect to ${source.name}.');
    }

    if (response.statusCode == 304) {
      final cached = _sourceCaches[source.id];
      if (cached == null) {
        throw NewsServiceException(
          '${source.name} returned not-modified without a local copy.',
        );
      }
      return _SourceOutcome(source: source, articles: cached, fromCache: true);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NewsServiceException(
        '${source.name} returned HTTP ${response.statusCode}.',
      );
    }
    if (response.bodyBytes.length > _maximumResponseBytes) {
      throw NewsServiceException(
        '${source.name} returned an unexpectedly large response.',
      );
    }

    late final String xml;
    try {
      xml = utf8.decode(response.bodyBytes, allowMalformed: false);
    } on FormatException {
      throw NewsServiceException('${source.name} returned invalid UTF-8 data.');
    }

    late final List<NewsArticle> articles;
    try {
      final normalized = xml.startsWith('\uFEFF') ? xml.substring(1) : xml;
      articles = _parseRss(normalized, source);
    } on XmlParserException {
      throw NewsServiceException('${source.name} returned invalid XML data.');
    } on FormatException {
      throw NewsServiceException('${source.name} returned invalid XML data.');
    }

    _sourceCaches[source.id] = List.unmodifiable(articles);
    final etag = response.headers['etag'];
    final lastModified = response.headers['last-modified'];
    if (etag != null && etag.length <= 500) _etags[source.id] = etag;
    if (lastModified != null && lastModified.length <= 500) {
      _lastModifiedValues[source.id] = lastModified;
    }
    return _SourceOutcome(source: source, articles: articles);
  }

  List<NewsArticle> _parseRss(String xml, NewsFeedSource source) {
    final document = XmlDocument.parse(xml);
    final articles = <NewsArticle>[];
    final seenUrls = <String>{};

    for (final item in document.findAllElements('item')) {
      if (articles.length >= maxArticlesPerSource) break;
      final title = _limitedNormalized(
        item.getElement('title')?.innerText,
        _maximumTitleCharacters,
      );
      final linkText = _limitedNormalized(
        item.getElement('link')?.innerText,
        2000,
      );
      final publishedText = _limitedNormalized(
        item.getElement('pubDate')?.innerText,
        200,
      );
      final url = Uri.tryParse(linkText);
      final publishedAt = _parsePublishedAt(publishedText);

      if (title.isEmpty ||
          url == null ||
          !_isTrustedArticleUrl(url, source) ||
          publishedAt == null ||
          !seenUrls.add(url.toString())) {
        continue;
      }

      final guid = _limitedNormalized(
        item.getElement('guid')?.innerText,
        _maximumIdCharacters,
      );
      final description = _cleanDescription(
        item.getElement('description')?.innerText ?? '',
      );
      final encodedContent = item.childElements
          .where((element) => element.name.local == 'encoded')
          .map((element) => _cleanDescription(element.innerText))
          .where((value) => value.isNotEmpty)
          .fold<String>('', (best, value) {
            return value.length > best.length ? value : best;
          });
      final category = _limitedNormalized(
        item.getElement('category')?.innerText,
        500,
      );

      articles.add(
        NewsArticle(
          id: guid.isEmpty ? url.toString() : guid,
          title: _decodeCommonEntities(title),
          summary: description,
          source: source.name,
          sourceCategory: _decodeCommonEntities(
            category.isEmpty ? source.defaultCategory : category,
          ),
          url: url,
          publishedAt: publishedAt,
          content: encodedContent.length > description.length
              ? encodedContent
              : '',
          sourceInformationUri: source.informationUri,
          sourceLanguageCode: source.languageCode,
        ),
      );
    }
    articles.sort(
      (left, right) => right.publishedAt.compareTo(left.publishedAt),
    );
    return articles;
  }

  bool _isTrustedArticleUrl(Uri uri, NewsFeedSource source) {
    return uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        source.allowedArticleHosts.contains(uri.host.toLowerCase());
  }

  DateTime? _parsePublishedAt(String value) {
    final isoDate = DateTime.tryParse(value);
    if (isoDate != null) return isoDate.toUtc();
    final match = RegExp(
      r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s+(GMT|UTC|UT|Z|[+-]\d{4})$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    try {
      final year = int.parse(match.group(3)!);
      final day = int.parse(match.group(1)!);
      final hour = int.parse(match.group(4)!);
      final minute = int.parse(match.group(5)!);
      final second = int.parse(match.group(6) ?? '0');
      if (day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) {
        return null;
      }
      var date = DateTime.utc(year, month, day, hour, minute, second);
      if (date.year != year ||
          date.month != month ||
          date.day != day ||
          date.hour != hour ||
          date.minute != minute ||
          date.second != second) {
        return null;
      }
      final zone = match.group(7)!.toUpperCase();
      if (zone.startsWith('+') || zone.startsWith('-')) {
        final sign = zone.startsWith('+') ? 1 : -1;
        final hours = int.parse(zone.substring(1, 3));
        final minutes = int.parse(zone.substring(3, 5));
        if (hours > 23 || minutes > 59) return null;
        date = date.subtract(Duration(minutes: sign * (hours * 60 + minutes)));
      }
      return date;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  String _cleanDescription(String value) {
    final withoutMarkup = value.replaceAll(RegExp(r'<[^>]*>'), ' ');
    final normalized = _decodeCommonEntities(
      withoutMarkup.replaceAll(RegExp(r'\s+'), ' ').trim(),
    );
    return _limit(normalized, _maximumBodyCharacters);
  }

  String _limitedNormalized(String? value, int maxLength) {
    final normalized = (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return _limit(normalized, maxLength);
  }

  String _limit(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }

  String _decodeCommonEntities(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
  }

  void clearCache() {
    _cachedSnapshot = null;
    _etags.clear();
    _lastModifiedValues.clear();
    _sourceCaches.clear();
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class _SourceOutcome {
  const _SourceOutcome({
    required this.source,
    this.articles = const [],
    this.fromCache = false,
    this.error,
  });

  final NewsFeedSource source;
  final List<NewsArticle> articles;
  final bool fromCache;
  final String? error;
}
