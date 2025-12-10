import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:provider/provider.dart';

import 'package:goal/screens/reward_controller.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  _AccountScreenState createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _amountController = TextEditingController();

  String? _username;
  String? _email;
  String? _mobile;
  DateTime? _createdAt;
  bool _isLoading = true;
  bool _error = false;

  double _walletBalance = 0.0;
  String? _upiId;
  List<Map<String, dynamic>> _withdrawals = [];
  bool _isWithdrawing = false;

  // Ad related variables
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  InterstitialAd? _interstitialAd;
  Timer? _adTimer;
  bool _isAdInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _initializeMobileAds();
  }

  Future<void> _initializeMobileAds() async {
    await MobileAds.instance.initialize();
    setState(() => _isAdInitialized = true);
    _initializeAds();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _adTimer?.cancel();
    super.dispose();
  }

  void _initializeAds() {
    if (!_isAdInitialized) return;
    
    _loadBannerAd();
    _startInterstitialAdTimer();
  }

  void _loadBannerAd() {
    _bannerAd?.dispose();
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test ad unit ID
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isBannerAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('BannerAd failed: $error');
          // Retry after delay
          Future.delayed(const Duration(seconds: 30), _loadBannerAd);
        },
      ),
    )..load();
  }

  void _loadAndShowInterstitialAd() {
    if (!mounted || !_isAdInitialized) return;
    
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1033173712', // Test ad unit ID
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (_) {
              ad.dispose();
              _interstitialAd = null;
              _startInterstitialAdTimer();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _startInterstitialAdTimer();
            },
          );
          if (mounted) {
            ad.show();
          } else {
            ad.dispose();
          }
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
    _adTimer = Timer(const Duration(minutes: 3), _loadAndShowInterstitialAd);
  }

  Widget _buildAdWidget() {
    if (!_isAdInitialized || !_isBannerAdLoaded || _bannerAd == null) {
      return const SizedBox();
    }
    
    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  Future<void> _loadUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final results = await Future.wait([
        _firestore.collection('users').doc(user.uid).get(),
        _firestore.collection('wallets').doc(user.uid).get(),
      ]);

      final userDoc = results[0];
      final walletDoc = results[1];

      if (mounted) {
        setState(() {
          _email = user.email;
          _mobile = userDoc.data()?['mobile'] ?? 'Not provided';
          _createdAt = userDoc.data()?['createdAt']?.toDate();
          _walletBalance = walletDoc.data()?['wallet_balance']?.toDouble() ?? 0.0;
          _upiId = walletDoc.data()?['upi_id'];
          _withdrawals = List<Map<String, dynamic>>.from(walletDoc.data()?['withdrawals'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout, color: Colors.red, size: 32),
        title: const Text('Confirm Sign Out'),
        content: const Text('Are you sure you want to sign out? You will need to log in again to access your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out', 
                style: TextStyle(color: Colors.red, fontSize: 16)),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    // Show loading indicator
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: Colors.white),
            ),
            SizedBox(width: 16),
            Text('Signing out...'),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      // Dispose ads before logging out
      _bannerAd?.dispose();
      _interstitialAd?.dispose();
      _adTimer?.cancel();

      await _auth.signOut();
      
      if (mounted) {
        messenger.hideCurrentSnackBar();
        // Navigate to auth screen and remove all routes
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/AuthScreen', // Make sure this route exists in your app
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Sign out failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }


  Future<void> _sendWithdrawalEmail(double amount, String upiId) async {
    const username = 'goalwithdraw@gmail.com';
    const password = 'ONEtime@123';
    const recipient = 'goalwithdraw@gmail.com';

    final smtpServer = gmail(username, password);

    final message = Message()
      ..from = const Address(username, 'App Withdrawal System')
      ..recipients.add(recipient)
      ..subject = 'New Withdrawal Request'
      ..text = '''
New withdrawal request:
User: $_email
UPI ID: $upiId
Amount: ₹$amount
Requested at: ${DateTime.now()}
''';

    try {
      await send(message, smtpServer);
    } catch (e) {
      debugPrint('Error sending email: $e');
    }
  }

  Future<void> _withdrawFunds() async {
    if (_upiId == null || _upiId!.isEmpty || !_upiId!.contains('@')) {
      _showErrorSnackbar("Please enter a valid UPI ID");
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount < 200) {
      _showErrorSnackbar("Minimum withdrawal amount is ₹500");
      return;
    }

    if (amount > 999) {
      _showErrorSnackbar("Maximum withdrawal amount is ₹999");
      return;
    }

    if (amount > _walletBalance) {
      _showErrorSnackbar("Insufficient balance");
      return;
    }

    final hundredDaysAgo = DateTime.now().subtract(const Duration(days: 100));
    final recentWithdrawals = _withdrawals.where((w) {
      final date = (w['date'] as Timestamp).toDate();
      return date.isAfter(hundredDaysAgo) && w['status'] != 'rejected';
    }).length;

    if (recentWithdrawals >= 2) {
      _showErrorSnackbar("You can only withdraw 2 times in 100 days");
      return;
    }

    if (mounted) {
      setState(() => _isWithdrawing = true);
    }

    try {
      final uid = _auth.currentUser!.uid;
      final walletRef = _firestore.collection('wallets').doc(uid);
      final newBalance = _walletBalance - amount;

      final withdrawalData = {
        'amount': amount,
        'date': Timestamp.now(),
        'status': 'pending',
        'upi_id': _upiId,
      };

      await _firestore.runTransaction((transaction) async {
        transaction.update(walletRef, {
          'wallet_balance': newBalance,
          'withdrawals': FieldValue.arrayUnion([withdrawalData]),
        });
      });

      await _sendWithdrawalEmail(amount, _upiId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Withdrawal request submitted successfully")),
        );
      }

      setState(() {
        _walletBalance = newBalance;
        _withdrawals.add(withdrawalData);
        _amountController.clear();
        final rewardController = Provider.of<RewardController?>(context, listen: false);
        rewardController?.refreshBalance();
      });
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar("Failed to request withdrawal: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isWithdrawing = false);
      }
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildCompactInfoCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.email, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _email ?? 'Not available',
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.phone, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(_mobile ?? 'Not provided', style: const TextStyle(fontSize: 14)),
                const Spacer(),
                Icon(Icons.calendar_today, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  _createdAt != null ? DateFormat('MMM yyyy').format(_createdAt!) : 'Unknown',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawalHistory() {
    if (_withdrawals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text("No withdrawal history", style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text("Withdrawal History", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        ..._withdrawals.reversed.take(3).map((withdrawal) { // Show only last 3 withdrawals
          final date = (withdrawal['date'] as Timestamp).toDate();
          final status = withdrawal['status'] ?? 'pending';
          Color statusColor = Colors.orange;
          if (status == 'completed') statusColor = Colors.green;
          if (status == 'rejected') statusColor = Colors.red;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              title: Text("₹${(withdrawal['amount'] as num).toStringAsFixed(0)}", 
                         style: const TextStyle(fontSize: 14)),
              subtitle: Text(DateFormat('MMM dd, yyyy').format(date), 
                           style: const TextStyle(fontSize: 11)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        }),
        if (_withdrawals.length > 3)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton(
              onPressed: () {
                // Show all withdrawals in a dialog or new screen
                _showAllWithdrawals();
              },
              child: Text('View all ${_withdrawals.length} withdrawals'),
            ),
          ),
      ],
    );
  }

  void _showAllWithdrawals() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("All Withdrawal History", 
                     style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _withdrawals.length,
                itemBuilder: (context, index) {
                  final withdrawal = _withdrawals.reversed.toList()[index];
                  final date = (withdrawal['date'] as Timestamp).toDate();
                  final status = withdrawal['status'] ?? 'pending';
                  Color statusColor = Colors.orange;
                  if (status == 'completed') statusColor = Colors.green;
                  if (status == 'rejected') statusColor = Colors.red;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text("₹${(withdrawal['amount'] as num).toStringAsFixed(2)}"),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('MMM dd, yyyy - hh:mm a').format(date)),
                          if (withdrawal['upi_id'] != null)
                            Text('UPI: ${withdrawal['upi_id']}', 
                                 style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Wallet Balance", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text("₹${_walletBalance.toStringAsFixed(2)}",
                    style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _upiId ?? '',
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'UPI ID (e.g., user@paytm)',
                prefixIcon: Icon(Icons.account_balance_wallet),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (val) => _upiId = val.trim(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Amount (₹500-₹999)',
                prefixIcon: Icon(Icons.currency_rupee),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isWithdrawing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance, size: 18),
                label: Text(_isWithdrawing ? "Processing..." : "Request Withdrawal",
                           style: const TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isWithdrawing ? null : _withdrawFunds,
              ),
            ),
            if (_walletBalance < 500)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text("Minimum ₹500 required to withdraw", 
                           style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Profile'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('Failed to load profile data'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _loadUserData,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            // Compact profile header
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [theme.primaryColor.withOpacity(0.1), Colors.transparent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundColor: theme.primaryColor.withOpacity(0.2),
                                    child: Icon(Icons.person, size: 30, color: theme.primaryColor),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _email?.split('@')[0] ?? 'User',
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Wallet: ₹${_walletBalance.toStringAsFixed(0)}',
                                          style: TextStyle(fontSize: 14, color: Colors.green.shade700),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildAdWidget(), // First ad placement
                            _buildCompactInfoCard(),
                            _buildWalletSection(),
                            _buildAdWidget(), // Second ad placement
                            _buildWithdrawalHistory(),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.logout, size: 18),
                                  label: const Text('Sign Out'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: _logout,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    _buildAdWidget(), // Bottom banner ad
                  ],
                ),
    );
  }
}