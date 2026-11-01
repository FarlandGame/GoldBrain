import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'news_ai_service.dart';
import 'backend_news_service.dart';
import 'news_service.dart';
import 'local_persistence_policy.dart';

class NewsArticleDisplay {
  const NewsArticleDisplay({
    required this.title,
    required this.summary,
    required this.category,
    required this.isTranslated,
    this.isPlaceholder = false,
    this.translationUnavailable = false,
  });

  final String title;
  final String summary;
  final String category;
  final bool isTranslated;
  final bool isPlaceholder;
  final bool translationUnavailable;
}

class NewsStore extends ChangeNotifier {
  NewsStore({
    NewsService? service,
    NewsAiClient? aiClient,
    Future<SharedPreferences> Function()? preferencesFactory,
    this.autoRefreshInterval = const Duration(minutes: 5),
    this.translationBatchDelay = const Duration(milliseconds: 900),
  }) : _service = service ?? BackendNewsService(),
       _ownsService = service == null,
       _aiClient = aiClient ?? BackendNewsAiClient(),
       _ownsAiClient = aiClient == null,
       _preferencesFactory =
           preferencesFactory ?? SharedPreferences.getInstance;

  static final NewsStore instance = NewsStore();

  static const _readIdsKey = 'news.read_ids.v1';
  // v2 deliberately invalidates older entries which were cached without
  // verifying that the model actually used the requested language.
  static const _translationCacheKey = 'news.translation_cache.v2';
  static const _summaryCacheKey = 'news.summary_cache.v2';
  static const _supportedLanguages = NewsAiLanguagePolicy.supportedLanguages;
  static const _maxRememberedReadIds = 500;
  static const _maxTranslationEntries = 80;
  static const _maxSummaryEntries = 40;
  static const _maxPersistedCacheCharacters = 350000;

  final NewsService _service;
  final bool _ownsService;
  final NewsAiClient _aiClient;
  final bool _ownsAiClient;
  final Future<SharedPreferences> Function() _preferencesFactory;
  final Duration autoRefreshInterval;
  final Duration translationBatchDelay;

  List<NewsArticle> _articles = const [];
  bool _isLoading = false;
  bool _initialized = false;
  bool _fromCache = false;
  bool _disposed = false;
  String? _errorMessage;
  DateTime? _lastUpdated;
  Future<void>? _inFlightLoad;

  SharedPreferences? _preferences;
  Future<void>? _persistenceLoad;
  bool _persistenceLoaded = false;
  final LinkedHashSet<String> _readIds = LinkedHashSet<String>();
  final LinkedHashMap<String, _TranslationCacheEntry> _translations =
      LinkedHashMap<String, _TranslationCacheEntry>();
  final LinkedHashMap<String, _SummaryCacheEntry> _summaries =
      LinkedHashMap<String, _SummaryCacheEntry>();

  String _languageCode = 'english';
  String? _translationErrorMessage;
  final LinkedHashMap<String, NewsArticle> _translationQueue =
      LinkedHashMap<String, NewsArticle>();
  final Set<String> _translatingKeys = <String>{};
  final Set<String> _translationFailures = <String>{};
  Future<void>? _translationWorker;
  int _translationEpoch = 0;

  final Set<String> _summarizingKeys = <String>{};
  final Map<String, String> _summaryDrafts = <String, String>{};
  final Map<String, String> _summaryErrors = <String, String>{};
  final Set<String> _summarySourceFallbackKeys = <String>{};

  Timer? _refreshTimer;
  int _autoRefreshRetainers = 0;

  List<NewsArticle> get articles => _articles;
  bool get isLoading => _isLoading;
  bool get initialized => _initialized;
  bool get fromCache => _fromCache;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasContent => _articles.isNotEmpty;
  bool get isInitialLoading => _isLoading && _articles.isEmpty;
  bool get isRefreshing => _isLoading && _articles.isNotEmpty;
  bool get aiConfigured => _aiClient.isConfigured;
  String get languageCode => _languageCode;
  String? get translationErrorMessage => _translationErrorMessage;
  bool get isTranslating =>
      _translationWorker != null || _translationQueue.isNotEmpty;
  int get unreadCount => _articles.where((article) => !isRead(article)).length;

  bool isRead(NewsArticle article) {
    return _readIds.contains(_readKey(article)) ||
        _readIds.contains(article.id); // Backward compatibility with v1.
  }

  Future<void> load({bool forceRefresh = false}) {
    final activeLoad = _inFlightLoad;
    if (activeLoad != null) return activeLoad;

    final load = _performLoad(forceRefresh: forceRefresh);
    _inFlightLoad = load;
    return load.whenComplete(() {
      if (identical(_inFlightLoad, load)) _inFlightLoad = null;
    });
  }

  Future<void> _performLoad({required bool forceRefresh}) async {
    _isLoading = true;
    _errorMessage = null;
    _notifySafely();

    try {
      await _ensurePersistenceLoaded();
      final snapshot = await _service.fetchArticles(forceRefresh: forceRefresh);
      _articles = List.unmodifiable(
        [...snapshot.articles]..sort((left, right) {
          final relevance = right.relevanceScore.compareTo(left.relevanceScore);
          return relevance != 0
              ? relevance
              : right.publishedAt.compareTo(left.publishedAt);
        }),
      );
      _lastUpdated = snapshot.fetchedAt;
      _fromCache = snapshot.fromCache;
      if (snapshot.sourceErrors.isNotEmpty) {
        _errorMessage =
            'Some news sources could not be refreshed: '
            '${snapshot.sourceErrors.values.toSet().join(' ')}';
      }
      _pruneReadIds();
    } on NewsServiceException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'An unexpected error occurred while loading news.';
    } finally {
      _initialized = true;
      _isLoading = false;
      _notifySafely();
    }
  }

  /// Keeps news fresh while at least one UI owner is interested in updates.
  /// Calls are reference-counted so the page and the sidebar can retain it
  /// independently without cancelling each other's timer.
  void retainAutoRefresh() {
    if (_disposed) return;
    _autoRefreshRetainers++;
    if (_autoRefreshRetainers != 1) return;
    if (!_initialized) unawaited(load());
    _refreshTimer = Timer.periodic(autoRefreshInterval, (_) {
      if (!_isLoading && !_disposed) {
        unawaited(load(forceRefresh: true));
      }
    });
  }

  void releaseAutoRefresh() {
    if (_autoRefreshRetainers > 0) _autoRefreshRetainers--;
    if (_autoRefreshRetainers == 0) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  Future<void> markRead(NewsArticle article) async {
    await _ensurePersistenceLoaded();
    if (!_readIds.add(_readKey(article))) return;
    _notifySafely();
    await _persistReadIds();
  }

  Future<void> markAllRead() async {
    await _ensurePersistenceLoaded();
    var changed = false;
    for (final article in _articles) {
      changed = _readIds.add(_readKey(article)) || changed;
    }
    if (!changed) return;
    _pruneReadIds();
    _notifySafely();
    await _persistReadIds();
  }

  Future<void> setLanguage(String languageCode) async {
    final normalized = _supportedLanguages.contains(languageCode)
        ? languageCode
        : 'english';
    if (_languageCode != normalized) {
      _languageCode = normalized;
      _translationEpoch++;
      _translationQueue.clear();
      _translationErrorMessage = null;
      _notifySafely();
    }
    await ensureTranslations(_articles.take(12));
  }

  NewsArticleDisplay displayFor(NewsArticle article) {
    if (_languageCode == article.sourceLanguageCode) {
      return NewsArticleDisplay(
        title: article.title,
        summary: article.bestAvailableBody,
        category: article.sourceCategory,
        isTranslated: false,
      );
    }
    final key = _contentKey(article, _languageCode);
    final cached =
        _translations[key] ?? _lastValidTranslationFor(article, _languageCode);
    if (cached == null) {
      return _translationPlaceholder(
        _languageCode,
        unavailable:
            _translationFailures.contains(key) || !_aiClient.isConfigured,
      );
    }
    return NewsArticleDisplay(
      title: cached.title,
      summary: cached.summary,
      category: cached.category.isEmpty
          ? _localizedNewsCategory(_languageCode)
          : cached.category,
      isTranslated: true,
    );
  }

  _TranslationCacheEntry? _lastValidTranslationFor(
    NewsArticle article,
    String languageCode,
  ) {
    _TranslationCacheEntry? latest;
    for (final translation in _translations.values) {
      if (translation.articleId != article.id ||
          translation.languageCode != languageCode) {
        continue;
      }
      if (latest == null || translation.savedAt.isAfter(latest.savedAt)) {
        latest = translation;
      }
    }
    return latest;
  }

  NewsArticleDisplay _translationPlaceholder(
    String languageCode, {
    required bool unavailable,
  }) {
    final values = switch (languageCode) {
      'persian' =>
        unavailable
            ? (
                'ترجمه در دسترس نیست',
                'ترجمهٔ این خبر در دسترس نیست. برای خواندن متن ناشر، بخش «متن اصلی» را باز کنید.',
                'ترجمه ناموفق',
              )
            : (
                'ترجمه در حال آماده‌سازی است',
                'این خبر در حال ترجمه به فارسی است.',
                'در حال ترجمه',
              ),
      'japanese' =>
        unavailable
            ? ('翻訳を利用できません', 'この記事の翻訳を利用できません。発行元の文章は「原文」から確認できます。', '翻訳エラー')
            : ('翻訳を準備しています', 'この記事を日本語に翻訳しています。', '翻訳中'),
      'russian' =>
        unavailable
            ? (
                'Перевод недоступен',
                'Перевод этой новости недоступен. Текст издателя можно открыть в разделе «Оригинал».',
                'Ошибка перевода',
              )
            : (
                'Перевод подготавливается',
                'Эта новость переводится на русский язык.',
                'Перевод',
              ),
      'chinese' =>
        unavailable
            ? ('翻译不可用', '此新闻的翻译不可用。可在“发布者原文”部分查看原文。', '翻译失败')
            : ('正在准备翻译', '此新闻正在翻译为中文。', '正在翻译'),
      'arabic' =>
        unavailable
            ? (
                'الترجمة غير متاحة',
                'ترجمة هذا الخبر غير متاحة. يمكن قراءة نص الناشر في قسم «النص الأصلي».',
                'تعذرت الترجمة',
              )
            : (
                'جارٍ إعداد الترجمة',
                'تتم ترجمة هذا الخبر إلى العربية.',
                'جارٍ الترجمة',
              ),
      'turkish' =>
        unavailable
            ? (
                'Çeviri kullanılamıyor',
                'Bu haberin çevirisi kullanılamıyor. Yayıncı metnini “Orijinal metin” bölümünden okuyabilirsiniz.',
                'Çeviri başarısız',
              )
            : (
                'Çeviri hazırlanıyor',
                'Bu haber Türkçeye çevriliyor.',
                'Çevriliyor',
              ),
      'french' =>
        unavailable
            ? (
                'Traduction indisponible',
                'La traduction de cette actualité est indisponible. Le texte de l’éditeur reste accessible dans « Original ».',
                'Échec de la traduction',
              )
            : (
                'Traduction en préparation',
                'Cette actualité est en cours de traduction en français.',
                'Traduction en cours',
              ),
      _ =>
        unavailable
            ? (
                'Translation unavailable',
                'This article could not be translated. Open “Publisher original” to read the source text.',
                'Translation failed',
              )
            : (
                'Translation is being prepared',
                'This article is being translated into English.',
                'Translating',
              ),
    };
    return NewsArticleDisplay(
      title: values.$1,
      summary: values.$2,
      category: values.$3,
      isTranslated: false,
      isPlaceholder: true,
      translationUnavailable: unavailable,
    );
  }

  String _localizedNewsCategory(String languageCode) => switch (languageCode) {
    'persian' => 'اخبار',
    'japanese' => 'ニュース',
    'russian' => 'Новости',
    'chinese' => '新闻',
    'arabic' => 'أخبار',
    'turkish' => 'Haberler',
    'french' => 'Actualités',
    _ => 'News',
  };

  bool isTranslationPending(NewsArticle article) {
    if (_languageCode == article.sourceLanguageCode) return false;
    final key = _contentKey(article, _languageCode);
    return _translationQueue.containsKey(key) || _translatingKeys.contains(key);
  }

  Future<void> ensureTranslations(
    Iterable<NewsArticle> articles, {
    bool retryFailed = false,
  }) async {
    await _ensurePersistenceLoaded();
    if (!_aiClient.isConfigured) {
      const message =
          'GAPGPT_API_KEY is not configured; translated news is unavailable.';
      if (_translationErrorMessage != message) {
        _translationErrorMessage = message;
        _notifySafely();
      }
      return;
    }

    for (final article in articles) {
      if (_languageCode == article.sourceLanguageCode) continue;
      final key = _contentKey(article, _languageCode);
      if (_translations.containsKey(key) ||
          _translatingKeys.contains(key) ||
          (!retryFailed && _translationFailures.contains(key))) {
        continue;
      }
      if (retryFailed) _translationFailures.remove(key);
      _translationQueue[key] = article;
    }
    if (_translationQueue.isEmpty) return;

    _translationErrorMessage = null;
    final activeWorker = _translationWorker;
    if (activeWorker != null) return activeWorker;
    final epoch = _translationEpoch;
    final worker = _runTranslationQueue(epoch);
    _translationWorker = worker;
    _notifySafely();
    await worker.whenComplete(() {
      if (identical(_translationWorker, worker)) {
        _translationWorker = null;
        _notifySafely();
      }
    });
  }

  Future<void> _runTranslationQueue(int epoch) async {
    while (!_disposed && epoch == _translationEpoch) {
      final batchEntries = _translationQueue.entries.take(6).toList();
      if (batchEntries.isEmpty) return;
      for (final entry in batchEntries) {
        _translationQueue.remove(entry.key);
        _translatingKeys.add(entry.key);
      }
      _notifySafely();

      try {
        final translations = await _aiClient.translateArticles(
          articles: batchEntries.map((entry) => entry.value).toList(),
          languageCode: _languageCode,
        );
        if (epoch != _translationEpoch || _disposed) return;
        final requestedById = {
          for (final entry in batchEntries) entry.value.id: entry,
        };
        for (final translation in translations) {
          final requested = requestedById[translation.articleId];
          if (requested == null || translation.languageCode != _languageCode) {
            continue;
          }
          if (!NewsAiLanguagePolicy.isExpectedLanguage(
            '${translation.title}\n${translation.summary}\n${translation.category}',
            _languageCode,
          )) {
            _translationFailures.add(requested.key);
            continue;
          }
          _translations.remove(requested.key);
          _translations[requested.key] = _TranslationCacheEntry(
            articleId: translation.articleId,
            languageCode: translation.languageCode,
            title: _limit(translation.title, 700),
            summary: _limit(translation.summary, 5000),
            category: _limit(translation.category, 500),
            savedAt: DateTime.now().toUtc(),
          );
        }
        for (final entry in batchEntries) {
          if (!_translations.containsKey(entry.key)) {
            _translationFailures.add(entry.key);
          }
        }
        _trimTranslationCache();
        await _persistTranslations();
      } on NewsAiException catch (error) {
        for (final entry in batchEntries) {
          _translationFailures.add(entry.key);
        }
        _translationErrorMessage = error.message;
      } catch (_) {
        for (final entry in batchEntries) {
          _translationFailures.add(entry.key);
        }
        _translationErrorMessage =
            'News translation failed; translated news is unavailable.';
      } finally {
        for (final entry in batchEntries) {
          _translatingKeys.remove(entry.key);
        }
        _notifySafely();
      }

      if (_translationQueue.isNotEmpty &&
          translationBatchDelay > Duration.zero) {
        await Future<void>.delayed(translationBatchDelay);
      }
    }
  }

  String? aiSummaryFor(NewsArticle article) {
    final key = _contentKey(article, _languageCode);
    final value = _summaryDrafts[key] ?? _summaries[key]?.text;
    if (value == null || value.isEmpty) return value;
    if (_summarySourceFallbackKeys.contains(key) ||
        NewsAiLanguagePolicy.isExpectedLanguage(value, _languageCode)) {
      return value;
    }
    _summaryDrafts.remove(key);
    _summaries.remove(key);
    return null;
  }

  bool isSummarySourceFallback(NewsArticle article) {
    return _summarySourceFallbackKeys.contains(
      _contentKey(article, _languageCode),
    );
  }

  String? aiSummaryErrorFor(NewsArticle article) {
    return _summaryErrors[_contentKey(article, _languageCode)];
  }

  bool isSummarizing(NewsArticle article) {
    return _summarizingKeys.contains(_contentKey(article, _languageCode));
  }

  Future<void> generateAiSummary(
    NewsArticle article, {
    bool forceRefresh = false,
  }) async {
    await _ensurePersistenceLoaded();
    final language = _languageCode;
    final key = _contentKey(article, language);
    if (_summarizingKeys.contains(key)) return;
    if (!forceRefresh && _summaries.containsKey(key)) return;
    if (!_aiClient.isConfigured) {
      _summaryErrors[key] =
          'News AI is not configured on the Backend; summary is unavailable.';
      _notifySafely();
      return;
    }

    _summaryErrors.remove(key);
    _summaryDrafts[key] = '';
    _summarySourceFallbackKeys.remove(key);
    _summarizingKeys.add(key);
    _notifySafely();
    try {
      final output = StringBuffer();
      await for (final chunk in _aiClient.summarizeArticle(
        article: article,
        languageCode: language,
      )) {
        if (_disposed || language != _languageCode) return;
        output.write(chunk);
        _summaryDrafts[key] = output.toString();
        _notifySafely();
      }
      final result = output.toString().trim();
      if (result.isEmpty) {
        throw const NewsAiException(
          'empty_summary',
          'The AI returned no summary.',
        );
      }
      if (!NewsAiLanguagePolicy.isExpectedLanguage(result, language)) {
        throw NewsAiException(
          'wrong_language',
          'The AI did not answer in the selected language.',
        );
      }
      _summaries.remove(key);
      _summaries[key] = _SummaryCacheEntry(
        articleId: article.id,
        languageCode: language,
        text: _limit(result, 5000),
        savedAt: DateTime.now().toUtc(),
      );
      _summaryDrafts.remove(key);
      _trimSummaryCache();
      await _persistSummaries();
    } on NewsAiException catch (error) {
      _summaryDrafts.remove(key);
      if (error.code == 'wrong_language' &&
          language == article.sourceLanguageCode) {
        final fallback = _extractiveSourceFallback(article.bestAvailableBody);
        if (fallback.isNotEmpty) {
          _summaryDrafts[key] = fallback;
          _summarySourceFallbackKeys.add(key);
          _summaryErrors[key] =
              'The AI used the wrong language, so publisher text is shown.';
        } else {
          _summaryErrors[key] = error.message;
        }
      } else {
        _summaryErrors[key] = error.message;
      }
    } catch (_) {
      _summaryDrafts.remove(key);
      _summaryErrors[key] = 'Could not connect to the AI summary service.';
    } finally {
      _summarizingKeys.remove(key);
      _notifySafely();
    }
  }

  Future<void> _ensurePersistenceLoaded() {
    if (_persistenceLoaded) return Future.value();
    final active = _persistenceLoad;
    if (active != null) return active;
    final load = _loadPersistence();
    _persistenceLoad = load;
    return load.whenComplete(() {
      _persistenceLoaded = true;
      if (identical(_persistenceLoad, load)) _persistenceLoad = null;
    });
  }

  Future<void> _loadPersistence() async {
    try {
      _preferences = await _preferencesFactory();
      final prefs = _preferences!;
      for (final id in prefs.getStringList(_readIdsKey) ?? const <String>[]) {
        final normalized = _limit(id.trim(), 600);
        if (normalized.isNotEmpty) _readIds.add(normalized);
      }
      _decodeTranslationCache(prefs.getString(_translationCacheKey));
      _decodeSummaryCache(prefs.getString(_summaryCacheKey));
      _pruneReadIds();
      _trimTranslationCache();
      _trimSummaryCache();
    } catch (_) {
      // News still works in-memory when local persistence is unavailable.
      _preferences = null;
    }
  }

  void _decodeTranslationCache(String? raw) {
    if (raw == null || raw.length > _maxPersistedCacheCharacters) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final key = item['key'];
        final articleId = item['articleId'];
        final languageCode = item['languageCode'];
        final title = item['title'];
        final summary = item['summary'];
        final category = item['category'];
        final savedAt = DateTime.tryParse(item['savedAt']?.toString() ?? '');
        if (key is! String ||
            articleId is! String ||
            languageCode is! String ||
            title is! String ||
            summary is! String ||
            category is! String ||
            savedAt == null ||
            key.length > 160 ||
            articleId.length > 600 ||
            !_supportedLanguages.contains(languageCode) ||
            title.isEmpty ||
            title.length > 700 ||
            summary.isEmpty ||
            summary.length > 5000 ||
            category.length > 500) {
          continue;
        }
        if (!NewsAiLanguagePolicy.isExpectedLanguage(
          '$title\n$summary\n$category',
          languageCode,
        )) {
          continue;
        }
        _translations[key] = _TranslationCacheEntry(
          articleId: articleId,
          languageCode: languageCode,
          title: title,
          summary: summary,
          category: category,
          savedAt: savedAt,
        );
      }
    } on FormatException {
      // Ignore a corrupt local cache; never show it as source content.
    }
  }

  void _decodeSummaryCache(String? raw) {
    if (raw == null || raw.length > _maxPersistedCacheCharacters) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final key = item['key'];
        final articleId = item['articleId'];
        final languageCode = item['languageCode'];
        final summary = item['text'];
        final savedAt = DateTime.tryParse(item['savedAt']?.toString() ?? '');
        if (key is! String ||
            articleId is! String ||
            languageCode is! String ||
            summary is! String ||
            savedAt == null ||
            key.length > 160 ||
            articleId.length > 600 ||
            !_supportedLanguages.contains(languageCode) ||
            summary.isEmpty ||
            summary.length > 5000) {
          continue;
        }
        if (!NewsAiLanguagePolicy.isExpectedLanguage(summary, languageCode)) {
          continue;
        }
        _summaries[key] = _SummaryCacheEntry(
          articleId: articleId,
          languageCode: languageCode,
          text: summary,
          savedAt: savedAt,
        );
      }
    } on FormatException {
      // Ignore a corrupt local cache.
    }
  }

  void _pruneReadIds() {
    while (_readIds.length > _maxRememberedReadIds) {
      _readIds.remove(_readIds.first);
    }
  }

  void _trimTranslationCache() {
    while (_translations.length > _maxTranslationEntries) {
      _translations.remove(_translations.keys.first);
    }
  }

  void _trimSummaryCache() {
    while (_summaries.length > _maxSummaryEntries) {
      _summaries.remove(_summaries.keys.first);
    }
  }

  Future<void> _persistReadIds() async {
    if (!LocalPersistencePolicy.instance.canWrite) return;
    final prefs = _preferences;
    if (prefs == null) return;
    _pruneReadIds();
    await prefs.setStringList(_readIdsKey, _readIds.toList());
  }

  Future<void> _persistTranslations() async {
    if (!LocalPersistencePolicy.instance.canWrite) return;
    final prefs = _preferences;
    if (prefs == null) return;
    final value = jsonEncode([
      for (final entry in _translations.entries)
        {
          'key': entry.key,
          'articleId': entry.value.articleId,
          'languageCode': entry.value.languageCode,
          'title': entry.value.title,
          'summary': entry.value.summary,
          'category': entry.value.category,
          'savedAt': entry.value.savedAt.toIso8601String(),
        },
    ]);
    if (value.length <= _maxPersistedCacheCharacters) {
      await prefs.setString(_translationCacheKey, value);
    }
  }

  Future<void> _persistSummaries() async {
    if (!LocalPersistencePolicy.instance.canWrite) return;
    final prefs = _preferences;
    if (prefs == null) return;
    final value = jsonEncode([
      for (final entry in _summaries.entries)
        {
          'key': entry.key,
          'articleId': entry.value.articleId,
          'languageCode': entry.value.languageCode,
          'text': entry.value.text,
          'savedAt': entry.value.savedAt.toIso8601String(),
        },
    ]);
    if (value.length <= _maxPersistedCacheCharacters) {
      await prefs.setString(_summaryCacheKey, value);
    }
  }

  String _contentKey(NewsArticle article, String languageCode) {
    final fingerprint = _fnv64(
      '${article.id}\u0000${article.title}\u0000${article.bestAvailableBody}',
    );
    return 'v2:$languageCode:$fingerprint';
  }

  String _extractiveSourceFallback(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 900) return normalized;
    final excerpt = normalized.substring(0, 900);
    final sentenceEnd = excerpt.lastIndexOf(RegExp(r'[.!?؟。]'));
    if (sentenceEnd >= 300) return excerpt.substring(0, sentenceEnd + 1);
    final wordEnd = excerpt.lastIndexOf(' ');
    return '${excerpt.substring(0, wordEnd > 0 ? wordEnd : excerpt.length)}…';
  }

  String _readKey(NewsArticle article) {
    return _limit('${article.source}|${article.id}', 600);
  }

  String _fnv64(String value) {
    var hash = 0xcbf29ce484222325;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _limit(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (_ownsService) _service.close();
    if (_ownsAiClient) _aiClient.close();
    super.dispose();
  }
}

class _TranslationCacheEntry {
  const _TranslationCacheEntry({
    required this.articleId,
    required this.languageCode,
    required this.title,
    required this.summary,
    required this.category,
    required this.savedAt,
  });

  final String articleId;
  final String languageCode;
  final String title;
  final String summary;
  final String category;
  final DateTime savedAt;
}

class _SummaryCacheEntry {
  const _SummaryCacheEntry({
    required this.articleId,
    required this.languageCode,
    required this.text,
    required this.savedAt,
  });

  final String articleId;
  final String languageCode;
  final String text;
  final DateTime savedAt;
}
