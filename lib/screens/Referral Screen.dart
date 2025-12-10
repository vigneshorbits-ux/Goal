import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? userData;
  List<Map<String, dynamic>> referrals = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Get user data
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        userData = userDoc.data();

        // Get user's referrals
        final referralsSnapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('referrals')
            .orderBy('referredAt', descending: true)
            .get();

        referrals = referralsSnapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList();
      }
    } catch (e) {
      _showSnackbar('Error loading data: ${e.toString()}', isError: true);
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _copyReferralEmail() async {
    if (userData?['email'] != null) {
      await Clipboard.setData(ClipboardData(text: userData!['email']));
      _showSnackbar('Referral email copied to clipboard!');
    }
  }

  Future<void> _shareReferralEmail() async {
    if (userData?['email'] != null) {
          const playStoreLink = 'https://play.google.com/store/apps/details?id=com.shadowbird.goal/'; 
      final message = '''
🎁 Join me on this amazing learning app!

Use my email as referral code: ${userData!['email']}

You'll get a special spin bonus when you sign up! 🎰

Download the app now and start Earning!$playStoreLink
      '''.trim();

      await Share.share(message, subject: 'Join me on our Learn and Earn app!');
    }
  }

  Future<void> _claimSpecialSpin() async {
    try {
      final user = _auth.currentUser;
      if (user != null && userData?['hasSpecialSpin'] == true) {
        // Update user's special spin status
        await _firestore.collection('users').doc(user.uid).update({
          'specialSpinUsed': true,
        });

        // Navigate to spin screen or show spin dialog
        _showSpinDialog();
        
        // Refresh data
        _loadUserData();
      }
    } catch (e) {
      _showSnackbar('Error claiming spin: ${e.toString()}', isError: true);
    }
  }

  void _showSpinDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('🎰 Special Spin!'),
        content: const Text('You have unlocked a special spin! This would navigate to your spin screen.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Navigate to actual spin screen
              // Navigator.pushNamed(context, '/spin');
            },
            child: const Text('Spin Now!'),
          ),
        ],
      ),
    );
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : Colors.green.shade800,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Referral Program',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSpecialSpinCard(theme),
                  const SizedBox(height: 20),
                  _buildReferralStatsCard(theme),
                  const SizedBox(height: 20),
                  _buildShareSection(theme),
                  const SizedBox(height: 20),
                  _buildReferralsList(theme),
                ],
              ),
            ),
    );
  }

  Widget _buildSpecialSpinCard(ThemeData theme) {
    final hasSpecialSpin = userData?['hasSpecialSpin'] == true;
    final spinUsed = userData?['specialSpinUsed'] == true;

    if (!hasSpecialSpin) return const SizedBox.shrink();

    return Card(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withOpacity(0.8),
            ],
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.casino,
              size: 48,
              color: Colors.white,
            ),
            const SizedBox(height: 12),
            Text(
              spinUsed ? 'Special Spin Used!' : 'Special Spin Available!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              spinUsed 
                  ? 'You have already used your special spin bonus!'
                  : 'You have earned a special spin! Claim it now for bonus rewards.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            if (!spinUsed) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _claimSpecialSpin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text(
                  'Claim Spin',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReferralStatsCard(ThemeData theme) {
    final referralCount = userData?['referralCount'] ?? 0;
    final rewards = userData?['rewards'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Referral Stats',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Total Referrals',
                    referralCount.toString(),
                    Icons.people,
                    theme,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Total Rewards',
                    rewards.toString(),
                    Icons.star,
                    theme,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, ThemeData theme) {
    return Column(
      children: [
        Icon(
          icon,
          size: 32,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildShareSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share Your Referral',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your friends can use your email as a referral code to get special bonuses!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      userData?['email'] ?? '',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _copyReferralEmail,
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy to clipboard',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _shareReferralEmail,
                                        icon: const Icon(Icons.share),
                    label: const Text('Share via...'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralsList(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your Referrals',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Total: ${referrals.length}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (referrals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 48,
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No referrals yet',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Share your referral code to invite friends!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: referrals.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final referral = referrals[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                      child: Icon(
                        Icons.person,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      referral['email'] ?? 'Unknown',
                      style: theme.textTheme.bodyLarge,
                    ),
                    subtitle: Text(
                      'Joined ${_formatDate(referral['referredAt']?.toDate())}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Icon(
                      Icons.check_circle,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown date';
    return '${date.day}/${date.month}/${date.year}';
  }
}