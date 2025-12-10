import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class LocalNotificationService {
  static final LocalNotificationService _instance = 
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  static late FlutterLocalNotificationsPlugin _notificationsPlugin;
  
  // Notification channels
  static const String _dailyChannelId = 'daily_quiz_channel';
  static const String _dailyChannelName = 'Daily Quiz Reminders';
  static const String _dailyChannelDesc = 'Notifications for daily quiz reminders';

  static const String _testChannelId = 'quiz_test_channel';
  static const String _testChannelName = 'Quiz Test Notifications';
  static const String _testChannelDesc = 'For testing notification functionality';

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    _notificationsPlugin = FlutterLocalNotificationsPlugin();
    tz.initializeTimeZones();

    try {
      // Android initialization
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS initialization
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await _notificationsPlugin.initialize(
        const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
        onDidReceiveNotificationResponse: (_) {},
      );

      await _createNotificationChannels();
      _initialized = true;
    } catch (e, stack) {
      debugPrint('Notification init failed: $e\n$stack');
    }
  }

  static Future<void> _createNotificationChannels() async {
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _dailyChannelId,
          _dailyChannelName,
          description: _dailyChannelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _testChannelId,
          _testChannelName,
          description: _testChannelDesc,
          importance: Importance.high,
          playSound: true,
        ),
      );
    }
  }

  static Future<bool> checkPermission() async {
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        return await androidPlugin.areNotificationsEnabled() ?? false;
      }
      return true;
    } catch (e) {
      debugPrint('Error checking permission: $e');
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        return await androidPlugin.requestNotificationsPermission() ?? false;
      }
      return true;
    } catch (e) {
      debugPrint('Error requesting permission: $e');
      return false;
    }
  }

  static Future<void> showTestNotification() async {
    if (!_initialized) await initialize();

    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        _testChannelId,
        _testChannelName,
        channelDescription: _testChannelDesc,
        importance: Importance.high,
      );

      await _notificationsPlugin.show(
        999,
        'Test Notification',
        'This is a test notification',
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing test notification: $e');
    }
  }

 static Future<void> scheduleDailyAtTime({
  required int id,
  required String title,
  required String body,
  required DateTime scheduledTime,
}) async {
  if (!_initialized) await initialize();

  try {
    debugPrint('Attempting to schedule notification for: $scheduledTime');
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _dailyChannelId,
      _dailyChannelName,
      channelDescription: _dailyChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      channelShowBadge: true,
    );

    final scheduledTZ = _nextInstanceOfTime(scheduledTime);
    debugPrint('Converted to local timezone: $scheduledTZ');

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTZ,
      const NotificationDetails(android: androidDetails),
      uiLocalNotificationDateInterpretation: 
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      androidAllowWhileIdle: true,
    );

    debugPrint('Notification scheduled successfully');
  } catch (e, stack) {
    debugPrint('Error scheduling notification: $e\n$stack');
    // Immediate fallback
    await _showImmediateNotification(
      id: id,
      title: 'Reminder: $title',
      body: body,
    );
  }
}
  static Future<void> _showImmediateNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _notificationsPlugin.show(
        id,
        'Reminder: $title',
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'fallback_channel',
            'Immediate Reminders',
            importance: Importance.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error showing immediate notification: $e');
    }
  }

  static tz.TZDateTime _nextInstanceOfTime(DateTime time) {
  tz.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata')); // Set your timezone
  } catch (_) {}
  
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime.from(time, tz.local);
  
  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  
  debugPrint('Scheduled time: $scheduled (Current: $now)');
  return scheduled;
}

  static Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('Error cancelling notifications: $e');
      rethrow;
    }
  }

  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      return await _notificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint('Error getting pending notifications: $e');
      return [];
    }
  }
}