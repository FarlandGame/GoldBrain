import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldbrain/core/notification_service.dart';
import 'package:goldbrain/screens/selection_screen.dart';
import 'package:goldbrain/widgets/notification_popup.dart';

void main() {
  testWidgets('localizes empty state for all supported languages', (
    tester,
  ) async {
    const expectations = {
      GoldBrainLanguage.english: 'No notifications',
      GoldBrainLanguage.persian: 'اعلانی وجود ندارد',
      GoldBrainLanguage.japanese: '通知はありません',
      GoldBrainLanguage.russian: 'Нет уведомлений',
      GoldBrainLanguage.chinese: '暂无通知',
      GoldBrainLanguage.arabic: 'لا توجد إشعارات',
      GoldBrainLanguage.turkish: 'Bildirim yok',
      GoldBrainLanguage.french: 'Aucune notification',
    };

    for (final entry in expectations.entries) {
      await tester.pumpWidget(_app(language: entry.key));
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets(
    'renders semantic content and delete tooltip in current language',
    (tester) async {
      final notification = AppNotification(
        id: 'seed-profileReady',
        title: 'Profile is ready',
        message: 'Your profile information was loaded successfully.',
        createdAt: DateTime.utc(2026, 8, 11),
        type: AppNotificationType.profile,
        semanticKey: AppNotificationSemanticKey.profileReady,
      );

      await tester.pumpWidget(
        _app(language: GoldBrainLanguage.french, notifications: [notification]),
      );

      expect(find.text('Profil prêt'), findsOneWidget);
      expect(
        find.text('Les informations de votre profil ont été chargées.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Supprimer la notification'), findsOneWidget);
    },
  );
}

Widget _app({
  required GoldBrainLanguage language,
  List<AppNotification> notifications = const [],
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: NotificationPopup(
          palette: themePalettes[GoldBrainTheme.gold]!,
          language: language,
          notifications: notifications,
          title: 'Notifications',
          subtitle: 'System messages',
          settingsLabel: 'Settings',
          onClose: () {},
          onOpenSettings: () {},
          onRemoveNotification: (_) {},
        ),
      ),
    ),
  );
}
