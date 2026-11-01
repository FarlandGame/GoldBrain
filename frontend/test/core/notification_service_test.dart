import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('semantic seed notifications resolve in all eight languages', () {
    final notification = AppNotification(
      id: 'seed-profileReady',
      title: 'Profile is ready',
      message: 'Your profile information was loaded successfully.',
      createdAt: DateTime.utc(2026, 8, 11),
      type: AppNotificationType.profile,
      semanticKey: AppNotificationSemanticKey.profileReady,
    );

    const expectedTitles = {
      'english': 'Profile is ready',
      'persian': 'پروفایل آماده است',
      'japanese': 'プロフィールの準備ができました',
      'russian': 'Профиль готов',
      'chinese': '个人资料已就绪',
      'arabic': 'الملف الشخصي جاهز',
      'turkish': 'Profil hazır',
      'french': 'Profil prêt',
    };

    for (final entry in expectedTitles.entries) {
      expect(
        notification.localizedTitle(entry.key),
        entry.value,
        reason: 'Incorrect ${entry.key} seed title.',
      );
      expect(notification.localizedMessage(entry.key), isNotEmpty);
    }
  });

  test('runtime notifications remain verbatim for every language', () {
    final notification = AppNotification(
      id: 'runtime',
      title: 'متن واقعی کاربر',
      message: 'Do not translate this runtime payload.',
      createdAt: DateTime.utc(2026, 8, 11),
      type: AppNotificationType.news,
    );

    for (final language in const [
      'english',
      'persian',
      'japanese',
      'russian',
      'chinese',
      'arabic',
      'turkish',
      'french',
    ]) {
      expect(notification.localizedTitle(language), 'متن واقعی کاربر');
      expect(
        notification.localizedMessage(language),
        'Do not translate this runtime payload.',
      );
    }
  });

  test(
    'migrates persisted legacy Persian seeds and preserves runtime data',
    () async {
      final createdAt = DateTime.utc(2026, 8, 11);
      SharedPreferences.setMockInitialValues({
        'app.notifications': jsonEncode([
          {
            'id': 'old-profile-id',
            'title': 'پروفایل آماده است',
            'message': 'اطلاعات پروفایل شما با موفقیت بارگذاری شد.',
            'createdAt': createdAt.toIso8601String(),
            'type': 'profile',
            'isRead': true,
          },
          {
            'id': 'currency-change-hint',
            'title': 'واحد پول قابل تغییر است',
            'message': 'legacy wording',
            'createdAt': createdAt.toIso8601String(),
            'type': 'settings',
            'isRead': false,
          },
          {
            'id': 'runtime-id',
            'title': 'اعلان واقعی',
            'message': 'payload',
            'createdAt': createdAt.toIso8601String(),
            'type': 'news',
            'isRead': false,
          },
        ]),
      });
      final service = NotificationService.forTesting();

      await service.load();

      final profile = service.notifications.firstWhere(
        (item) => item.id == 'old-profile-id',
      );
      expect(profile.semanticKey, AppNotificationSemanticKey.profileReady);
      expect(profile.isRead, isTrue);
      expect(profile.localizedTitle('english'), 'Profile is ready');

      final currency = service.notifications.firstWhere(
        (item) => item.id == 'currency-change-hint',
      );
      expect(
        currency.semanticKey,
        AppNotificationSemanticKey.currencyChangeHint,
      );

      final runtime = service.notifications.firstWhere(
        (item) => item.id == 'runtime-id',
      );
      expect(runtime.semanticKey, isNull);
      expect(runtime.localizedTitle('english'), 'اعلان واقعی');

      final preferences = await SharedPreferences.getInstance();
      final persisted =
          jsonDecode(preferences.getString('app.notifications')!) as List;
      final persistedProfile = persisted.cast<Map>().firstWhere(
        (item) => item['id'] == 'old-profile-id',
      );
      expect(persistedProfile['semanticKey'], 'profileReady');
      service.dispose();
    },
  );

  test('initial seeds are semantic and are not duplicated', () async {
    final service = NotificationService.forTesting();

    await service.addInitialNotifications();
    await service.addInitialNotifications();

    expect(service.notifications, hasLength(4));
    expect(service.notifications.map((item) => item.semanticKey).toSet(), {
      AppNotificationSemanticKey.profileReady,
      AppNotificationSemanticKey.settingsReady,
      AppNotificationSemanticKey.cloudNotConnected,
      AppNotificationSemanticKey.currencyChangeHint,
    });
    expect(
      service.notifications
          .map((item) => item.localizedTitle('chinese'))
          .every((value) => value.isNotEmpty),
      isTrue,
    );
    service.dispose();
  });

  test(
    'semantic market events persist payload and localize in eight languages',
    () async {
      final service = NotificationService.forTesting();
      await service.load();

      expect(
        service.addSemanticNotificationIfAbsent(
          id: 'signal-1',
          semanticKey: AppNotificationSemanticKey.strongAiSignal,
          semanticData: const {
            'symbol': 'GOLD18',
            'direction': 'upward',
            'confidence': '78',
            'horizonHours': '12',
          },
          type: AppNotificationType.ai,
        ),
        isTrue,
      );
      expect(
        service.addSemanticNotificationIfAbsent(
          id: 'signal-1',
          semanticKey: AppNotificationSemanticKey.strongAiSignal,
          semanticData: const {},
          type: AppNotificationType.ai,
        ),
        isFalse,
      );
      for (final language in const [
        'english',
        'persian',
        'japanese',
        'russian',
        'chinese',
        'arabic',
        'turkish',
        'french',
      ]) {
        expect(
          service.notifications.single.localizedTitle(language),
          isNotEmpty,
        );
        expect(
          service.notifications.single.localizedMessage(language),
          contains('GOLD18'),
        );
      }
      await Future<void>.delayed(Duration.zero);
      final preferences = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(preferences.getString('app.notifications')!) as List;
      expect((saved.single as Map)['semanticData']['confidence'], '78');
      service.dispose();
    },
  );
}
