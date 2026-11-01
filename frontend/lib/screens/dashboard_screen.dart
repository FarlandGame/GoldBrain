import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'ai_assistant_screen.dart';
import 'watchlist_screen.dart';
import 'portfolio_screen.dart';
import 'profile_screen.dart';
import '../core/profile_store.dart';
import 'settings_screen.dart';
import 'about_us_screen.dart';
import '../core/settings_store.dart';
import '../core/notification_service.dart';
import '../core/currency_service.dart';
import '../core/currency_rate_store.dart';
import '../core/live_market_store.dart';
import '../core/market_history_service.dart';
import '../core/market_pulse.dart';
import '../core/backend_api_client.dart';
import '../core/country_pulse_service.dart';
import '../core/market_intelligence_store.dart';
import '../core/news_store.dart';
import '../core/app_sound_service.dart';
import '../core/app_translations.dart';
import '../core/motion_preferences.dart';

import 'selection_screen.dart';
import 'markets_screen.dart';
import 'news_screen.dart';
import '../widgets/goldbrain_sidebar.dart';
import '../widgets/notification_popup.dart';
import '../widgets/cinematic_notification_dialog.dart';
import '../widgets/deep_market_analysis_card.dart';
import '../widgets/retained_tab.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.selectedTheme,
    required this.selectedLanguage,
    this.marketStore,
    this.historyService,
    this.countryPulseService,
  });

  final GoldBrainTheme selectedTheme;
  final GoldBrainLanguage selectedLanguage;
  final LiveMarketStore? marketStore;
  final MarketHistoryService? historyService;
  final CountryPulseService? countryPulseService;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _ambientController;
  late final AnimationController _scanController;
  final ProfileStore _profileStore = ProfileStore.instance;
  final SettingsStore _settingsStore = SettingsStore.instance;
  final CurrencyRateStore _currencyRateStore = CurrencyRateStore.instance;
  final NotificationService _notificationService = NotificationService.instance;
  final NewsStore _newsStore = NewsStore.instance;
  final MarketIntelligenceStore _intelligenceStore =
      MarketIntelligenceStore.instance;
  late final LiveMarketStore _liveMarketStore;
  late final MarketHistoryService _marketHistoryService;
  late final CountryPulseService _countryPulseService;
  late final bool _ownsMarketHistoryService;

  int selectedNavigationIndex = 0;
  bool aiPanelExpanded = true;
  bool sidebarExpanded = true;
  late GoldBrainTheme _activeTheme;
  late GoldBrainLanguage _activeLanguage;
  final Set<String> _knownNotificationIds = <String>{};
  AppNotification? _toastNotification;
  Timer? _toastTimer;
  MarketHistoryRange _dashboardHistoryRange = MarketHistoryRange.oneDay;
  String _pulseAsset = 'XAU';
  String? _pulseCountry;
  CountryPulseEvidence? _countryEvidence;
  String? _countryError;
  bool _countryLoading = false;
  int _countryRequestId = 0;
  MarketHistorySeries? _dashboardHistory;
  bool _dashboardHistoryLoading = false;
  String? _dashboardHistoryError;
  DateTime? _dashboardHistoryPriceUpdate;
  int _dashboardHistoryRequestId = 0;

  ThemePalette get palette => themePalettes[_activeTheme]!;

  double get _densityScale {
    switch (_settingsStore.density) {
      case 'compact':
        return 0.78;
      case 'spacious':
        return 1.25;
      case 'comfortable':
      default:
        return 1.0;
    }
  }

  String get _motionKey => [
    _settingsStore.motionEnabled,
    _settingsStore.reducedMotion,
    _settingsStore.animationIntensity.toStringAsFixed(2),
  ].join('-');

  void _applyMotionSettings() {
    _entranceController.duration = MotionPreferences.controllerDuration(2200);
    _ambientController.duration = MotionPreferences.controllerDuration(4200);
    _scanController.duration = MotionPreferences.controllerDuration(2800);

    if (!_settingsStore.motionEnabled || _settingsStore.reducedMotion) {
      _ambientController.stop();
      _scanController.stop();
      return;
    }

    if (!_ambientController.isAnimating) _ambientController.repeat();
    if (!_scanController.isAnimating) _scanController.repeat();
  }

  @override
  void initState() {
    super.initState();

    _activeTheme = widget.selectedTheme;
    _activeLanguage = widget.selectedLanguage;
    _liveMarketStore = widget.marketStore ?? LiveMarketStore.instance;
    _ownsMarketHistoryService = widget.historyService == null;
    _marketHistoryService = widget.historyService ?? MarketHistoryService();
    _countryPulseService = widget.countryPulseService ?? CountryPulseService();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _settingsStore.load().then((_) {
      if (!mounted) return;

      setState(() {
        selectedNavigationIndex = _settingsStore.startupNavigationIndex();
        _activeTheme = _themeFromCode(_settingsStore.themeCode);
        _activeLanguage = _languageFromCode(_settingsStore.languageCode);
      });
      _intelligenceStore.updateLanguage(_activeLanguage.name, refresh: false);
      _applyMotionSettings();
      _startDashboardMusic();
      AppSoundService.instance.playDashboardReady(
        enabled:
            _settingsStore.soundEnabled &&
            _settingsStore.interfaceSoundsEnabled,
        volume: _settingsStore.interfaceVolume,
      );
    });

    _profileStore.load().then((_) {
      if (!mounted) return;
      setState(() {});
    });

    _liveMarketStore.addListener(_onLiveMarketChanged);
    _currencyRateStore.addListener(_onCurrencyRatesChanged);
    _liveMarketStore.startAutoRefresh();
    unawaited(_loadDashboardHistory());

    _newsStore.addListener(_onNewsChanged);
    unawaited(_newsStore.setLanguage(_activeLanguage.name));
    _newsStore.retainAutoRefresh();
    unawaited(_newsStore.load());
    unawaited(
      _intelligenceStore.start(
        languageCode: _activeLanguage.name,
        refreshImmediately: false,
      ),
    );

    _initializeNotifications();
  }

  void _onLiveMarketChanged() {
    if (!mounted) return;
    void applyChange() {
      if (!mounted) return;
      setState(() {});
      final updatedAt = _liveMarketStore.loadedAt;
      if (updatedAt != null && updatedAt != _dashboardHistoryPriceUpdate) {
        _dashboardHistoryPriceUpdate = updatedAt;
        unawaited(_loadDashboardHistory(forceRefresh: true));
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => applyChange());
    } else {
      applyChange();
    }
  }

  void _onCurrencyRatesChanged() {
    if (mounted) setState(() {});
  }

  void _onNewsChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  Future<void> _loadDashboardHistory({bool forceRefresh = false}) async {
    if (_pulseCountry != null) return;
    final requestId = ++_dashboardHistoryRequestId;
    if (mounted) {
      setState(() {
        _dashboardHistoryLoading = true;
        _dashboardHistoryError = null;
      });
    }
    try {
      final series = await _marketHistoryService.fetchHistory(
        _pulseAsset,
        range: _dashboardHistoryRange,
        forceRefresh: forceRefresh,
      );
      if (series.symbol != _pulseAsset ||
          series.range != _dashboardHistoryRange) {
        throw const FormatException('History identity mismatch');
      }
      if (!mounted || requestId != _dashboardHistoryRequestId) return;
      setState(() => _dashboardHistory = series);
    } on MarketHistoryException catch (error) {
      if (!mounted || requestId != _dashboardHistoryRequestId) return;
      setState(() {
        _dashboardHistoryError = error.message;
        _dashboardHistory = _dashboardHistory?.asStale();
      });
    } catch (_) {
      if (!mounted || requestId != _dashboardHistoryRequestId) return;
      setState(() {
        _dashboardHistoryError =
            'Verified $_pulseAsset history is unavailable.';
        _dashboardHistory = _dashboardHistory?.asStale();
      });
    } finally {
      if (mounted && requestId == _dashboardHistoryRequestId) {
        setState(() => _dashboardHistoryLoading = false);
      }
    }
  }

  void _changeDashboardHistoryRange(MarketHistoryRange range) {
    if (_dashboardHistoryRange == range) return;
    setState(() {
      _dashboardHistoryRange = range;
      _dashboardHistory = null;
      _countryEvidence = null;
      _countryError = null;
      _countryLoading = false;
      _countryRequestId++;
    });
    if (_pulseCountry != null) {
      unawaited(_loadCountryEvidence());
    } else {
      unawaited(_loadDashboardHistory());
    }
  }

  void _changePulseAsset(String symbol) {
    if (_pulseAsset == symbol && _pulseCountry == null) return;
    setState(() {
      _pulseAsset = symbol;
      _pulseCountry = null;
      _countryRequestId++;
      _countryEvidence = null;
      _countryError = null;
      _countryLoading = false;
      _dashboardHistory = null;
      _dashboardHistoryError = null;
    });
    unawaited(_loadDashboardHistory());
  }

  void _changePulseCountry(String country) {
    if (_pulseCountry == country) return;
    setState(() {
      _pulseCountry = country;
      _dashboardHistoryRequestId++;
      _dashboardHistory = null;
      _dashboardHistoryError = null;
      _dashboardHistoryLoading = false;
      _countryEvidence = null;
      _countryError = null;
      if (_dashboardHistoryRange == MarketHistoryRange.oneHour) {
        _dashboardHistoryRange = MarketHistoryRange.oneDay;
      }
    });
    unawaited(_loadCountryEvidence());
  }

  MarketHistorySeries? get _selectedPulseHistory =>
      _pulseCountry == null ? _dashboardHistory : _countryEvidence?.series;

  bool get _selectedPulseLoading =>
      _pulseCountry == null ? _dashboardHistoryLoading : _countryLoading;

  String get _selectedPulseName =>
      _pulseCountry == null ? _pulseAsset : _pulseCountries[_pulseCountry]!;

  // Weekly/monthly country evidence is sampled once per trading session.
  // Adjacent observations form a trend even across closed-market days.
  bool get _connectDailyIndexObservations =>
      _pulseCountry != null &&
      (_dashboardHistoryRange == MarketHistoryRange.oneWeek ||
          _dashboardHistoryRange == MarketHistoryRange.oneMonth);

  ({
    MarketHistorySeries series,
    bool conversionStale,
    bool conversionUnavailable,
  })
  _displayPulseHistory(MarketHistorySeries series) => _pulseCountry != null
      ? (series: series, conversionStale: false, conversionUnavailable: false)
      : series.forDisplay(
          selectedCode: _settingsStore.currencyCode,
          language: _activeLanguage,
        );

  String? get _selectedPulseError {
    if (_pulseCountry == null) return _dashboardHistoryError;
    if (_countryError != null) return _countryError;
    final evidence = _countryEvidence;
    if (evidence == null) return null;
    return '${evidence.indexName} · ${evidence.indexProvider} · ' +
        translatedText(
          english: 'Insufficient verified index history for this window.',
          persian: 'تاریخچهٔ معتبر شاخص برای این بازه کافی نیست.',
          japanese: 'この期間の検証済み指数履歴が不足しています。',
          russian: 'Недостаточно проверенной истории индекса за этот период.',
        );
  }

  Future<void> _loadCountryEvidence() async {
    final country = _pulseCountry;
    if (country == null || _dashboardHistoryRange == MarketHistoryRange.oneHour)
      return;
    final requestId = ++_countryRequestId;
    setState(() {
      _countryLoading = true;
      _countryEvidence = null;
      _countryError = null;
    });
    try {
      final evidence = await _countryPulseService.fetch(
        country,
        _dashboardHistoryRange,
      );
      if (mounted && requestId == _countryRequestId) {
        setState(() => _countryEvidence = evidence);
      }
    } catch (error) {
      if (mounted && requestId == _countryRequestId) {
        setState(() {
          _countryError =
              error is GoldBrainBackendException && error.code == 'http_401'
              ? translatedText(
                  english: 'Sign in to load country market data.',
                  persian: 'برای دریافت دادهٔ بازار کشورها وارد حساب شوید.',
                  japanese: '国別市場データを見るにはログインしてください。',
                  russian: 'Войдите, чтобы загрузить данные рынков стран.',
                )
              : translatedText(
                  english: 'Country evidence is unavailable. Please retry.',
                  persian: 'دادهٔ کشور در دسترس نیست؛ دوباره تلاش کنید.',
                  japanese: '国別データを取得できません。再試行してください。',
                  russian: 'Данные страны недоступны. Повторите попытку.',
                );
        });
      }
    } finally {
      if (mounted && requestId == _countryRequestId) {
        setState(() => _countryLoading = false);
      }
    }
  }

  String _dashboardHistoryCaption(MarketHistorySeries series) {
    if (_pulseCountry != null) {
      final evidence = _countryEvidence!;
      final caption =
          '${evidence.indexName} · ${series.providerLabel} · ' +
          translatedText(
            english: '${series.candles.length} observed index points',
            persian: '${series.candles.length} مشاهدهٔ شاخص · واحد: نقطهٔ شاخص',
            japanese: '${series.candles.length} 件の指数観測',
            russian: '${series.candles.length} наблюдений индекса',
          );
      return series.isStale
          ? '$caption · ${_pulseReason('Latest market observation is too old.')}'
          : caption;
    }
    if (series.isStale) {
      return translatedText(
        english: 'Latest source observation is old · ${series.providerLabel}',
        persian: 'آخرین مشاهدهٔ منبع قدیمی است · ${series.providerLabel}',
        japanese: '最新の元データが古くなっています · ${series.providerLabel}',
        russian:
            'Последнее наблюдение источника устарело · ${series.providerLabel}',
      );
    }
    if (series.isProxy) {
      return translatedText(
        english:
            'Real COMEX futures proxy, not XAU spot · ${series.providerLabel}',
        persian:
            'نمایندهٔ واقعی قرارداد آتی COMEX، نه قیمت نقدی اونس · ${series.providerLabel}',
        japanese: '実際のCOMEX先物代理（現物XAUではありません）· ${series.providerLabel}',
        russian:
            'Реальный фьючерсный прокси COMEX, не спот XAU · ${series.providerLabel}',
      );
    }
    if (series.isPriceSample) {
      return translatedText(
        english:
            '${series.candles.length} observed prices (not OHLC) · ${series.providerLabel}',
        persian:
            '${series.candles.length} قیمت ثبت‌شده (نه کندل) · ${series.providerLabel}',
        japanese:
            '${series.candles.length} 件の実測価格（OHLCではありません）· ${series.providerLabel}',
        russian:
            '${series.candles.length} наблюдаемых цен (не OHLC) · ${series.providerLabel}',
      );
    }
    return translatedText(
      english:
          '${series.candles.length} verified OHLC points · ${series.providerLabel}',
      persian:
          '${series.candles.length} نقطهٔ واقعی OHLC · ${series.providerLabel}',
      japanese: '${series.candles.length} 件の検証済みOHLC · ${series.providerLabel}',
      russian:
          '${series.candles.length} проверенных OHLC-точек · ${series.providerLabel}',
    );
  }

  Future<void> _showDashboardHistoryDialog() {
    final series = _selectedPulseHistory;
    if (series == null) return Future.value();
    final display = _displayPulseHistory(series);
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (context) => Dialog(
        key: const ValueKey('dashboard-history-dialog'),
        backgroundColor: palette.surface,
        insetPadding: const EdgeInsets.all(28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: palette.primary.withValues(alpha: 0.35)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.show_chart_rounded, color: palette.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        translatedText(
                          english:
                              'Observed market history · $_selectedPulseName',
                          persian: 'تاریخچهٔ واقعی بازار · $_selectedPulseName',
                          japanese: '市場履歴 · $_selectedPulseName',
                          russian: 'История рынка · $_selectedPulseName',
                        ),
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _ambientController,
                        _scanController,
                      ]),
                      builder: (context, _) => CustomPaint(
                        painter: NeuralChartPainter(
                          palette: palette,
                          candles: display.series.candles,
                          isPriceSample: display.series.isPriceSample,
                          connectDailyIndexObservations:
                              _connectDailyIndexObservations,
                          animationProgress: _ambientController.value,
                          scanProgress: _scanController.value,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _dashboardHistoryCaption(series),
                  style: TextStyle(color: palette.mutedText, fontSize: 11),
                ),
                if (display.conversionStale || display.conversionUnavailable)
                  Text(
                    display.conversionUnavailable
                        ? translatedText(
                            english:
                                'Exchange rate unavailable; chart remains in ${series.currency}.',
                            persian:
                                'نرخ تبدیل در دسترس نیست؛ نمودار به ${series.currency} باقی مانده است.',
                            japanese:
                                '為替レートを取得できないため、チャートは ${series.currency} のままです。',
                            russian:
                                'Курс недоступен; график остается в ${series.currency}.',
                          )
                        : translatedText(
                            english: 'Chart uses the last known exchange rate.',
                            persian:
                                'نمودار با آخرین نرخ تبدیل ثبت‌شده نمایش داده می‌شود.',
                            japanese: 'チャートには最後に取得した為替レートを使用しています。',
                            russian:
                                'График использует последний известный курс.',
                          ),
                    style: const TextStyle(
                      color: Color(0xFFFFC857),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _initializeNotifications() async {
    await _notificationService.addInitialNotifications();
    _knownNotificationIds.addAll(
      _notificationService.notifications.map((item) => item.id),
    );
    _notificationService.addListener(_onNotificationsChanged);
  }

  void _onNotificationsChanged() {
    if (!mounted) return;

    final notifications = _notificationService.notifications;
    AppNotification? newest;
    for (final notification in notifications) {
      if (!_knownNotificationIds.contains(notification.id)) {
        newest ??= notification;
      }
    }
    _knownNotificationIds
      ..clear()
      ..addAll(notifications.map((item) => item.id));

    setState(() {
      if (newest != null && _settingsStore.notificationsEnabled) {
        _toastNotification = newest;
      }
    });

    if (newest != null && _settingsStore.notificationsEnabled) {
      AppSoundService.instance.playNotification(
        enabled:
            _settingsStore.soundEnabled &&
            _settingsStore.interfaceSoundsEnabled,
        volume: _settingsStore.interfaceVolume,
      );
      _toastTimer?.cancel();
      _toastTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _toastNotification = null);
      });
    }
  }

  @override
  void dispose() {
    _notificationService.removeListener(_onNotificationsChanged);
    _liveMarketStore.removeListener(_onLiveMarketChanged);
    _currencyRateStore.removeListener(_onCurrencyRatesChanged);
    _liveMarketStore.stopAutoRefresh();
    _newsStore.removeListener(_onNewsChanged);
    _newsStore.releaseAutoRefresh();
    _intelligenceStore.stop();
    if (_ownsMarketHistoryService) _marketHistoryService.close();
    _toastTimer?.cancel();

    _entranceController.dispose();
    _ambientController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  Future<void> playClickSound() async {
    if (!_settingsStore.soundEnabled ||
        !_settingsStore.interfaceSoundsEnabled) {
      return;
    }

    await AppSoundService.instance.playClick(
      enabled: true,
      volume: _settingsStore.interfaceVolume,
    );
  }

  Future<void> playTabSound() async {
    if (!_settingsStore.soundEnabled ||
        !_settingsStore.interfaceSoundsEnabled) {
      return;
    }

    await AppSoundService.instance.playTab(
      enabled: true,
      volume: _settingsStore.interfaceVolume,
    );
  }

  Future<void> playHoverSound() async {
    if (!_settingsStore.soundEnabled ||
        !_settingsStore.interfaceSoundsEnabled) {
      return;
    }

    await AppSoundService.instance.playHover(
      enabled: true,
      volume: _settingsStore.interfaceVolume,
    );
  }

  Future<void> _startDashboardMusic() {
    return AppSoundService.instance.startMusic(
      track: AppMusicTrack.dashboard,
      enabled: _settingsStore.soundEnabled,
      musicEnabled: _settingsStore.musicEnabled,
      volume: _settingsStore.interfaceVolume,
    );
  }

  Future<void> _refreshSettings() async {
    await _settingsStore.load();

    if (!mounted) return;

    setState(() {
      _activeTheme = _themeFromCode(_settingsStore.themeCode);
      _activeLanguage = _languageFromCode(_settingsStore.languageCode);
    });
    unawaited(_newsStore.setLanguage(_activeLanguage.name));
    _intelligenceStore.updateLanguage(_activeLanguage.name);
    _applyMotionSettings();
    await _startDashboardMusic();
  }

  GoldBrainTheme _themeFromCode(String value) {
    return GoldBrainTheme.values.firstWhere(
      (theme) => theme.name == value,
      orElse: () => widget.selectedTheme,
    );
  }

  GoldBrainLanguage _languageFromCode(String value) {
    return GoldBrainLanguage.values.firstWhere(
      (language) => language.name == value,
      orElse: () => widget.selectedLanguage,
    );
  }

  Future<void> _refreshProfile() async {
    await _profileStore.load();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showNotificationsPanel() async {
    if (!_settingsStore.notificationsEnabled) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: palette.surface,
            content: Text(
              translatedText(
                english: 'Notifications are disabled in Settings.',
                persian: 'اعلان‌ها در تنظیمات غیرفعال شده‌اند.',
                japanese: '設定で通知が無効になっています。',
                russian: 'Уведомления отключены в настройках.',
              ),
              style: TextStyle(color: palette.text),
            ),
          ),
        );

      return;
    }

    await AppSoundService.instance.playNotification(
      enabled:
          _settingsStore.soundEnabled && _settingsStore.interfaceSoundsEnabled,
      volume: _settingsStore.interfaceVolume,
    );

    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      barrierDismissible: true,
      barrierLabel: translatedText(
        english: 'Close notifications',
        persian: 'بستن اعلان‌ها',
        japanese: '通知を閉じる',
        russian: 'Закрыть уведомления',
      ),
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, _, __) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return CinematicNotificationDialog(
              palette: palette,
              motionEnabled: _settingsStore.motionEnabled,
              reducedMotion: _settingsStore.reducedMotion,
              intensity: _settingsStore.animationIntensity,
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(24),
                child: NotificationPopup(
                  palette: palette,
                  language: _activeLanguage,
                  notifications: _notificationService.notifications,
                  title: translatedText(
                    english: 'Notifications',
                    persian: 'اعلان‌ها',
                    japanese: '通知',
                    russian: 'Уведомления',
                  ),
                  subtitle: translatedText(
                    english: 'GoldBrain system messages',
                    persian: 'پیام‌های سامانه GoldBrain',
                    japanese: 'GoldBrainシステムメッセージ',
                    russian: 'Системные сообщения GoldBrain',
                  ),
                  settingsLabel: translatedText(
                    english: 'Notification Settings',
                    persian: 'تنظیمات اعلان‌ها',
                    japanese: '通知設定',
                    russian: 'Настройки уведомлений',
                  ),
                  onClose: () {
                    Navigator.of(dialogContext).pop();
                  },
                  onOpenSettings: () {
                    Navigator.of(dialogContext).pop();

                    setState(() {
                      selectedNavigationIndex = 7;
                    });
                  },
                  onRemoveNotification: (notificationId) {
                    _notificationService.removeNotification(notificationId);

                    setDialogState(() {});
                  },
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;

    _notificationService.markAllAsRead();
  }

  Animation<double> fadeAnimation(double start, double end) {
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Animation<Offset> slideAnimation(
    double start,
    double end, {
    Offset begin = const Offset(0, 0.25),
  }) {
    return Tween<Offset>(begin: begin, end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Interval(start, end, curve: Curves.easeOutBack),
      ),
    );
  }

  String translatedText({
    required String english,
    required String persian,
    required String japanese,
    required String russian,
    String? chinese,
  }) {
    switch (_activeLanguage) {
      case GoldBrainLanguage.persian:
        return persian;
      case GoldBrainLanguage.japanese:
        return japanese;
      case GoldBrainLanguage.russian:
        return russian;
      case GoldBrainLanguage.chinese:
        return chinese ?? AppTranslations.simplifiedChinese(english);
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic(english);
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish(english);
      case GoldBrainLanguage.french:
        return AppTranslations.french(english);
      case GoldBrainLanguage.english:
        return english;
    }
  }

  String formatDashboardPrice(double value) {
    return CurrencyService.formatPrice(
      value: value,
      selectedCode: _settingsStore.currencyCode,
      language: _activeLanguage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRtl =
        _activeLanguage == GoldBrainLanguage.persian ||
        _activeLanguage == GoldBrainLanguage.arabic;
    final mediaSize = MediaQuery.sizeOf(context);
    final compactLandscape =
        mediaSize.width < 1000 && mediaSize.width > mediaSize.height;
    final densityScale = compactLandscape
        ? math.min(_densityScale, 0.74)
        : _densityScale;
    final compactToast = mediaSize.width < 500;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: palette.background,
        body: Stack(
          children: [
            _buildAnimatedBackground(),

            SafeArea(
              child: Padding(
                padding: EdgeInsets.all(
                  compactLandscape ? 7 : 18 * densityScale,
                ),
                child: Row(
                  textDirection: TextDirection.ltr,
                  children: [
                    FadeTransition(
                      opacity: fadeAnimation(0.00, 0.30),
                      child: SlideTransition(
                        position: slideAnimation(
                          0.00,
                          0.30,
                          begin: const Offset(-0.65, 0),
                        ),
                        child: _buildSidebar(
                          compactLandscape: compactLandscape,
                        ),
                      ),
                    ),

                    SizedBox(width: compactLandscape ? 7 : 18 * densityScale),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            FadeTransition(
                              opacity: fadeAnimation(0.08, 0.38),
                              child: SlideTransition(
                                position: slideAnimation(
                                  0.08,
                                  0.38,
                                  begin: const Offset(0, -0.45),
                                ),
                                child: _buildHeader(
                                  compactLandscape: compactLandscape,
                                ),
                              ),
                            ),

                            AnimatedSwitcher(
                              duration: MotionPreferences.duration(280),
                              child: _liveMarketStore.isOffline
                                  ? Padding(
                                      key: const ValueKey('offline-warning'),
                                      padding: EdgeInsets.only(
                                        top: 14 * densityScale,
                                      ),
                                      child: _buildInternetWarning(),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('online-no-warning'),
                                    ),
                            ),

                            SizedBox(
                              height: compactLandscape ? 8 : 18 * densityScale,
                            ),

                            if (!compactLandscape ||
                                selectedNavigationIndex == 0) ...[
                              _buildMarketCards(
                                compactLandscape: compactLandscape,
                              ),
                              SizedBox(
                                height: compactLandscape
                                    ? 8
                                    : 18 * densityScale,
                              ),
                            ],

                            _buildSelectedPage(
                              compactLandscape: compactLandscape,
                            ),

                            SizedBox(height: 18 * densityScale),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 28,
              left: compactToast ? 16 : null,
              right: compactToast ? 16 : 28,
              width: compactToast ? null : 390,
              child: IgnorePointer(
                ignoring: _toastNotification == null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 360),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(.18, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _toastNotification == null
                      ? const SizedBox.shrink(key: ValueKey('no-toast'))
                      : _NotificationToast(
                          key: ValueKey(_toastNotification!.id),
                          palette: palette,
                          notification: _toastNotification!,
                          languageCode: _activeLanguage.name,
                          newLabel: translatedText(
                            english: 'New notification',
                            persian: 'اعلان جدید دارید',
                            japanese: '新しい通知',
                            russian: 'Новое уведомление',
                          ),
                          onOpen: _showNotificationsPanel,
                          onClose: () {
                            final id = _toastNotification!.id;
                            _toastTimer?.cancel();
                            setState(() => _toastNotification = null);
                            _notificationService.removeNotification(id);
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInternetWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5F70).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF7182).withValues(alpha: 0.48),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF7182)),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              translatedText(
                english:
                    'No internet connection. GoldBrain needs internet for live prices, news and AI.',
                persian:
                    'اتصال اینترنت برقرار نیست؛ برنامه بدون اینترنت کار نمی‌کند.',
                japanese: 'インターネットに接続されていません。リアルタイム価格、ニュース、AIには接続が必要です。',
                russian:
                    'Нет подключения к интернету. Для цен, новостей и ИИ требуется интернет.',
              ),
              style: const TextStyle(
                color: Color(0xFFFFA0AA),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _liveMarketStore.loading
                ? null
                : () => unawaited(_liveMarketStore.retryNow()),
            icon: _liveMarketStore.loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 17),
            label: Text(
              translatedText(
                english: 'Retry',
                persian: 'تلاش دوباره',
                japanese: '再試行',
                russian: 'Повторить',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    if (!_settingsStore.motionEnabled || _settingsStore.reducedMotion) {
      return Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: DashboardGridPainter(
                color: palette.primary,
                progress: 0,
              ),
            ),
          ),
        ],
      );
    }
    return AnimatedBuilder(
      animation: _ambientController,
      builder: (context, child) {
        final phase = _ambientController.value * math.pi * 2;
        final intensity = _settingsStore.animationIntensity;

        final movementX = math.sin(phase) * (2 + intensity * 46);
        final movementY = math.cos(phase) * (2 + intensity * 36);

        return Stack(
          children: [
            Positioned(
              top: -260 + movementY,
              right: -180 + movementX,
              child: Container(
                width: 620,
                height: 620,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.primary.withValues(
                        alpha: 0.035 + intensity * 0.12,
                      ),
                      palette.primary.withValues(
                        alpha: 0.008 + intensity * 0.03,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: -310 - movementY,
              left: -220 - movementX,
              child: Container(
                width: 680,
                height: 680,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.secondary.withValues(
                        alpha: 0.018 + intensity * 0.075,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            Positioned.fill(
              child: CustomPaint(
                painter: DashboardGridPainter(
                  color: palette.primary,
                  progress: _ambientController.value,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSidebar({bool compactLandscape = false}) {
    final items = <GoldBrainSidebarItem>[
      GoldBrainSidebarItem(
        icon: Icons.space_dashboard_rounded,
        label: translatedText(
          english: 'Dashboard',
          persian: 'داشبورد',
          japanese: 'ダッシュボード',
          russian: 'Панель',
        ),
      ),
      GoldBrainSidebarItem(
        icon: Icons.candlestick_chart_rounded,
        label: translatedText(
          english: 'Markets',
          persian: 'بازارها',
          japanese: '市場',
          russian: 'Рынки',
        ),
      ),
      GoldBrainSidebarItem(
        icon: Icons.newspaper_rounded,
        label: translatedText(
          english: 'News',
          persian: 'اخبار',
          japanese: 'ニュース',
          russian: 'Новости',
          chinese: '新闻',
        ),
        badge: _newsStore.unreadCount > 0
            ? (_newsStore.unreadCount > 99
                  ? '99+'
                  : '${_newsStore.unreadCount}')
            : null,
      ),
      GoldBrainSidebarItem(
        icon: Icons.auto_awesome_rounded,
        label: translatedText(
          english: 'AI Assistant',
          persian: 'دستیار هوشمند',
          japanese: 'AIアシスタント',
          russian: 'ИИ-помощник',
        ),
      ),
      GoldBrainSidebarItem(
        icon: Icons.star_outline_rounded,
        label: translatedText(
          english: 'Watchlist',
          persian: 'دیده‌بان',
          japanese: 'ウォッチリスト',
          russian: 'Избранное',
        ),
      ),
      GoldBrainSidebarItem(
        icon: Icons.account_balance_wallet_outlined,
        label: translatedText(
          english: 'Portfolio',
          persian: 'سبد دارایی',
          japanese: 'ポートフォリオ',
          russian: 'Портфель',
        ),
      ),
      GoldBrainSidebarItem(
        icon: Icons.person_outline_rounded,
        label: translatedText(
          english: 'Profile',
          persian: 'پروفایل',
          japanese: 'プロフィール',
          russian: 'Профиль',
        ),
      ),
      GoldBrainSidebarItem(
        icon: Icons.settings_rounded,
        label: translatedText(
          english: 'Settings',
          persian: 'تنظیمات',
          japanese: '設定',
          russian: 'Настройки',
        ),
      ),
      GoldBrainSidebarItem(
        icon: Icons.info_outline_rounded,
        label: translatedText(
          english: 'About Us',
          persian: 'درباره ما',
          japanese: '私たちについて',
          russian: 'О нас',
        ),
      ),
    ];

    return GoldBrainSidebar(
      palette: palette,
      items: items,
      selectedIndex: selectedNavigationIndex,
      expanded: compactLandscape ? false : sidebarExpanded,
      compactLandscape: compactLandscape,
      onToggleExpanded: () {
        playTabSound();
        setState(() => sidebarExpanded = !sidebarExpanded);
      },
      onSelected: (index) {
        playTabSound();
        setState(() => selectedNavigationIndex = index);
      },
      onHover: playHoverSound,
      profileName: _profileStore.name.isEmpty
          ? translatedText(
              english: 'GoldBrain User',
              persian: 'کاربر GoldBrain',
              japanese: 'GoldBrainユーザー',
              russian: 'Пользователь GoldBrain',
            )
          : _profileStore.name,
      profileSubtitle: translatedText(
        english: 'Neural account',
        persian: 'حساب عصبی',
        japanese: 'ニューラルアカウント',
        russian: 'Нейронный аккаунт',
      ),
      profileImagePath: _profileStore.imagePath ?? '',
    );
  }

  Widget _buildHeader({bool compactLandscape = false}) {
    if (compactLandscape) {
      return Container(
        key: const ValueKey('mobile-landscape-header'),
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.primary.withValues(alpha: 0.18)),
        ),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [
            Icon(Icons.hub_rounded, color: palette.primary, size: 25),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'GoldBrain AI',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Semantics(
              label: translatedText(
                english: 'System online',
                persian: 'سامانه فعال',
                japanese: 'システム稼働中',
                russian: 'Система в сети',
              ),
              child: Icon(
                Icons.cloud_done_rounded,
                color: const Color(0xFF47E596),
                size: 20,
              ),
            ),
            const SizedBox(width: 5),
            _HeaderIconButton(
              icon: Icons.notifications_none_rounded,
              palette: palette,
              badgeCount: _settingsStore.notificationsEnabled
                  ? _notificationService.unreadCount
                  : 0,
              onTap: _showNotificationsPanel,
              onHover: playHoverSound,
            ),
            _HeaderIconButton(
              icon: Icons.settings_rounded,
              palette: palette,
              onTap: () {
                playClickSound();
                setState(() => selectedNavigationIndex = 7);
              },
              onHover: playHoverSound,
            ),
          ],
        ),
      );
    }
    final densityScale = _densityScale;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 26 * densityScale,
        vertical: 19 * densityScale,
      ),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: palette.primary.withValues(alpha: 0.16)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      colors: [palette.primary, palette.secondary],
                    ).createShader(bounds);
                  },
                  child: const Text(
                    'GoldBrain AI',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  translatedText(
                    english: 'Neural market intelligence system',
                    persian: 'سامانه هوشمند تحلیل عصبی بازار',
                    japanese: 'ニューラル市場インテリジェンスシステム',
                    russian: 'Нейронная система анализа рынка',
                  ),
                  style: TextStyle(color: palette.mutedText, fontSize: 13),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          _HeaderStatusChip(
            palette: palette,
            icon: Icons.cloud_done_rounded,
            text: translatedText(
              english: 'SYSTEM ONLINE',
              persian: 'سامانه فعال',
              japanese: 'システム稼働中',
              russian: 'СИСТЕМА В СЕТИ',
            ),
          ),

          const SizedBox(width: 12),

          _HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            palette: palette,
            badgeCount: _settingsStore.notificationsEnabled
                ? _notificationService.unreadCount
                : 0,
            onTap: _showNotificationsPanel,
            onHover: playHoverSound,
          ),

          const SizedBox(width: 10),

          _HeaderIconButton(
            icon: Icons.settings_rounded,
            palette: palette,
            onTap: () {
              playClickSound();

              setState(() {
                selectedNavigationIndex = 7;
              });
            },
            onHover: playHoverSound,
          ),
        ],
      ),
    );
  }

  Widget _buildMarketCards({bool compactLandscape = false}) {
    final cards = [
      _liveMarketCard(
        symbol: 'GOLD18',
        icon: Icons.auto_awesome_rounded,
        title: translatedText(
          english: 'Gold 18K',
          persian: 'طلای ۱۸ عیار',
          japanese: '18金',
          russian: 'Золото 18К',
        ),
      ),
      _liveMarketCard(
        symbol: 'USD',
        icon: Icons.attach_money_rounded,
        title: translatedText(
          english: 'US Dollar',
          persian: 'دلار آمریکا',
          japanese: '米ドル',
          russian: 'Доллар США',
        ),
      ),
      _liveMarketCard(
        symbol: 'XAU',
        icon: Icons.public_rounded,
        title: translatedText(
          english: 'Global Ounce',
          persian: 'اونس جهانی',
          japanese: '世界の金価格',
          russian: 'Мировая унция',
        ),
      ),
    ];

    if (compactLandscape) {
      return SizedBox(
        key: const ValueKey('mobile-landscape-market-strip'),
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => SizedBox(
            width: 210,
            child: DashboardMarketCard(
              data: cards[index],
              palette: palette,
              ambientController: _ambientController,
              densityScale: 0.67,
            ),
          ),
        ),
      );
    }

    return Row(
      textDirection: TextDirection.ltr,
      children: List.generate(cards.length, (index) {
        final start = 0.22 + index * 0.10;
        final end = 0.52 + index * 0.10;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == cards.length - 1 ? 0 : 14),
            child: FadeTransition(
              opacity: fadeAnimation(start, end),
              child: SlideTransition(
                position: slideAnimation(
                  start,
                  end,
                  begin: Offset(0, 0.55 + index * 0.08),
                ),
                child: DashboardMarketCard(
                  data: cards[index],
                  palette: palette,
                  ambientController: _ambientController,
                  densityScale: _densityScale,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  MarketCardData _liveMarketCard({
    required String symbol,
    required IconData icon,
    required String title,
  }) {
    final quote = _liveMarketStore.quoteFor(symbol);
    final change = quote?.changePercent;
    final conversion = quote == null
        ? null
        : CurrencyService.conversionStatus(
            sourceCode: quote.currency,
            selectedCode: _settingsStore.currencyCode,
            language: _activeLanguage,
          );
    final conversionUnavailable = conversion?.unavailable ?? false;
    final stale =
        quote != null &&
        (quote.isStale ||
            (_liveMarketStore.batch?.errors.containsKey(symbol) ?? false) ||
            (conversion?.isStale ?? false));
    final delayed =
        quote?.freshnessStatus?.toUpperCase() == 'DELAYED' &&
        quote?.dataQualityStatus == 'VALID' &&
        !(_liveMarketStore.batch?.errors.containsKey(symbol) ?? false) &&
        !(conversion?.isStale ?? false);
    final value = quote == null
        ? (_liveMarketStore.loading ? '…' : '—')
        : _formatSourcedPrice(quote.price, quote.currency);
    final updatedAt = quote?.updatedAt.toLocal();
    final isNavasanDomestic =
        quote != null &&
        const {'USD', 'EUR', 'GOLD18'}.contains(quote.symbol.toUpperCase()) &&
        (quote.provider.name == 'navasan' ||
            quote.upstreamSource?.trim().toLowerCase() == 'navasan');
    final cadenceLabel = isNavasanDomestic
        ? translatedText(
            english:
                'Navasan source ~2h · app checks no more than once per 8h · not live',
            persian:
                'منبع نوسان حدود ۲ساعته · برنامه بیش از یک بار در هر ۸ ساعت بررسی نمی‌کند · لحظه‌ای نیست',
            japanese: 'Navasan提供元は約2時間更新 · アプリの確認は8時間に1回以下 · リアルタイムではありません',
            russian:
                'Источник Navasan ~2 ч · приложение проверяет не чаще раза в 8 ч · не в реальном времени',
          )
        : null;
    final sourceDetails = quote == null
        ? null
        : '${cadenceLabel == null ? '' : '$cadenceLabel · '}${quote.providerLabel} · ${updatedAt!.year}-${updatedAt.month.toString().padLeft(2, '0')}-${updatedAt.day.toString().padLeft(2, '0')} ${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}' +
              (conversionUnavailable
                  ? ' · FX N/A'
                  : delayed
                  ? ' · DELAYED'
                  : stale
                  ? ' · STALE'
                  : '');
    return MarketCardData(
      icon: icon,
      title: title,
      value: value,
      change: conversionUnavailable
          ? 'FX N/A'
          : delayed
          ? 'DELAYED'
          : stale
          ? 'STALE'
          : change == null
          ? '—'
          : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
      positive: stale || conversionUnavailable || change == null
          ? null
          : change >= 0,
      stale: stale || conversionUnavailable,
      sourceDetails: sourceDetails,
    );
  }

  String _formatSourcedPrice(double value, String currencyCode) {
    return CurrencyService.formatPrice(
      value: value,
      sourceCode: currencyCode,
      selectedCode: _settingsStore.currencyCode,
      language: _activeLanguage,
    );
  }

  Widget _buildSelectedPage({bool compactLandscape = false}) {
    return RetainedTab(
      key: const ValueKey('retained-assistant-tab'),
      active: selectedNavigationIndex == 3,
      retainedChild: AiAssistantScreen(
        key: const ValueKey('ai-assistant'),
        palette: palette,
        selectedLanguage: _activeLanguage,
      ),
      otherChild: selectedNavigationIndex == 3
          ? const SizedBox.shrink()
          : _buildOtherPage(compactLandscape: compactLandscape),
    );
  }

  Widget _buildOtherPage({bool compactLandscape = false}) {
    switch (selectedNavigationIndex) {
      case 1:
        return MarketsScreen(
          key: ValueKey('markets-${_settingsStore.currencyCode}-$_motionKey'),
          palette: palette,
          selectedLanguage: _activeLanguage,
          currencyCode: _settingsStore.currencyCode,
          marketStore: _liveMarketStore,
        );

      case 2:
        return NewsScreen(
          key: ValueKey('news-$_motionKey'),
          palette: palette,
          selectedLanguage: _activeLanguage,
        );

      case 4:
        return WatchlistScreen(
          key: ValueKey('watchlist-${_settingsStore.currencyCode}-$_motionKey'),
          palette: palette,
          selectedLanguage: _activeLanguage,
          currencyCode: _settingsStore.currencyCode,
        );

      case 5:
        return PortfolioScreen(
          key: ValueKey('portfolio-$_motionKey'),
          palette: palette,
          selectedLanguage: _activeLanguage,
        );

      case 6:
        return ProfileScreen(
          key: ValueKey('profile-$_motionKey'),
          palette: palette,
          selectedLanguage: _activeLanguage,
          onProfileChanged: _refreshProfile,
        );

      case 7:
        return SettingsScreen(
          key: const ValueKey('settings'),
          selectedTheme: _activeTheme,
          selectedLanguage: _activeLanguage,
          onSettingsChanged: _refreshSettings,
        );

      case 8:
        return AboutUsScreen(
          key: ValueKey('about-${_activeTheme.name}-${_activeLanguage.name}'),
          palette: palette,
          selectedLanguage: _activeLanguage,
        );

      case 0:
      default:
        return KeyedSubtree(
          key: const ValueKey('dashboard'),
          child: _buildMainDashboardContent(compactLandscape: compactLandscape),
        );
    }
  }

  Widget _buildMainDashboardContent({bool compactLandscape = false}) {
    final densityScale = _densityScale;
    if (compactLandscape) {
      return Column(
        key: const ValueKey('mobile-landscape-dashboard-content'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildChartPanel(densityScale: 0.72),
          const SizedBox(height: 8),
          _buildAiPanel(densityScale: 0.72),
        ],
      );
    }
    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: FadeTransition(
            opacity: fadeAnimation(0.48, 0.80),
            child: SlideTransition(
              position: slideAnimation(
                0.48,
                0.80,
                begin: const Offset(-0.22, 0.30),
              ),
              child: _buildChartPanel(),
            ),
          ),
        ),

        SizedBox(width: 16 * densityScale),

        Expanded(
          flex: 4,
          child: FadeTransition(
            opacity: fadeAnimation(0.58, 0.90),
            child: SlideTransition(
              position: slideAnimation(
                0.58,
                0.90,
                begin: const Offset(0.28, 0.30),
              ),
              child: _buildAiPanel(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChartPanel({double? densityScale}) {
    final effectiveDensity = densityScale ?? _densityScale;
    return Container(
      height: (effectiveDensity < 0.9 ? 660 : 610) * effectiveDensity,
      padding: EdgeInsets.all(24 * effectiveDensity),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.83),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: palette.primary.withValues(alpha: 0.20)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: TextDirection.ltr,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(Icons.show_chart_rounded, color: palette.primary),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translatedText(
                        english: 'Neural Market Pulse',
                        persian: 'نبض عصبی بازار',
                        japanese: 'ニューラル市場パルス',
                        russian: 'Нейронный пульс рынка',
                      ),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      translatedText(
                        english:
                            'Observed market pulse · descriptive, not a forecast',
                        persian: 'نبض داده‌های واقعی بازار · نه پیش‌بینی',
                        japanese: '観測市場パルス · 予測ではありません',
                        russian: 'Пульс рынка по данным · не прогноз',
                      ),
                      style: TextStyle(color: palette.mutedText, fontSize: 12),
                    ),
                  ],
                ),
              ),

              if (_pulseCountry == null) ...[
                _TimeRangeButton(
                  text: '1H',
                  selected:
                      _dashboardHistoryRange == MarketHistoryRange.oneHour,
                  palette: palette,
                  onTap: () =>
                      _changeDashboardHistoryRange(MarketHistoryRange.oneHour),
                ),
                const SizedBox(width: 7),
              ],
              _TimeRangeButton(
                text: '24H',
                selected: _dashboardHistoryRange == MarketHistoryRange.oneDay,
                palette: palette,
                onTap: () =>
                    _changeDashboardHistoryRange(MarketHistoryRange.oneDay),
              ),
              const SizedBox(width: 7),
              _TimeRangeButton(
                text: '7D',
                selected: _dashboardHistoryRange == MarketHistoryRange.oneWeek,
                palette: palette,
                onTap: () =>
                    _changeDashboardHistoryRange(MarketHistoryRange.oneWeek),
              ),
              const SizedBox(width: 7),
              _TimeRangeButton(
                text: '30D',
                selected: _dashboardHistoryRange == MarketHistoryRange.oneMonth,
                palette: palette,
                onTap: () =>
                    _changeDashboardHistoryRange(MarketHistoryRange.oneMonth),
              ),
            ],
          ),

          const SizedBox(height: 10),
          _buildPulseAssetPicker(),
          const SizedBox(height: 8),
          _buildAssetPulseSummary(),
          const SizedBox(height: 8),
          Expanded(child: _buildDashboardHistoryBody()),
        ],
      ),
    );
  }

  Widget _buildPulseAssetPicker() {
    final symbols = _liveMarketStore.assets
        .where((asset) => asset.liveQuote)
        .map((asset) => asset.symbol)
        .toSet();
    symbols.add(_pulseAsset);
    final sorted = symbols.toList()..sort();
    return Row(
      children: [
        Icon(Icons.tune_rounded, color: palette.primary, size: 17),
        const SizedBox(width: 8),
        Text(
          translatedText(
            english: 'Market',
            persian: 'بازار',
            japanese: '市場',
            russian: 'Рынок',
          ),
          style: TextStyle(color: palette.mutedText, fontSize: 11),
        ),
        const SizedBox(width: 10),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey('pulse-asset-picker'),
            value: _pulseCountry == null
                ? _pulseAsset
                : 'country:$_pulseCountry',
            dropdownColor: palette.surface,
            style: TextStyle(
              color: palette.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            items: [
              for (final country in _pulseCountries.entries)
                DropdownMenuItem(
                  key: ValueKey('pulse-country-${country.key}'),
                  value: 'country:${country.key}',
                  child: Text(country.value),
                ),
              for (final symbol in sorted)
                DropdownMenuItem(value: symbol, child: Text(symbol)),
            ],
            onChanged: (value) {
              if (value == null) return;
              if (value.startsWith('country:')) {
                _changePulseCountry(value.substring('country:'.length));
              } else {
                _changePulseAsset(value);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAssetPulseSummary() {
    final series = _selectedPulseHistory;
    final pulse = series == null
        ? null
        : _pulseCountry != null
        ? _countryEvidence!.calculatePulse()
        : const MarketPulseCalculator().calculate(series);
    final score = pulse?.score;
    final detail = score == null
        ? (_selectedPulseLoading
              ? translatedText(
                  english: 'Loading observed history…',
                  persian: 'در حال دریافت تاریخچهٔ واقعی…',
                  japanese: '履歴を読み込み中…',
                  russian: 'Загрузка истории…',
                )
              : _countryError ??
                    _pulseReason(pulse?.reason) ??
                    translatedText(
                      english: 'Insufficient verified history',
                      persian: 'تاریخچهٔ معتبر کافی نیست',
                      japanese: '検証済み履歴が不足しています',
                      russian: 'Недостаточно проверенной истории',
                    ))
        : '${pulse!.priceReturnPercent!.toStringAsFixed(2)}% · ' +
              (_pulseCountry != null
                  ? '${_countryEvidence!.indexName} · ' +
                        (pulse.hasNews
                            ? translatedText(
                                english: 'index + news tone',
                                persian: 'شاخص + لحن خبرها',
                                japanese: '指数とニューストーン',
                                russian: 'Индекс и тон новостей',
                              )
                            : translatedText(
                                english: 'index only; news unavailable',
                                persian: 'فقط شاخص؛ خبر در دسترس نیست',
                                japanese: '指数のみ、ニュースなし',
                                russian: 'Только индекс; новости недоступны',
                              ))
                  : pulse.hasVolume
                  ? translatedText(
                      english: 'price + volatility + volume; news unavailable',
                      persian: 'قیمت + نوسان + حجم؛ خبر در دسترس نیست',
                      japanese: '価格・変動・出来高、ニュースなし',
                      russian:
                          'Цена, волатильность и объём; новости недоступны',
                    )
                  : translatedText(
                      english:
                          'price + volatility only; volume/news unavailable',
                      persian: 'فقط قیمت و نوسان؛ حجم/خبر در دسترس نیست',
                      japanese: '価格と変動のみ、出来高・ニュースなし',
                      russian:
                          'Только цена и волатильность; объём и новости недоступны',
                    ));
    return Container(
      key: const ValueKey('asset-pulse-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Text(
            score == null ? '—' : '$score/100',
            key: const ValueKey('asset-pulse-score'),
            style: TextStyle(
              color: palette.primary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              detail,
              key: _pulseCountry == null
                  ? null
                  : const ValueKey('country-pulse-status'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.mutedText, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  String? _pulseReason(String? reason) => switch (reason) {
    null => null,
    'Source history is stale or unverified.' => translatedText(
      english: reason,
      persian: 'تاریخچهٔ منبع قدیمی یا تأییدنشده است.',
      japanese: '履歴は古いか未検証です。',
      russian: 'История источника устарела или не подтверждена.',
    ),
    'Latest market observation is too old.' => translatedText(
      english: reason,
      persian: 'آخرین مشاهدهٔ بازار بیش از حد قدیمی است.',
      japanese: '最新の市場観測が古すぎます。',
      russian: 'Последнее наблюдение рынка слишком старое.',
    ),
    'Insufficient history: at least four observations are required.' ||
    'Insufficient coverage for the selected window.' => translatedText(
      english: reason,
      persian: 'تاریخچهٔ کافی برای این بازه وجود ندارد.',
      japanese: 'この期間の履歴が不足しています。',
      russian: 'Недостаточно истории для этого периода.',
    ),
    'History contains invalid or unordered observations.' => translatedText(
      english: reason,
      persian: 'تاریخچه دارای دادهٔ نامعتبر یا نامرتب است.',
      japanese: '履歴に無効または順序外のデータがあります。',
      russian: 'История содержит неверные или неупорядоченные данные.',
    ),
    _ => reason,
  };

  Map<String, String> get _pulseCountries => <String, String>{
    'usa': translatedText(
      english: 'USA',
      persian: 'آمریکا',
      japanese: '米国',
      russian: 'США',
    ),
    'germany': translatedText(
      english: 'Germany',
      persian: 'آلمان',
      japanese: 'ドイツ',
      russian: 'Германия',
    ),
    'japan': translatedText(
      english: 'Japan',
      persian: 'ژاپن',
      japanese: '日本',
      russian: 'Япония',
    ),
    'china': translatedText(
      english: 'China',
      persian: 'چین',
      japanese: '中国',
      russian: 'Китай',
    ),
    'france': translatedText(
      english: 'France',
      persian: 'فرانسه',
      japanese: 'フランス',
      russian: 'Франция',
    ),
    'iran': translatedText(
      english: 'Iran',
      persian: 'ایران',
      japanese: 'イラン',
      russian: 'Иран',
    ),
  };

  Widget _buildDashboardHistoryBody() {
    final series = _selectedPulseHistory;
    if (_selectedPulseLoading && series == null) {
      return Center(
        key: const ValueKey('dashboard-history-loading'),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: palette.primary,
        ),
      );
    }
    if (series == null || series.candles.length < 2) {
      return Container(
        key: const ValueKey('dashboard-history-unavailable'),
        decoration: BoxDecoration(
          color: palette.background.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.primary.withValues(alpha: 0.10)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, color: palette.mutedText, size: 34),
              const SizedBox(height: 10),
              Text(
                translatedText(
                  english:
                      'Verified $_selectedPulseName history is unavailable',
                  persian: 'تاریخچهٔ معتبر $_selectedPulseName در دسترس نیست',
                  japanese: '$_selectedPulseName の検証済み履歴は利用できません',
                  russian: 'Проверенная история $_selectedPulseName недоступна',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedPulseError ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.mutedText, fontSize: 10),
              ),
              const SizedBox(height: 8),
              IconButton.filledTonal(
                key: const ValueKey('retry-dashboard-history'),
                onPressed: () => unawaited(
                  _pulseCountry == null
                      ? _loadDashboardHistory(forceRefresh: true)
                      : _loadCountryEvidence(),
                ),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
      );
    }

    final display = _displayPulseHistory(series);

    return Column(
      key: ValueKey(
        'dashboard-history-${series.range.name}-${series.fetchedAt.millisecondsSinceEpoch}',
      ),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const ValueKey('open-dashboard-history'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_showDashboardHistoryDialog()),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _ambientController,
                    _scanController,
                  ]),
                  builder: (context, child) {
                    return CustomPaint(
                      painter: NeuralChartPainter(
                        palette: palette,
                        candles: display.series.candles,
                        isPriceSample: display.series.isPriceSample,
                        connectDailyIndexObservations:
                            _connectDailyIndexObservations,
                        animationProgress: _ambientController.value,
                        scanProgress: _scanController.value,
                      ),
                      child: const SizedBox.expand(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Icon(
              series.isStale
                  ? Icons.history_toggle_off_rounded
                  : series.isProxy
                  ? Icons.info_outline_rounded
                  : Icons.verified_rounded,
              size: 13,
              color: series.isStale || series.isProxy
                  ? const Color(0xFFFFC857)
                  : const Color(0xFF50E397),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _dashboardHistoryCaption(series),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.mutedText, fontSize: 9),
              ),
            ),
            if (_selectedPulseLoading)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: palette.primary,
                ),
              ),
          ],
        ),
        if (display.conversionStale || display.conversionUnavailable)
          Text(
            display.conversionUnavailable
                ? translatedText(
                    english:
                        'Exchange rate unavailable; chart remains in ${series.currency}.',
                    persian:
                        'نرخ تبدیل در دسترس نیست؛ نمودار به ${series.currency} باقی مانده است.',
                    japanese: '為替レートを取得できないため、チャートは ${series.currency} のままです。',
                    russian:
                        'Курс недоступен; график остается в ${series.currency}.',
                  )
                : translatedText(
                    english: 'Chart uses the last known exchange rate.',
                    persian:
                        'نمودار با آخرین نرخ تبدیل ثبت‌شده نمایش داده می‌شود.',
                    japanese: 'チャートには最後に取得した為替レートを使用しています。',
                    russian: 'График использует последний известный курс.',
                  ),
            style: const TextStyle(color: Color(0xFFFFC857), fontSize: 10),
          ),
      ],
    );
  }

  Widget _buildAiPanel({double? densityScale}) => DeepMarketAnalysisCard(
    palette: palette,
    language: _activeLanguage,
    store: _intelligenceStore,
    densityScale: densityScale ?? _densityScale,
  );

  // Kept temporarily as an internal visual reference while the new evidence-
  // based analyst card is rolled out. It is no longer placed in the widget tree.
  // ignore: unused_element
  Widget _buildLegacyAiPanel() {
    final densityScale = _densityScale;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      height: (aiPanelExpanded ? 500 : 114) * densityScale,
      padding: EdgeInsets.all(23 * densityScale),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: palette.primary.withValues(
            alpha: aiPanelExpanded ? 0.55 : 0.22,
          ),
          width: aiPanelExpanded ? 1.8 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(
              alpha: aiPanelExpanded ? 0.18 : 0.06,
            ),
            blurRadius: aiPanelExpanded ? 44 : 26,
            spreadRadius: aiPanelExpanded ? 3 : 0,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // During expansion, the box initially still has the collapsed
          // height. Inserting the full body in that frame causes the exact
          // RenderFlex overflow reported on Windows. Only reveal it once the
          // animated box has enough physical space.
          final showDetails = aiPanelExpanded && constraints.maxHeight >= 330;

          return Column(
            children: [
              Row(
                textDirection: TextDirection.ltr,
                children: [
                  AnimatedBuilder(
                    animation: _ambientController,
                    builder: (context, child) {
                      final pulse = 0.92 + _ambientController.value * 0.10;

                      return Transform.scale(
                        scale: pulse,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              transform: GradientRotation(
                                _ambientController.value * math.pi * 2,
                              ),
                              colors: [
                                palette.primary,
                                palette.secondary,
                                Colors.white,
                                palette.primary,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: palette.primary.withValues(alpha: 0.40),
                                blurRadius: 25,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Container(
                            decoration: BoxDecoration(
                              color: palette.surface,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.psychology_alt_rounded,
                              color: palette.primary,
                              size: 28,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GOLDBRAIN CORE',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: palette.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          translatedText(
                            english: 'Neural analysis engine',
                            persian: 'موتور تحلیل عصبی',
                            japanese: 'ニューラル分析エンジン',
                            russian: 'Нейронный аналитический движок',
                          ),
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  IconButton(
                    onPressed: () {
                      playClickSound();

                      setState(() {
                        aiPanelExpanded = !aiPanelExpanded;
                      });
                    },
                    icon: AnimatedRotation(
                      duration: const Duration(milliseconds: 350),
                      turns: aiPanelExpanded ? 0.5 : 0,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: palette.mutedText,
                      ),
                    ),
                  ),
                ],
              ),

              if (showDetails) ...[
                const SizedBox(height: 24),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _ambientController,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: AiCorePainter(
                              palette: palette,
                              progress: _ambientController.value,
                            ),
                            child: const SizedBox.expand(),
                          );
                        },
                      ),

                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'AI',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              color: palette.secondary,
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(
                                  color: palette.primary.withValues(
                                    alpha: 0.50,
                                  ),
                                  blurRadius: 22,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            translatedText(
                              english: 'ASSISTANT CORE',
                              persian: 'هسته دستیار هوشمند',
                              japanese: 'AIアシスタントコア',
                              russian: 'ЯДРО ИИ-ПОМОЩНИКА',
                            ),
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    translatedText(
                      english:
                          'Open the AI Assistant to ask a question. No market signal is shown without sourced live data.',
                      persian:
                          'برای پرسیدن سؤال، دستیار هوشمند را باز کنید. بدون داده زنده و منبع‌دار هیچ سیگنال بازاری نمایش داده نمی‌شود.',
                      japanese: 'AIアシスタントで質問できます。出典付きライブデータなしに市場シグナルは表示しません。',
                      russian:
                          'Откройте ИИ-помощник. Без актуальных данных с источником рыночный сигнал не показывается.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.mutedText,
                      height: 1.5,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class MarketCardData {
  const MarketCardData({
    required this.icon,
    required this.title,
    required this.value,
    required this.change,
    required this.positive,
    this.stale = false,
    this.sourceDetails,
  });

  final IconData icon;
  final String title;
  final String value;
  final String change;
  final bool? positive;
  final bool stale;
  final String? sourceDetails;
}

class DashboardNavigationButton extends StatefulWidget {
  const DashboardNavigationButton({
    super.key,
    required this.icon,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final ThemePalette palette;
  final VoidCallback onTap;

  @override
  State<DashboardNavigationButton> createState() =>
      _DashboardNavigationButtonState();
}

class _DashboardNavigationButtonState extends State<DashboardNavigationButton> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          hovered = false;
          pressed = false;
        });
      },
      child: GestureDetector(
        onTapDown: (_) {
          setState(() {
            pressed = true;
          });
        },
        onTapCancel: () {
          setState(() {
            pressed = false;
          });
        },
        onTapUp: (_) {
          setState(() {
            pressed = false;
          });

          widget.onTap();
        },
        child: AnimatedScale(
          scale: pressed
              ? 0.90
              : hovered
              ? 1.08
              : 1,
          duration: const Duration(milliseconds: 170),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: widget.selected
                  ? widget.palette.primary.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: hovered ? 0.07 : 0.025),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: widget.selected
                    ? widget.palette.primary
                    : hovered
                    ? widget.palette.primary.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
              boxShadow: [
                if (widget.selected)
                  BoxShadow(
                    color: widget.palette.primary.withValues(alpha: 0.22),
                    blurRadius: 18,
                  ),
              ],
            ),
            child: Icon(
              widget.icon,
              color: widget.selected
                  ? widget.palette.secondary
                  : widget.palette.mutedText,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardMarketCard extends StatefulWidget {
  const DashboardMarketCard({
    super.key,
    required this.data,
    required this.palette,
    required this.ambientController,
    required this.densityScale,
  });

  final MarketCardData data;
  final ThemePalette palette;
  final AnimationController ambientController;
  final double densityScale;

  @override
  State<DashboardMarketCard> createState() => _DashboardMarketCardState();
}

class _DashboardMarketCardState extends State<DashboardMarketCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final changeColor = widget.data.stale
        ? const Color(0xFFFFC857)
        : widget.data.positive == null
        ? widget.palette.mutedText
        : widget.data.positive!
        ? const Color(0xFF54E69A)
        : const Color(0xFFFF7D89);
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) {
        setState(() {
          hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          hovered = false;
        });
      },
      child: AnimatedBuilder(
        animation: widget.ambientController,
        builder: (context, child) {
          final pulse = widget.ambientController.value * 0.04;

          return AnimatedScale(
            scale: hovered ? 1.025 : 1,
            duration: const Duration(milliseconds: 260),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              height: 154 * widget.densityScale,
              padding: EdgeInsets.all(20 * widget.densityScale),
              decoration: BoxDecoration(
                color: widget.palette.surface.withValues(
                  alpha: hovered ? 0.94 : 0.82,
                ),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: widget.palette.primary.withValues(
                    alpha: hovered ? 0.52 : 0.18,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.palette.primary.withValues(
                      alpha: hovered ? 0.17 : pulse,
                    ),
                    blurRadius: hovered ? 30 : 18,
                    spreadRadius: hovered ? 2 : 0,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -46,
                    right: -38,
                    child: Container(
                      width: 125,
                      height: 125,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            widget.palette.primary.withValues(alpha: 0.12),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        textDirection: TextDirection.ltr,
                        children: [
                          Container(
                            width: 39,
                            height: 39,
                            decoration: BoxDecoration(
                              color: widget.palette.primary.withValues(
                                alpha: 0.11,
                              ),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              widget.data.icon,
                              color: widget.palette.primary,
                              size: 21,
                            ),
                          ),

                          const SizedBox(width: 11),

                          Expanded(
                            child: Text(
                              widget.data.title,
                              style: TextStyle(
                                color: widget.palette.mutedText,
                                fontSize: 13,
                              ),
                            ),
                          ),

                          Tooltip(
                            message: widget.data.sourceDetails ?? '',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: changeColor.withValues(alpha: 0.11),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                widget.data.change,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  color: changeColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        textDirection: TextDirection.ltr,
                        children: [
                          Text(
                            widget.data.value,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              color: widget.palette.text,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      if (widget.densityScale >= 0.8 &&
                          widget.data.sourceDetails != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.data.sourceDetails!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.data.stale
                                ? const Color(0xFFFFC857)
                                : widget.palette.mutedText,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderStatusChip extends StatelessWidget {
  const _HeaderStatusChip({
    required this.palette,
    required this.icon,
    required this.text,
  });

  final ThemePalette palette;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: palette.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Icon(icon, color: palette.primary, size: 16),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: palette.primary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.palette,
    required this.onTap,
    this.onHover,
    this.badgeCount = 0,
  });

  final IconData icon;
  final ThemePalette palette;
  final VoidCallback onTap;
  final VoidCallback? onHover;
  final int badgeCount;

  @override
  State<_HeaderIconButton> createState() {
    return _HeaderIconButtonState();
  }
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        widget.onHover?.call();
        setState(() {
          hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          hovered = false;
          pressed = false;
        });
      },
      child: GestureDetector(
        onTapDown: (_) {
          setState(() {
            pressed = true;
          });
        },
        onTapCancel: () {
          setState(() {
            pressed = false;
          });
        },
        onTapUp: (_) {
          setState(() {
            pressed = false;
          });

          widget.onTap();
        },
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: pressed ? 0.92 : 1,
          child: SizedBox(
            width: 45,
            height: 45,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 41,
                  height: 41,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: hovered ? 0.08 : 0.035,
                    ),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: hovered
                          ? widget.palette.primary.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    color: hovered
                        ? widget.palette.primary
                        : widget.palette.mutedText,
                    size: 20,
                  ),
                ),
                if (widget.badgeCount > 0)
                  Positioned(
                    top: -5,
                    right: -3,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 19,
                        minHeight: 19,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5868),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.palette.surface,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.badgeCount > 99 ? '99+' : '${widget.badgeCount}',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeRangeButton extends StatelessWidget {
  const _TimeRangeButton({
    required this.text,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final ThemePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: text,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: MotionPreferences.duration(180),
          width: 39,
          height: 31,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? palette.primary.withValues(alpha: 0.15)
                : palette.text.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? palette.primary
                  : palette.text.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            text,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: selected ? palette.secondary : palette.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationToast extends StatelessWidget {
  const _NotificationToast({
    super.key,
    required this.palette,
    required this.notification,
    required this.languageCode,
    required this.newLabel,
    required this.onOpen,
    required this.onClose,
  });

  final ThemePalette palette;
  final AppNotification notification;
  final String languageCode;
  final String newLabel;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(65 * (1 - value), 0),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0).toDouble(),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: .98),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.primary.withValues(alpha: .45)),
              boxShadow: [
                BoxShadow(
                  color: palette.primary.withValues(alpha: .18),
                  blurRadius: 30,
                  spreadRadius: 1,
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.primary.withValues(alpha: .14),
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: palette.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        newLabel,
                        style: TextStyle(
                          color: palette.primary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.localizedTitle(languageCode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.localizedMessage(languageCode),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 9.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                  color: palette.mutedText,
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardGridPainter extends CustomPainter {
  DashboardGridPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.025)
      ..strokeWidth = 0.8;

    const spacing = 52.0;

    final offset = progress * spacing;

    for (double x = -spacing + offset; x < size.width + spacing; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (
      double y = -spacing + offset;
      y < size.height + spacing;
      y += spacing
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant DashboardGridPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class NeuralChartPainter extends CustomPainter {
  NeuralChartPainter({
    required this.palette,
    required this.candles,
    this.isPriceSample = false,
    this.connectDailyIndexObservations = false,
    required this.animationProgress,
    required this.scanProgress,
  });

  final ThemePalette palette;
  final List<MarketCandle> candles;
  final bool isPriceSample;
  final bool connectDailyIndexObservations;
  final double animationProgress;
  final double scanProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundRect = Offset.zero & size;

    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          palette.primary.withValues(alpha: 0.055),
          palette.surface.withValues(alpha: 0.0),
        ],
      ).createShader(backgroundRect);

    canvas.drawRect(backgroundRect, backgroundPaint);

    final gridPaint = Paint()
      ..color = palette.primary.withValues(alpha: 0.07)
      ..strokeWidth = 0.8;

    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6;

      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 1; i < 10; i++) {
      final x = size.width * i / 10;

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (candles.length < 2) return;

    const horizontalPadding = 8.0;
    const verticalPadding = 12.0;
    final chartWidth = math.max(1.0, size.width - horizontalPadding * 2);
    final chartHeight = math.max(1.0, size.height - verticalPadding * 2);
    final closes = candles.map((candle) => candle.close);
    var minValue = closes.reduce(math.min);
    var maxValue = closes.reduce(math.max);
    if ((maxValue - minValue).abs() < 0.0000001) {
      final padding = math.max(1.0, maxValue.abs() * 0.01);
      minValue -= padding;
      maxValue += padding;
    } else {
      final padding = (maxValue - minValue) * 0.08;
      minValue -= padding;
      maxValue += padding;
    }
    final firstTime = candles.first.time.millisecondsSinceEpoch;
    final lastTime = candles.last.time.millisecondsSinceEpoch;
    final timeSpan = math.max(1, lastTime - firstTime);
    final points = <Offset>[
      for (final candle in candles)
        Offset(
          horizontalPadding +
              chartWidth *
                  (candle.time.millisecondsSinceEpoch - firstTime) /
                  timeSpan,
          verticalPadding +
              chartHeight *
                  (1 - (candle.close - minValue) / (maxValue - minValue)),
        ),
    ];

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);

    for (var i = 1; i < points.length; i++) {
      final current = points[i];
      if (isPriceSample &&
          !connectDailyIndexObservations &&
          candles[i].time.difference(candles[i - 1].time) >
              const Duration(hours: 4)) {
        linePath.moveTo(current.dx, current.dy);
      } else {
        linePath.lineTo(current.dx, current.dy);
      }
    }

    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height - verticalPadding)
      ..lineTo(points.first.dx, size.height - verticalPadding)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          palette.primary.withValues(alpha: 0.25),
          palette.primary.withValues(alpha: 0.03),
          Colors.transparent,
        ],
      ).createShader(backgroundRect);

    if (!isPriceSample) canvas.drawPath(fillPath, fillPaint);

    final glowPaint = Paint()
      ..color = palette.primary.withValues(alpha: 0.36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    canvas.drawPath(linePath, glowPaint);

    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          palette.primary,
          palette.secondary,
          palette.text,
          palette.secondary,
        ],
      ).createShader(backgroundRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(linePath, linePaint);

    final pointStep = math.max(1, (points.length / 9).ceil());
    for (var i = 0; i < points.length; i += pointStep) {
      final pulse = math.sin(animationProgress * math.pi * 2 + i) * 0.5 + 0.5;

      final glowPointPaint = Paint()
        ..color = palette.primary.withValues(alpha: 0.28 + pulse * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

      canvas.drawCircle(points[i], 5 + pulse * 3, glowPointPaint);

      canvas.drawCircle(points[i], 2.4, Paint()..color = palette.secondary);
    }

    final scanX = size.width * scanProgress;

    final scanRect = Rect.fromCenter(
      center: Offset(scanX, size.height / 2),
      width: 110,
      height: size.height,
    );

    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          palette.primary.withValues(alpha: 0.06),
          palette.secondary.withValues(alpha: 0.14),
          palette.primary.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(scanRect);

    canvas.drawRect(scanRect, scanPaint);
  }

  @override
  bool shouldRepaint(covariant NeuralChartPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
        oldDelegate.scanProgress != scanProgress ||
        oldDelegate.candles != candles ||
        oldDelegate.isPriceSample != isPriceSample ||
        oldDelegate.connectDailyIndexObservations !=
            connectDailyIndexObservations ||
        oldDelegate.palette != palette;
  }
}

class AiCorePainter extends CustomPainter {
  AiCorePainter({required this.palette, required this.progress});

  final ThemePalette palette;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final maxRadius = math.min(size.width, size.height) * 0.37;

    for (var layer = 0; layer < 3; layer++) {
      final rotation = progress * math.pi * 2 * (layer.isEven ? 1 : -1);

      final radius = maxRadius * (0.55 + layer * 0.17);

      final rect = Rect.fromCircle(center: center, radius: radius);

      final arcPaint = Paint()
        ..color = palette.primary.withValues(alpha: 0.16 + layer * 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 + layer * 0.6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      canvas.drawArc(
        rect,
        rotation,
        math.pi * (0.65 + layer * 0.14),
        false,
        arcPaint,
      );

      canvas.drawArc(
        rect,
        rotation + math.pi,
        math.pi * (0.48 + layer * 0.12),
        false,
        arcPaint,
      );
    }

    for (var i = 0; i < 28; i++) {
      final angle = i * 0.72 + progress * math.pi * 2.5;

      final radius = maxRadius * (0.48 + (i % 7) * 0.065);

      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle * 1.13) * radius * 0.72,
      );

      final particlePaint = Paint()
        ..color = (i % 4 == 0 ? palette.secondary : palette.primary).withValues(
          alpha: 0.20 + (i % 5) * 0.09,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      canvas.drawCircle(point, 1.2 + (i % 3), particlePaint);
    }

    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.32),
          palette.secondary.withValues(alpha: 0.22),
          palette.primary.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius * 0.55));

    canvas.drawCircle(center, maxRadius * 0.55, corePaint);
  }

  @override
  bool shouldRepaint(covariant AiCorePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.palette != palette;
  }
}
