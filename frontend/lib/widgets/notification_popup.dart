import 'package:flutter/material.dart';

import '../core/notification_service.dart';
import '../screens/selection_screen.dart';
import '../core/motion_preferences.dart';

class NotificationPopup extends StatelessWidget {
  const NotificationPopup({
    super.key,
    required this.palette,
    required this.language,
    required this.notifications,
    required this.title,
    required this.subtitle,
    required this.settingsLabel,
    required this.onClose,
    required this.onOpenSettings,
    required this.onRemoveNotification,
  });

  final ThemePalette palette;
  final GoldBrainLanguage language;
  final List<AppNotification> notifications;
  final String title;
  final String subtitle;
  final String settingsLabel;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onRemoveNotification;

  String _localized({
    required String en,
    required String fa,
    required String ja,
    required String ru,
    required String zh,
    required String ar,
    required String tr,
    required String fr,
  }) => switch (language) {
    GoldBrainLanguage.english => en,
    GoldBrainLanguage.persian => fa,
    GoldBrainLanguage.japanese => ja,
    GoldBrainLanguage.russian => ru,
    GoldBrainLanguage.chinese => zh,
    GoldBrainLanguage.arabic => ar,
    GoldBrainLanguage.turkish => tr,
    GoldBrainLanguage.french => fr,
  };

  IconData _notificationIcon(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.profile:
        return Icons.person_rounded;
      case AppNotificationType.settings:
        return Icons.settings_rounded;
      case AppNotificationType.priceAlert:
        return Icons.trending_up_rounded;
      case AppNotificationType.news:
        return Icons.newspaper_rounded;
      case AppNotificationType.ai:
        return Icons.auto_awesome_rounded;
      case AppNotificationType.system:
        return Icons.notifications_active_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: palette.primary.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: palette.primary.withValues(alpha: 0.14),
              blurRadius: 38,
            ),
            const BoxShadow(
              color: Colors.black54,
              blurRadius: 32,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              textDirection: TextDirection.ltr,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.notifications_active_rounded,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close_rounded, color: palette.mutedText),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Flexible(
              child: notifications.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          _localized(
                            en: 'No notifications',
                            fa: 'اعلانی وجود ندارد',
                            ja: '通知はありません',
                            ru: 'Нет уведомлений',
                            zh: '暂无通知',
                            ar: 'لا توجد إشعارات',
                            tr: 'Bildirim yok',
                            fr: 'Aucune notification',
                          ),
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) {
                        return const SizedBox(height: 10);
                      },
                      itemBuilder: (context, index) {
                        final notification = notifications[index];

                        return _NotificationItem(
                          palette: palette,
                          icon: _notificationIcon(notification.type),
                          title: notification.localizedTitle(language.name),
                          message: notification.localizedMessage(language.name),
                          deleteTooltip: _localized(
                            en: 'Delete notification',
                            fa: 'حذف اعلان',
                            ja: '通知を削除',
                            ru: 'Удалить уведомление',
                            zh: '删除通知',
                            ar: 'حذف الإشعار',
                            tr: 'Bildirimi sil',
                            fr: 'Supprimer la notification',
                          ),
                          onRemove: () {
                            onRemoveNotification(notification.id);
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_rounded),
                label: Text(settingsLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.primary,
                  foregroundColor: palette.isLight
                      ? Colors.white
                      : Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationItem extends StatefulWidget {
  const _NotificationItem({
    required this.palette,
    required this.icon,
    required this.title,
    required this.message,
    required this.deleteTooltip,
    required this.onRemove,
  });

  final ThemePalette palette;
  final IconData icon;
  final String title;
  final String message;
  final String deleteTooltip;
  final VoidCallback onRemove;

  @override
  State<_NotificationItem> createState() => _NotificationItemState();
}

class _NotificationItemState extends State<_NotificationItem> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: MotionPreferences.duration(180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.palette.background.withValues(
            alpha: hovered ? 0.52 : 0.42,
          ),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: widget.palette.primary.withValues(
              alpha: hovered ? 0.24 : 0.10,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.palette.primary.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(widget.icon, color: widget.palette.primary, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    textDirection:
                        RegExp(r'[\u0600-\u06FF]').hasMatch(widget.title)
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: widget.palette.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.message,
                    textDirection:
                        RegExp(r'[\u0600-\u06FF]').hasMatch(widget.message)
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: widget.palette.mutedText,
                      fontSize: 10,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: MotionPreferences.duration(150),
              opacity: hovered ? 1 : 0,
              child: IconButton(
                onPressed: widget.onRemove,
                tooltip: widget.deleteTooltip,
                icon: Icon(
                  Icons.close_rounded,
                  color: widget.palette.mutedText,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
