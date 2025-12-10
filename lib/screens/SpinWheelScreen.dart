import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fortune_wheel/flutter_fortune_wheel.dart';

class SpinWheelScreen extends StatefulWidget {
  final String userId;
  final String username;
  final bool isSpecialSpin;

  const SpinWheelScreen({
    required this.userId,
    required this.username,
    required this.isSpecialSpin,
    super.key,
  });

  @override
  State<SpinWheelScreen> createState() => _SpinWheelScreenState();
}

class _SpinWheelScreenState extends State<SpinWheelScreen> with TickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;
  final _controller = StreamController<int>();
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  late final AnimationController _pulseController;

  final _normalRewards = [
    WheelItem('5 pts', Colors.blueAccent, Icons.star),
    WheelItem('10 pts', Colors.greenAccent, Icons.star),
    WheelItem('Coupon', Colors.orangeAccent, Icons.local_offer),
    WheelItem('Try Again', Colors.grey, Icons.refresh),
    WheelItem('20 pts', Colors.purpleAccent, Icons.bolt),
    WheelItem('15 pts', Colors.tealAccent, Icons.star),
  ];

  final _specialRewards = [
    WheelItem('₹10', Colors.amberAccent, Icons.money),
    WheelItem('₹20', Colors.tealAccent, Icons.money),
    WheelItem('₹25', Colors.redAccent, Icons.money),
    WheelItem('₹10', Colors.greenAccent, Icons.money),
    WheelItem('₹25', Colors.deepPurpleAccent, Icons.money),
    WheelItem('₹5', Colors.grey, Icons.refresh),
  ];

  List<WheelItem> _currentRewards = [];
  bool _isLoading = true;
  bool _canSpin = false;
  bool _isSpecial = false;
  bool _isSpinning = false;
  String? _lastReward;
  String? _spinStatusMessage;
  int _consecutiveDays = 0;
  bool _showStreakBonus = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _checkSpinEligibility();
  }

  Future<void> _checkSpinEligibility() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startOfWeek = _getStartOfWeek(now);
      
      // Get user's spin history
      final spinDoc = await _firestore.collection('spin_history').doc(widget.userId).get();
      final lastSpin = spinDoc.data()?['lastSpin'] as Timestamp?;
      final lastSpecialSpin = spinDoc.data()?['lastSpecialSpin'] as Timestamp?;
      final lastSpinDate = lastSpin?.toDate();
      final lastSpecialSpinDate = lastSpecialSpin?.toDate();
      
      // Check if user spun today
      final spunToday = lastSpinDate != null && _isSameDay(lastSpinDate, now);
      _lastReward = spinDoc.data()?['reward'] as String?;
      
      // Check consecutive days
      _consecutiveDays = await _checkConsecutiveDays(spinDoc.data());

      // Check leaderboard position for special spin
      final isEligibleForSpecialSpin = await _checkSpecialSpinEligibility(
        startOfWeek, 
        lastSpecialSpinDate,
        widget.isSpecialSpin
      );

      setState(() {
        _isSpecial = widget.isSpecialSpin || isEligibleForSpecialSpin;
        _canSpin = !spunToday;
        _currentRewards = _isSpecial ? _specialRewards : _normalRewards;
        _spinStatusMessage = _getSpinStatusMessage(
          spunToday, 
          isEligibleForSpecialSpin,
          _consecutiveDays
        );
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error checking spin eligibility: $e");
      _showError("Could not check eligibility. Try again later.");
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkSpecialSpinEligibility(
    DateTime startOfWeek, 
    DateTime? lastSpecialSpinDate,
    bool isSpecialSpin
  ) async {
    if (isSpecialSpin) return true;
    
    // Check if user is in top 100
    final topUsers = await _firestore
        .collection('leaderboard')
        .orderBy('score', descending: true)
        .limit(100)
        .get();
    final isTop100 = topUsers.docs.any((doc) => doc.id == widget.userId);
    
    // Check if weekly special spin is available
    final canSpecialSpin = lastSpecialSpinDate == null || 
                        !lastSpecialSpinDate.isAfter(startOfWeek);
    
    return isTop100 && canSpecialSpin;
  }

  Future<int> _checkConsecutiveDays(Map<String, dynamic>? spinData) async {
    if (spinData == null || spinData['lastSpin'] == null) return 0;
    
    final now = DateTime.now();
    final lastSpinDate = (spinData['lastSpin'] as Timestamp).toDate();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    
    if (_isSameDay(lastSpinDate, yesterday)) {
      return (spinData['consecutiveDays'] as int? ?? 0) + 1;
    } else if (!_isSameDay(lastSpinDate, now)) {
      return 0; // Reset if missed a day
    }
    return spinData['consecutiveDays'] as int? ?? 0;
  }

  String _getSpinStatusMessage(bool spunToday, bool isEligibleForSpecial, int streak) {
    if (spunToday) {
      return "Come back tomorrow for another spin!";
    }
    
    if (_isSpecial) {
      return isEligibleForSpecial 
          ? "🌟 Weekly Special Spin Available!" 
          : "🌟 Bonus Special Spin!";
    }
    
    if (streak > 0) {
      return "🔥 $streak-day streak! Spin to keep it going!";
    }
    
    return "Daily spin available!";
  }

  DateTime _getStartOfWeek(DateTime date) {
    // Returns Monday of current week at 00:00
    return date.subtract(Duration(days: date.weekday - 1)).copyWith(
      hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _spinWheel() async {
    if (_isSpinning || !_canSpin) return;

    setState(() => _isSpinning = true);
    _animationController.forward();

    // Determine reward with weighted probabilities
    final selected = _getWeightedRandomIndex();
    _controller.add(selected);

    await Future.delayed(const Duration(seconds: 5));
    final reward = _currentRewards[selected].text;
    final rewardValue = _parseRewardValue(reward);

    try {
      await _saveSpinResult(reward);
      await _handleReward(reward, rewardValue);

      // Check for streak bonus
      if (_consecutiveDays >= 3 && !_isSpecial) {
        final bonus = _calculateStreakBonus(_consecutiveDays);
        if (bonus > 0) {
          await _updateLeaderboard(bonus);
          setState(() => _showStreakBonus = true);
        }
      }

      if (!mounted) return;
      await _showResultDialog(reward, rewardValue);
    } catch (e) {
      debugPrint("Error during spin: $e");
      _showError("Something went wrong during spin. Try again.");
    } finally {
      if (mounted) {
        setState(() {
          _isSpinning = false;
          _canSpin = false;
          _animationController.reverse();
        });
      }
    }
  }

  int _getWeightedRandomIndex() {
    // Higher probability for lower value rewards
    final weights = _currentRewards.map((item) {
      if (item.text.contains('5 pts') || item.text.contains('₹5')) return 0.3;
      if (item.text.contains('5 pts') || item.text.contains('₹10')) return 0.2;
      if (item.text.contains('10 pts') || item.text.contains('₹20')) return 0.15;
      if (item.text.contains('15 pts') || item.text.contains('₹25')) return 0.1;
      return 0.05; // For highest value rewards
    }).toList();

    final sum = weights.reduce((a, b) => a + b);
    final random = Random().nextDouble() * sum;
    
    double cumulative = 0;
    for (int i = 0; i < weights.length; i++) {
      cumulative += weights[i];
      if (random < cumulative) return i;
    }
    
    return 0; // fallback
  }

  int _parseRewardValue(String reward) {
    if (reward.endsWith('pts')) {
      return int.tryParse(reward.split(' ').first) ?? 0;
    } else if (reward.startsWith('₹')) {
      return int.tryParse(reward.replaceAll('₹', '')) ?? 0;
    }
    return 0; // For coupons or other non-point rewards
  }

  int _calculateStreakBonus(int streak) {
    if (streak >= 7) return 50;
    if (streak >= 5) return 30;
    if (streak >= 3) return 15;
    return 0;
  }

  Future<void> _saveSpinResult(String reward) async {
    final now = Timestamp.now();
    final data = {
      'lastSpin': now,
      'reward': reward,
      'isSpecialSpin': _isSpecial,
      'consecutiveDays': _consecutiveDays + 1,
      'username': widget.username,
    };
    
    if (_isSpecial) {
      data['lastSpecialSpin'] = now;
    }

    await _firestore.collection('spin_history').doc(widget.userId).set(data);
  }

  Future<void> _handleReward(String reward, int value) async {
    if (value > 0) {
      if (reward.endsWith('pts')) {
        await _updateLeaderboard(value);
      } else if (reward.startsWith('₹')) {
        await _updateWallet(value);
      }
    }
  }

  Future<void> _updateLeaderboard(int points) async {
    final ref = _firestore.collection('leaderboard').doc(widget.userId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final currentScore = snapshot.exists ? (snapshot.data()?['score'] ?? 0) : 0;
      transaction.set(ref, {
        'score': currentScore + points,
        'timestamp': FieldValue.serverTimestamp(),
        'username': widget.username,
      }, SetOptions(merge: true));
    });
  }

  Future<void> _updateWallet(int amount) async {
    final ref = _firestore.collection('wallets').doc(widget.userId);
    await ref.set({
      'wallet_balance': FieldValue.increment(amount),
      'last_updated': FieldValue.serverTimestamp(),
      'username': widget.username,
    }, SetOptions(merge: true));
    
    // Record transaction
    await _firestore.collection('transactions').add({
      'userId': widget.userId,
      'amount': amount,
      'type': 'spin_reward',
      'timestamp': FieldValue.serverTimestamp(),
      'description': 'Won in spin wheel',
    });
  }

  Future<void> _showResultDialog(String reward, int value) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScaleTransition(
        scale: _scaleAnimation,
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: AlertDialog(
            backgroundColor: Colors.white.withOpacity(0.95),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Colors.amber, width: 2),
            ),
            title: Center(
              child: Text(
                "🎉 Congratulations!",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.celebration,
                  color: Colors.amber,
                  size: 60,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "You won: $reward",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_showStreakBonus && !_isSpecial)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            "+${_calculateStreakBonus(_consecutiveDays)} pts streak bonus!",
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Claim",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text("Error"),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  // Helper method to build earn spin options
  Widget _buildEarnSpinOption({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: Colors.amber.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.close();
    _animationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    final wheelSize = min(size.width, size.height) * 0.8;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSpecial ? '🌟 Special Spin' : '🎡 Daily Spin'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: _isSpecial 
          ? Colors.deepPurple.withOpacity(0.8)
          : colors.primary.withOpacity(0.8),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Checking spin eligibility..."),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Status information
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isSpecial ? Colors.amber : colors.primary,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          if (_lastReward != null)
                            Text(
                              "Last Reward: $_lastReward",
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            _spinStatusMessage ?? "",
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _canSpin ? colors.primary : colors.onSurface.withOpacity(0.7),
                            ),
                          ),
                          if (_consecutiveDays > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.local_fire_department, 
                                    color: Colors.orange, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    "$_consecutiveDays-day streak",
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Wheel with indicator
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: wheelSize,
                          height: wheelSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: colors.primary.withOpacity(0.2),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: FortuneWheel(
                            selected: _controller.stream,
                            items: [
                              for (var item in _currentRewards)
                                FortuneItem(
                                  child: _WheelItemWidget(item: item),
                                  style: FortuneItemStyle(
                                    color: item.color,
                                    borderColor: Colors.white,
                                    borderWidth: 2,
                                  ),
                                ),
                            ],
                            animateFirst: false,
                            physics: CircularPanPhysics(
                              duration: const Duration(seconds: 5),
                              curve: Curves.decelerate,
                            ),
                            onAnimationStart: () => setState(() => _isSpinning = true),
                            onAnimationEnd: () => setState(() => _isSpinning = false),
                          ),
                        ),
                        // Indicator arrow
                        Positioned(
                          top: -10,
                          child: Icon(
                            Icons.arrow_drop_down,
                            size: 60,
                            color: colors.primary,
                          ),
                        ),
                        // Center decoration
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // Spin button
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _isSpinning
                          ? Column(
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  "Spinning...",
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ],
                            )
                          : ScaleTransition(
                              scale: _canSpin 
                                ? Tween(begin: 0.95, end: 1.0).animate(_pulseController)
                                : const AlwaysStoppedAnimation(1.0),
                              child: ElevatedButton(
                                key: ValueKey(_canSpin),
                                onPressed: _canSpin ? _spinWheel : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _canSpin
                                      ? (_isSpecial ? Colors.deepPurple : colors.primary)
                                      : colors.surfaceContainerHighest,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(size.width * 0.6, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  elevation: 5,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32, vertical: 16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _canSpin ? Icons.autorenew : Icons.lock,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _canSpin 
                                        ? (_isSpecial ? "SPECIAL SPIN" : "SPIN NOW")
                                        : "SPIN UNAVAILABLE",
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),

                    // Earn More Spins Section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colors.primary,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "EARN MORE SPINS",
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildEarnSpinOption(
                            icon: Icons.quiz,
                            title: "Take More Quizzes",
                            description: "Complete 3 quizzes to earn an extra spin",
                          ),
                          const SizedBox(height: 12),
                          _buildEarnSpinOption(
                            icon: Icons.leaderboard,
                            title: "Top the Leaderboard",
                            description: "Finish in top 100 weekly for special spins",
                          ),
                          const SizedBox(height: 12),
                          _buildEarnSpinOption(
                            icon: Icons.calendar_today,
                            title: "Daily Streak Bonus",
                            description: "Spin daily to earn bonus points",
                          ),
                        ],
                      ),
                    ),

                    // Weekly Reset Information
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Weekly leaderboard resets every Sunday at midnight. "
                              "Daily quiz bonuses are added to your spin rewards.",
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _WheelItemWidget extends StatelessWidget {
  final WheelItem item;

  const _WheelItemWidget({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            item.text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class WheelItem {
  final String text;
  final Color color;
  final IconData icon;

  WheelItem(this.text, this.color, this.icon);
}