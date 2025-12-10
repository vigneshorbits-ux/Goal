
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:goal/screens/AdminPdfUploadScreen.dart';
import 'package:goal/screens/Referral%20Screen.dart';
import 'package:goal/screens/admin.dart';
import 'package:goal/screens/battle.dart';
import 'package:goal/screens/homescreen.dart';
import 'package:goal/screens/reward_controller.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'firebase_options.dart';
import 'local_notification_service.dart';
import 'screens/auth_screen.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/reward.dart';
import 'screens/quiz_selection_screen.dart';
import 'screens/Account Screen.dart';
import 'screens/resetpassword.dart';
import 'screens/privacy_policy.dart';
import 'screens/tips_screen.dart';
import 'screens/ads.dart';
import 'screens/ReminderSettingsScreen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class AppInitialization {
  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _initializeComponents();
  }

  static Future<void> _initializeComponents() async {
    try {
      _initializeTimeZone();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await _initializeAds();
      await _initializeNotifications();
      debugPrint("✅ App initialization completed successfully");
    } catch (e, stack) {
      debugPrint("🚨 Critical initialization error: $e\n$stack");
    }
  }

  static void _initializeTimeZone() {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (e) {
      debugPrint("⚠️ Could not set timezone location: $e");
      tz.setLocalLocation(tz.UTC);
    }
  }

  static Future<void> _initializeAds() async {
    try {
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: const []),
      );
    } catch (e) {
      debugPrint("⚠️ Ad initialization failed: $e");
    }
  }

  static Future<void> _initializeNotifications() async {
    try {
      await LocalNotificationService.initialize();
      final prefs = await SharedPreferences.getInstance();
      final remindersSetUp = prefs.getBool('reminders_set_up') ?? false;

      if (!remindersSetUp) {
        debugPrint("📱 Reminders not set up yet");
        return;
      }

      final hasPermission = await LocalNotificationService.checkPermission();
      if (!hasPermission) {
        debugPrint("❌ No notification permission");
        return;
      }

      final pendingNotifications = await LocalNotificationService.getPendingNotifications();
      if (pendingNotifications.isNotEmpty) {
        debugPrint("📅 ${pendingNotifications.length} notifications already scheduled");
        return;
      }

      await _scheduleDefaultReminder();
    } catch (e, stack) {
      debugPrint("⚠️ Notification initialization failed: $e\n$stack");
    }
  }

  static Future<void> _scheduleDefaultReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reminderHour = prefs.getInt('reminder_hour') ?? 9;
      final reminderMinute = prefs.getInt('reminder_minute') ?? 0;

      final now = DateTime.now();
      final reminderTime = DateTime(
        now.year,
        now.month,
        now.day,
        reminderHour,
        reminderMinute,
      );

      await LocalNotificationService.scheduleDailyAtTime(
        id: 1,
        title: 'Quiz Time! 🧠',
        body: 'Ready to challenge your mind? Start your daily quiz now!',
        scheduledTime: reminderTime,
      );

      debugPrint("✅ Default reminder scheduled for $reminderHour:${reminderMinute.toString().padLeft(2, '0')}");
    } catch (e) {
      debugPrint("❌ Failed to schedule default reminder: $e");
    }
  }

  static Future<void> rescheduleNotifications() async {
    try {
      await LocalNotificationService.cancelAllNotifications();
      final prefs = await SharedPreferences.getInstance();
      final remindersEnabled = prefs.getBool('reminders_enabled') ?? false;

      if (!remindersEnabled) {
        debugPrint("🔕 Reminders disabled, not rescheduling");
        return;
      }

      final hasPermission = await LocalNotificationService.checkPermission();
      if (!hasPermission) {
        debugPrint("❌ No notification permission for rescheduling");
        return;
      }

      await _scheduleDefaultReminder();
    } catch (e) {
      debugPrint("❌ Failed to reschedule notifications: $e");
    }
  }

  static Future<void> testNotification() async {
    try {
      final hasPermission = await LocalNotificationService.checkPermission();
      if (!hasPermission) {
        final granted = await LocalNotificationService.requestPermission();
        if (!granted) {
          debugPrint("❌ Permission denied for test notification");
          return;
        }
      }

      await LocalNotificationService.showTestNotification();
      debugPrint("✅ Test notification sent");
    } catch (e) {
      debugPrint("❌ Failed to send test notification: $e");
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await AppInitialization.initialize();

  runApp(MyApp(navigatorKey: navigatorKey));
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const MyApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RewardController(userId: '')),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Quiz App',
        debugShowCheckedModeBanner: false,
        theme: _buildAppTheme(Brightness.light),
        darkTheme: _buildAppTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const AuthScreen(),
        routes: _buildAppRoutes(),
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => const AuthScreen(),
          );
        },
      ),
    );
  }

  ThemeData _buildAppTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blueAccent,
        brightness: brightness,
      ),
      textTheme: GoogleFonts.poppinsTextTheme().apply(
        bodyColor: isDark ? Colors.white : Colors.blueGrey[800],
        displayColor: isDark ? Colors.white : Colors.blue[900],
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.blueGrey[800],
        ),
      ),
    );
  }

  Map<String, WidgetBuilder> _buildAppRoutes() {
    return {
      '/leaderboard': (context) => const LeaderboardScreen(),
      '/rewards': (context) => const RewardScreen(),
      '/quizSelection': (context) => const QuizSelectionScreen(),
      '/account': (context) => const AccountScreen(),
      '/forgot-password': (context) => const ForgotPasswordScreen(),
      '/privacy-policy': (context) => const PrivacyPolicyScreen(),
      '/announcements': (context) => const UpcomingExamsScreen(),
      '/ads': (context) => const AdScreen(),
      '/referral': (context) => const ReferralScreen(),
      '/battle': (context) => const BattleScreen(),
      '/reminders': (context) => ReminderSettingsScreen(
        onComplete: () {
          AppInitialization.rescheduleNotifications();
          Navigator.of(context).pop();
        },
      ),
      '/admin': (context) => const AdminWithdrawScreen(),
      '/admin-upload-pdf': (context) => const AdminPdfUploadScreen(),

      '/HomeScreen': (context) => const HomeScreen(username: ''), // Set username after login
    };
  }
}
