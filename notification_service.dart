import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);

    // ✅ FIX 1: Parameter name is 'settings', not 'initializationSettings'
    await flutterLocalNotificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {},
    );
  }

  // ✅ FIX 2: Add permission request method
  Future<void> requestPermissions() async {
    // Android doesn't need explicit permission request
    // iOS needs permission request
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'library_channel',
      'Library notifications',
      channelDescription: 'Notifications for library entry/exit and reminders',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker', // ✅ FIX 3: WAJIB ada dalam version baru
    );
    const iosDetails = DarwinNotificationDetails();
    const platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails
    );

    await flutterLocalNotificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: platformDetails
    );
  }

  // ✅ Break reminder
  Future<void> showBreakReminder(int minutesStudied) async {
    String message;
    String title;
    int id = 200 + minutesStudied;

    if (minutesStudied >= 60) {
      title = '☕ Long Study Session!';
      message = 'You\'ve studied for ${minutesStudied ~/ 60} hour${minutesStudied ~/ 60 > 1 ? 's' : ''}. Take a 10-15 minute break!';
    } else if (minutesStudied >= 30) {
      title = '⏰ Break Time!';
      message = 'You\'ve studied for $minutesStudied minutes. Take a 5-minute break to recharge!';
    } else {
      title = '🧠 Keep Going!';
      message = 'You\'ve studied for $minutesStudied minutes. Remember to rest your eyes.';
    }

    await showNotification(
      id: id,
      title: title,
      body: message,
    );
  }

  // ✅ Time spent reminder
  Future<void> showTimeSpentReminder(int minutes) async {
    await showNotification(
      id: 100 + minutes,
      title: '📚 Time Spent',
      body: 'You have been in the library for $minutes minute${minutes > 1 ? 's' : ''}.',
    );
  }

  // ✅ Silent mode reminder
  Future<void> showSilentModeReminder() async {
    await showNotification(
      id: 301,
      title: '🔇 Silent Mode Reminder',
      body: 'Please switch your phone to silent mode while in the library.',
    );
  }

  // ✅ Exit message
  Future<void> showExitMessage(String duration) async {
    await showNotification(
      id: 302,
      title: '👋 Thank You!',
      body: 'Thanks for visiting the library. You studied for $duration.',
    );
  }

  // Cancel all notifications
  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}