import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class BattleActiveScreen extends StatefulWidget {
  final String battleId;

  const BattleActiveScreen({super.key, required this.battleId});

  @override
  _BattleActiveScreenState createState() => _BattleActiveScreenState();
}

enum BattleState {
  loading,
  waitingForOpponent,
  inProgress,
  completed,
  expired,
  error
}

class _BattleActiveScreenState extends State<BattleActiveScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late StreamSubscription<DocumentSnapshot> _battleSubscription;
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  // Battle state management
  BattleState _battleState = BattleState.loading;
  Map<String, dynamic>? _battleData;
  int _currentQuestionIndex = 0;
  String? _selectedAnswer;
  bool _hasAnswered = false;
  int _score = 0;
  List<Map<String, dynamic>> _questions = [];
  final Map<int, String?> _userAnswers = {};
  bool _isSubmitting = false;
  bool _isInTieBreaker = false;
  int _tieBreakerScore = 0;
  bool _hasJoined = false;
  Timer? _countdownTimer;
  int _timeRemaining = 780; // 13 minutes in seconds
  bool _opponentJoined = false;
  String? _opponentId;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser?.uid;
    _loadBattleData();
    _loadAd();
    _joinBattle();
  }

  Future<void> _loadAd() async {
    try {
      _bannerAd = BannerAd(
        size: AdSize.banner,
        adUnitId: 'ca-app-pub-3940256099942544/6300978111',
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            setState(() {
              _isAdLoaded = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint('Ad failed to load: $error');
            ad.dispose();
          },
        ),
        request: const AdRequest(),
      );
      await _bannerAd?.load();
    } catch (e) {
      debugPrint('Error loading ad: $e');
    }
  }

  Future<void> _joinBattle() async {
    if (_currentUserId == null) return;

    try {
      await _firestore.collection('battles').doc(widget.battleId).update({
        'userJoinTimes.$_currentUserId': FieldValue.serverTimestamp(),
      });
      setState(() {
        _hasJoined = true;
      });
    } catch (e) {
      debugPrint('Error joining battle: $e');
      _setBattleState(BattleState.error);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        setState(() {
          _timeRemaining--;
        });
      } else {
        timer.cancel();
        _timeUp();
      }
    });
  }

  void _timeUp() {
    if (_battleState == BattleState.inProgress && !_isInTieBreaker) {
      _completeBattle();
    } else if (_isInTieBreaker) {
      _completeTieBreaker();
    }
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _loadBattleData() async {
    try {
      _battleSubscription = _firestore
          .collection('battles')
          .doc(widget.battleId)
          .snapshots()
          .listen((snapshot) async {
        if (!snapshot.exists) {
          _showError('Battle not found');
          Navigator.pop(context);
          return;
        }

        final data = snapshot.data()!;
        _processBattleData(data);
      });
    } catch (e) {
      debugPrint('Error loading battle data: $e');
      _setBattleState(BattleState.error);
    }
  }

  void _processBattleData(Map<String, dynamic> data) {
    setState(() {
      _battleData = data;
      _questions = List<Map<String, dynamic>>.from(data['questions'] ?? []);
      _isInTieBreaker = data['isInTieBreaker'] ?? false;
      
      // Determine opponent ID
      _opponentId = _currentUserId == data['creatorId'] 
          ? data['opponentId'] 
          : data['creatorId'];

      // Check opponent join status
      final userJoinTimes = Map<String, dynamic>.from(data['userJoinTimes'] ?? {});
      _opponentJoined = userJoinTimes.containsKey(_opponentId);
    });

    // Update battle state based on current conditions
    _updateBattleState(data);

    // Show real-time notifications
    _showRealTimeNotifications(data);

    // Start countdown when both users join
    if (_hasJoined && _opponentJoined && _countdownTimer == null) {
      _startCountdown();
    }

    // Handle tie-breaker initiation
    if (data['isInTieBreaker'] == true && !_isInTieBreaker) {
      _initiateTieBreaker();
    }
  }

  void _updateBattleState(Map<String, dynamic> data) {
    final status = data['status'];
    final completedUsers = List<String>.from(data['completedUsers'] ?? []);
    final tieBreakerCompleted = List<String>.from(data['tieBreakerCompletedUsers'] ?? []);

    if (status == 'completed' || status == 'expired') {
      _setBattleState(BattleState.completed);
      _handleBattleEnd();
      return;
    }

    if (!_opponentJoined) {
      _setBattleState(BattleState.waitingForOpponent);
      return;
    }

    if (_isUserCompleted(completedUsers, tieBreakerCompleted)) {
      _setBattleState(BattleState.waitingForOpponent); // Waiting for opponent to finish
      return;
    }

    _setBattleState(BattleState.inProgress);
  }

  bool _isUserCompleted(List<String> completedUsers, List<String> tieBreakerCompleted) {
    if (_isInTieBreaker) {
      return tieBreakerCompleted.contains(_currentUserId) || _currentQuestionIndex >= 18;
    } else {
      return completedUsers.contains(_currentUserId) || _currentQuestionIndex >= 15;
    }
  }

  void _setBattleState(BattleState state) {
    if (mounted) {
      setState(() {
        _battleState = state;
      });
    }
  }

  void _showRealTimeNotifications(Map<String, dynamic> data) {
    final completedUsers = List<String>.from(data['completedUsers'] ?? []);
    final tieBreakerCompleted = List<String>.from(data['tieBreakerCompletedUsers'] ?? []);

    // Check if opponent just joined
    final userJoinTimes = Map<String, dynamic>.from(data['userJoinTimes'] ?? {});
    if (userJoinTimes.containsKey(_opponentId) && !_opponentJoined) {
      _showNotification('🔥 Opponent joined the battle!', Colors.green);
    }

    // Check if opponent completed
    if (completedUsers.contains(_opponentId)) {
      _showNotification('⚡ Opponent finished the quiz!', Colors.orange);
    }

    // Check if opponent completed tie-breaker
    if (_isInTieBreaker && tieBreakerCompleted.contains(_opponentId)) {
      _showNotification('🎯 Opponent completed tie-breaker!', Colors.purple);
    }
  }

  void _showNotification(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _initiateTieBreaker() {
    setState(() {
      _isInTieBreaker = true;
      _currentQuestionIndex = 15;
      _tieBreakerScore = 0;
      _hasAnswered = false;
      _selectedAnswer = null;
      _timeRemaining = 180; // 3 minutes for tie-breaker
    });
    
    _showTieBreakerDialog();
  }

  void _showTieBreakerDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('🔥 TIE BREAKER! 🔥', textAlign: TextAlign.center),
        content: const Text(
          'The battle is tied! Answer 3 more questions to determine the winner.',
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _startCountdown();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Start Tie-Breaker'),
            ),
          ),
        ],
      ),
    );
  }

  void _handleBattleEnd() {
    _countdownTimer?.cancel();
    
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _buildResultDialog(),
        );
      }
    });
  }

  // Enhanced answer handling with better UX
  void _answerQuestion(String answer) {
    if (_hasAnswered || _isSubmitting || _battleState != BattleState.inProgress) return;

    setState(() {
      _selectedAnswer = answer;
      _hasAnswered = true;
      _userAnswers[_currentQuestionIndex] = answer;
    });

    // Check if answer is correct
    final correctAnswer = _questions[_currentQuestionIndex]['correctAnswer'];
    if (answer == correctAnswer) {
      setState(() {
        if (_isInTieBreaker) {
          _tieBreakerScore++;
        } else {
          _score++;
        }
      });
    }

    _saveAnswerToFirestore(answer);
  }

  Future<void> _saveAnswerToFirestore(String answer) async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      if (_currentUserId == null) return;

      if (_isInTieBreaker) {
        await _firestore.collection('battles').doc(widget.battleId).update({
          'tieBreakerResults.$_currentUserId.${_currentQuestionIndex - 15}': answer,
        });
      } else {
        await _firestore.collection('battles').doc(widget.battleId).update({
          'results.$_currentUserId.$_currentQuestionIndex': answer,
        });
      }

      // Auto-proceed after 1.5 seconds for better UX
      await Future.delayed(const Duration(milliseconds: 1500));
      
      _proceedToNextStep();
    } catch (e) {
      debugPrint('Error saving answer: $e');
      _showError('Failed to save answer. Please try again.');
      setState(() {
        _hasAnswered = false;
        _selectedAnswer = null;
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _proceedToNextStep() {
    if (_isInTieBreaker) {
      if (_currentQuestionIndex < 17) {
        _goToNextQuestion();
      } else {
        _completeTieBreaker();
      }
    } else {
      if (_currentQuestionIndex < 14) {
        _goToNextQuestion();
      } else {
        _completeBattle();
      }
    }
  }

  void _goToNextQuestion() {
    setState(() {
      _currentQuestionIndex++;
      _selectedAnswer = null;
      _hasAnswered = false;
    });
  }

  // Enhanced battle completion logic
  Future<void> _completeBattle() async {
    if (_currentUserId == null) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _firestore.runTransaction((transaction) async {
        final battleRef = _firestore.collection('battles').doc(widget.battleId);
        final battleDoc = await transaction.get(battleRef);
        final data = battleDoc.data()!;

        // Update scores and mark user as completed
        transaction.update(battleRef, {
          'scores.$_currentUserId': _score,
          'completedUsers': FieldValue.arrayUnion([_currentUserId]),
        });

        final completedUsers = List<String>.from(data['completedUsers'] ?? []);
        completedUsers.add(_currentUserId!);

        // Check if both players completed
        if (completedUsers.length >= 2) {
          await _determineBattleWinner(transaction, battleRef, data);
        }
      });
    } catch (e) {
      debugPrint('Error completing battle: $e');
      _showError('Failed to complete battle. Please try again.');
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _determineBattleWinner(
      Transaction transaction, DocumentReference battleRef, Map<String, dynamic> data) async {
    final scores = Map<String, dynamic>.from(data['scores'] ?? {});
    scores[_currentUserId!] = _score;
    
    final creatorScore = scores[data['creatorId']] ?? 0;
    final opponentScore = scores[data['opponentId']] ?? 0;

    if (creatorScore == opponentScore) {
      // Initiate tie-breaker
      transaction.update(battleRef, {
        'isInTieBreaker': true,
        'tieBreakerStartTime': FieldValue.serverTimestamp(),
      });
    } else {
      await _declareWinner(transaction, battleRef, data, creatorScore, opponentScore);
    }
  }

  Future<void> _declareWinner(
      Transaction transaction, DocumentReference battleRef, Map<String, dynamic> data,
      int creatorScore, int opponentScore) async {
    final winner = creatorScore > opponentScore ? data['creatorId'] : data['opponentId'];
    final loser = winner == data['creatorId'] ? data['opponentId'] : data['creatorId'];
    final totalPrize = (data['prize'] ?? 0) + (data['opponentPrize'] ?? 0);
    
    transaction.update(battleRef, {
      'status': 'completed',
      'winner': winner,
      'endedAt': FieldValue.serverTimestamp(),
    });

    // Award prize to winner
    if (totalPrize > 0) {
      transaction.update(_firestore.collection('wallets').doc(winner), {
        'wallet_balance': FieldValue.increment(totalPrize.toDouble()),
      });
    }

    // Update user stats
    await _updateUserStats(transaction, winner, loser);
  }

  Future<void> _updateUserStats(Transaction transaction, String winner, String loser) async {
    transaction.update(_firestore.collection('users').doc(winner), {
      'battleWins': FieldValue.increment(1),
      'totalBattles': FieldValue.increment(1),
      'lastBattleAt': FieldValue.serverTimestamp(),
    });

    transaction.update(_firestore.collection('users').doc(loser), {
      'totalBattles': FieldValue.increment(1),
      'lastBattleAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _completeTieBreaker() async {
    if (_currentUserId == null) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _firestore.runTransaction((transaction) async {
        final battleRef = _firestore.collection('battles').doc(widget.battleId);
        final battleDoc = await transaction.get(battleRef);
        final data = battleDoc.data()!;

        // Update tie-breaker scores
        transaction.update(battleRef, {
          'tieBreakerScores.$_currentUserId': _tieBreakerScore,
          'tieBreakerCompletedUsers': FieldValue.arrayUnion([_currentUserId]),
        });

        final tieBreakerCompleted = List<String>.from(data['tieBreakerCompletedUsers'] ?? []);
        tieBreakerCompleted.add(_currentUserId!);

        // Check if both completed tie-breaker
        if (tieBreakerCompleted.length >= 2) {
          await _determineTieBreakerWinner(transaction, battleRef, data);
        }
      });
    } catch (e) {
      debugPrint('Error completing tie-breaker: $e');
      _showError('Failed to complete tie-breaker. Please try again.');
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _determineTieBreakerWinner(
      Transaction transaction, DocumentReference battleRef, Map<String, dynamic> data) async {
    final tieBreakerScores = Map<String, dynamic>.from(data['tieBreakerScores'] ?? {});
    tieBreakerScores[_currentUserId!] = _tieBreakerScore;
    
    final creatorTieScore = tieBreakerScores[data['creatorId']] ?? 0;
    final opponentTieScore = tieBreakerScores[data['opponentId']] ?? 0;
    final totalPrize = (data['prize'] ?? 0) + (data['opponentPrize'] ?? 0);

    if (creatorTieScore == opponentTieScore) {
      // Still a tie - return money to both
      transaction.update(battleRef, {
        'status': 'completed',
        'winner': 'tie',
        'endedAt': FieldValue.serverTimestamp(),
      });

      if (totalPrize > 0) {
        transaction.update(_firestore.collection('wallets').doc(data['creatorId']), {
          'wallet_balance': FieldValue.increment((data['prize'] ?? 0).toDouble()),
        });

        transaction.update(_firestore.collection('wallets').doc(data['opponentId']), {
          'wallet_balance': FieldValue.increment((data['opponentPrize'] ?? 0).toDouble()),
        });
      }

      // Update stats for both
      await _updateUserStatsForTie(transaction, data['creatorId'], data['opponentId']);
    } else {
      final winner = creatorTieScore > opponentTieScore ? data['creatorId'] : data['opponentId'];
      final loser = winner == data['creatorId'] ? data['opponentId'] : data['creatorId'];
      
      transaction.update(battleRef, {
        'status': 'completed',
        'winner': winner,
        'endedAt': FieldValue.serverTimestamp(),
      });

      // Award prize to winner
      if (totalPrize > 0) {
        transaction.update(_firestore.collection('wallets').doc(winner), {
          'wallet_balance': FieldValue.increment(totalPrize.toDouble()),
        });
      }

      await _updateUserStats(transaction, winner, loser);
    }
  }

  Future<void> _updateUserStatsForTie(Transaction transaction, String creatorId, String opponentId) async {
    transaction.update(_firestore.collection('users').doc(creatorId), {
      'totalBattles': FieldValue.increment(1),
      'lastBattleAt': FieldValue.serverTimestamp(),
    });

    transaction.update(_firestore.collection('users').doc(opponentId), {
      'totalBattles': FieldValue.increment(1),
      'lastBattleAt': FieldValue.serverTimestamp(),
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildResultDialog() {
    final isWinner = _battleData?['winner'] == _currentUserId;
    final isTie = _battleData?['winner'] == 'tie';
    final prize = (_battleData?['prize'] ?? 0) + (_battleData?['opponentPrize'] ?? 0);
    final myScore = _battleData?['scores']?[_currentUserId] ?? 0;
    final opponentScore = _battleData?['scores']?[_opponentId] ?? 0;
    final myTieBreakerScore = _battleData?['tieBreakerScores']?[_currentUserId] ?? 0;
    final opponentTieBreakerScore = _battleData?['tieBreakerScores']?[_opponentId] ?? 0;
    final endedAt = (_battleData?['endedAt'] as Timestamp?)?.toDate();

    return WillPopScope(
      onWillPop: () async {
        Navigator.popUntil(context, (route) => route.isFirst);
        return false;
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isTie ? Icons.people_alt : 
                isWinner ? Icons.emoji_events : Icons.thumb_up,
                size: 80,
                color: isTie ? Colors.blue : 
                      isWinner ? Colors.amber : Colors.green,
              ),
              const SizedBox(height: 16),
              Text(
                isTie ? '🤝 It\'s a Tie!' : 
                isWinner ? '🏆 Victory! 🏆' : '🎖️ Good Game!',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              if (isWinner && !isTie && prize > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Text(
                    '💰 You won $prize coins!',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              if (isTie)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: const Text(
                    '🤝 Both players get their coins back!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              const SizedBox(height: 16),
              
              FutureBuilder<DocumentSnapshot>(
                future: _firestore.collection('users').doc(_opponentId).get(),
                builder: (context, snapshot) {
                  final opponentName = snapshot.data?['username'] ?? 'Opponent';
                  return Text(
                    'vs $opponentName',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  );
                },
              ),
              
              const SizedBox(height: 12),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      Text('You', style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isWinner ? Colors.green : Colors.grey[700],
                      )),
                      Text('$myScore/15', style: const TextStyle(fontSize: 18)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Opponent', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('$opponentScore/15', style: const TextStyle(fontSize: 18)),
                    ],
                  ),
                ],
              ),
              
              if (_isInTieBreaker || (_battleData?['isInTieBreaker'] ?? false)) ...[
                const SizedBox(height: 12),
                const Text('Tie-Breaker', style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text('$myTieBreakerScore/3'),
                    Text('$opponentTieBreakerScore/3'),
                  ],
                ),
              ],
              
              if (endedAt != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Completed: ${DateFormat('MMM dd, hh:mm a').format(endedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              
              if (_isAdLoaded && _bannerAd != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
              ],
              
              const SizedBox(height: 20),
              
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.popUntil(context, (route) => route.isFirst);
                      },
                      child: const Text('Home'),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _shareBattleResult,
                      child: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shareBattleResult() {
    final isWinner = _battleData?['winner'] == _currentUserId;
    final isTie = _battleData?['winner'] == 'tie';
    final prize = (_battleData?['prize'] ?? 0) + (_battleData?['opponentPrize'] ?? 0);
    final score = _battleData?['scores']?[_currentUserId] ?? 0;

    String message;
    if (isTie) {
      message = 'I just played an epic quiz battle on GOAL Quiz that ended in a TIE! Score: $score/15. Challenge me for a rematch! #GOAL';
    } else if (isWinner) {
      message = 'I just WON a quiz battle on GOAL Quiz and earned $prize coins! Score: $score/15. Think you can beat me? #GOAL';
    } else {
      message = 'I just played a challenging quiz battle on GOAL Quiz. Score: $score/15. Ready for your turn? #GOAL';
    }

    Share.share(message, subject: 'My Quiz Battle Result');
  }

  Widget _buildQuestionScreen() {
    if (_currentQuestionIndex >= _questions.length) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'No more questions available',
              style: TextStyle(fontSize: 18),
            ),
          ],
        ),
      );
    }

    final question = _questions[_currentQuestionIndex];
    final options = List<String>.from(question['options'] ?? []);
    final questionNumber = _isInTieBreaker 
        ? _currentQuestionIndex - 14 
        : _currentQuestionIndex + 1;
    final totalQuestions = _isInTieBreaker ? 3 : 15;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isInTieBreaker 
              ? 'Tie-Breaker $questionNumber/$totalQuestions'
              : 'Question $questionNumber/$totalQuestions'
        ),
        backgroundColor: _isInTieBreaker ? Colors.purple : Colors.red,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(_timeRemaining),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  _isInTieBreaker 
                      ? 'TB: $_tieBreakerScore' 
                      : 'Score: $_score',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _isInTieBreaker 
                    ? [Colors.purple[50]!, Colors.red[50]!]
                    : [Colors.red[50]!, Colors.orange[50]!],
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isInTieBreaker)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple),
                      ),
                      child: const Text(
                        '🔥 TIE-BREAKER ROUND 🔥',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_isInTieBreaker) const SizedBox(height: 16),
                  
                  // Question Card
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        question['question'] ?? 'Question not available',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Options
                  ...options.asMap().entries.map((entry) {
                    final index = entry.key;
                    final option = entry.value;
                    final isSelected = _selectedAnswer == option;
                    final isCorrect = option == question['correctAnswer'];
                    final showCorrect = _hasAnswered && isCorrect;
                    final showIncorrect = _hasAnswered && isSelected && !isCorrect;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        elevation: isSelected ? 6 : 2,
                        color: showCorrect
                            ? Colors.green[100]
                            : showIncorrect
                                ? Colors.red[100]
                                : isSelected
                                    ? Colors.blue[100]
                                    : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: showCorrect
                                ? Colors.green
                                : showIncorrect
                                    ? Colors.red
                                    : isSelected
                                        ? Colors.blue
                                        : Colors.grey[300]!,
                            width: isSelected || showCorrect || showIncorrect ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          title: Text(
                            option,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: showCorrect || showIncorrect ? Colors.black87 : null,
                            ),
                          ),
                          onTap: _isSubmitting ? null : () => _answerQuestion(option),
                          trailing: _buildOptionTrailing(showCorrect, showIncorrect, isSelected),
                        ),
                      ),
                    );
                  }),
                  
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          
          // Ad banner
          if (_isAdLoaded && _bannerAd != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.white,
                child: SizedBox(
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildOptionTrailing(bool showCorrect, bool showIncorrect, bool isSelected) {
    if (showCorrect) {
      return const Icon(Icons.check_circle, color: Colors.green);
    } else if (showIncorrect) {
      return const Icon(Icons.cancel, color: Colors.red);
    } else if (_isSubmitting && isSelected) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    switch (_battleState) {
      case BattleState.loading:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('Loading battle...'),
              ],
            ),
          ),
        );
        
      case BattleState.waitingForOpponent:
        return Scaffold(
          appBar: AppBar(
            title: const Text('Waiting for Opponent'),
            automaticallyImplyLeading: false,
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_opponentJoined) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  const Text(
                    'Waiting for opponent to join...',
                    style: TextStyle(fontSize: 18),
                  ),
                ] else ...[
                  Icon(Icons.hourglass_empty, size: 80, color: Colors.orange[600]),
                  const SizedBox(height: 20),
                  Text(
                    _isInTieBreaker ? 'Tie-breaker completed!' : 'Quiz completed!',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text('Waiting for opponent to finish...'),
                  const SizedBox(height: 20),
                  Text(
                    _isInTieBreaker 
                        ? 'Your tie-breaker score: $_tieBreakerScore/3'
                        : 'Your score: $_score/15',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
                const SizedBox(height: 20),
                Text('Time remaining: ${_formatTime(_timeRemaining)}'),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Leave Battle'),
                ),
              ],
            ),
          ),
        );
        
      case BattleState.inProgress:
        return _buildQuestionScreen();
        
      case BattleState.completed:
        return Scaffold(
          appBar: AppBar(
            title: const Text('Battle Completed'),
            automaticallyImplyLeading: false,
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 100, color: Colors.green[600]),
                const SizedBox(height: 20),
                const Text(
                  'Battle has ended!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        );
        
      case BattleState.error:
        return Scaffold(
          appBar: AppBar(
            title: const Text('Error'),
            automaticallyImplyLeading: false,
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 80, color: Colors.red[600]),
                const SizedBox(height: 20),
                const Text(
                  'Something went wrong',
                  style: TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        );
        
      default:
        return const Scaffold(
          body: Center(child: Text('Unknown state')),
        );
    }
  }

  @override
  void dispose() {
    _battleSubscription.cancel();
    _countdownTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }
}