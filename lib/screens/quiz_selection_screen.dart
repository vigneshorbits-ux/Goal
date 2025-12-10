import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:goal/screens/quiz_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class QuizSelectionScreen extends StatefulWidget {
  const QuizSelectionScreen({super.key});

  @override
  State<QuizSelectionScreen> createState() => _QuizSelectionScreenState();
}

class _QuizSelectionScreenState extends State<QuizSelectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  int _numberOfQuestions = 10;
  String _username = '';
  String _userId = '';
  bool _isLoading = true;
  bool _errorOccurred = false;
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  String _selectedLanguage = "English"; // 👈 default language

  // Test Ad Unit ID - replace with your actual ad unit ID for production
  final String _adUnitId = Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/2934735716';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fetchUserData();
    _loadAd();
  }

  Future<void> _loadAd() async {
    await MobileAds.instance.initialize();
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        setState(() {
          _username = userDoc.data()?['username'] ?? 'Quiz Master';
          _userId = user.uid;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorOccurred = true;
        _isLoading = false;
      });
    }
  }

  void _startQuiz() {
    if (_username.isEmpty) {
      _showSnack('Please complete your profile to start the quiz');
      return;
    }

    _animationController.forward().then((_) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => QuizScreen(
            numberOfQuestions: _numberOfQuestions,
            username: _username,
            isBattleMode: false,
            language: _selectedLanguage, // 👈 pass selected language
          ),
          transitionsBuilder: (_, a, __, c) =>
              FadeTransition(opacity: a, child: c),
        ),
      );
      _animationController.reset();
    });
  }

  Future<void> _startBattleMode() async {
    try {
      final battleQuery = await FirebaseFirestore.instance
          .collection('battles')
          .where('opponent', isEqualTo: _username)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (battleQuery.docs.isEmpty) {
        _showSnack('No pending battle invites found for you.');
        return;
      }

      final battleData = battleQuery.docs.first.data();
      final battleId = battleQuery.docs.first.id;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuizScreen(
            numberOfQuestions: battleData['questions'].length,
            username: _username,
            isBattleMode: true,
            battleId: battleId,
            opponent: battleData['creator'] ?? '',
            prize: (battleData['prize'] ?? 0).toDouble(),
            language: _selectedLanguage, // 👈 keep consistent
          ),
        ),
      );
    } catch (e) {
      _showSnack('Error loading battle: $e');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Quiz Setup', style: GoogleFonts.poppins()),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorOccurred
              ? _buildErrorState()
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildWelcomeHeader(theme),
                            const SizedBox(height: 32),
                            _buildLanguageSelector(theme, colors), // 👈 new dropdown
                            const SizedBox(height: 32),
                            _buildQuestionCountCard(theme, colors),
                            const SizedBox(height: 32),
                            _buildStartButton(theme, colors),
                            const SizedBox(height: 16),
                            _buildBattleButton(theme, colors),
                          ],
                        ),
                      ),
                    ),
                    if (_isAdLoaded && _bannerAd != null)
                      Container(
                        alignment: Alignment.center,
                        width: _bannerAd!.size.width.toDouble(),
                        height: _bannerAd!.size.height.toDouble(),
                        child: AdWidget(ad: _bannerAd!),
                      ),
                  ],
                ),
    );
  }

  Widget _buildErrorState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load profile',
              style: GoogleFonts.poppins(fontSize: 18),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _fetchUserData,
              child: const Text('Try Again'),
            ),
            if (_isAdLoaded && _bannerAd != null)
              Container(
                margin: const EdgeInsets.only(top: 20),
                alignment: Alignment.center,
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      );

  Widget _buildWelcomeHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome,',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _username,
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'More Questions More Rewards:',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  /// 🔽 Language selector dropdown
  Widget _buildLanguageSelector(ThemeData theme, ColorScheme colors) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Language:', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _selectedLanguage,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'English', child: Text('English')),
                DropdownMenuItem(value: 'Tamil', child: Text('தமிழ்')),
                DropdownMenuItem(value: 'Hindi', child: Text('हिन्दी')),
                DropdownMenuItem(
                  value: 'Other',
                  child: Text(
                    '🌍 Other Languages (Coming Soon...)',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  if (value == 'Other') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Other languages will be available soon!',
                        ),
                      ),
                    );
                  } else {
                    setState(() => _selectedLanguage = value);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCountCard(ThemeData theme, ColorScheme colors) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Questions:', style: theme.textTheme.titleMedium),
                ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.2).animate(
                    CurvedAnimation(
                      parent: _animationController,
                      curve: Curves.easeOut,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_numberOfQuestions',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Slider(
              value: _numberOfQuestions.toDouble(),
              min: 5,
              max: 25,
              divisions: 20,
              label: _numberOfQuestions.toString(),
              onChanged: (value) {
                setState(() => _numberOfQuestions = value.toInt());
                _animationController
                    .forward()
                    .then((_) => _animationController.reverse());
              },
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('5'),
                Text('25'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartButton(ThemeData theme, ColorScheme colors) {
    return ElevatedButton.icon(
      onPressed: _startQuiz,
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(
        'Start Individual Quiz',
        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildBattleButton(ThemeData theme, ColorScheme colors) {
    return OutlinedButton.icon(
      onPressed: _startBattleMode,
      icon: const Icon(Icons.sports_rounded),
      label: Text(
        'Start Battle Mode',
        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(color: colors.primary),
        foregroundColor: colors.primary,
      ),
    );
  }
}
