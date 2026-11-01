import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/chat_message_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/motion_preferences.dart';
import '../core/app_translations.dart';
import '../core/news_service.dart';
import '../core/news_store.dart';
import 'selection_screen.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({
    super.key,
    required this.palette,
    required this.selectedLanguage,
    this.newsStore,
  });

  final ThemePalette palette;
  final GoldBrainLanguage selectedLanguage;
  final NewsStore? newsStore;

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final AnimationController _entranceController;
  late NewsStore _store;
  String? _selectedArticleId;
  String? _selectedCategory;

  ThemePalette get palette => widget.palette;
  bool get _isRtl =>
      widget.selectedLanguage == GoldBrainLanguage.persian ||
      widget.selectedLanguage == GoldBrainLanguage.arabic;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: MotionPreferences.controllerDuration(720),
    )..forward();
    _attachStore(widget.newsStore ?? NewsStore.instance);
    _store.retainAutoRefresh();
    unawaited(_store.setLanguage(widget.selectedLanguage.name));
    unawaited(_store.load());
  }

  @override
  void didUpdateWidget(covariant NewsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextStore = widget.newsStore ?? NewsStore.instance;
    final storeChanged = !identical(nextStore, _store);
    if (storeChanged) {
      _store.releaseAutoRefresh();
      _store.removeListener(_onStoreChanged);
      _attachStore(nextStore);
      _store.retainAutoRefresh();
      unawaited(_store.load());
    }
    if (storeChanged || oldWidget.selectedLanguage != widget.selectedLanguage) {
      unawaited(_store.setLanguage(widget.selectedLanguage.name));
    }
  }

  void _attachStore(NewsStore store) {
    _store = store;
    _store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (!mounted) return;
    final selectedId = _selectedArticleId;
    if (selectedId != null &&
        !_store.articles.any((article) => article.id == selectedId)) {
      _selectedArticleId = null;
    }
    final selectedCategory = _selectedCategory;
    if (selectedCategory != null &&
        !_store.articles.any(
          (article) => _store.displayFor(article).category == selectedCategory,
        )) {
      _selectedCategory = null;
    }
    setState(() {});
    if (_store.hasContent) {
      unawaited(_store.ensureTranslations(_store.articles.take(12)));
    }
  }

  @override
  void dispose() {
    _store.releaseAutoRefresh();
    _store.removeListener(_onStoreChanged);
    _searchController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  String tr({
    required String en,
    required String fa,
    required String ja,
    required String ru,
    required String zh,
    String? ar,
    String? trText,
    String? fr,
  }) {
    switch (widget.selectedLanguage) {
      case GoldBrainLanguage.persian:
        return fa;
      case GoldBrainLanguage.japanese:
        return ja;
      case GoldBrainLanguage.russian:
        return ru;
      case GoldBrainLanguage.english:
        return en;
      case GoldBrainLanguage.chinese:
        return zh;
      case GoldBrainLanguage.arabic:
        return ar ?? AppTranslations.arabic(en);
      case GoldBrainLanguage.turkish:
        return trText ?? AppTranslations.turkish(en);
      case GoldBrainLanguage.french:
        return fr ?? AppTranslations.french(en);
    }
  }

  TextDirection get _articleDirection =>
      _isRtl ? TextDirection.rtl : TextDirection.ltr;

  String? _technicalMessage(String? value) {
    return widget.selectedLanguage == GoldBrainLanguage.english ? value : null;
  }

  List<String> get _categories {
    final values = _store.articles
        .map((article) => _store.displayFor(article).category)
        .where((category) => category.trim().isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  List<NewsArticle> get _visibleArticles {
    final query = _searchController.text.trim().toLowerCase();
    return _store.articles.where((article) {
      final display = _store.displayFor(article);
      final categoryMatches =
          _selectedCategory == null || display.category == _selectedCategory;
      final queryMatches =
          query.isEmpty ||
          display.title.toLowerCase().contains(query) ||
          display.summary.toLowerCase().contains(query) ||
          article.title.toLowerCase().contains(query) ||
          article.source.toLowerCase().contains(query) ||
          display.category.toLowerCase().contains(query);
      return categoryMatches && queryMatches;
    }).toList();
  }

  NewsArticle? get _selectedArticle {
    final items = _visibleArticles;
    if (items.isEmpty) return null;
    final selectedId = _selectedArticleId;
    if (selectedId == null) return items.first;
    for (final article in items) {
      if (article.id == selectedId) return article;
    }
    return items.first;
  }

  void _selectArticle(NewsArticle article) {
    setState(() => _selectedArticleId = article.id);
    unawaited(_store.markRead(article));
    if (widget.selectedLanguage.name != article.sourceLanguageCode) {
      unawaited(_store.ensureTranslations([article]));
    }
  }

  Future<void> _openArticle(NewsArticle article) async {
    var opened = false;
    try {
      opened = await launchUrl(
        article.url,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!mounted || opened) return;
    _showMessage(
      tr(
        en: 'The original article could not be opened.',
        fa: 'بازکردن نسخه اصلی خبر ممکن نشد.',
        ja: '元の記事を開けませんでした。',
        ru: 'Не удалось открыть оригинал новости.',
        zh: '无法打开原始新闻。',
      ),
    );
  }

  Future<void> _openFeedInformation([NewsArticle? article]) async {
    var opened = false;
    try {
      opened = await launchUrl(
        article?.sourceInformationUri ?? NewsService.officialFeedInformationUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!mounted || opened) return;
    _showMessage(
      tr(
        en: 'The official source information page could not be opened.',
        fa: 'بازکردن صفحه اطلاعات منبع رسمی ممکن نشد.',
        ja: '公式ソースの情報ページを開けませんでした。',
        ru: 'Не удалось открыть страницу официального источника.',
        zh: '无法打开官方来源信息页面。',
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: palette.surface,
          content: Text(message, style: TextStyle(color: palette.text)),
        ),
      );
  }

  BoxDecoration _panelDecoration({double alpha = 0.82}) {
    return BoxDecoration(
      color: palette.surface.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: palette.primary.withValues(alpha: 0.18)),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 10)),
      ],
    );
  }

  Widget _entranceSection({
    required String id,
    required Widget child,
    required double start,
    required double end,
    required bool reducedMotion,
  }) {
    if (reducedMotion) return child;
    return AnimatedBuilder(
      key: ValueKey('news-entrance-$id'),
      animation: _entranceController,
      child: child,
      builder: (context, staticChild) {
        final progress = Curves.easeOutCubic.transform(
          Interval(start, end).transform(_entranceController.value),
        );
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 18),
            child: staticChild,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final platformReducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final reducedMotion = platformReducedMotion || !MotionPreferences.enabled;
    return Directionality(
      textDirection: _isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _entranceSection(
            id: 'header',
            child: _buildHeader(),
            start: 0,
            end: 0.55,
            reducedMotion: reducedMotion,
          ),
          const SizedBox(height: 14),
          if (_store.errorMessage != null && _store.hasContent) ...[
            _buildWarning(
              icon: Icons.cloud_off_rounded,
              message: tr(
                en: 'Some news sources are unavailable. Available articles remain visible.',
                fa: 'بعضی منابع خبر در دسترس نیستند؛ خبرهای دریافت‌شده همچنان نمایش داده می‌شوند.',
                ja: '一部のニュースソースを取得できません。取得済みの記事は引き続き表示されます。',
                ru: 'Некоторые источники новостей недоступны. Полученные статьи остаются видимыми.',
                zh: '部分新闻来源暂时不可用；已获取的新闻仍可查看。',
                ar: 'بعض مصادر الأخبار غير متاحة. تبقى الأخبار المستلمة قابلة للعرض.',
                trText:
                    'Bazı haber kaynakları kullanılamıyor. Alınan haberler görünür kalır.',
                fr: 'Certaines sources sont indisponibles. Les articles reçus restent visibles.',
              ),
              technical: _technicalMessage(_store.errorMessage),
            ),
            const SizedBox(height: 10),
          ],
          if (_store.translationErrorMessage != null) ...[
            _buildWarning(
              icon: Icons.translate_rounded,
              message: tr(
                en: 'Translation is unavailable. Publisher text remains available only under the explicit original section.',
                fa: 'ترجمه در دسترس نیست؛ متن ناشر فقط در بخش مشخص «متن اصلی» در دسترس است.',
                ja: '翻訳を利用できません。発行元の文章は明示された「原文」セクションでのみ確認できます。',
                ru: 'Перевод недоступен. Текст издателя доступен только в отдельном разделе «Оригинал».',
                zh: '翻译不可用。发布者文本仅保留在明确标示的“原文”部分。',
                ar: 'الترجمة غير متاحة. يبقى نص الناشر متاحًا فقط في قسم «النص الأصلي» المحدد.',
                trText:
                    'Çeviri kullanılamıyor. Yayıncı metni yalnızca açıkça belirtilen “Orijinal” bölümünde yer alır.',
                fr: 'La traduction est indisponible. Le texte de l’éditeur reste accessible uniquement dans la section « Original ».',
              ),
              technical: _technicalMessage(_store.translationErrorMessage),
            ),
            const SizedBox(height: 10),
          ],
          _entranceSection(
            id: 'filters',
            child: _buildFilters(),
            start: 0.14,
            end: 0.75,
            reducedMotion: reducedMotion,
          ),
          const SizedBox(height: 14),
          _entranceSection(
            id: 'content',
            child: _buildContent(),
            start: 0.28,
            end: 1,
            reducedMotion: reducedMotion,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;
          final title = Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  color: palette.primary.withValues(alpha: 0.12),
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.32),
                  ),
                ),
                child: Icon(
                  Icons.newspaper_rounded,
                  color: palette.primary,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        en: 'Financial News',
                        fa: 'اخبار مالی',
                        ja: '金融ニュース',
                        ru: 'Финансовые новости',
                        zh: '财经新闻',
                      ),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(
                        en: 'Relevant assets first • automatic refresh every 5 minutes',
                        fa: 'خبرهای مرتبط با دارایی‌ها در ابتدا • به‌روزرسانی خودکار هر ۵ دقیقه',
                        ja: '関連資産を優先 • 5分ごとに自動更新',
                        ru: 'Сначала связанные активы • автообновление каждые 5 минут',
                        zh: '相关资产优先 • 每 5 分钟自动刷新',
                      ),
                      style: TextStyle(color: palette.mutedText, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = _buildHeaderActions();
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 14), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InkWell(
          onTap: () => _openFeedInformation(_selectedArticle),
          borderRadius: BorderRadius.circular(13),
          child: _StatusChip(
            palette: palette,
            icon: Icons.verified_rounded,
            label: tr(
              en: 'Iranian & international RSS',
              fa: 'خبرهای ایران و جهان با منبع مشخص',
              ja: 'イランと世界のRSS',
              ru: 'RSS Ирана и мира',
              zh: '伊朗及国际 RSS',
            ),
          ),
        ),
        _StatusChip(
          key: const ValueKey('news-unread-count'),
          palette: palette,
          icon: Icons.mark_email_unread_outlined,
          label: tr(
            en: '${_store.unreadCount} unread',
            fa: '${_store.unreadCount} خوانده‌نشده',
            ja: '未読 ${_store.unreadCount}件',
            ru: 'Непрочитано: ${_store.unreadCount}',
            zh: '${_store.unreadCount} 条未读',
          ),
        ),
        if (_store.unreadCount > 0)
          TextButton(
            key: const ValueKey('mark-all-news-read'),
            onPressed: _store.markAllRead,
            child: Text(
              tr(
                en: 'Mark all read',
                fa: 'خواندن همه',
                ja: 'すべて既読',
                ru: 'Прочитать все',
                zh: '全部标为已读',
              ),
            ),
          ),
        IconButton(
          onPressed: _store.isLoading
              ? null
              : () => _store.load(forceRefresh: true),
          tooltip: tr(
            en: 'Refresh now',
            fa: 'به‌روزرسانی اکنون',
            ja: '今すぐ更新',
            ru: 'Обновить сейчас',
            zh: '立即刷新',
          ),
          style: IconButton.styleFrom(
            backgroundColor: palette.primary.withValues(alpha: 0.11),
            foregroundColor: palette.primary,
          ),
          icon: _store.isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.primary,
                  ),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _buildWarning({
    required IconData icon,
    required String message,
    String? technical,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.orangeAccent, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              technical == null ? message : '$message\n$technical',
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _panelDecoration(alpha: 0.70),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: palette.text, fontSize: 12),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, color: palette.primary),
              hintText: tr(
                en: 'Search real news...',
                fa: 'جست‌وجو در اخبار واقعی...',
                ja: '実際のニュースを検索...',
                ru: 'Поиск по реальным новостям...',
                zh: '搜索真实新闻...',
              ),
              hintStyle: TextStyle(color: palette.mutedText),
              filled: true,
              fillColor: palette.background.withValues(alpha: 0.30),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CategoryChip(
                    label: tr(
                      en: 'All',
                      fa: 'همه',
                      ja: 'すべて',
                      ru: 'Все',
                      zh: '全部',
                    ),
                    selected: _selectedCategory == null,
                    palette: palette,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  for (final category in _categories) ...[
                    const SizedBox(width: 8),
                    _CategoryChip(
                      label: category,
                      selected: _selectedCategory == category,
                      palette: palette,
                      onTap: () => setState(() => _selectedCategory = category),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_store.isInitialLoading) {
      return _StatePanel(
        key: const ValueKey('news-loading'),
        palette: palette,
        loading: true,
        icon: Icons.cloud_download_rounded,
        title: tr(
          en: 'Loading the official feed...',
          fa: 'در حال دریافت خوراک رسمی خبر...',
          ja: '公式フィードを読み込んでいます...',
          ru: 'Загрузка официальной ленты...',
          zh: '正在加载官方订阅源...',
        ),
        message: tr(
          en: 'No sample article is shown while real data is loading.',
          fa: 'تا دریافت داده واقعی، هیچ خبر نمونه‌ای نمایش داده نمی‌شود.',
          ja: '実データの取得中はサンプル記事を表示しません。',
          ru: 'Во время загрузки демо-новости не показываются.',
          zh: '真实数据加载时不显示示例新闻。',
        ),
      );
    }
    if (_store.errorMessage != null && !_store.hasContent) {
      return _StatePanel(
        key: const ValueKey('news-error'),
        palette: palette,
        icon: Icons.cloud_off_rounded,
        title: tr(
          en: 'Official news is currently unavailable',
          fa: 'اخبار رسمی فعلاً در دسترس نیست',
          ja: '公式ニュースは現在利用できません',
          ru: 'Официальные новости сейчас недоступны',
          zh: '官方新闻暂时不可用',
        ),
        message: tr(
          en: 'Check the internet connection. The app never inserts fabricated content.',
          fa: 'اتصال اینترنت را بررسی کنید؛ برنامه هیچ خبر ساختگی درج نمی‌کند.',
          ja: 'インターネット接続を確認してください。架空の記事は表示しません。',
          ru: 'Проверьте интернет. Приложение не добавляет вымышленные новости.',
          zh: '请检查网络连接。应用不会插入虚构内容。',
        ),
        technicalMessage: _technicalMessage(_store.errorMessage),
        actionLabel: tr(
          en: 'Try again',
          fa: 'تلاش دوباره',
          ja: '再試行',
          ru: 'Повторить',
          zh: '重试',
        ),
        onAction: () => _store.load(forceRefresh: true),
      );
    }
    if (!_store.hasContent) {
      return _StatePanel(
        key: const ValueKey('news-empty'),
        palette: palette,
        icon: Icons.inbox_outlined,
        title: tr(
          en: 'No valid release was returned',
          fa: 'هیچ خبر معتبر جدیدی دریافت نشد',
          ja: '有効な発表はありません',
          ru: 'Источник не вернул публикаций',
          zh: '未返回有效新闻',
        ),
        message: tr(
          en: 'Refresh later. No placeholder news was inserted.',
          fa: 'بعداً دوباره بررسی کنید؛ خبر جایگزین ساختگی درج نشده است.',
          ja: '後でもう一度更新してください。',
          ru: 'Обновите позже; заглушки не добавлены.',
          zh: '请稍后刷新；未添加任何占位新闻。',
        ),
      );
    }

    final items = _visibleArticles;
    if (items.isEmpty) {
      return _StatePanel(
        key: const ValueKey('news-filter-empty'),
        palette: palette,
        icon: Icons.search_off_rounded,
        title: tr(
          en: 'No matching official release',
          fa: 'خبر رسمی مطابق جست‌وجو پیدا نشد',
          ja: '一致する公式発表はありません',
          ru: 'Подходящих публикаций нет',
          zh: '没有匹配的官方新闻',
        ),
        message: tr(
          en: 'Change the search text or category.',
          fa: 'عبارت جست‌وجو یا دسته‌بندی را تغییر دهید.',
          ja: '検索語またはカテゴリを変更してください。',
          ru: 'Измените запрос или категорию.',
          zh: '请更改搜索内容或分类。',
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        if (compact) {
          return Column(
            children: [
              SizedBox(height: 470, child: _buildArticleList(items)),
              const SizedBox(height: 14),
              _buildArticleDetails(_selectedArticle!),
            ],
          );
        }
        return SizedBox(
          height: 760,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 390, child: _buildArticleList(items)),
              const SizedBox(width: 14),
              Expanded(child: _buildArticleDetails(_selectedArticle!)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArticleList(List<NewsArticle> articles) {
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 11),
            child: Row(
              children: [
                Icon(Icons.rss_feed_rounded, color: palette.primary, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(
                      en: 'NEWS FEED',
                      fa: 'فهرست خبرها',
                      ja: 'ニュース一覧',
                      ru: 'ЛЕНТА НОВОСТЕЙ',
                      zh: '新闻列表',
                      ar: 'قائمة الأخبار',
                      trText: 'HABER LİSTESİ',
                      fr: 'FIL D’ACTUALITÉS',
                    ),
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${articles.length}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: palette.mutedText, fontSize: 10),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.primary.withValues(alpha: 0.10)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(11),
              itemCount: articles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final article = articles[index];
                final display = _store.displayFor(article);
                return _NewsTile(
                  article: article,
                  title: display.title,
                  translated: display.isTranslated,
                  translationPending: _store.isTranslationPending(article),
                  read: _store.isRead(article),
                  selected: _selectedArticle?.id == article.id,
                  palette: palette,
                  direction: _articleDirection,
                  timeLabel: _formatRelativeTime(article.publishedAt),
                  onTap: () => _selectArticle(article),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleDetails(NewsArticle article) {
    final display = _store.displayFor(article);
    final summary = _store.aiSummaryFor(article);
    final summaryError = _store.aiSummaryErrorFor(article);
    final summarizing = _store.isSummarizing(article);
    final summaryIsSourceFallback = _store.isSummarySourceFallback(article);
    final translationPending = _store.isTranslationPending(article);

    return Container(
      decoration: _panelDecoration(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(23),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              display.category.toUpperCase(),
              textDirection: _articleDirection,
              style: TextStyle(
                color: palette.primary,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              display.title,
              textDirection: _articleDirection,
              style: TextStyle(
                color: palette.text,
                fontSize: 22,
                height: 1.45,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  palette: palette,
                  icon: Icons.verified_outlined,
                  label: article.source,
                ),
                _StatusChip(
                  palette: palette,
                  icon: Icons.schedule_rounded,
                  label: _formatRelativeTime(article.publishedAt),
                ),
                if (display.isTranslated)
                  _StatusChip(
                    palette: palette,
                    icon: Icons.translate_rounded,
                    label: tr(
                      en: 'AI translated',
                      fa: 'ترجمه‌شده با AI',
                      ja: 'AI翻訳',
                      ru: 'Переведено ИИ',
                      zh: 'AI 已翻译',
                      ar: 'مترجم بالذكاء الاصطناعي',
                      trText: 'Yapay zekâ ile çevrildi',
                      fr: 'Traduit par l’IA',
                    ),
                  )
                else if (translationPending)
                  _StatusChip(
                    palette: palette,
                    icon: Icons.hourglass_top_rounded,
                    label: tr(
                      en: 'Translating...',
                      fa: 'در حال ترجمه...',
                      ja: '翻訳中...',
                      ru: 'Перевод...',
                      zh: '正在翻译...',
                      ar: 'جارٍ الترجمة...',
                      trText: 'Çevriliyor...',
                      fr: 'Traduction en cours…',
                    ),
                  )
                else if (display.translationUnavailable)
                  _StatusChip(
                    palette: palette,
                    icon: Icons.translate_rounded,
                    label: tr(
                      en: 'Translation unavailable',
                      fa: 'ترجمه در دسترس نیست',
                      ja: '翻訳を利用できません',
                      ru: 'Перевод недоступен',
                      zh: '翻译不可用',
                      ar: 'الترجمة غير متاحة',
                      trText: 'Çeviri kullanılamıyor',
                      fr: 'Traduction indisponible',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _Section(
              palette: palette,
              title: tr(
                en: display.isTranslated
                    ? 'TRANSLATED SOURCE DESCRIPTION'
                    : display.isPlaceholder
                    ? 'TRANSLATION STATUS'
                    : 'OFFICIAL FEED DESCRIPTION',
                fa: display.isTranslated
                    ? 'ترجمه توضیح رسمی منبع'
                    : display.isPlaceholder
                    ? 'وضعیت ترجمه'
                    : 'توضیح رسمی منبع',
                ja: display.isTranslated
                    ? '公式説明の翻訳'
                    : display.isPlaceholder
                    ? '翻訳状況'
                    : '公式フィードの説明',
                ru: display.isTranslated
                    ? 'ПЕРЕВОД ОПИСАНИЯ ИСТОЧНИКА'
                    : display.isPlaceholder
                    ? 'СТАТУС ПЕРЕВОДА'
                    : 'ОПИСАНИЕ ИЗ ОФИЦИАЛЬНОЙ ЛЕНТЫ',
                zh: display.isTranslated
                    ? '来源描述译文'
                    : display.isPlaceholder
                    ? '翻译状态'
                    : '官方订阅源描述',
                ar: display.isTranslated
                    ? 'ترجمة وصف المصدر'
                    : display.isPlaceholder
                    ? 'حالة الترجمة'
                    : 'وصف الخلاصة الرسمية',
                trText: display.isTranslated
                    ? 'KAYNAK AÇIKLAMASI ÇEVİRİSİ'
                    : display.isPlaceholder
                    ? 'ÇEVİRİ DURUMU'
                    : 'RESMÎ AKIŞ AÇIKLAMASI',
                fr: display.isTranslated
                    ? 'TRADUCTION DE LA DESCRIPTION SOURCE'
                    : display.isPlaceholder
                    ? 'ÉTAT DE LA TRADUCTION'
                    : 'DESCRIPTION DU FLUX OFFICIEL',
              ),
              child: Text(
                display.summary,
                textDirection: _articleDirection,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 14,
                  height: 1.8,
                ),
              ),
            ),
            if (widget.selectedLanguage.name != article.sourceLanguageCode) ...[
              const SizedBox(height: 10),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: Material(
                  type: MaterialType.transparency,
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    iconColor: palette.primary,
                    collapsedIconColor: palette.mutedText,
                    title: Text(
                      tr(
                        en: 'View publisher original',
                        fa: 'نمایش متن اصلی ناشر',
                        ja: '発行元の原文を表示',
                        ru: 'Показать оригинал издателя',
                        zh: '查看发布者原文',
                      ),
                      style: TextStyle(color: palette.mutedText, fontSize: 11),
                    ),
                    children: [
                      SelectableText(
                        '${article.title}\n\n${article.bestAvailableBody}',
                        textDirection: article.sourceLanguageCode == 'persian'
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 11,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (!display.isTranslated &&
                widget.selectedLanguage.name != article.sourceLanguageCode &&
                !translationPending) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    _store.ensureTranslations([article], retryFailed: true),
                icon: const Icon(Icons.translate_rounded, size: 18),
                label: Text(
                  tr(
                    en: 'Retry real AI translation',
                    fa: 'تلاش دوباره برای ترجمه واقعی',
                    ja: 'AI翻訳を再試行',
                    ru: 'Повторить перевод ИИ',
                    zh: '重试 AI 真实翻译',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _Section(
              key: const ValueKey('news-ai-summary'),
              palette: palette,
              title: tr(
                en: summaryIsSourceFallback
                    ? 'PUBLISHER TEXT FALLBACK'
                    : 'OPTIONAL AI SUMMARY',
                fa: summaryIsSourceFallback
                    ? 'خلاصه جایگزین از متن ناشر'
                    : 'خلاصه اختیاری هوش مصنوعی',
                ja: summaryIsSourceFallback ? '発行元テキストの代替表示' : '任意のAI要約',
                ru: summaryIsSourceFallback
                    ? 'ТЕКСТ ИЗДАТЕЛЯ ВМЕСТО РЕЗЮМЕ'
                    : 'ДОПОЛНИТЕЛЬНОЕ РЕЗЮМЕ ИИ',
                zh: summaryIsSourceFallback ? '发布者文本备用内容' : '可选 AI 摘要',
                ar: summaryIsSourceFallback
                    ? 'نص الناشر البديل'
                    : 'ملخص اختياري بالذكاء الاصطناعي',
                trText: summaryIsSourceFallback
                    ? 'YAYINCI METNİ YEDEĞİ'
                    : 'İSTEĞE BAĞLI YAPAY ZEKÂ ÖZETİ',
                fr: summaryIsSourceFallback
                    ? 'TEXTE DE SECOURS DE L’ÉDITEUR'
                    : 'RÉSUMÉ IA FACULTATIF',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (summary != null && summary.isNotEmpty)
                    ChatMessageText(
                      summary,
                      markdown: !summaryIsSourceFallback,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 13,
                        height: 1.75,
                      ),
                    )
                  else
                    Text(
                      tr(
                        en: 'Generated only when requested. The summary is based on the publisher text above.',
                        fa: 'فقط با درخواست شما ساخته می‌شود و مبنای آن متن ناشر در بالاست.',
                        ja: '要求した場合のみ、上記の発行元テキストを基に生成します。',
                        ru: 'Создаётся только по запросу на основе текста издателя выше.',
                        zh: '仅在请求时根据上方发布者文本生成。',
                        ar: 'يُنشأ عند الطلب فقط استنادًا إلى نص الناشر أعلاه.',
                        trText:
                            'Yalnızca istendiğinde, yukarıdaki yayıncı metnine dayanarak oluşturulur.',
                        fr: 'Généré uniquement sur demande à partir du texte de l’éditeur ci-dessus.',
                      ),
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  if (summarizing) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      color: palette.primary,
                      backgroundColor: palette.primary.withValues(alpha: 0.12),
                    ),
                  ],
                  if (summaryError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      tr(
                        en: summaryError,
                        fa: summaryIsSourceFallback
                            ? 'پاسخ هوش مصنوعی به زبان انتخابی نبود؛ متن واقعی ناشر جایگزین شد.'
                            : 'خلاصه هوش مصنوعی فعلاً در دسترس نیست.',
                        ja: summaryIsSourceFallback
                            ? 'AIの応答言語が異なったため、発行元の本文を表示しています。'
                            : 'AI要約は現在利用できません。',
                        ru: summaryIsSourceFallback
                            ? 'ИИ ответил не на выбранном языке; показан текст издателя.'
                            : 'Резюме ИИ сейчас недоступно.',
                        zh: summaryIsSourceFallback
                            ? 'AI 未使用所选语言，因此改为显示发布者文本。'
                            : 'AI 摘要暂时不可用。',
                        ar: summaryIsSourceFallback
                            ? 'لم يجب الذكاء الاصطناعي باللغة المحددة؛ تم عرض نص الناشر.'
                            : 'ملخص الذكاء الاصطناعي غير متاح حاليًا.',
                        trText: summaryIsSourceFallback
                            ? 'Yapay zekâ seçilen dilde yanıt vermedi; yayıncı metni gösteriliyor.'
                            : 'Yapay zekâ özeti şu anda kullanılamıyor.',
                        fr: summaryIsSourceFallback
                            ? 'L’IA n’a pas répondu dans la langue choisie ; le texte de l’éditeur est affiché.'
                            : 'Le résumé IA est actuellement indisponible.',
                      ),
                      textDirection: _articleDirection,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 10,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const ValueKey('generate-news-ai-summary'),
                      onPressed: summarizing
                          ? null
                          : () => _store.generateAiSummary(
                              article,
                              forceRefresh: summary != null,
                            ),
                      icon: Icon(
                        summary == null
                            ? Icons.auto_awesome_rounded
                            : Icons.refresh_rounded,
                        size: 18,
                      ),
                      label: Text(
                        summary == null
                            ? tr(
                                en: 'Generate summary',
                                fa: 'ساخت خلاصه',
                                ja: '要約を生成',
                                ru: 'Создать резюме',
                                zh: '生成摘要',
                                ar: 'إنشاء الملخص',
                                trText: 'Özet oluştur',
                                fr: 'Générer le résumé',
                              )
                            : tr(
                                en: 'Regenerate',
                                fa: 'ساخت دوباره',
                                ja: '再生成',
                                ru: 'Создать заново',
                                zh: '重新生成',
                                ar: 'إعادة الإنشاء',
                                trText: 'Yeniden oluştur',
                                fr: 'Régénérer',
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr(
                en: 'AI translations and summaries may contain mistakes. The publisher original is authoritative. This content is informational and not investment advice.',
                fa: 'ترجمه و خلاصه هوش مصنوعی ممکن است خطا داشته باشد؛ متن اصلی ناشر مرجع است. این محتوا صرفاً اطلاع‌رسانی است و توصیه سرمایه‌گذاری نیست.',
                ja: 'AI翻訳・要約には誤りがあり得ます。発行元の原文が正式です。投資助言ではありません。',
                ru: 'Перевод и резюме ИИ могут содержать ошибки; оригинал издателя является основным. Это не инвестиционный совет.',
                zh: 'AI 翻译和摘要可能有误；以发布者原文为准。本内容仅供参考，不构成投资建议。',
                ar: 'قد تحتوي ترجمة وملخصات الذكاء الاصطناعي على أخطاء؛ نص الناشر الأصلي هو المرجع. هذا المحتوى للمعلومات فقط وليس نصيحة استثمارية.',
                trText:
                    'Yapay zekâ çevirileri ve özetleri hata içerebilir; yayıncının özgün metni esastır. Bu içerik bilgilendirme amaçlıdır, yatırım tavsiyesi değildir.',
                fr: 'Les traductions et résumés de l’IA peuvent contenir des erreurs ; le texte original de l’éditeur fait foi. Ce contenu est informatif et ne constitue pas un conseil en investissement.',
              ),
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 9,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: const ValueKey('open-original-news'),
                  onPressed: () => _openArticle(article),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.primary,
                    foregroundColor: palette.background,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(
                    tr(
                      en: 'Open original article',
                      fa: 'بازکردن خبر اصلی',
                      ja: '元の記事を開く',
                      ru: 'Открыть оригинал',
                      zh: '打开原始新闻',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openFeedInformation(article),
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  label: Text(
                    tr(
                      en: 'Source feed information',
                      fa: 'اطلاعات خوراک منبع',
                      ja: 'ソースフィード情報',
                      ru: 'Информация об источнике',
                      zh: '来源订阅源信息',
                    ),
                  ),
                ),
                _StatusChip(
                  palette: palette,
                  icon: Icons.event_outlined,
                  label: _formatAbsoluteTime(article.publishedAt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime value) {
    final difference = DateTime.now().toUtc().difference(value.toUtc());
    if (difference.isNegative) return _formatAbsoluteTime(value);
    if (difference.inMinutes < 1) {
      return tr(
        en: 'just now',
        fa: 'همین حالا',
        ja: 'たった今',
        ru: 'только что',
        zh: '刚刚',
      );
    }
    if (difference.inHours < 1) {
      return tr(
        en: '${difference.inMinutes} min ago',
        fa: '${difference.inMinutes} دقیقه پیش',
        ja: '${difference.inMinutes}分前',
        ru: '${difference.inMinutes} мин. назад',
        zh: '${difference.inMinutes} 分钟前',
      );
    }
    if (difference.inDays < 1) {
      return tr(
        en: '${difference.inHours} hours ago',
        fa: '${difference.inHours} ساعت پیش',
        ja: '${difference.inHours}時間前',
        ru: '${difference.inHours} ч. назад',
        zh: '${difference.inHours} 小时前',
      );
    }
    if (difference.inDays < 30) {
      return tr(
        en: '${difference.inDays} days ago',
        fa: '${difference.inDays} روز پیش',
        ja: '${difference.inDays}日前',
        ru: '${difference.inDays} дн. назад',
        zh: '${difference.inDays} 天前',
      );
    }
    return _formatAbsoluteTime(value);
  }

  String _formatAbsoluteTime(DateTime value) {
    final utc = value.toUtc();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)} UTC';
  }
}

class _NewsTile extends StatefulWidget {
  const _NewsTile({
    required this.article,
    required this.title,
    required this.translated,
    required this.translationPending,
    required this.read,
    required this.selected,
    required this.palette,
    required this.direction,
    required this.timeLabel,
    required this.onTap,
  });

  final NewsArticle article;
  final String title;
  final bool translated;
  final bool translationPending;
  final bool read;
  final bool selected;
  final ThemePalette palette;
  final TextDirection direction;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  State<_NewsTile> createState() => _NewsTileState();
}

class _NewsTileState extends State<_NewsTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.palette.primary.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: _hovered ? 0.045 : 0.012),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected
                  ? widget.palette.primary.withValues(alpha: 0.50)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              if (!widget.read) ...[
                Container(
                  key: const ValueKey('news-unread-dot'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.palette.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textDirection: widget.direction,
                      style: TextStyle(
                        color: widget.palette.text,
                        fontSize: 11,
                        height: 1.4,
                        fontWeight: widget.read
                            ? FontWeight.w700
                            : FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.article.source} • ${widget.timeLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              color: widget.palette.mutedText,
                              fontSize: 8,
                            ),
                          ),
                        ),
                        if (widget.translationPending)
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: widget.palette.primary,
                            ),
                          )
                        else if (widget.translated)
                          Icon(
                            Icons.translate_rounded,
                            color: widget.palette.primary,
                            size: 13,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                color: widget.palette.primary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ThemePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? palette.primary.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? palette.primary.withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.text : palette.mutedText,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    super.key,
    required this.palette,
    required this.icon,
    required this.label,
  });

  final ThemePalette palette;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: palette.primary, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.palette,
    required this.title,
    required this.child,
  });

  final ThemePalette palette;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.31),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.primary.withValues(alpha: 0.11)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.primary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 11),
          child,
        ],
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    required this.message,
    this.technicalMessage,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String message;
  final String? technicalMessage;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 330),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: palette.primary,
              ),
            )
          else
            Icon(icon, color: palette.primary, size: 48),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          if (technicalMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              technicalMessage!,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: palette.mutedText.withValues(alpha: 0.75),
                fontSize: 9,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
