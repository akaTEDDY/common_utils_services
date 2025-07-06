import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);

    // Android 알림 채널 생성
    await _createNotificationChannels();
  }

  // 알림 채널 생성
  Future<void> _createNotificationChannels() async {
    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImplementation != null) {
      // 기본 채널
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'plengi_channel',
          'Plengi Notifications',
          description: 'Notifications from Plengi AI',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
      );

      // 일기 작성 알림 채널
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'daily_diary_reminder',
          '일기 작성 알림',
          description: '매일 일기 작성을 권유하는 알림',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
      );

      // AI 피드백 알림 채널
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'daily_feedback',
          'AI 피드백 알림',
          description: '매일 AI 피드백을 제공하는 알림',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
      );
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'plengi_channel',
      'Plengi Notifications',
      channelDescription: 'Notifications from Plengi AI',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification_pinary',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(DateTime.now().millisecond, title, body, details);
  }

  // 스케줄된 알림 등록
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String channelId,
    required String channelName,
    required String channelDescription,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: true,
      enableLights: true,
      playSound: true,
      category: AndroidNotificationCategory.reminder,
      icon: 'ic_notification_pinary',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: matchDateTimeComponents,
    );
  }

  // 특정 알림 취소
  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  // 여러 알림 취소
  Future<void> cancelNotifications(List<int> ids) async {
    for (final id in ids) {
      await _notifications.cancel(id);
    }
  }

  // 모든 알림 취소
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
}
