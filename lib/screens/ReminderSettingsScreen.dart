import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:goal/screens/notification_permission_handler.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../local_notification_service.dart';

class ReminderSettingsScreen extends StatefulWidget {
  final VoidCallback? onReminderSet;
  final VoidCallback? onComplete;

  const ReminderSettingsScreen({
    super.key,
    this.onReminderSet,
    this.onComplete,
  });

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  TimeOfDay selectedTime = const TimeOfDay(hour: 8, minute: 0);
  bool _isProcessing = false;
  bool _permissionGranted = false;
  bool _hasAskedForPermission = false;
  bool _isCheckingPermission = true;
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  InterstitialAd? _interstitialAd;
  Timer? _adTimer;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
    _checkInitialPermissionStatus();
  }

  Future<void> _initializeScreen() async {
    _loadBannerAd();
    _startInterstitialAdTimer();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _adTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialPermissionStatus() async {
    setState(() => _isCheckingPermission = true);

    try {
      final hasPermission = await NotificationPermissionHandler.checkPermission();
      final prefs = await SharedPreferences.getInstance();
      final hasAsked = prefs.getBool('notification_permission_asked') ?? false;

      if (mounted) {
        setState(() {
          _permissionGranted = hasPermission;
          _hasAskedForPermission = hasAsked;
          _isCheckingPermission = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingPermission = false);
      }
      debugPrint('Error checking initial permission: $e');
    }
  }

  Future<void> _requestNotificationPermission() async {
    setState(() => _isProcessing = true);

    try {
      final granted = await NotificationPermissionHandler.requestPermission();

      if (mounted) {
        setState(() {
          _permissionGranted = granted;
          _hasAskedForPermission = true;
          _isProcessing = false;
        });

        if (granted) {
          _showSnackBar('Notifications enabled!', Colors.green);
        } else {
          _showSnackBar('Please enable notifications in app settings', Colors.orange);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      _showSnackBar('Failed to request permission', Colors.red);
    }
  }

  Widget _buildPermissionExplanationCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active,
                    color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text('Enable Notifications',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Get daily reminders to take your quiz and maintain your streak.'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _requestNotificationPermission,
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Enable Notifications'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reminder Time', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.access_time),
          title: const Text('Select Time'),
          subtitle: Text(selectedTime.format(context)),
          trailing: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _permissionGranted ? _pickTime : null,
          ),
          onTap: _permissionGranted ? _pickTime : null,
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _permissionGranted ? _scheduleDailyReminder : null,
            child: _isProcessing
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Set Daily Reminder'),
          ),
        ),
        const SizedBox(height: 12),
        if (_permissionGranted)
          TextButton(
            onPressed: _cancelReminders,
            child: const Text('Cancel All Reminders',
                style: TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  Widget _buildHelpAndFeedbackSection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 24, bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: Theme.of(context).primaryColor),
                const SizedBox(width: 8),
                Text('Help & Feedback',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Need help or have suggestions? We\'d love to hear from you!',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  Icon(Icons.email_outlined, 
                      color: Theme.of(context).primaryColor, size: 24),
                  const SizedBox(height: 8),
                  const Text(
                    'Write to us at:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _copyEmailToClipboard,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'contactgoal4service@gmail.com',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.copy,
                            size: 14,
                            color: Theme.of(context).primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sendEmail,
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: const Text('Send Email', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyEmailToClipboard,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy Email', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Share your doubts, suggestions, or any issues you\'re experiencing. We\'re here to help!',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendEmail() async {
  const email = 'contactgoal4service@gmail.com';
  const subject = 'Goal App - Help & Feedback';
  const body = 'Hi Goal Team,\n\nI would like to:\n\n[Please describe your query, feedback, or issue here]\n\nThanks!';

  final uri = Uri(
    scheme: 'mailto',
    path: email,
    query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );

  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication, // 👈 force external email app
    );

    if (!launched) {
      _copyEmailToClipboard();
      _showSnackBar(
        'Email app not found. Email address copied to clipboard!',
        Colors.orange,
      );
    }
  } catch (e) {
    _copyEmailToClipboard();
    _showSnackBar(
      'Failed to open email app. Email address copied to clipboard!',
      Colors.orange,
    );
  }
}


  Future<void> _copyEmailToClipboard() async {
    const email = 'contactgoal4service@gmail.com';
    await Clipboard.setData(const ClipboardData(text: email));
    _showSnackBar('Email address copied to clipboard!', Colors.green);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: Theme.of(context).cardColor,
              onSurface:
                  Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
            ),
            timePickerTheme: TimePickerThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => selectedTime = picked);
    }
  }

  Future<void> _scheduleDailyReminder() async {
    setState(() => _isProcessing = true);

    try {
      final now = DateTime.now();
      final scheduledTime = DateTime(
        now.year, now.month, now.day, selectedTime.hour, selectedTime.minute);

      await LocalNotificationService.scheduleDailyAtTime(
        id: 100,
        title: '⏰ Quiz Time!',
        body: 'Time to test your knowledge!',
        scheduledTime: scheduledTime,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('reminders_set_up', true);

      final pending = await LocalNotificationService.getPendingNotifications();
      debugPrint('Pending notifications: ${pending.length}');

      _showSnackBar('Reminder set for ${selectedTime.format(context)}!', Colors.green);

      widget.onReminderSet?.call();
      if (mounted) widget.onComplete?.call();
    } catch (e) {
      debugPrint('Error in _scheduleDailyReminder: $e');
      _showSnackBar('Failed to set reminder: ${e.toString()}', Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cancelReminders() async {
    try {
      await LocalNotificationService.cancelAllNotifications();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('reminders_set_up', false);
      _showSnackBar('All reminders cancelled', Colors.orange);
    } catch (e) {
      _showSnackBar('Failed to cancel reminders', Colors.red);
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.largeBanner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isBannerAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('BannerAd failed: $error');
        },
      ),
    )..load();
  }

  void _loadAndShowInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712',
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (_) {
              ad.dispose();
              _interstitialAd = null;
              _loadBannerAd();
              _startInterstitialAdTimer();
            },
          );
          _interstitialAd!.show();
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed: $error');
          _startInterstitialAdTimer();
        },
      ),
    );
  }

  void _startInterstitialAdTimer() {
    _adTimer?.cancel();
    _adTimer = Timer(const Duration(minutes: 2), _loadAndShowInterstitialAd);
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Widget buildAdWidget() {
    if (_isBannerAdLoaded && _bannerAd != null) {
      return Container(
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    } else {
      return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Reminders'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isCheckingPermission
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_hasAskedForPermission || !_permissionGranted)
                          _buildPermissionExplanationCard(),
                        _buildTimePickerSection(),
                        const SizedBox(height: 24),
                        _buildActionButtons(),
                        _buildHelpAndFeedbackSection(),
                      ],
                    ),
                  ),
                ),
                buildAdWidget(),
              ],
            ),
    );
  }
}