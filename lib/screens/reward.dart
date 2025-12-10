import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'SpinWheelScreen.dart';
import 'reward_controller.dart';
import 'reward_service.dart';
import 'ecommerce_store.dart';

class RewardScreen extends StatelessWidget {
  const RewardScreen({super.key});

  Future<void> _ensureWalletExists(String userId) async {
    final walletRef = FirebaseFirestore.instance.collection('wallets').doc(userId);
    await walletRef.set({
      'wallet_balance': 0,
      'withdrawals': [],
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to access rewards')),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('wallets').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Error: ${snapshot.error}')));
        }

        if (snapshot.hasData && !snapshot.data!.exists) {
          _ensureWalletExists(user.uid);
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final walletData = snapshot.data!.data() as Map<String, dynamic>?;
        final walletBalance = (walletData?['wallet_balance'] ?? 0).toDouble();

        return ChangeNotifierProvider(
          create: (_) => RewardController(userId: user.uid)..initialize(walletBalance.toInt()),
          child: Consumer<RewardController>(
            builder: (context, controller, _) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Reward Zone'),
                  centerTitle: true,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => controller.refreshBalance(),
                    ),
                  ],
                ),
                body: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ListView(
                    children: [
                      _buildWalletCard(context, walletBalance.toInt()),
                      const SizedBox(height: 20),
                      _buildSpinSection(context),
                      const SizedBox(height: 30),
                      _buildGoToStoreButton(context),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildWalletCard(BuildContext context, int balance) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Wallet', style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 4),
                Text('₹$balance', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.account_balance_wallet, color: Colors.green, size: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpinSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Earn More by', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Take quizzes & top the leaderboard to win spins!', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSpinButton(context, title: 'Daily Spin', icon: Icons.casino, color: Colors.blue, isSpecial: false),
            _buildSpinButton(context, title: 'Money Spin', icon: Icons.attach_money, color: Colors.purple, isSpecial: true),
          ],
        ),
      ],
    );
  }

  Widget _buildSpinButton(BuildContext context,
      {required String title, required IconData icon, required Color color, required bool isSpecial}) {
    return Consumer<RewardController>(
      builder: (context, controller, _) {
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size(150, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: controller.isProcessing ? null : () => _handleSpinButtonPress(context, controller, isSpecial),
          child: Row(
            mainAxisSize: MainAxisSize.min, 
            children: [
              Icon(icon), 
              const SizedBox(width: 8), 
              Text(title),
              // Show loading indicator if processing
              if (controller.isProcessing) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

Future<void> _handleSpinButtonPress(
    BuildContext context, RewardController controller, bool isSpecial) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    controller.setProcessing(true);

    // Check if special spin is allowed
    if (isSpecial) {
      final isTop100 = await RewardService.isUserInTop100(user.uid);
      if (!isTop100) {
        controller.setProcessing(false);
        if (context.mounted) {
          _showDialog(
            context,
            'Premium Spin',
            'Reach Top 100 in leaderboard to unlock this spin.',
            isError: false,
          );
        }
        return;
      }
    }

    // Show loading dialog
    if (context.mounted) {
      _showLoadingDialog(context, 'Loading rewarded ad...');
    }

    // Load Rewarded Ad
    RewardedAd.load(
      adUnitId: "ca-app-pub-3940256099942544/5224354917", // Test Rewarded ID
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          Navigator.of(context).pop(); // close loading
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              controller.setProcessing(false);
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              controller.setProcessing(false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Failed to show ad")),
              );
            },
          );

          ad.show(
            onUserEarnedReward: (ad, reward) async {
              // User finished ad → go to spin screen
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get();
              final username = userDoc.data()?['username'] ?? 'Anonymous';

              if (context.mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SpinWheelScreen(
                      userId: user.uid,
                      username: username,
                      isSpecialSpin: isSpecial,
                    ),
                  ),
                );
              }
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          Navigator.of(context).pop(); // close loading
          controller.setProcessing(false);
          debugPrint("Rewarded Ad failed: $error");

          // Fallback → still allow spin
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Ad not available, proceeding to spin"),
              backgroundColor: Colors.orange,
            ),
          );

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SpinWheelScreen(
                userId: user.uid,
                username: "Anonymous",
                isSpecialSpin: isSpecial,
              ),
            ),
          );
        },
      ),
    );
  } catch (e) {
    debugPrint('Error in spin button press: $e');
    if (context.mounted) {
      Navigator.of(context).pop(); // close any dialog
    }
    controller.setProcessing(false);
  }
}

  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _showDialog(BuildContext context, String title, String message, {bool isError = false}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: isError ? Colors.red : Colors.blue,
            ),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildGoToStoreButton(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Center(
      child: ElevatedButton.icon(
        onPressed: () {
          if (user != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EcommerceScreen(userId: user.uid, username: ''),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("User not logged in")),
            );
          }
        },
        icon: const Icon(Icons.store),
        label: const Text('Go to PDF Store'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}