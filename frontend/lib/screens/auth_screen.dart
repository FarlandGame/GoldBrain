import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../animations/auth_intro_animation.dart';
import '../animations/auth_mode_transition.dart';
import '../core/app_sound_service.dart';
import '../core/app_translations.dart';
import '../core/backend_api_client.dart';
import '../core/backend_connection.dart';
import '../core/motion_preferences.dart';
import '../core/settings_store.dart';
import 'dashboard_screen.dart';
import 'selection_screen.dart';

enum _AuthStep { credentials, verification, resetRequest, resetConfirm }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.selectedTheme,
    required this.selectedLanguage,
    this.connection,
  });

  final GoldBrainTheme selectedTheme;
  final GoldBrainLanguage selectedLanguage;
  final BackendConnection? connection;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _panelBoundaryKey = GlobalKey();

  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  bool showLogin = true;
  bool hidePassword = true;
  bool introCompleted = false;
  bool switchingMode = false;
  bool showModeTransition = false;
  bool _authSubmitting = false;
  _AuthStep _step = _AuthStep.credentials;
  String _challengeEmail = '';
  int _resendSeconds = 0;
  int _expirySeconds = 0;
  bool _codeExpired = false;
  Timer? _challengeTimer;

  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _codeError;
  String? _authError;
  String? _authNotice;

  AuthTransitionType transitionType = AuthTransitionType.bullet;

  ui.Image? transitionSnapshot;
  Rect? transitionSnapshotRect;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final nameController = TextEditingController();
  final codeController = TextEditingController();
  DateTime? _lastTypingSoundAt;
  late final BackendConnection _connection;

  @override
  void initState() {
    super.initState();
    _connection = widget.connection ?? BackendConnection.instance;
    passwordController.addListener(_updatePasswordConfirmation);
    confirmPasswordController.addListener(_updatePasswordConfirmation);
    _startAuthMusic();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.045),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (!MotionPreferences.enabled) {
      introCompleted = true;
      _controller.value = 1;
    }
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await _connection.restore();
    if (!mounted ||
        !_connection.session.authenticated ||
        _authSubmitting ||
        _step != _AuthStep.credentials) {
      return;
    }
    await enterDashboard();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if ((MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        !introCompleted) {
      introCompleted = true;
      _controller.value = 1;
    }
  }

  Future<void> _startAuthMusic() async {
    final settings = SettingsStore.instance;
    await settings.load();

    if (!mounted) return;

    await AppSoundService.instance.startMusic(
      track: AppMusicTrack.auth,
      enabled: settings.soundEnabled,
      musicEnabled: settings.musicEnabled,
      volume: settings.interfaceVolume,
    );
  }

  void _playTypingSound() {
    final now = DateTime.now();
    if (_lastTypingSoundAt != null &&
        now.difference(_lastTypingSoundAt!).inMilliseconds < 55) {
      return;
    }

    _lastTypingSoundAt = now;
    final settings = SettingsStore.instance;
    AppSoundService.instance.playTyping(
      enabled: settings.soundEnabled && settings.interfaceSoundsEnabled,
      volume: settings.interfaceVolume,
    );
  }

  void _playModeTransitionSound(AuthTransitionType type) {
    final settings = SettingsStore.instance;
    final enabled = settings.soundEnabled && settings.interfaceSoundsEnabled;

    if (type == AuthTransitionType.bullet) {
      AppSoundService.instance.playSignupTransition(
        enabled: enabled,
        volume: settings.interfaceVolume,
      );
      return;
    }

    AppSoundService.instance.playLoginTransition(
      enabled: enabled,
      volume: settings.interfaceVolume,
    );
  }

  @override
  void dispose() {
    transitionSnapshot?.dispose();
    _controller.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    nameController.dispose();
    codeController.dispose();
    _challengeTimer?.cancel();
    super.dispose();
  }

  ThemePalette get palette => themePalettes[widget.selectedTheme]!;

  bool get isPersian =>
      widget.selectedLanguage == GoldBrainLanguage.persian ||
      widget.selectedLanguage == GoldBrainLanguage.arabic;

  String translatedText({
    required String english,
    required String persian,
    required String japanese,
    required String russian,
  }) {
    switch (widget.selectedLanguage) {
      case GoldBrainLanguage.persian:
        return persian;
      case GoldBrainLanguage.japanese:
        return japanese;
      case GoldBrainLanguage.russian:
        return russian;
      case GoldBrainLanguage.chinese:
        return AppTranslations.simplifiedChinese(english);
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

  Future<void> enterDashboard() async {
    final settings = SettingsStore.instance;
    await AppSoundService.instance.playLogin(
      enabled: settings.soundEnabled && settings.interfaceSoundsEnabled,
      volume: settings.interfaceVolume,
    );

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 900),
        pageBuilder: (_, animation, secondaryAnimation) {
          return DashboardScreen(
            selectedTheme: widget.selectedTheme,
            selectedLanguage: widget.selectedLanguage,
          );
        },
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutExpo,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: ScaleTransition(
              scale: Tween<double>(
                begin: 0.96,
                end: 1,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _authenticate() async {
    if (_step != _AuthStep.credentials) {
      await _submitEmailFlow();
      return;
    }
    if (_authSubmitting || switchingMode || !_validateAuthForm()) return;

    setState(() {
      _authSubmitting = true;
      _authError = null;
      _authNotice = null;
    });

    try {
      final email = emailController.text.trim();
      final challenge = await _connection.signIn(
        email,
        passwordController.text,
        name: showLogin ? null : nameController.text.trim(),
      );
      if (!mounted) return;
      if (challenge != null) {
        _showChallenge(challenge, _AuthStep.verification);
        return;
      }
      if (!mounted || !_connection.session.authenticated) return;
      await enterDashboard();
    } on GoldBrainBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.serverCode == 'email_verification_required' ||
            error.serverCode == 'account_pending_verification' ||
            (!showLogin && error.serverCode == 'email_delivery_failed')) {
          _step = _AuthStep.verification;
          _challengeEmail = emailController.text.trim();
          codeController.clear();
        }
        _authError = _localizedAuthError(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authError = translatedText(
          english: 'Unexpected authentication error. Please try again.',
          persian: 'خطای پیش‌بینی‌نشده در ورود رخ داد. دوباره تلاش کنید.',
          japanese: '認証中に予期しないエラーが発生しました。',
          russian: 'Непредвиденная ошибка входа. Повторите попытку.',
        );
      });
    } finally {
      if (mounted) setState(() => _authSubmitting = false);
    }
  }

  void _showChallenge(BackendEmailChallenge challenge, _AuthStep step) {
    _challengeTimer?.cancel();
    setState(() {
      _step = step;
      _challengeEmail = challenge.email;
      _expirySeconds = challenge.expiresInSeconds;
      _codeExpired = false;
      _resendSeconds = challenge.resendAfterSeconds;
      codeController.clear();
      if (step != _AuthStep.verification) {
        passwordController.clear();
        confirmPasswordController.clear();
      }
      _codeError = null;
      _passwordError = null;
      _confirmPasswordError =
          step == _AuthStep.verification &&
              confirmPasswordController.text.isNotEmpty
          ? _passwordConfirmationError()
          : null;
      _authError = null;
      _authNotice = translatedText(
        english: step == _AuthStep.verification
            ? 'Check your email for the verification code.'
            : 'If this account is available, a reset code has been emailed.',
        persian: step == _AuthStep.verification
            ? 'کد تأیید ارسال شد؛ ایمیل خود را بررسی کنید.'
            : 'اگر این حساب در دسترس باشد، کد بازیابی به ایمیل آن ارسال می‌شود.',
        japanese: 'メールの確認コードを確認してください。',
        russian: 'Проверьте код подтверждения в электронной почте.',
      );
    });
    _startChallengeTimer();
  }

  void _startChallengeTimer() {
    _challengeTimer?.cancel();
    var previousTick = 0;
    _challengeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      // Missed callbacks (for example while Windows is busy) still count.
      final elapsedSeconds = timer.tick - previousTick;
      previousTick = timer.tick;
      setState(() {
        _resendSeconds = elapsedSeconds >= _resendSeconds
            ? 0
            : _resendSeconds - elapsedSeconds;
        if (_expirySeconds > 0) {
          _expirySeconds = elapsedSeconds >= _expirySeconds
              ? 0
              : _expirySeconds - elapsedSeconds;
          if (_expirySeconds == 0) _codeExpired = true;
        }
      });
      if (_resendSeconds == 0 && _expirySeconds == 0) timer.cancel();
    });
  }

  void _cancelEmailFlow() {
    _challengeTimer?.cancel();
    setState(() {
      _step = _AuthStep.credentials;
      showLogin = true;
      _challengeEmail = '';
      _resendSeconds = 0;
      _expirySeconds = 0;
      _codeExpired = false;
      codeController.clear();
      passwordController.clear();
      confirmPasswordController.clear();
      _codeError = null;
      _nameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
      _authError = null;
      _authNotice = null;
    });
  }

  Future<void> _submitEmailFlow({bool resend = false}) async {
    if (_authSubmitting || switchingMode || (resend && _resendSeconds > 0)) {
      return;
    }
    final requesting = resend || _step == _AuthStep.resetRequest;
    if (!requesting && _codeExpired) return;
    final code = codeController.text.trim().replaceAllMapped(
      RegExp('[۰-۹٠-٩]'),
      (match) {
        final digit = match[0]!.codeUnitAt(0);
        return '${digit >= 0x06f0 ? digit - 0x06f0 : digit - 0x0660}';
      },
    );
    final email = requesting && _step == _AuthStep.resetRequest
        ? emailController.text.trim()
        : _challengeEmail;
    final validEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    setState(() {
      _emailError = !validEmail
          ? translatedText(
              english: 'Enter a valid email address.',
              persian: 'یک ایمیل معتبر وارد کنید.',
              japanese: '有効なメールアドレスを入力してください。',
              russian: 'Введите корректный адрес электронной почты.',
            )
          : null;
      _codeError = !requesting && !RegExp(r'^\d{6}$').hasMatch(code)
          ? translatedText(
              english: 'Enter the six-digit code from your email.',
              persian: 'کد شش‌رقمی ایمیل را وارد کنید.',
              japanese: 'メールの6桁のコードを入力してください。',
              russian: 'Введите шестизначный код из письма.',
            )
          : null;
      final password = passwordController.text;
      _passwordError =
          !requesting &&
              (password.length < 10 ||
                  password.length > 128 ||
                  !RegExp(r'\p{L}', unicode: true).hasMatch(password) ||
                  !RegExp(r'\p{Nd}', unicode: true).hasMatch(password))
          ? translatedText(
              english: 'Use 10–128 characters with a letter and a number.',
              persian: 'رمز باید ۱۰ تا ۱۲۸ نویسه و شامل حرف و عدد باشد.',
              japanese: '英字と数字を含む10～128文字を使用してください。',
              russian: 'Используйте 10–128 символов, включая букву и цифру.',
            )
          : null;
      _confirmPasswordError = requesting ? null : _passwordConfirmationError();
      _authError = null;
    });
    if (_emailError != null ||
        _codeError != null ||
        _passwordError != null ||
        _confirmPasswordError != null) {
      return;
    }
    setState(() => _authSubmitting = true);
    try {
      if (requesting) {
        final verification = _step == _AuthStep.verification;
        final challenge = verification
            ? await _connection.api.requestEmailVerification(email)
            : await _connection.api.requestPasswordReset(email);
        if (!mounted) return;
        _showChallenge(
          challenge,
          verification ? _AuthStep.verification : _AuthStep.resetConfirm,
        );
      } else if (_step == _AuthStep.verification) {
        await _connection.verifyEmail(email, code, passwordController.text);
        if (!mounted || !_connection.session.authenticated) return;
        _challengeTimer?.cancel();
        codeController.clear();
        passwordController.clear();
        confirmPasswordController.clear();
        await enterDashboard();
      } else {
        await _connection.resetPassword(email, code, passwordController.text);
        if (!mounted) return;
        _cancelEmailFlow();
        setState(() {
          _authNotice = translatedText(
            english: 'Password updated. Sign in with your new password.',
            persian: 'رمز تغییر کرد. با رمز جدید وارد شوید.',
            japanese: 'パスワードを変更しました。新しいパスワードでログインしてください。',
            russian: 'Пароль изменён. Войдите с новым паролем.',
          );
        });
      }
    } on GoldBrainBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.serverCode == 'otp_expired' ||
            error.serverCode == 'otp_attempts_exceeded') {
          _expirySeconds = 0;
          _codeExpired = true;
        }
        if (error.retryAfterSeconds != null) {
          _resendSeconds = error.retryAfterSeconds!;
        }
        _authError = _localizedAuthError(error);
        _authNotice = null;
      });
      if (error.retryAfterSeconds != null) _startChallengeTimer();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _authError = translatedText(
          english: 'Could not complete this request. Please try again.',
          persian: 'درخواست کامل نشد. دوباره تلاش کنید.',
          japanese: 'リクエストを完了できませんでした。再試行してください。',
          russian: 'Не удалось выполнить запрос. Повторите попытку.',
        ),
      );
    } finally {
      if (mounted) setState(() => _authSubmitting = false);
    }
  }

  bool get _passwordsMatch =>
      passwordController.text == confirmPasswordController.text;

  bool get _needsPasswordConfirmation =>
      (_step == _AuthStep.credentials && !showLogin) ||
      _step == _AuthStep.verification ||
      _step == _AuthStep.resetConfirm;

  String? _passwordConfirmationError() {
    if (confirmPasswordController.text.isEmpty) {
      return translatedText(
        english: 'Please re-enter your password.',
        persian: 'رمز عبور را دوباره وارد کنید.',
        japanese: 'パスワードをもう一度入力してください。',
        russian: 'Введите пароль ещё раз.',
      );
    }
    if (!_passwordsMatch) {
      return translatedText(
        english: 'Passwords do not match.',
        persian: 'رمز عبور و تکرار آن یکسان نیستند.',
        japanese: 'パスワードが一致しません。',
        russian: 'Пароли не совпадают.',
      );
    }
    return null;
  }

  void _updatePasswordConfirmation() {
    if (!mounted) return;
    setState(() {
      _confirmPasswordError =
          _needsPasswordConfirmation &&
              (confirmPasswordController.text.isNotEmpty ||
                  _confirmPasswordError != null)
          ? _passwordConfirmationError()
          : null;
    });
  }

  bool _validateAuthForm() {
    final email = emailController.text.trim();
    final password = passwordController.text;
    final name = nameController.text.trim();
    final validEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

    setState(() {
      _nameError = !showLogin && (name.isEmpty || name.length > 100)
          ? translatedText(
              english: 'Enter your full name.',
              persian: 'نام و نام خانوادگی را وارد کنید.',
              japanese: '氏名を入力してください。',
              russian: 'Введите имя и фамилию.',
            )
          : null;
      _emailError = !validEmail
          ? translatedText(
              english: 'Enter a valid email address.',
              persian: 'یک ایمیل معتبر وارد کنید.',
              japanese: '有効なメールアドレスを入力してください。',
              russian: 'Введите корректный адрес электронной почты.',
            )
          : null;
      _passwordError = showLogin
          ? (password.isEmpty
                ? translatedText(
                    english: 'Enter your password.',
                    persian: 'رمز عبور را وارد کنید.',
                    japanese: 'パスワードを入力してください。',
                    russian: 'Введите пароль.',
                  )
                : null)
          : (password.length < 10 ||
                password.length > 128 ||
                !RegExp(r'\p{L}', unicode: true).hasMatch(password) ||
                !RegExp(r'\p{Nd}', unicode: true).hasMatch(password))
          ? translatedText(
              english: 'Use 10–128 characters with a letter and a number.',
              persian: 'رمز باید ۱۰ تا ۱۲۸ نویسه و شامل حرف و عدد باشد.',
              japanese: '英字と数字を含む10～128文字を使用してください。',
              russian: 'Используйте 10–128 символов, включая букву и цифру.',
            )
          : null;
      _authError = null;
      _authNotice = null;
      _confirmPasswordError = showLogin ? null : _passwordConfirmationError();
    });
    return _nameError == null &&
        _emailError == null &&
        _passwordError == null &&
        _confirmPasswordError == null;
  }

  String _localizedAuthError(GoldBrainBackendException error) {
    switch (error.serverCode) {
      case 'email_delivery_failed':
        return translatedText(
          english:
              'The email could not be sent. Please try sending the code again.',
          persian: 'ایمیل ارسال نشد. ارسال کد را دوباره امتحان کنید.',
          japanese: 'メールを送信できませんでした。コードを再送してください。',
          russian: 'Не удалось отправить письмо. Повторите отправку кода.',
        );
      case 'email_verification_required':
      case 'account_pending_verification':
        return translatedText(
          english:
              'Verify your email before signing in. Enter your code or request a new one.',
          persian:
              'ابتدا ایمیل را تأیید کنید. کد را وارد کنید یا کد جدید بخواهید.',
          japanese: 'ログイン前にメールを確認してください。コードを入力または再送してください。',
          russian:
              'Подтвердите почту перед входом. Введите код или запросите новый.',
        );
      case 'otp_expired':
        return translatedText(
          english: 'This code has expired. Request a new code.',
          persian: 'این کد منقضی شده است. کد جدید درخواست کنید.',
          japanese: 'コードの有効期限が切れました。新しいコードをリクエストしてください。',
          russian: 'Срок действия кода истёк. Запросите новый код.',
        );
      case 'otp_invalid':
        return translatedText(
          english:
              'The code is incorrect or no longer valid. Check it or request a new one.',
          persian:
              'کد نادرست یا بی‌اعتبار است. آن را بررسی یا کد جدید درخواست کنید.',
          japanese: 'コードが正しくないか無効です。確認または再送してください。',
          russian:
              'Код неверен или недействителен. Проверьте или запросите новый.',
        );
      case 'otp_attempts_exceeded':
        return translatedText(
          english:
              'Too many incorrect codes. Request a new code after the cooldown.',
          persian:
              'کدهای نادرست بیش از حد مجاز بود. پس از زمان انتظار کد جدید بخواهید.',
          japanese: '誤ったコードが多すぎます。しばらくして再送してください。',
          russian: 'Слишком много неверных кодов. Подождите и запросите новый.',
        );
      case 'account_exists':
        return translatedText(
          english:
              'An account already exists with this email. Sign in instead.',
          persian: 'این ایمیل قبلاً ثبت شده است. از بخش ورود استفاده کنید.',
          japanese: 'このメールアドレスは登録済みです。ログインしてください。',
          russian: 'Эта почта уже зарегистрирована. Войдите в аккаунт.',
        );
    }
    switch (error.code) {
      case 'invalid_configuration':
        return translatedText(
          english: 'The GoldBrain server address is not configured correctly.',
          persian: 'آدرس سرور GoldBrain درست تنظیم نشده است.',
          japanese: 'GoldBrainサーバーのアドレスが正しく設定されていません。',
          russian: 'Адрес сервера GoldBrain настроен неверно.',
        );
      case 'http_401':
      case 'http_403':
        return translatedText(
          english:
              'Email or password is incorrect, or the account is unavailable.',
          persian: 'ایمیل یا رمز عبور نادرست است، یا حساب در دسترس نیست.',
          japanese: 'メールまたはパスワードが違うか、アカウントが利用できません。',
          russian: 'Неверная почта/пароль или аккаунт недоступен.',
        );
      case 'http_429':
        return translatedText(
          english: 'Too many attempts. Please wait and try again.',
          persian: 'تلاش‌ها بیش از حد مجاز است. کمی صبر و دوباره تلاش کنید.',
          japanese: '試行回数が多すぎます。しばらくして再試行してください。',
          russian: 'Слишком много попыток. Подождите и повторите.',
        );
      case 'network_error':
      case 'timeout':
        return translatedText(
          english:
              'Could not reach the login service. Check the network and try again.',
          persian:
              'اتصال به سرویس ورود ممکن نشد. اینترنت را بررسی و دوباره تلاش کنید.',
          japanese: 'ログインサービスに接続できません。ネットワークを確認してください。',
          russian: 'Не удалось подключиться к сервису входа. Проверьте сеть.',
        );
      case 'http_409':
        return translatedText(
          english:
              'An account already exists with this email. Sign in instead.',
          persian: 'این ایمیل قبلاً ثبت شده است. از بخش ورود استفاده کنید.',
          japanese: 'このメールアドレスは登録済みです。ログインしてください。',
          russian: 'Эта почта уже зарегистрирована. Войдите в аккаунт.',
        );
      case 'http_400':
      case 'http_422':
        return translatedText(
          english:
              'Check your account details. The server could not accept them.',
          persian: 'اطلاعات حساب را بررسی کنید؛ سرور آن‌ها را نپذیرفت.',
          japanese: '入力内容を確認してください。サーバーが受け付けませんでした。',
          russian: 'Проверьте данные аккаунта: сервер не принял их.',
        );
      case 'secure_storage':
        return translatedText(
          english: 'Secure sign-in storage is unavailable. Please try again.',
          persian: 'ذخیره امن نشست در دسترس نیست. دوباره تلاش کنید.',
          japanese: '安全なログインストレージが利用できません。再試行してください。',
          russian: 'Защищённое хранилище недоступно. Повторите попытку.',
        );
      default:
        return translatedText(
          english: 'Authentication failed: ${error.message}',
          persian: 'احراز هویت ناموفق بود: ${error.message}',
          japanese: '認証に失敗しました: ${error.message}',
          russian: 'Ошибка аутентификации: ${error.message}',
        );
    }
  }

  Future<void> startModeTransition() async {
    if (switchingMode) return;

    setState(() {
      switchingMode = true;
      confirmPasswordController.clear();
      _nameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
      _authError = null;
      _authNotice = null;
    });

    _playModeTransitionSound(
      showLogin ? AuthTransitionType.bullet : AuthTransitionType.pencil,
    );

    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        _panelBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;

    if (boundary == null || !boundary.hasSize) {
      if (mounted) {
        setState(() {
          switchingMode = false;
        });
      }
      return;
    }

    final image = await boundary.toImage(pixelRatio: 1.35);

    if (!mounted) {
      image.dispose();
      return;
    }

    final box = boundary as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);

    transitionSnapshot?.dispose();

    setState(() {
      transitionSnapshot = image;
      transitionSnapshotRect = topLeft & box.size;
      transitionType = showLogin
          ? AuthTransitionType.bullet
          : AuthTransitionType.pencil;
      showModeTransition = true;
    });
  }

  void switchModeAtMidpoint() {
    if (!mounted) return;

    setState(() {
      showLogin = !showLogin;
    });

    _controller.forward(from: 0);
  }

  void finishModeTransition() {
    if (!mounted) return;

    setState(() {
      showModeTransition = false;
      switchingMode = false;
    });

    transitionSnapshot?.dispose();
    transitionSnapshot = null;
    transitionSnapshotRect = null;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: palette.background,
        body: Stack(
          children: [
            if (introCompleted) ...[
              Positioned(
                top: -180,
                right: -140,
                child: _GlowOrb(color: palette.primary, size: 460),
              ),
              Positioned(
                bottom: -220,
                left: -160,
                child: _GlowOrb(color: palette.secondary, size: 520),
              ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: RepaintBoundary(
                          key: _panelBoundaryKey,
                          child: _buildAuthPanel(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (!introCompleted)
              Positioned.fill(
                child: AuthIntroAnimation(
                  accentColor: palette.primary,
                  onCompleted: () {
                    if (!mounted) return;

                    setState(() {
                      introCompleted = true;
                    });

                    _controller.forward(from: 0);
                  },
                ),
              ),
            if (showModeTransition &&
                transitionSnapshot != null &&
                transitionSnapshotRect != null)
              Positioned.fill(
                child: AuthModeTransition(
                  type: transitionType,
                  accentColor: palette.primary,
                  snapshot: transitionSnapshot!,
                  snapshotRect: transitionSnapshotRect!,
                  onMidpoint: switchModeAtMidpoint,
                  onCompleted: finishModeTransition,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthPanel() {
    final compact = MediaQuery.sizeOf(context).width < 820;
    return AnimatedContainer(
      duration: MotionPreferences.duration(450),
      curve: Curves.easeOutCubic,
      width: compact ? double.infinity : 1050,
      constraints: BoxConstraints(
        minHeight: compact ? 0 : (showLogin ? 620 : 690),
      ),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: palette.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.13),
            blurRadius: 70,
            spreadRadius: 4,
          ),
          const BoxShadow(
            color: Colors.black54,
            blurRadius: 45,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 22),
                  child: _buildForm(),
                ),
                SizedBox(height: 350, child: _buildVisualPanel()),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: _buildForm(),
                  ),
                ),
                Expanded(child: _buildVisualPanel()),
              ],
            ),
    );
  }

  Widget _buildForm() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.03, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _step != _AuthStep.credentials
          ? _buildEmailForm()
          : Column(
              key: ValueKey(showLogin),
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GOLDBRAIN',
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  showLogin
                      ? translatedText(
                          english: 'Welcome back',
                          persian: 'خوش آمدید',
                          japanese: 'おかえりなさい',
                          russian: 'С возвращением',
                        )
                      : translatedText(
                          english: 'Create your account',
                          persian: 'حساب خود را بسازید',
                          japanese: 'アカウントを作成',
                          russian: 'Создайте аккаунт',
                        ),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  translatedText(
                    english: 'Enter the GoldBrain intelligence network.',
                    persian: 'وارد شبکه هوشمند GoldBrain شوید.',
                    japanese: 'GoldBrainインテリジェンスネットワークへ。',
                    russian: 'Войдите в интеллектуальную сеть GoldBrain.',
                  ),
                  style: TextStyle(color: palette.mutedText, fontSize: 14),
                ),
                const SizedBox(height: 34),
                if (!showLogin) ...[
                  _AuthField(
                    key: const Key('auth-name'),
                    controller: nameController,
                    hint: translatedText(
                      english: 'Full name',
                      persian: 'نام و نام خانوادگی',
                      japanese: '氏名',
                      russian: 'Имя и фамилия',
                    ),
                    icon: Icons.person_outline_rounded,
                    palette: palette,
                    onChangedSound: _playTypingSound,
                    errorText: _nameError,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                  ),
                  const SizedBox(height: 16),
                ],
                _AuthField(
                  key: const Key('auth-email'),
                  controller: emailController,
                  hint: translatedText(
                    english: 'Email address',
                    persian: 'آدرس ایمیل',
                    japanese: 'メールアドレス',
                    russian: 'Электронная почта',
                  ),
                  icon: Icons.alternate_email_rounded,
                  palette: palette,
                  onChangedSound: _playTypingSound,
                  errorText: _emailError,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 16),
                _buildPasswordFields(emailFlow: false),
                if (showLogin)
                  TextButton(
                    key: const Key('auth-forgot-password'),
                    onPressed: switchingMode || _authSubmitting
                        ? null
                        : () {
                            setState(() {
                              _step = _AuthStep.resetRequest;
                              passwordController.clear();
                              confirmPasswordController.clear();
                              _emailError = null;
                              _passwordError = null;
                              _confirmPasswordError = null;
                              _authError = null;
                              _authNotice = null;
                            });
                          },
                    child: Text(
                      translatedText(
                        english: 'Forgot password?',
                        persian: 'رمز عبور را فراموش کرده‌اید؟',
                        japanese: 'パスワードをお忘れですか？',
                        russian: 'Забыли пароль?',
                      ),
                      style: TextStyle(
                        color: palette.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_authError != null || _authNotice != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          (_authError != null
                                  ? const Color(0xFFFF7182)
                                  : const Color(0xFF54E69A))
                              .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            (_authError != null
                                    ? const Color(0xFFFF7182)
                                    : const Color(0xFF54E69A))
                                .withValues(alpha: 0.30),
                      ),
                    ),
                    child: Text(
                      _authError ?? _authNotice!,
                      style: TextStyle(
                        color: _authError != null
                            ? const Color(0xFFFF9AA6)
                            : const Color(0xFF75EDB1),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: FilledButton(
                    key: const Key('auth-submit'),
                    onPressed:
                        switchingMode ||
                            _authSubmitting ||
                            (_needsPasswordConfirmation && !_passwordsMatch)
                        ? null
                        : _authenticate,
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.primary,
                      disabledBackgroundColor: palette.primary.withValues(
                        alpha: 0.42,
                      ),
                      foregroundColor: palette.isLight
                          ? Colors.white
                          : Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _authSubmitting
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: palette.isLight
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          )
                        : Text(
                            showLogin
                                ? translatedText(
                                    english: 'ENTER GOLDBRAIN',
                                    persian: 'ورود به GOLDBRAIN',
                                    japanese: 'GOLDBRAINへログイン',
                                    russian: 'ВОЙТИ В GOLDBRAIN',
                                  )
                                : translatedText(
                                    english: 'CREATE ACCOUNT',
                                    persian: 'ساخت حساب',
                                    japanese: 'アカウントを作成',
                                    russian: 'СОЗДАТЬ АККАУНТ',
                                  ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: switchingMode || _authSubmitting
                        ? null
                        : enterDashboard,
                    icon: Icon(
                      Icons.person_outline_rounded,
                      size: 17,
                      color: palette.mutedText,
                    ),
                    label: Text(
                      translatedText(
                        english: 'Continue as guest (local only)',
                        persian: 'ادامه به‌عنوان مهمان (فقط محلی)',
                        japanese: 'ゲストとして続行（ローカルのみ）',
                        russian: 'Продолжить как гость (локально)',
                      ),
                      style: TextStyle(
                        color: palette.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Center(
                  child: TextButton(
                    key: const Key('auth-switch-mode'),
                    onPressed: switchingMode || _authSubmitting
                        ? null
                        : startModeTransition,
                    child: Text(
                      showLogin
                          ? translatedText(
                              english: 'No account? Create one',
                              persian: 'حساب ندارید؟ ثبت‌نام کنید',
                              japanese: 'アカウントを作成',
                              russian: 'Нет аккаунта? Создать',
                            )
                          : translatedText(
                              english: 'Already registered? Sign in',
                              persian: 'قبلاً ثبت‌نام کرده‌اید؟ وارد شوید',
                              japanese: 'すでに登録済みですか？',
                              russian: 'Уже зарегистрированы? Войти',
                            ),
                      style: TextStyle(
                        color: palette.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPasswordFields({required bool emailFlow}) {
    final confirming = emailFlow || !showLogin;
    final passwordField = _AuthField(
      key: Key(emailFlow ? 'auth-new-password' : 'auth-password'),
      controller: passwordController,
      hint: translatedText(
        english: emailFlow ? 'New password' : 'Password',
        persian: emailFlow ? 'رمز عبور جدید' : 'رمز عبور',
        japanese: emailFlow ? '新しいパスワード' : 'パスワード',
        russian: emailFlow ? 'Новый пароль' : 'Пароль',
      ),
      icon: Icons.lock_outline_rounded,
      palette: palette,
      onChangedSound: _playTypingSound,
      errorText: _passwordError,
      textInputAction: confirming ? TextInputAction.next : TextInputAction.done,
      autofillHints: [
        confirming ? AutofillHints.newPassword : AutofillHints.password,
      ],
      onSubmitted: confirming ? null : (_) => _authenticate(),
      obscureText: hidePassword,
      suffixIcon: IconButton(
        onPressed: () => setState(() => hidePassword = !hidePassword),
        icon: Icon(
          hidePassword
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          color: palette.mutedText,
        ),
      ),
    );
    if (!confirming) return passwordField;
    final confirmationField = _AuthField(
      key: Key(
        emailFlow ? 'auth-new-password-confirm' : 'auth-password-confirm',
      ),
      controller: confirmPasswordController,
      hint: translatedText(
        english: 'Confirm password',
        persian: 'تکرار رمز عبور',
        japanese: 'パスワードを確認',
        russian: 'Повторите пароль',
      ),
      icon: Icons.lock_outline_rounded,
      palette: palette,
      onChangedSound: _playTypingSound,
      errorText: _confirmPasswordError,
      obscureText: hidePassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newPassword],
      onSubmitted: (_) => emailFlow ? _submitEmailFlow() : _authenticate(),
    );
    return LayoutBuilder(
      builder: (_, constraints) => constraints.maxWidth >= 420
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: passwordField),
                const SizedBox(width: 16),
                Expanded(child: confirmationField),
              ],
            )
          : Column(
              children: [
                passwordField,
                const SizedBox(height: 16),
                confirmationField,
              ],
            ),
    );
  }

  Widget _buildEmailForm() {
    final verification = _step == _AuthStep.verification;
    final requesting = _step == _AuthStep.resetRequest;
    final codeTime =
        '${(_expirySeconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(_expirySeconds % 60).toString().padLeft(2, '0')}';
    return Column(
      key: ValueKey(_step),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GOLDBRAIN',
          style: TextStyle(
            color: palette.primary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          translatedText(
            english: verification ? 'Verify your email' : 'Reset your password',
            persian: verification ? 'تأیید ایمیل' : 'بازیابی رمز عبور',
            japanese: verification ? 'メールを確認' : 'パスワードを再設定',
            russian: verification ? 'Подтвердите почту' : 'Сброс пароля',
          ),
          style: TextStyle(
            color: palette.text,
            fontSize: 34,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          translatedText(
            english: requesting
                ? 'Enter your account email to request a reset code.'
                : 'Enter the six-digit email code and choose your password.',
            persian: requesting
                ? 'برای دریافت کد بازیابی، ایمیل حساب را وارد کنید.'
                : 'کد شش‌رقمی ایمیل را وارد و رمز عبور خود را تعیین کنید.',
            japanese: 'メールの6桁のコードを入力し、パスワードを設定してください。',
            russian: 'Введите шестизначный код из письма и задайте пароль.',
          ),
          style: TextStyle(color: palette.mutedText, fontSize: 14),
        ),
        if (!requesting) ...[
          const SizedBox(height: 10),
          Text(
            _challengeEmail,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            key: const Key('auth-email-spam-note'),
            translatedText(
              english:
                  "Check your Spam/Junk folder if you don't see the email within a minute.",
              persian:
                  'اگر تا یک دقیقه ایمیل را ندیدید، پوشهٔ Spam/Junk (هرزنامه) را بررسی کنید.',
              japanese: '1分以内にメールが届かない場合は、迷惑メールフォルダを確認してください。',
              russian:
                  'Если письмо не пришло в течение минуты, проверьте папку «Спам».',
            ),
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 34),
        if (requesting)
          _AuthField(
            key: const Key('auth-reset-email'),
            controller: emailController,
            hint: translatedText(
              english: 'Email address',
              persian: 'آدرس ایمیل',
              japanese: 'メールアドレス',
              russian: 'Электронная почта',
            ),
            icon: Icons.alternate_email_rounded,
            palette: palette,
            errorText: _emailError,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onChangedSound: _playTypingSound,
            onSubmitted: (_) => _submitEmailFlow(),
          )
        else ...[
          _AuthField(
            key: const Key('auth-email-code'),
            controller: codeController,
            hint: translatedText(
              english: 'Verification code',
              persian: 'کد تأیید',
              japanese: '確認コード',
              russian: 'Код подтверждения',
            ),
            icon: Icons.mark_email_read_outlined,
            palette: palette,
            errorText: _codeError,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.oneTimeCode],
            onChangedSound: _playTypingSound,
          ),
          const SizedBox(height: 16),
          _buildPasswordFields(emailFlow: true),
          const SizedBox(height: 16),
          Text(
            _codeExpired
                ? translatedText(
                    english: 'Code expired. Request a new code below.',
                    persian: 'کد منقضی شد. از پایین کد جدید بخواهید.',
                    japanese: 'コードの期限が切れました。再送してください。',
                    russian: 'Код истёк. Запросите новый ниже.',
                  )
                : _expirySeconds > 0
                ? translatedText(
                    english: 'Code validity (minutes:seconds): $codeTime.',
                    persian: 'اعتبار کد (دقیقه:ثانیه): $codeTime.',
                    japanese: 'コードの有効期間（分:秒）: $codeTime。',
                    russian: 'Код действует (минуты:секунды): $codeTime.',
                  )
                : translatedText(
                    english: 'Have no valid code? Request a new one below.',
                    persian: 'کد معتبر ندارید؟ از پایین کد جدید بخواهید.',
                    japanese: '有効なコードがない場合は再送してください。',
                    russian: 'Нет действующего кода? Запросите новый ниже.',
                  ),
            key: const Key('auth-code-validity'),
            style: TextStyle(color: palette.mutedText, fontSize: 12),
          ),
        ],
        if (_authError != null || _authNotice != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  (_authError != null
                          ? const Color(0xFFFF7182)
                          : const Color(0xFF54E69A))
                      .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    (_authError != null
                            ? const Color(0xFFFF7182)
                            : const Color(0xFF54E69A))
                        .withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              _authError ?? _authNotice!,
              style: TextStyle(
                color: _authError != null
                    ? const Color(0xFFFF9AA6)
                    : const Color(0xFF75EDB1),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: FilledButton(
            key: const Key('auth-email-submit'),
            onPressed:
                _authSubmitting ||
                    _codeExpired ||
                    (_needsPasswordConfirmation && !_passwordsMatch)
                ? null
                : () => _submitEmailFlow(),
            style: FilledButton.styleFrom(
              backgroundColor: palette.primary,
              disabledBackgroundColor: palette.primary.withValues(alpha: 0.42),
              foregroundColor: palette.isLight ? Colors.white : Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: _authSubmitting
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: palette.isLight ? Colors.white : Colors.black,
                    ),
                  )
                : Text(
                    translatedText(
                      english: requesting
                          ? 'SEND RESET CODE'
                          : verification
                          ? 'VERIFY EMAIL'
                          : 'UPDATE PASSWORD',
                      persian: requesting
                          ? 'ارسال کد بازیابی'
                          : verification
                          ? 'تأیید ایمیل'
                          : 'تغییر رمز عبور',
                      japanese: requesting ? 'コードを送信' : '確認',
                      russian: requesting ? 'ОТПРАВИТЬ КОД' : 'ПОДТВЕРДИТЬ',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
          ),
        ),
        if (!requesting)
          Center(
            child: TextButton(
              key: const Key('auth-resend-code'),
              onPressed: _authSubmitting || _resendSeconds > 0
                  ? null
                  : () => _submitEmailFlow(resend: true),
              child: Text(
                translatedText(
                  english: _resendSeconds > 0
                      ? 'Resend code in $_resendSeconds seconds'
                      : 'Resend code',
                  persian: _resendSeconds > 0
                      ? 'ارسال مجدد پس از $_resendSeconds ثانیه'
                      : 'ارسال مجدد کد',
                  japanese: _resendSeconds > 0
                      ? '$_resendSeconds 秒後に再送'
                      : 'コードを再送',
                  russian: _resendSeconds > 0
                      ? 'Повторить через $_resendSeconds сек.'
                      : 'Отправить код снова',
                ),
                style: TextStyle(
                  color: palette.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        Center(
          child: TextButton(
            key: const Key('auth-back-to-login'),
            onPressed: _authSubmitting ? null : _cancelEmailFlow,
            child: Text(
              translatedText(
                english: 'Back to sign in',
                persian: 'بازگشت به ورود',
                japanese: 'ログインに戻る',
                russian: 'Назад ко входу',
              ),
              style: TextStyle(
                color: palette.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVisualPanel() {
    return Container(
      margin: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.primary.withValues(alpha: 0.24),
            palette.background,
            palette.secondary.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: palette.primary.withValues(alpha: 0.20)),
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: palette.primary.withValues(alpha: 0.42),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.20),
                    blurRadius: 55,
                    spreadRadius: 15,
                  ),
                ],
              ),
              child: Icon(
                Icons.psychology_alt_rounded,
                color: palette.secondary,
                size: 105,
              ),
            ),
          ),
          Positioned(
            left: 34,
            right: 34,
            bottom: 38,
            child: Column(
              children: [
                Text(
                  translatedText(
                    english: 'YOUR INTELLIGENCE. AMPLIFIED.',
                    persian: 'هوش شما، تقویت‌شده.',
                    japanese: '知性を、さらに強く。',
                    russian: 'ВАШ ИНТЕЛЛЕКТ. УСИЛЕН.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  translatedText(
                    english:
                        'Markets, news and artificial intelligence in one neural command center.',
                    persian:
                        'بازار، اخبار و هوش مصنوعی در یک مرکز فرماندهی عصبی.',
                    japanese: '市場、ニュース、AIをひとつのニューラルセンターに。',
                    russian:
                        'Рынки, новости и ИИ в едином интеллектуальном центре.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.mutedText, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.palette,
    this.obscureText = false,
    this.suffixIcon,
    this.onChangedSound,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ThemePalette palette;
  final bool obscureText;
  final Widget? suffixIcon;
  final VoidCallback? onChangedSound;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      autocorrect: false,
      enableSuggestions: !obscureText,
      onChanged: (_) => onChangedSound?.call(),
      style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        errorMaxLines: 3,
        hintStyle: TextStyle(color: palette.mutedText),
        prefixIcon: Icon(icon, color: palette.primary),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: palette.background.withValues(alpha: 0.62),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(
            color: palette.primary.withValues(alpha: 0.16),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: BorderSide(color: palette.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.17), Colors.transparent],
          ),
        ),
      ),
    );
  }
}
