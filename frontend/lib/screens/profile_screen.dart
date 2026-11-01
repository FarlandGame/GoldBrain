import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import '../core/app_translations.dart';
import '../core/backend_connection.dart';
import '../core/notification_service.dart';
import '../core/settings_store.dart';
import '../core/local_persistence_policy.dart';
import '../core/managed_app_file_store.dart';

import '../core/profile_store.dart';
import 'auth_screen.dart';
import 'selection_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.palette,
    required this.selectedLanguage,
    this.onProfileChanged,
    this.connection,
  });

  final ThemePalette palette;
  final GoldBrainLanguage selectedLanguage;
  final VoidCallback? onProfileChanged;
  final BackendConnection? connection;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileStore _profileStore = ProfileStore.instance;

  final NotificationService _notificationService = NotificationService.instance;
  final SettingsStore _settingsStore = SettingsStore.instance;

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  bool _loading = true;
  bool _saving = false;
  bool _selectingImage = false;
  bool _signingOut = false;
  Timer? _autoSaveTimer;
  BackendConnection get _connection =>
      widget.connection ?? BackendConnection.instance;

  ThemePalette get palette => widget.palette;

  bool get isPersian =>
      widget.selectedLanguage == GoldBrainLanguage.persian ||
      widget.selectedLanguage == GoldBrainLanguage.arabic;

  String tr({
    required String en,
    required String fa,
    required String ja,
    required String ru,
  }) {
    switch (widget.selectedLanguage) {
      case GoldBrainLanguage.persian:
        return fa;
      case GoldBrainLanguage.japanese:
        return ja;
      case GoldBrainLanguage.russian:
        return ru;
      case GoldBrainLanguage.chinese:
        return AppTranslations.simplifiedChinese(en);
      case GoldBrainLanguage.arabic:
        return AppTranslations.arabic(en);
      case GoldBrainLanguage.turkish:
        return AppTranslations.turkish(en);
      case GoldBrainLanguage.french:
        return AppTranslations.french(en);
      case GoldBrainLanguage.english:
        return en;
    }
  }

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();

    _loadProfile();
  }

  Future<void> _loadProfile() async {
    await Future.wait([_profileStore.load(), _settingsStore.load()]);
    try {
      await _connection.refreshProfile();
    } catch (_) {
      // Keep the last authenticated identity if an account refresh is offline.
      // The transport still expires credentials rejected by the server.
    }

    if (!mounted) return;

    _nameController.text = _profileStore.name;
    _emailController.text = _profileStore.email;
    _phoneController.text = _profileStore.phone;

    setState(() {
      _loading = false;
    });
  }

  Future<void> _signOut() async {
    if (_signingOut || _saving) return;
    _autoSaveTimer?.cancel();
    setState(() => _signingOut = true);
    try {
      await _connection.signOut();
      if (!mounted) return;
      final theme = GoldBrainTheme.values.firstWhere(
        (value) => value.name == _settingsStore.themeCode,
        orElse: () => GoldBrainTheme.gold,
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => AuthScreen(
            selectedTheme: theme,
            selectedLanguage: widget.selectedLanguage,
            connection: _connection,
          ),
        ),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        tr(
          en: 'The server could not confirm sign out. Please try again.',
          fa: 'سرور خروج از حساب را تأیید نکرد. دوباره تلاش کنید.',
          ja: 'サーバーがログアウトを確認できませんでした。再試行してください。',
          ru: 'Сервер не подтвердил выход. Повторите попытку.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _scheduleAutoSave() {
    if (!_settingsStore.autoSaveEnabled || _loading) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted && !_saving) _saveProfile(silent: true);
    });
  }

  Future<void> _pickProfileImage() async {
    if (_selectingImage) return;

    if (!LocalPersistencePolicy.instance.canWrite) {
      _showMessage(
        tr(
          en: 'Local storage is paused. Choose Forever in data retention before adding an image.',
          fa: 'ذخیره‌سازی محلی متوقف است؛ پیش از افزودن تصویر، در مدت نگهداری داده گزینه «همیشه» را انتخاب کنید.',
          ja: 'ローカル保存は停止中です。画像を追加する前に、データ保持で「無期限」を選択してください。',
          ru: 'Локальное хранение приостановлено. Перед добавлением изображения выберите «Всегда».',
        ),
        isError: true,
      );
      return;
    }

    SystemSound.play(SystemSoundType.click);

    setState(() {
      _selectingImage = true;
    });

    try {
      final selected = await FilePicker.pickFile(type: FileType.image);

      if (selected == null) return;

      final selectedPath = selected.path;

      if (selectedPath == null || selectedPath.trim().isEmpty) {
        _showMessage(
          tr(
            en: 'The selected image could not be opened.',
            fa: 'تصویر انتخاب‌شده قابل باز شدن نیست.',
            ja: '選択した画像を開けませんでした。',
            ru: 'Не удалось открыть выбранное изображение.',
          ),
          isError: true,
        );
        return;
      }

      final selectedFile = File(selectedPath);

      if (!await selectedFile.exists()) {
        _showMessage(
          tr(
            en: 'The selected image file was not found.',
            fa: 'فایل تصویر انتخاب‌شده پیدا نشد.',
            ja: '選択した画像ファイルが見つかりません。',
            ru: 'Выбранный файл изображения не найден.',
          ),
          isError: true,
        );
        return;
      }

      // Retention may expire while the native picker is open.
      if (!LocalPersistencePolicy.instance.canWrite) {
        _showMessage(
          tr(
            en: 'Local storage is paused. Choose Forever in data retention before adding an image.',
            fa: 'ذخیره‌سازی محلی متوقف است؛ پیش از افزودن تصویر، در مدت نگهداری داده گزینه «همیشه» را انتخاب کنید.',
            ja: 'ローカル保存は停止中です。画像を追加する前に、データ保持で「無期限」を選択してください。',
            ru: 'Локальное хранение приостановлено. Перед добавлением изображения выберите «Всегда».',
          ),
          isError: true,
        );
        return;
      }

      final extension = path.extension(selectedPath).toLowerCase();

      final safeExtension = extension.isEmpty ? '.png' : extension;

      final oldImagePath = _profileStore.imagePath ?? '';
      final copiedImage = await ManagedAppFileStore.instance.copy(
        source: selectedFile,
        directoryName: 'profile',
        fileName: 'profile_image$safeExtension',
      );
      final destinationPath = copiedImage.path;
      if (oldImagePath.isNotEmpty && oldImagePath != destinationPath) {
        await ManagedAppFileStore.instance.delete(
          directoryName: 'profile',
          filePath: oldImagePath,
        );
      }

      await _profileStore.save(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        imagePath: destinationPath,
      );
      if (!LocalPersistencePolicy.instance.canWrite) {
        await ManagedAppFileStore.instance.delete(
          directoryName: 'profile',
          filePath: destinationPath,
        );
        await _profileStore.removeImage();
        return;
      }

      if (!mounted) return;

      setState(() {});

      widget.onProfileChanged?.call();

      _showMessage(
        tr(
          en: 'Profile image saved successfully.',
          fa: 'عکس پروفایل با موفقیت ذخیره شد.',
          ja: 'プロフィール画像を保存しました。',
          ru: 'Изображение профиля сохранено.',
        ),
      );
    } on LocalPersistenceSuspendedException {
      if (!mounted) return;
      _showMessage(
        tr(
          en: 'Local storage is paused. Choose Forever in data retention before adding an image.',
          fa: 'ذخیره‌سازی محلی متوقف است؛ پیش از افزودن تصویر، در مدت نگهداری داده گزینه «همیشه» را انتخاب کنید.',
          ja: 'ローカル保存は停止中です。画像を追加する前に、データ保持で「無期限」を選択してください。',
          ru: 'Локальное хранение приостановлено. Перед добавлением изображения выберите «Всегда».',
        ),
        isError: true,
      );
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        tr(
          en: 'An error occurred while saving the image.',
          fa: 'هنگام ذخیره عکس خطایی رخ داد.',
          ja: '画像の保存中にエラーが発生しました。',
          ru: 'При сохранении изображения произошла ошибка.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _selectingImage = false;
        });
      }
    }
  }

  Future<void> _removeProfileImage() async {
    SystemSound.play(SystemSoundType.click);

    final currentImagePath = _profileStore.imagePath ?? '';

    if (currentImagePath.isNotEmpty) {
      await ManagedAppFileStore.instance.delete(
        directoryName: 'profile',
        filePath: currentImagePath,
      );
    }

    await _profileStore.removeImage();

    if (!mounted) return;

    setState(() {});

    widget.onProfileChanged?.call();

    _showMessage(
      tr(
        en: 'Profile image removed.',
        fa: 'عکس پروفایل حذف شد.',
        ja: 'プロフィール画像を削除しました。',
        ru: 'Изображение профиля удалено.',
      ),
    );
  }

  Future<void> _saveProfile({bool silent = false}) async {
    if (_saving) return;

    if (!silent) SystemSound.play(SystemSoundType.click);

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      if (silent) return;
      _showMessage(
        tr(
          en: 'Please enter your display name.',
          fa: 'لطفاً نام نمایشی را وارد کنید.',
          ja: '表示名を入力してください。',
          ru: 'Введите отображаемое имя.',
        ),
        isError: true,
      );
      return;
    }

    if (email.isNotEmpty && !_isValidEmail(email)) {
      if (silent) return;
      _showMessage(
        tr(
          en: 'Please enter a valid email address.',
          fa: 'لطفاً یک ایمیل معتبر وارد کنید.',
          ja: '有効なメールアドレスを入力してください。',
          ru: 'Введите корректный адрес электронной почты.',
        ),
        isError: true,
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await _profileStore.save(
        name: name,
        email: email,
        phone: phone,
        imagePath: _profileStore.imagePath ?? '',
      );

      if (!mounted) return;

      setState(() {});

      widget.onProfileChanged?.call();
      if (!silent) {
        _notificationService.addNotification(
          title: tr(
            en: 'Profile Updated',
            fa: 'پروفایل به‌روزرسانی شد',
            ja: 'プロフィールを更新しました',
            ru: 'Профиль обновлён',
          ),
          message: tr(
            en: 'Your profile information has been saved successfully.',
            fa: 'اطلاعات پروفایل شما با موفقیت ذخیره شد.',
            ja: 'プロフィール情報を保存しました。',
            ru: 'Информация профиля успешно сохранена.',
          ),
          type: AppNotificationType.profile,
        );
        _showMessage(
          tr(
            en: 'Profile changes saved locally.',
            fa: 'تغییرات پروفایل به‌صورت محلی ذخیره شد.',
            ja: 'プロフィール変更をローカルに保存しました。',
            ru: 'Изменения профиля сохранены локально.',
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;

      if (silent) return;
      _showMessage(
        tr(
          en: 'Profile changes could not be saved.',
          fa: 'ذخیره تغییرات پروفایل انجام نشد.',
          ja: 'プロフィール変更を保存できませんでした。',
          ru: 'Не удалось сохранить изменения профиля.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  bool _isValidEmail(String value) {
    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    return emailPattern.hasMatch(value);
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError
              ? const Color(0xFFB93B4A)
              : const Color(0xFF176B4A),
          content: Text(message),
        ),
      );
  }

  Widget _buildProfileImage({double size = 96}) {
    final imagePath = _profileStore.imagePath ?? '';

    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [palette.primary, palette.secondary]),
        border: Border.all(
          color: palette.primary.withValues(alpha: 0.45),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.28),
            blurRadius: 30,
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: hasImage
            ? Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return _buildDefaultAvatar();
                },
              )
            : _buildDefaultAvatar(),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: palette.primary,
      child: Icon(
        Icons.person_rounded,
        color: palette.isLight ? Colors.white : Colors.black,
        size: 48,
      ),
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: 720,
        child: Center(child: CircularProgressIndicator(color: palette.primary)),
      );
    }

    return Directionality(
      textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 690, child: _buildIdentityPanel()),
                const SizedBox(height: 16),
                SizedBox(height: 760, child: _buildProfilePanel()),
              ],
            );
          }
          return SizedBox(
            height: 720,
            child: Row(
              textDirection: TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 310, child: _buildIdentityPanel()),
                const SizedBox(width: 16),
                Expanded(child: _buildProfilePanel()),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildIdentityPanel() {
    final shownName = _nameController.text.trim().isEmpty
        ? tr(
            en: 'GoldBrain User',
            fa: 'کاربر GoldBrain',
            ja: 'GoldBrainユーザー',
            ru: 'Пользователь GoldBrain',
          )
        : _nameController.text.trim();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildProfileImage(),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Material(
                    color: palette.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _selectingImage ? null : _pickProfileImage,
                      child: SizedBox(
                        width: 35,
                        height: 35,
                        child: _selectingImage
                            ? Padding(
                                padding: const EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.isLight
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              )
                            : Icon(
                                Icons.photo_camera_rounded,
                                color: palette.isLight
                                    ? Colors.white
                                    : Colors.black,
                                size: 18,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            shownName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.text,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            tr(
              en: 'Neural Account',
              fa: 'حساب عصبی',
              ja: 'ニューラルアカウント',
              ru: 'Нейронный аккаунт',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.mutedText, fontSize: 11),
          ),
          const SizedBox(height: 13),
          TextButton.icon(
            onPressed: _selectingImage ? null : _pickProfileImage,
            icon: Icon(Icons.image_outlined, color: palette.primary, size: 18),
            label: Text(
              tr(
                en: 'Choose Image',
                fa: 'انتخاب عکس',
                ja: '画像を選択',
                ru: 'Выбрать изображение',
              ),
              style: TextStyle(
                color: palette.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (_profileStore.hasValidImage)
            TextButton.icon(
              onPressed: _removeProfileImage,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFFF7182),
                size: 18,
              ),
              label: Text(
                tr(
                  en: 'Remove Image',
                  fa: 'حذف عکس',
                  ja: '画像を削除',
                  ru: 'Удалить изображение',
                ),
                style: const TextStyle(
                  color: Color(0xFFFF7182),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(height: 12),
          _StatusCard(
            palette: palette,
            icon: Icons.phonelink_lock_rounded,
            title: tr(
              en: 'Account status',
              fa: 'وضعیت حساب',
              ja: 'アカウント状態',
              ru: 'Статус аккаунта',
            ),
            value: tr(
              en: 'Local profile',
              fa: 'پروفایل محلی',
              ja: 'ローカルプロフィール',
              ru: 'Локальный профиль',
            ),
          ),
          const SizedBox(height: 10),
          _StatusCard(
            palette: palette,
            icon: Icons.cloud_done_rounded,
            title: tr(
              en: 'Cloud sync',
              fa: 'همگام‌سازی ابری',
              ja: 'クラウド同期',
              ru: 'Облачная синхронизация',
            ),
            value: tr(
              en: 'Not connected',
              fa: 'متصل نشده',
              ja: '未接続',
              ru: 'Не подключено',
            ),
          ),
          const SizedBox(height: 10),
          _StatusCard(
            palette: palette,
            icon: Icons.psychology_alt_rounded,
            title: tr(
              en: 'AI profile',
              fa: 'پروفایل هوش مصنوعی',
              ja: 'AIプロフィール',
              ru: 'ИИ-профиль',
            ),
            value: tr(
              en: _settingsStore.personalizedAiEnabled ? 'Active' : 'Off',
              fa: _settingsStore.personalizedAiEnabled ? 'فعال' : 'خاموش',
              ja: _settingsStore.personalizedAiEnabled ? '有効' : 'オフ',
              ru: _settingsStore.personalizedAiEnabled ? 'Активен' : 'Отключен',
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: palette.primary.withValues(alpha: 0.17),
              ),
            ),
            child: Text(
              tr(
                en: 'Later, GoldBrain will use your preferences, watchlist and portfolio to personalize analysis.',
                fa: 'بعداً GoldBrain از ترجیحات، دیده‌بان و سبد دارایی شما برای شخصی‌سازی تحلیل‌ها استفاده می‌کند.',
                ja: '将来、設定、ウォッチリスト、ポートフォリオを利用して分析を最適化します。',
                ru: 'Позже GoldBrain будет персонализировать анализ по вашим настройкам и портфелю.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 11,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePanel() {
    return Container(
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    Icons.manage_accounts_rounded,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(
                          en: 'Profile & Identity',
                          fa: 'پروفایل و هویت کاربری',
                          ja: 'プロフィールとID',
                          ru: 'Профиль и идентичность',
                        ),
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(
                          en: 'Manage personal information and account preferences.',
                          fa: 'اطلاعات شخصی و ترجیحات حساب را مدیریت کنید.',
                          ja: '個人情報とアカウント設定を管理します。',
                          ru: 'Управляйте личными данными и настройками аккаунта.',
                        ),
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.primary.withValues(alpha: 0.10)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTextField(
                    controller: _nameController,
                    readOnly: _profileStore.hasBackendIdentity,
                    label: tr(
                      en: 'Display name',
                      fa: 'نام نمایشی',
                      ja: '表示名',
                      ru: 'Отображаемое имя',
                    ),
                    icon: Icons.person_outline_rounded,
                    onChanged: (_) {
                      setState(() {});
                      _scheduleAutoSave();
                    },
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    controller: _emailController,
                    readOnly: _profileStore.hasBackendIdentity,
                    label: tr(
                      en: 'Email address',
                      fa: 'ایمیل',
                      ja: 'メールアドレス',
                      ru: 'Электронная почта',
                    ),
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => _scheduleAutoSave(),
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    controller: _phoneController,
                    label: tr(
                      en: 'Phone number',
                      fa: 'شماره تماس',
                      ja: '電話番号',
                      ru: 'Номер телефона',
                    ),
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => _scheduleAutoSave(),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final languageCard = _PreferenceCard(
                        palette: palette,
                        icon: Icons.language_rounded,
                        title: tr(
                          en: 'Language',
                          fa: 'زبان',
                          ja: '言語',
                          ru: 'Язык',
                        ),
                        value: tr(
                          en: 'English',
                          fa: 'فارسی',
                          ja: '日本語',
                          ru: 'Русский',
                        ),
                      );
                      final themeCard = _PreferenceCard(
                        palette: palette,
                        icon: Icons.palette_outlined,
                        title: tr(
                          en: 'Theme',
                          fa: 'تم برنامه',
                          ja: 'テーマ',
                          ru: 'Тема',
                        ),
                        value: tr(
                          en: 'Active theme',
                          fa: 'تم فعال',
                          ja: '現在のテーマ',
                          ru: 'Активная тема',
                        ),
                      );
                      if (constraints.maxWidth < 430) {
                        return Column(
                          children: [
                            languageCard,
                            const SizedBox(height: 12),
                            themeCard,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: languageCard),
                          const SizedBox(width: 12),
                          Expanded(child: themeCard),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        if (_connection.session.authenticated)
                          TextButton.icon(
                            onPressed: _signingOut || _saving ? null : _signOut,
                            icon: const Icon(Icons.logout_rounded),
                            label: Text(
                              tr(
                                en: 'Sign out',
                                fa: 'خروج از حساب',
                                ja: 'ログアウト',
                                ru: 'Выйти',
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: palette.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 16,
                              ),
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: _saving ? null : _saveProfile,
                          icon: _saving
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.isLight
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(
                            _saving
                                ? tr(
                                    en: 'Saving...',
                                    fa: 'در حال ذخیره...',
                                    ja: '保存中...',
                                    ru: 'Сохранение...',
                                  )
                                : tr(
                                    en: 'Save Changes',
                                    fa: 'ذخیره تغییرات',
                                    ja: '変更を保存',
                                    ru: 'Сохранить изменения',
                                  ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.primary,
                            disabledBackgroundColor: palette.primary.withValues(
                              alpha: 0.55,
                            ),
                            foregroundColor: palette.isLight
                                ? Colors.white
                                : Colors.black,
                            disabledForegroundColor: palette.isLight
                                ? Colors.white54
                                : Colors.black54,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool readOnly = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: TextStyle(color: palette.text, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: palette.mutedText),
        prefixIcon: Icon(icon, color: palette.primary),
        filled: true,
        fillColor: palette.background.withValues(alpha: 0.38),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: palette.primary.withValues(alpha: 0.12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.primary),
        ),
      ),
    );
  }

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: palette.surface.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(27),
      border: Border.all(color: palette.primary.withValues(alpha: 0.18)),
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 25, offset: Offset(0, 12)),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.palette,
    required this.icon,
    required this.title,
    required this.value,
  });

  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.primary.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: palette.mutedText, fontSize: 9),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.palette,
    required this.icon,
    required this.title,
    required this.value,
  });

  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 105,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: palette.primary.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: palette.mutedText, fontSize: 10),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
