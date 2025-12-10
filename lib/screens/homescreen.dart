import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:goal/screens/ecommerce_store.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:iconsax/iconsax.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  const HomeScreen({super.key, required this.username});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late String username;
  bool isLoading = true;
  late BannerAd _bannerAd;
  bool _isBannerAdReady = false;
  bool _isPopupShown = false;
  bool _leaderboardAdShown = false;

  InterstitialAd? _interstitialAd;

  @override
  void initState() {
    super.initState();
    _fetchUsername();
    _loadBannerAd();
    _loadInterstitialAd();
    Future.delayed(const Duration(milliseconds: 500), _showRewardPopup);
  }

  void _showRewardPopup() {
    if (!_isPopupShown) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Earn Rewards! 🎉"),
          content: const Text(
              "Take daily quizzes to earn points and keep your streak alive for bigger rewards!"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Later"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/quizSelection');
              },
              child: const Text("Start Quiz"),
            ),
          ],
        ),
      );
      _isPopupShown = true;
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdReady = true),
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
      size: AdSize.banner,
    );
    _bannerAd.load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712', // Test ID
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) => _interstitialAd = null,
      ),
    );
  }

  void _showLeaderboardWithAd() {
    if (!_leaderboardAdShown && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback =
          FullScreenContentCallback(onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _leaderboardAdShown = true;
        Navigator.pushNamed(context, '/leaderboard');
        _loadInterstitialAd();
      }, onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _leaderboardAdShown = true;
        Navigator.pushNamed(context, '/leaderboard');
        _loadInterstitialAd();
      });
      _interstitialAd!.show();
    } else {
      Navigator.pushNamed(context, '/leaderboard');
    }
  }

  void _showStoreWithAd() {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback =
          FullScreenContentCallback(onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EcommerceScreen(
              userId: FirebaseAuth.instance.currentUser!.uid,
              username: username,
            ),
          ),
        );
        _loadInterstitialAd();
      }, onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EcommerceScreen(
              userId: FirebaseAuth.instance.currentUser!.uid,
              username: username,
            ),
          ),
        );
        _loadInterstitialAd();
      });
      _interstitialAd!.show();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EcommerceScreen(
            userId: FirebaseAuth.instance.currentUser!.uid,
            username: username,
          ),
        ),
      );
    }
  }

  Future<void> _fetchUsername() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        setState(() {
          username = userDoc.exists ? userDoc['username'] ?? 'User' : 'User';
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching username: $e');
      setState(() {
        username = 'User';
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.notifications_active),
          tooltip: 'Reminder Settings',
          onPressed: () => Navigator.pushNamed(context, '/reminders'),
        ),
        title: Text(
          'Goal',
          style:
              theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'PDF Store',
            onPressed: () {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                _showStoreWithAd();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("User not logged in")),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Refer a Friend',
            onPressed: () => Navigator.pushNamed(context, '/referral'),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            tooltip: 'Account',
            onPressed: () => Navigator.pushNamed(context, '/account'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWelcomeHeader(theme),
                  const SizedBox(height: 32),
                  Expanded(child: _buildCustomGrid(context)),
                  if (_isBannerAdReady)
                    SizedBox(height: 50, child: AdWidget(ad: _bannerAd)),
                ],
              ),
      ),
    );
  }

  Widget _buildWelcomeHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welcome back,',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.8))),
        const SizedBox(height: 4),
        Text(username,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            )),
      ],
    );
  }

  Widget _buildCustomGrid(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
                child: _FeatureCard(
                    label: 'Live',
                    icon: Icons.announcement,
                    route: '/announcements')),
            SizedBox(width: 16),
            Expanded(
                child: _FeatureCard(
                    label: 'Daily Quiz',
                    icon: Icons.quiz,
                    route: '/quizSelection')),
          ],
        ),
        const SizedBox(height: 16),
        const _BattleFeatureCard(),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
                child: _FeatureCard(
                    label: 'Rewards',
                    icon: Icons.card_giftcard,
                    route: '/rewards')),
            const SizedBox(width: 16),
            Expanded(
              child: _FeatureCard(
                label: 'Leaderboard',
                icon: Icons.leaderboard,
                onTap: () => _showLeaderboardWithAd(), // ✅ FIX
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// 🔹 FeatureCard supports either route or custom onTap
class _FeatureCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? route;
  final VoidCallback? onTap;

  const _FeatureCard({
    required this.label,
    required this.icon,
    this.route,
    this.onTap,
  });

  List<Color> _getGradientColors() {
    switch (label) {
      case 'Live':
        return [Colors.indigo, Colors.blueAccent];
      case 'Daily Quiz':
        return [Colors.teal, Colors.greenAccent];
      case 'Rewards':
        return [Colors.orange, Colors.deepOrangeAccent];
      case 'Leaderboard':
        return [Colors.cyan, Colors.lightBlueAccent];
      default:
        return [Colors.grey, Colors.blueGrey];
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = _getGradientColors();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap ??
              () {
                if (route != null) {
                  Navigator.pushNamed(context, route!);
                }
              },
          splashColor: Colors.white24,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32, color: Colors.white),
                const SizedBox(height: 12),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BattleFeatureCard extends StatelessWidget {
  const _BattleFeatureCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.deepPurple, Colors.purpleAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.pushNamed(context, '/battle'),
            splashColor: Colors.white24,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Iconsax.award, size: 40, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(
                    'Battle',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'More battles, more money 💰',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
