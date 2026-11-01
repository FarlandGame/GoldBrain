import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_persistence_policy.dart';

enum AppNotificationType { system, profile, settings, priceAlert, news, ai }

/// Stable identifiers for notifications owned by GoldBrain itself.
///
/// Runtime/user notifications intentionally do not use these keys: their
/// title and message are displayed verbatim. Seed notifications are resolved
/// at render time so changing the app language also changes existing seeds.
enum AppNotificationSemanticKey {
  profileReady,
  settingsReady,
  cloudNotConnected,
  currencyChangeHint,
  importantFinancialNews,
  strongAiSignal,
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.type,
    this.isRead = false,
    this.semanticKey,
    this.semanticData = const <String, String>{},
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final AppNotificationType type;
  final bool isRead;
  final AppNotificationSemanticKey? semanticKey;
  final Map<String, String> semanticData;

  bool get isLocalizedSeed => semanticKey != null;

  String localizedTitle(String languageCode) =>
      _localizedNotificationText(
        semanticKey,
        languageCode,
        semanticData,
      )?.title ??
      title;

  String localizedMessage(String languageCode) =>
      _localizedNotificationText(
        semanticKey,
        languageCode,
        semanticData,
      )?.message ??
      message;

  AppNotification copyWith({
    String? id,
    String? title,
    String? message,
    DateTime? createdAt,
    AppNotificationType? type,
    bool? isRead,
    AppNotificationSemanticKey? semanticKey,
    Map<String, String>? semanticData,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      semanticKey: semanticKey ?? this.semanticKey,
      semanticData: semanticData ?? this.semanticData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'createdAt': createdAt.toIso8601String(),
      'type': type.name,
      'isRead': isRead,
      if (semanticKey != null) 'semanticKey': semanticKey!.name,
      if (semanticData.isNotEmpty) 'semanticData': semanticData,
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      type: _notificationTypeFromName(json['type'] as String?),
      isRead: json['isRead'] as bool? ?? false,
      semanticKey: _semanticKeyFromName(json['semanticKey']?.toString()),
      semanticData: json['semanticData'] is Map
          ? Map<String, String>.from(
              (json['semanticData'] as Map).map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            )
          : const <String, String>{},
    );
  }

  static AppNotificationType _notificationTypeFromName(String? value) {
    return AppNotificationType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => AppNotificationType.system,
    );
  }

  static AppNotificationSemanticKey? _semanticKeyFromName(String? value) {
    if (value == null) return null;
    for (final key in AppNotificationSemanticKey.values) {
      if (key.name == value) return key;
    }
    return null;
  }
}

typedef _LocalizedNotificationText = ({String title, String message});

_LocalizedNotificationText? _localizedNotificationText(
  AppNotificationSemanticKey? key,
  String languageCode,
  Map<String, String> data,
) {
  if (key == null) return null;
  final language = _supportedNotificationLanguages.contains(languageCode)
      ? languageCode
      : 'english';
  if (key == AppNotificationSemanticKey.importantFinancialNews) {
    return _importantNewsText(language, data);
  }
  if (key == AppNotificationSemanticKey.strongAiSignal) {
    return _strongAiSignalText(language, data);
  }
  return _seedTranslations[key]![language] ??
      _seedTranslations[key]!['english'];
}

_LocalizedNotificationText _importantNewsText(
  String language,
  Map<String, String> data,
) {
  final headline = data['headline']?.trim().isNotEmpty == true
      ? data['headline']!.trim()
      : '—';
  final source = data['source']?.trim().isNotEmpty == true
      ? data['source']!.trim()
      : '—';
  return switch (language) {
    'persian' => (
      title: 'خبر مالی مهم جدید',
      message: '$headline · منبع: $source',
    ),
    'japanese' => (title: '重要な金融ニュース', message: '$headline · 出典: $source'),
    'russian' => (
      title: 'Важная финансовая новость',
      message: '$headline · Источник: $source',
    ),
    'chinese' => (title: '重要财经新闻', message: '$headline · 来源：$source'),
    'arabic' => (title: 'خبر مالي مهم', message: '$headline · المصدر: $source'),
    'turkish' => (
      title: 'Önemli finans haberi',
      message: '$headline · Kaynak: $source',
    ),
    'french' => (
      title: 'Actualité financière importante',
      message: '$headline · Source : $source',
    ),
    _ => (
      title: 'Important financial news',
      message: '$headline · Source: $source',
    ),
  };
}

_LocalizedNotificationText _strongAiSignalText(
  String language,
  Map<String, String> data,
) {
  final symbol = data['symbol'] ?? '—';
  final confidence = data['confidence'] ?? '—';
  final horizon = data['horizonHours'] ?? '12';
  final rawDirection = data['direction'] ?? 'neutral';
  final direction = switch ((language, rawDirection)) {
    ('persian', 'upward') => 'صعودی',
    ('persian', 'downward') => 'نزولی',
    ('japanese', 'upward') => '上昇',
    ('japanese', 'downward') => '下落',
    ('russian', 'upward') => 'рост',
    ('russian', 'downward') => 'снижение',
    ('chinese', 'upward') => '上涨',
    ('chinese', 'downward') => '下跌',
    ('arabic', 'upward') => 'صعودي',
    ('arabic', 'downward') => 'هبوطي',
    ('turkish', 'upward') => 'yükseliş',
    ('turkish', 'downward') => 'düşüş',
    ('french', 'upward') => 'haussier',
    ('french', 'downward') => 'baissier',
    (_, 'upward') => 'upward',
    (_, 'downward') => 'downward',
    _ => 'neutral',
  };
  final message = switch (language) {
    'persian' =>
      '$symbol · سناریوی $direction · اطمینان $confidence٪ · افق $horizon ساعت',
    'japanese' => '$symbol · $directionシナリオ · 信頼度 $confidence% · $horizon時間',
    'russian' =>
      '$symbol · сценарий: $direction · уверенность $confidence% · горизонт $horizon ч',
    'chinese' => '$symbol · $direction情景 · 置信度 $confidence% · $horizon 小时',
    'arabic' =>
      '$symbol · سيناريو $direction · ثقة $confidence٪ · أفق $horizon ساعة',
    'turkish' =>
      '$symbol · $direction senaryosu · güven $confidence% · $horizon saat',
    'french' =>
      '$symbol · scénario $direction · confiance $confidence % · horizon $horizon h',
    _ =>
      '$symbol · $direction scenario · $confidence% confidence · ${horizon}h horizon',
  };
  final title = switch (language) {
    'persian' => 'سیگنال مهم هوش مصنوعی',
    'japanese' => '重要なAI市場シグナル',
    'russian' => 'Сильный сигнал ИИ',
    'chinese' => '重要 AI 市场信号',
    'arabic' => 'إشارة مهمة من الذكاء الاصطناعي',
    'turkish' => 'Güçlü AI piyasa sinyali',
    'french' => 'Signal de marché IA important',
    _ => 'Strong AI market signal',
  };
  return (title: title, message: message);
}

const _supportedNotificationLanguages = {
  'english',
  'persian',
  'japanese',
  'russian',
  'chinese',
  'arabic',
  'turkish',
  'french',
};

const Map<AppNotificationSemanticKey, Map<String, _LocalizedNotificationText>>
_seedTranslations = {
  AppNotificationSemanticKey.profileReady: {
    'english': (
      title: 'Profile is ready',
      message: 'Your profile information was loaded successfully.',
    ),
    'persian': (
      title: 'پروفایل آماده است',
      message: 'اطلاعات پروفایل شما با موفقیت بارگذاری شد.',
    ),
    'japanese': (title: 'プロフィールの準備ができました', message: 'プロフィール情報を正常に読み込みました。'),
    'russian': (
      title: 'Профиль готов',
      message: 'Данные профиля успешно загружены.',
    ),
    'chinese': (title: '个人资料已就绪', message: '已成功加载您的个人资料信息。'),
    'arabic': (
      title: 'الملف الشخصي جاهز',
      message: 'تم تحميل معلومات ملفك الشخصي بنجاح.',
    ),
    'turkish': (
      title: 'Profil hazır',
      message: 'Profil bilgileriniz başarıyla yüklendi.',
    ),
    'french': (
      title: 'Profil prêt',
      message: 'Les informations de votre profil ont été chargées.',
    ),
  },
  AppNotificationSemanticKey.settingsReady: {
    'english': (
      title: 'Settings are ready',
      message: 'GoldBrain settings were activated successfully.',
    ),
    'persian': (
      title: 'تنظیمات آماده است',
      message: 'تنظیمات GoldBrain با موفقیت فعال شد.',
    ),
    'japanese': (title: '設定の準備ができました', message: 'GoldBrain の設定が正常に有効になりました。'),
    'russian': (
      title: 'Настройки готовы',
      message: 'Настройки GoldBrain успешно активированы.',
    ),
    'chinese': (title: '设置已就绪', message: 'GoldBrain 设置已成功启用。'),
    'arabic': (
      title: 'الإعدادات جاهزة',
      message: 'تم تفعيل إعدادات GoldBrain بنجاح.',
    ),
    'turkish': (
      title: 'Ayarlar hazır',
      message: 'GoldBrain ayarları başarıyla etkinleştirildi.',
    ),
    'french': (
      title: 'Paramètres prêts',
      message: 'Les paramètres de GoldBrain ont été activés.',
    ),
  },
  AppNotificationSemanticKey.cloudNotConnected: {
    'english': (
      title: 'Cloud is not connected',
      message: 'Cloud connection will be added in a future update.',
    ),
    'persian': (
      title: 'فضای ابری متصل نیست',
      message: 'اتصال به فضای ابری در مرحله آینده اضافه خواهد شد.',
    ),
    'japanese': (title: 'クラウドは未接続です', message: 'クラウド接続は今後のアップデートで追加されます。'),
    'russian': (
      title: 'Облако не подключено',
      message: 'Подключение к облаку появится в будущем обновлении.',
    ),
    'chinese': (title: '云端尚未连接', message: '云端连接将在后续更新中加入。'),
    'arabic': (
      title: 'السحابة غير متصلة',
      message: 'ستتم إضافة الاتصال بالسحابة في تحديث لاحق.',
    ),
    'turkish': (
      title: 'Bulut bağlı değil',
      message: 'Bulut bağlantısı gelecek bir güncellemede eklenecek.',
    ),
    'french': (
      title: 'Cloud non connecté',
      message:
          'La connexion au cloud sera ajoutée dans une prochaine mise à jour.',
    ),
  },
  AppNotificationSemanticKey.currencyChangeHint: {
    'english': (
      title: 'Display currency can be changed',
      message: 'Choose your preferred price display currency in Settings.',
    ),
    'persian': (
      title: 'واحد پول قابل تغییر است',
      message: 'از بخش تنظیمات می‌توانید واحد پول نمایش قیمت‌ها را تغییر دهید.',
    ),
    'japanese': (title: '表示通貨を変更できます', message: '設定で価格表示に使用する通貨を選択できます。'),
    'russian': (
      title: 'Валюту отображения можно изменить',
      message: 'Выберите валюту отображения цен в настройках.',
    ),
    'chinese': (title: '可以更改显示货币', message: '您可以在设置中选择价格的显示货币。'),
    'arabic': (
      title: 'يمكن تغيير عملة العرض',
      message: 'اختر عملة عرض الأسعار المفضلة من الإعدادات.',
    ),
    'turkish': (
      title: 'Görüntüleme para birimi değiştirilebilir',
      message: 'Ayarlardan tercih ettiğiniz fiyat para birimini seçin.',
    ),
    'french': (
      title: 'La devise d’affichage peut être modifiée',
      message: 'Choisissez la devise d’affichage des prix dans les paramètres.',
    ),
  },
};

class NotificationService extends ChangeNotifier {
  NotificationService._({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  /// Creates an isolated service for tests without mutating the app singleton.
  @visibleForTesting
  NotificationService.forTesting({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static final NotificationService instance = NotificationService._();

  static const _storageKey = 'app.notifications';

  static const _legacyPersianSeeds = {
    AppNotificationSemanticKey.profileReady: (
      title: 'پروفایل آماده است',
      message: 'اطلاعات پروفایل شما با موفقیت بارگذاری شد.',
      type: AppNotificationType.profile,
    ),
    AppNotificationSemanticKey.settingsReady: (
      title: 'تنظیمات آماده است',
      message: 'تنظیمات GoldBrain با موفقیت فعال شد.',
      type: AppNotificationType.settings,
    ),
    AppNotificationSemanticKey.cloudNotConnected: (
      title: 'فضای ابری متصل نیست',
      message: 'اتصال به فضای ابری در مرحله آینده اضافه خواهد شد.',
      type: AppNotificationType.system,
    ),
    AppNotificationSemanticKey.currencyChangeHint: (
      title: 'واحد پول قابل تغییر است',
      message:
          'از بخش تنظیمات می‌توانید واحد پول نمایش قیمت‌ها را به واحد دلخواه خود تغییر دهید.',
      type: AppNotificationType.settings,
    ),
  };

  final List<AppNotification> _notifications = [];

  SharedPreferences? _preferences;
  final Future<SharedPreferences> Function() _preferencesLoader;
  bool _loaded = false;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount =>
      _notifications.where((notification) => !notification.isRead).length;

  bool get hasUnreadNotifications => unreadCount > 0;

  bool get loaded => _loaded;

  bool containsId(String id) =>
      _notifications.any((notification) => notification.id == id);

  Future<void> load() async {
    if (_loaded) return;

    _preferences ??= await _preferencesLoader();

    final savedData = _preferences!.getString(_storageKey);
    var migratedLegacySeed = false;

    if (savedData != null && savedData.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedData);

        if (decoded is List) {
          final restored = <AppNotification>[];
          for (final item in decoded.whereType<Map>()) {
            final parsed = AppNotification.fromJson(
              Map<String, dynamic>.from(item),
            );
            final migrated = _migrateLegacySeed(parsed);
            migratedLegacySeed =
                migratedLegacySeed ||
                migrated.semanticKey != parsed.semanticKey;
            restored.add(migrated);
          }
          _notifications
            ..clear()
            ..addAll(restored);
        }
      } catch (_) {
        _notifications.clear();
      }
    }

    _loaded = true;
    if (migratedLegacySeed) await _saveNotifications();
    notifyListeners();
  }

  void addNotification({
    required String title,
    required String message,
    AppNotificationType type = AppNotificationType.system,
  }) {
    final notification = AppNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      message: message,
      createdAt: DateTime.now(),
      type: type,
    );

    _notifications.insert(0, notification);

    notifyListeners();
    _saveNotifications();
  }

  void addOrReplaceNotification({
    required String id,
    required String title,
    required String message,
    AppNotificationType type = AppNotificationType.system,
  }) {
    _notifications.removeWhere((notification) => notification.id == id);

    final notification = AppNotification(
      id: id,
      title: title,
      message: message,
      createdAt: DateTime.now(),
      type: type,
    );

    _notifications.insert(0, notification);

    notifyListeners();
    _saveNotifications();
  }

  /// Inserts a persisted semantic event once. Stable event identifiers make
  /// repeated store notifications and application restarts idempotent.
  bool addSemanticNotificationIfAbsent({
    required String id,
    required AppNotificationSemanticKey semanticKey,
    required Map<String, String> semanticData,
    required AppNotificationType type,
  }) {
    if (containsId(id)) return false;
    final english = _localizedNotificationText(
      semanticKey,
      'english',
      semanticData,
    );
    if (english == null) return false;
    _notifications.insert(
      0,
      AppNotification(
        id: id,
        title: english.title,
        message: english.message,
        createdAt: DateTime.now(),
        type: type,
        semanticKey: semanticKey,
        semanticData: Map<String, String>.unmodifiable(semanticData),
      ),
    );
    notifyListeners();
    _saveNotifications();
    return true;
  }

  Future<void> addInitialNotifications() async {
    await load();

    var changed = false;
    if (_notifications.isEmpty) {
      _insertSeed(
        key: AppNotificationSemanticKey.profileReady,
        type: AppNotificationType.profile,
      );

      _insertSeed(
        key: AppNotificationSemanticKey.settingsReady,
        type: AppNotificationType.settings,
      );

      _insertSeed(
        key: AppNotificationSemanticKey.cloudNotConnected,
        type: AppNotificationType.system,
      );
      changed = true;
    }

    final hasCurrencyHint = _notifications.any(
      (notification) =>
          notification.id == 'currency-change-hint' ||
          notification.semanticKey ==
              AppNotificationSemanticKey.currencyChangeHint,
    );

    if (!hasCurrencyHint) {
      _insertSeed(
        id: 'currency-change-hint',
        key: AppNotificationSemanticKey.currencyChangeHint,
        type: AppNotificationType.settings,
      );
      changed = true;
    }

    if (changed) {
      notifyListeners();
      await _saveNotifications();
    }
  }

  void _insertSeed({
    required AppNotificationSemanticKey key,
    required AppNotificationType type,
    String? id,
  }) {
    final english = _localizedNotificationText(
      key,
      'english',
      const <String, String>{},
    )!;
    _notifications.insert(
      0,
      AppNotification(
        id: id ?? 'seed-${key.name}',
        title: english.title,
        message: english.message,
        createdAt: DateTime.now(),
        type: type,
        semanticKey: key,
      ),
    );
  }

  AppNotification _migrateLegacySeed(AppNotification notification) {
    if (notification.semanticKey != null) return notification;
    if (notification.id == 'currency-change-hint') {
      return notification.copyWith(
        semanticKey: AppNotificationSemanticKey.currencyChangeHint,
      );
    }
    for (final entry in _legacyPersianSeeds.entries) {
      final legacy = entry.value;
      if (notification.type == legacy.type &&
          notification.title == legacy.title &&
          notification.message == legacy.message) {
        return notification.copyWith(semanticKey: entry.key);
      }
    }
    return notification;
  }

  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere(
      (notification) => notification.id == notificationId,
    );

    if (index == -1) return;

    _notifications[index] = _notifications[index].copyWith(isRead: true);

    notifyListeners();
    _saveNotifications();
  }

  void markAllAsRead() {
    for (var index = 0; index < _notifications.length; index++) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
    }

    notifyListeners();
    _saveNotifications();
  }

  void removeNotification(String notificationId) {
    _notifications.removeWhere(
      (notification) => notification.id == notificationId,
    );

    notifyListeners();
    _saveNotifications();
  }

  void clearAll() {
    _notifications.clear();

    notifyListeners();
    _saveNotifications();
  }

  Future<void> _saveNotifications() async {
    if (!LocalPersistencePolicy.instance.canWrite) return;
    _preferences ??= await _preferencesLoader();

    final encoded = jsonEncode(
      _notifications.map((notification) => notification.toJson()).toList(),
    );

    await _preferences!.setString(_storageKey, encoded);
  }
}
