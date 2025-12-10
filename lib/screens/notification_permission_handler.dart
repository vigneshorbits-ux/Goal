import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPermissionHandler {
  static Future<bool> checkPermission() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      return await androidPlugin.areNotificationsEnabled() ?? false;
    }
    return false;
  }

  static Future<bool> requestPermission() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final prefs = await SharedPreferences.getInstance();
    final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      await prefs.setBool('notification_permission_asked', true);
      return granted ?? false;
    }
    return false;
  }
}