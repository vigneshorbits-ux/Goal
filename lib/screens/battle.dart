import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:goal/screens/BattleActiveScreen.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

class BattleScreen extends StatefulWidget {
  const BattleScreen({super.key});

  @override
  _BattleScreenState createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> 
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late TabController _tabController;
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  String? _currentBattleId;
  bool _isLoading = true;
  bool _hasActiveBattle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _initializeBattleScreen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh battle status when app comes to foreground
      _checkCurrentBattle();
    }
  }

  Future<void> _initializeBattleScreen() async {
    await Future.wait([
      _checkCurrentBattle(),
      _loadAd(),
      _autoExpireOldBattles(),
    ]);
    setState(() {
      _isLoading = false;
    });
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

  Future<void> _checkCurrentBattle() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      // Check for active battle first
      final activeBattleQuery = await _firestore
          .collection('battles')
          .where('participants', arrayContains: currentUserId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (activeBattleQuery.docs.isNotEmpty) {
        setState(() {
          _currentBattleId = activeBattleQuery.docs.first.id;
          _hasActiveBattle = true;
        });
        return;
      }

      // Check for pending battles
      final pendingBattleQuery = await _firestore
          .collection('battles')
          .where('creatorId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (pendingBattleQuery.docs.isNotEmpty) {
        setState(() {
          _currentBattleId = pendingBattleQuery.docs.first.id;
          _hasActiveBattle = true;
        });
      } else {
        setState(() {
          _hasActiveBattle = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking current battle: $e');
      setState(() {
        _hasActiveBattle = false;
      });
    }
  }

  Future<void> _autoExpireOldBattles() async {
    try {
      final now = DateTime.now();
      final snapshot = await _firestore
          .collection('battles')
          .where('status', whereIn: ['pending', 'active'])
          .get();

      final batch = _firestore.batch();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        final status = data['status'];
        
        if (createdAt == null) continue;

        // Expire pending battles after 24 hours
        if (status == 'pending' && now.difference(createdAt).inHours >= 24) {
          final prize = data['prize'] ?? 0;
          final creatorId = data['creatorId'];
          
          batch.update(doc.reference, {
            'status': 'expired',
            'endedAt': FieldValue.serverTimestamp(),
            'winner': 'expired',
          });
          
          // Return money to creator
          if (prize > 0) {
            batch.update(_firestore.collection('wallets').doc(creatorId), {
              'wallet_balance': FieldValue.increment(prize.toDouble()),
            });
          }
        }
        
        // Expire active battles after 30 minutes if no one has completed
        else if (status == 'active') {
          final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
          if (startedAt != null && now.difference(startedAt).inMinutes >= 30) {
            final completedUsers = List<String>.from(data['completedUsers'] ?? []);
            final creatorId = data['creatorId'];
            final opponentId = data['opponentId'];
            
            if (completedUsers.isEmpty) {
              // No one completed - return money to both
              batch.update(doc.reference, {
                'status': 'expired',
                'endedAt': FieldValue.serverTimestamp(),
                'winner': 'expired',
              });
              
              batch.update(_firestore.collection('wallets').doc(creatorId), {
                'wallet_balance': FieldValue.increment((data['prize'] ?? 0).toDouble()),
              });
              
              batch.update(_firestore.collection('wallets').doc(opponentId), {
                'wallet_balance': FieldValue.increment((data['opponentPrize'] ?? 0).toDouble()),
              });
            } else if (completedUsers.length == 1) {
              // Only one completed - they win
              final winner = completedUsers.first;
              final totalPrize = (data['prize'] ?? 0) + (data['opponentPrize'] ?? 0);
              
              batch.update(doc.reference, {
                'status': 'completed',
                'endedAt': FieldValue.serverTimestamp(),
                'winner': winner,
              });
              
              if (totalPrize > 0) {
                batch.update(_firestore.collection('wallets').doc(winner), {
                  'wallet_balance': FieldValue.increment(totalPrize.toDouble()),
                });
              }
            }
          }
        }
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error auto-expiring battles: $e');
    }
  }

  void _refreshBattleStatus() {
    setState(() {
      _isLoading = true;
    });
    _checkCurrentBattle().then((_) {
      setState(() {
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading Battle Arena...'),
            ],
          ),
        ),
      );
    }

    if (_hasActiveBattle && _currentBattleId != null) {
      return BattleActiveScreen(battleId: _currentBattleId!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battle Arena'),
        elevation: 4,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red[600]!, Colors.orange[600]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Iconsax.award), text: 'Create'),
            Tab(icon: Icon(Iconsax.notification), text: 'Invites'),
            Tab(icon: Icon(Iconsax.clock), text: 'History'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.refresh),
            onPressed: _refreshBattleStatus,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.red[50]!, Colors.orange[50]!],
          ),
        ),
        child: TabBarView(
          controller: _tabController,
          children: const [
            CreateBattleTab(),
            BattleInvitationsTab(),
            BattleHistoryTab(),
          ],
        ),
      ),
      bottomNavigationBar: _isAdLoaded && _bannerAd != null
          ? Container(
              color: Colors.white,
              child: SizedBox(
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            )
          : null,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }
}

class CreateBattleTab extends StatefulWidget {
  const CreateBattleTab({super.key});

  @override
  _CreateBattleTabState createState() => _CreateBattleTabState();
}

class _CreateBattleTabState extends State<CreateBattleTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _prizeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  String? _selectedOpponentId;
  String? _selectedOpponentName;
  bool _isCreating = false;
  bool _isLoadingUsers = true;
  double _currentBalance = 0.0;
  bool _hasExistingBattle = false;

  static const String _questionsSheetUrl = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQHtA8_3vH6TjRCb3aJA8ayircjC0qPj3f8As_kiAKMvwbFLzs2WeQdRinjnSHd2uB35kRH_49Ytkj2/pub?output=csv';

  @override
  void initState() {
    super.initState();
    _initializeCreateTab();
  }

  Future<void> _initializeCreateTab() async {
    await Future.wait([
      _loadWalletBalance(),
      _loadUsers(),
      _checkExistingBattle(),
    ]);
  }

  Future<void> _checkExistingBattle() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      final existingBattleCheck = await _firestore
          .collection('battles')
          .where('participants', arrayContains: currentUserId)
          .where('status', whereIn: ['active', 'pending'])
          .limit(1)
          .get();

      setState(() {
        _hasExistingBattle = existingBattleCheck.docs.isNotEmpty;
      });
    } catch (e) {
      debugPrint('Error checking existing battle: $e');
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      final walletDoc = await _firestore.collection('wallets').doc(currentUserId).get();
      setState(() {
        _currentBalance = walletDoc.data()?['wallet_balance']?.toDouble() ?? 0.0;
      });
    } catch (e) {
      debugPrint('Error loading wallet balance: $e');
    }
  }

  Future<void> _loadUsers() async {
    try {
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId == null) return;

      final usersSnapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, isNotEqualTo: currentUserId)
          .where('isActive', isEqualTo: true)
          .limit(100)
          .get();

      final users = usersSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'username': data['username'] ?? 'Anonymous',
          'email': data['email'] ?? '',
          'wins': data['battleWins'] ?? 0,
          'totalBattles': data['totalBattles'] ?? 0,
          'lastActive': data['lastActive'],
        };
      }).toList();

      // Sort by last active and win rate
      users.sort((a, b) {
        final aWinRate = (a['totalBattles'] ?? 0) > 0 ? (a['wins'] ?? 0) / (a['totalBattles'] ?? 1) : 0;
        final bWinRate = (b['totalBattles'] ?? 0) > 0 ? (b['wins'] ?? 0) / (b['totalBattles'] ?? 1) : 0;
        return bWinRate.compareTo(aWinRate);
      });

      setState(() {
        _users = users;
        _filteredUsers = users;
        _isLoadingUsers = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingUsers = false;
      });
      _showError('Failed to load users');
    }
  }

  void _filterUsers(String query) {
    setState(() {
      _filteredUsers = _users.where((user) {
        final username = user['username'].toString().toLowerCase();
        return username.contains(query.toLowerCase());
      }).toList();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchQuestionsFromSheet() async {
    try {
      final response = await http.get(Uri.parse(_questionsSheetUrl));
      if (response.statusCode == 200) {
        final List<String> lines = response.body.split('\n');
        final List<Map<String, dynamic>> questions = [];
        
        // Skip header line
        for (int i = 1; i < lines.length && questions.length < 18; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          
          final parts = line.split(',');
          if (parts.length >= 6) {
            questions.add({
              'question': parts[0].trim().replaceAll('"', ''),
              'options': [
                parts[1].trim().replaceAll('"', ''),
                parts[2].trim().replaceAll('"', ''),
                parts[3].trim().replaceAll('"', ''),
                parts[4].trim().replaceAll('"', ''),
              ],
              'correctAnswer': parts[5].trim().replaceAll('"', ''),
              'difficulty': parts.length > 6 ? parts[6].trim() : 'medium',
            });
          }
        }
        
        // Shuffle and return 18 questions (15 main + 3 tie-breaker)
        questions.shuffle(Random());
        return questions.take(18).toList();
      } else {
        throw Exception('Failed to fetch questions: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching questions: $e');
      // Fallback to Firestore if sheet fails
      return await _generateFallbackQuestions();
    }
  }

  Future<List<Map<String, dynamic>>> _generateFallbackQuestions() async {
    try {
      final snapshot = await _firestore.collection('quizQuestions')
          .where('isActive', isEqualTo: true)
          .limit(50)
          .get();
      
      final allQuestions = snapshot.docs.map((doc) => doc.data()).toList();
      allQuestions.shuffle(Random());
      return allQuestions.take(18).toList();
    } catch (e) {
      // Ultimate fallback - generate simple questions
      return _generateBasicQuestions();
    }
  }

  List<Map<String, dynamic>> _generateBasicQuestions() {
    // Simple fallback questions
    return [
      {
        'question': 'What is 2 + 2?',
        'options': ['3', '4', '5', '6'],
        'correctAnswer': '4',
        'difficulty': 'easy'
      },
      // Add more basic questions as needed
    ];
  }

  Future<void> _createBattle() async {
    if (_hasExistingBattle) {
      _showError('You already have an active or pending battle');
      return;
    }

    if (_selectedOpponentId == null) {
      _showError('Please select an opponent');
      return;
    }

    final prize = int.tryParse(_prizeController.text) ?? 0;
    if (prize < 10) {
      _showError('Minimum prize is 10 points');
      return;
    }

    if (prize > _currentBalance) {
      _showError('Insufficient balance to create this battle');
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final battleId = _firestore.collection('battles').doc().id;
      final questions = await _fetchQuestionsFromSheet();

      await _firestore.runTransaction((transaction) async {
        // Create battle with questions
        transaction.set(_firestore.collection('battles').doc(battleId), {
          'id': battleId,
          'creatorId': _auth.currentUser!.uid,
          'opponentId': _selectedOpponentId,
          'participants': [_auth.currentUser!.uid, _selectedOpponentId],
          'prize': prize,
          'opponentPrize': 0,
          'questionCount': 15,
          'tieBreakerQuestions': 3,
          'questions': questions,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
          'scores': {},
          'results': {},
          'completedUsers': [],
          'winner': null,
          'isInTieBreaker': false,
          'tieBreakerScores': {},
          'tieBreakerResults': {},
          'tieBreakerCompletedUsers': [],
          'userStartTimes': {},
          'userJoinTimes': {},
          'battleType': 'one_vs_one',
          'version': '1.0',
        });

        // Deduct prize from creator's wallet
        transaction.update(_firestore.collection('wallets').doc(_auth.currentUser!.uid), {
          'wallet_balance': FieldValue.increment(-prize.toDouble()),
        });

        // Create notification for opponent
        transaction.set(_firestore.collection('notifications').doc(), {
          'userId': _selectedOpponentId,
          'type': 'battle_invitation',
          'title': 'Battle Challenge! 🥊',
          'message': '${_auth.currentUser?.displayName ?? "Someone"} challenged you to a quiz battle for $prize points!',
          'battleId': battleId,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
          'data': {
            'battleId': battleId,
            'creatorName': _auth.currentUser?.displayName ?? 'Unknown',
            'prize': prize,
            'opponentRequiredPrize': (prize * 0.5).ceil(),
          }
        });
      });

      _showSuccess('Battle created successfully! Waiting for opponent...');
      
      // Clear form
      _clearForm();
      
      // Refresh the parent screen to show the new battle
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const BattleScreen()),
        );
      }
    } catch (e) {
      _showError('Failed to create battle: ${e.toString()}');
    } finally {
      setState(() {
        _isCreating = false;
      });
    }
  }

  void _clearForm() {
    _prizeController.clear();
    _searchController.clear();
    setState(() {
      _selectedOpponentId = null;
      _selectedOpponentName = null;
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

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasExistingBattle) _buildExistingBattleWarning(),
          _buildWalletInfo(),
          const SizedBox(height: 16),
          _buildBattleSettings(),
          const SizedBox(height: 24),
          _buildOpponentSelection(),
          const SizedBox(height: 32),
          _buildCreateButton(),
        ],
      ),
    );
  }

  Widget _buildExistingBattleWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          Icon(Iconsax.info_circle, color: Colors.orange[800]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You already have an active battle. Complete it before creating a new one.',
              style: TextStyle(
                color: Colors.orange[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletInfo() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Iconsax.wallet, color: Colors.green[600], size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Wallet Balance',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '${_currentBalance.toStringAsFixed(0)} points',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Iconsax.refresh),
              onPressed: _loadWalletBalance,
              tooltip: 'Refresh Balance',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBattleSettings() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Battle Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red[800],
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _prizeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Your Prize Amount',
                hintText: 'Enter your prize (min: 10, max: ${_currentBalance.toInt()})',
                prefixIcon: const Icon(Iconsax.coin),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                helperText: 'Opponent must contribute at least 50% of this amount',
                suffixText: 'points',
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  _buildInfoRow(Iconsax.document_text, '15 Questions + 3 Tie-Breakers'),
                  const SizedBox(height: 8),
                  _buildInfoRow(Iconsax.clock, 'Time Limit: 12 minutes'),
                  const SizedBox(height: 8),
                  _buildInfoRow(Iconsax.award, 'Winner takes all points'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue[600], size: 16),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: Colors.blue[700],
          ),
        ),
      ],
    );
  }

  Widget _buildOpponentSelection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Opponent',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red[800],
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users by username...',
                prefixIcon: const Icon(Iconsax.search_normal),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _filterUsers,
            ),
            const SizedBox(height: 16),

            if (_selectedOpponentName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    Icon(Iconsax.tick_circle, color: Colors.green[600]),
                    const SizedBox(width: 8),
                    Text(
                      'Selected: $_selectedOpponentName',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_isLoadingUsers)
              const Center(child: CircularProgressIndicator())
            else if (_filteredUsers.isEmpty)
              const Center(
                child: Column(
                  children: [
                    Icon(Iconsax.people, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('No users found'),
                  ],
                ),
              )
            else
              SizedBox(
                height: 250,
                child: ListView.builder(
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = _filteredUsers[index];
                    final isSelected = _selectedOpponentId == user['id'];
                    final wins = user['wins'] ?? 0;
                    final total = user['totalBattles'] ?? 0;
                    final winRate = total > 0 ? (wins / total * 100).toStringAsFixed(1) : '0.0';

                    return Card(
                      elevation: isSelected ? 3 : 1,
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isSelected ? Colors.red[50] : Colors.white,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red[600],
                          child: Text(
                            user['username'][0].toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          user['username'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Win Rate: $winRate%'),
                            Text('Battles: $total | Wins: $wins'),
                          ],
                        ),
                        trailing: isSelected
                            ? Icon(Iconsax.tick_circle, color: Colors.red[600])
                            : const Icon(Iconsax.add_circle),
                        onTap: () {
                          setState(() {
                            _selectedOpponentId = user['id'];
                            _selectedOpponentName = user['username'];
                          });
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isCreating || _hasExistingBattle ? null : _createBattle,
        icon: _isCreating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Iconsax.award),
        label: Text(_isCreating ? 'Creating Battle...' : 'Create Battle'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _hasExistingBattle ? Colors.grey : Colors.red[600],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _prizeController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}

// Rest of the code for BattleInvitationsTab, BattleInvitationCard, BattleHistoryTab, and BattleHistoryCard remains the same as in your original code...
// (I've kept the original implementation for these components as they were already well-structured)
class BattleInvitationsTab extends StatelessWidget {
  const BattleInvitationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return const Center(child: Text('Please log in'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('battles')
          .where('opponentId', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.activity, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No Battle Invitations',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Challenge friends to start battling!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final battle = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return BattleInvitationCard(battle: battle);
          },
        );
      },
    );
  }
}

class BattleInvitationCard extends StatefulWidget {
  final Map<String, dynamic> battle;

  const BattleInvitationCard({super.key, required this.battle});

  @override
  _BattleInvitationCardState createState() => _BattleInvitationCardState();
}

class _BattleInvitationCardState extends State<BattleInvitationCard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isProcessing = false;

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _acceptBattle() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final currentUserId = _auth.currentUser!.uid;
      final battleId = widget.battle['id'];
      final creatorPrize = widget.battle['prize'] ?? 0;
      final minOpponentPrize = (creatorPrize * 0.5).ceil(); // 50% minimum

      // Check if user already has an active battle
      final existingBattleCheck = await _firestore
          .collection('battles')
          .where('participants', arrayContains: currentUserId)
          .where('status', whereIn: ['active', 'pending'])
          .limit(1)
          .get();

      if (existingBattleCheck.docs.isNotEmpty && 
          existingBattleCheck.docs.first.id != battleId) {
        _showError('You already have an active or pending battle');
        setState(() => _isProcessing = false);
        return;
      }

      // Show contribution dialog
      final TextEditingController contributionController = TextEditingController(
        text: creatorPrize.toString()
      );
      
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Set Your Prize Contribution'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Creator\'s prize: $creatorPrize points'),
              Text('Minimum required: $minOpponentPrize points'),
              const SizedBox(height: 16),
              TextField(
                controller: contributionController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter your contribution',
                  labelText: 'Your Prize Amount',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<DocumentSnapshot>(
                future: _firestore.collection('wallets').doc(currentUserId).get(),
                builder: (context, snapshot) {
                  final balance = snapshot.data?.data() as Map<String, dynamic>?;
                  final currentBalance = balance?['wallet_balance']?.toDouble() ?? 0.0;
                  return Text(
                    'Your balance: ${currentBalance.toStringAsFixed(0)} points',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              child: const Text('Accept Battle'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() => _isProcessing = false);
        return;
      }

      final enteredPrize = int.tryParse(contributionController.text ?? '') ?? 0;
      if (enteredPrize < minOpponentPrize) {
        _showError('Minimum required is $minOpponentPrize points.');
        setState(() => _isProcessing = false);
        return;
      }

      // Check balance
      final walletDoc = await _firestore.collection('wallets').doc(currentUserId).get();
      final balance = walletDoc.data()?['wallet_balance'] ?? 0;
      if (enteredPrize > balance) {
        _showError('Insufficient balance');
        setState(() => _isProcessing = false);
        return;
      }

      await _firestore.runTransaction((transaction) async {
        // Update battle to active
        transaction.update(_firestore.collection('battles').doc(battleId), {
          'status': 'active',
          'opponentPrize': enteredPrize,
          'startedAt': FieldValue.serverTimestamp(),
        });

        // Deduct from opponent's wallet
        transaction.update(_firestore.collection('wallets').doc(currentUserId), {
          'wallet_balance': FieldValue.increment(-enteredPrize.toDouble()),
        });

        // Notify creator
        transaction.set(_firestore.collection('notifications').doc(), {
          'userId': widget.battle['creatorId'],
          'type': 'battle_accepted',
          'title': 'Battle Accepted! 🔥',
          'message': 'Your opponent accepted and contributed $enteredPrize points! The battle is now live!',
          'battleId': battleId,
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });

        // Decline other pending battles for this user
        final pendingBattles = await _firestore
            .collection('battles')
            .where('opponentId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'pending')
            .get();

        for (var doc in pendingBattles.docs) {
          if (doc.id != battleId) {
            transaction.update(doc.reference, {
              'status': 'declined',
              'endedAt': FieldValue.serverTimestamp(),
              'declineReason': 'User accepted another battle',
            });

            // Return money to creator
            transaction.update(_firestore.collection('wallets').doc(doc['creatorId']), {
              'wallet_balance': FieldValue.increment((doc['prize'] ?? 0).toDouble()),
            });

            // Notify other creators
            transaction.set(_firestore.collection('notifications').doc(), {
              'userId': doc['creatorId'],
              'type': 'battle_declined',
              'title': 'Battle Declined',
              'message': 'Opponent accepted another challenge.',
              'battleId': doc.id,
              'createdAt': FieldValue.serverTimestamp(),
              'read': false,
            });
          }
        }
      });

      _showSuccess('Battle accepted! Get ready to fight!');

      // Navigate to battle screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => BattleActiveScreen(battleId: battleId),
        ),
      );
    } catch (e) {
      _showError('Failed to accept battle: $e');
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _declineBattle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Battle'),
        content: const Text('Are you sure you want to decline this battle invitation?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Decline'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await _firestore.runTransaction((transaction) async {
        // Update battle status
        transaction.update(_firestore.collection('battles').doc(widget.battle['id']), {
          'status': 'declined',
          'endedAt': FieldValue.serverTimestamp(),
          'declineReason': 'User declined',
        });

        // Return money to creator
        transaction.update(
          _firestore.collection('wallets').doc(widget.battle['creatorId']), {
          'wallet_balance': FieldValue.increment((widget.battle['prize'] ?? 0).toDouble()),
        });

        // Notify creator
        transaction.set(_firestore.collection('notifications').doc(), {
          'userId': widget.battle['creatorId'],
          'type': 'battle_declined',
          'title': 'Battle Declined',
          'message': 'Your battle invitation was declined.',
          'battleId': widget.battle['id'],
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
      });

      _showSuccess('Battle declined');
    } catch (e) {
      _showError('Failed to decline battle: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = (widget.battle['createdAt'] as Timestamp?)?.toDate();
    final expiresAt = (widget.battle['expiresAt'] as Timestamp?)?.toDate();
    final timeLeft = expiresAt != null 
        ? expiresAt.difference(DateTime.now()) 
        : const Duration();

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.orange[50]!, Colors.red[50]!],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Quiz Battle Challenge! 🥊',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.battle['prize']} points',
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<DocumentSnapshot>(
                future: _firestore.collection('users').doc(widget.battle['creatorId']).get(),
                builder: (context, snapshot) {
                  final creatorData = snapshot.data?.data() as Map<String, dynamic>?;
                  final creatorName = creatorData?['username'] ?? 'Unknown';
                  final wins = creatorData?['battleWins'] ?? 0;
                  final total = creatorData?['totalBattles'] ?? 0;
                  final winRate = total > 0 ? (wins / total * 100).toStringAsFixed(1) : '0';
                  
                  return Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.red[600],
                        radius: 20,
                        child: Text(
                          creatorName[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              creatorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Win Rate: $winRate% ($wins/$total)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Iconsax.info_circle, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '15 questions + tie-breaker if needed\nYou need to contribute at least ${(widget.battle['prize'] * 0.5).ceil()} points',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (createdAt != null) ...[
                Text(
                  'Invited: ${DateFormat('MMM dd, hh:mm a').format(createdAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
              ],
              if (timeLeft.inHours > 0)
                Text(
                  'Expires in: ${timeLeft.inHours}h ${timeLeft.inMinutes.remainder(60)}m',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[600],
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                Text(
                  'Expired',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _declineBattle,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Iconsax.close_circle),
                      label: const Text('Decline'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.red[400]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _acceptBattle,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Iconsax.award),
                      label: const Text('Accept Battle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
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
}

class BattleHistoryTab extends StatelessWidget {
  const BattleHistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return const Center(child: Text('Please log in'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('battles')
          .where('participants', arrayContains: currentUserId)
          .where('status', whereIn: ['completed', 'expired', 'declined'])
          .orderBy('endedAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Iconsax.clock, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No Battle History',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Complete battles to see your history',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final battle = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return BattleHistoryCard(battle: battle);
          },
        );
      },
    );
  }
}

class BattleHistoryCard extends StatelessWidget {
  final Map<String, dynamic> battle;

  const BattleHistoryCard({super.key, required this.battle});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isWinner = battle['winner'] == currentUserId;
    final isTie = battle['winner'] == 'tie';
    final isExpired = battle['status'] == 'expired';
    final isDeclined = battle['status'] == 'declined';
    final endedAt = (battle['endedAt'] as Timestamp?)?.toDate();
    final prize = (battle['prize'] ?? 0) + (battle['opponentPrize'] ?? 0);
    final creatorId = battle['creatorId'];
    final opponentId = battle['opponentId'];
    final isCreator = creatorId == currentUserId;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isDeclined) {
      statusColor = Colors.grey;
      statusText = 'Declined';
      statusIcon = Iconsax.close_circle;
    } else if (isExpired) {
      statusColor = Colors.orange;
      statusText = 'Expired';
      statusIcon = Iconsax.clock;
    } else if (isTie) {
      statusColor = Colors.blue;
      statusText = 'Tie';
      statusIcon = Iconsax.medal;
    } else if (isWinner) {
      statusColor = Colors.green;
      statusText = 'Victory';
      statusIcon = Iconsax.crown;
    } else {
      statusColor = Colors.red;
      statusText = 'Defeat';
      statusIcon = Iconsax.award;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              statusColor.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Quiz Battle',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 16, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!isDeclined) ...[
                Text(
                  'Prize Pool: $prize points',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
              ],
              if (endedAt != null) ...[
                Text(
                  'Ended: ${DateFormat('MMM dd, yyyy - hh:mm a').format(endedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCreator ? 'You' : 'Creator',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(creatorId)
                              .get(),
                          builder: (context, snapshot) {
                            final username = snapshot.data?.get('username') ?? 'Unknown';
                            return Text(
                              username,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            );
                          },
                        ),
                        if (!isDeclined && battle['scores'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Score: ${battle['scores'][creatorId] ?? 0}/15',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      'VS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          !isCreator ? 'You' : 'Opponent',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(opponentId)
                              .get(),
                          builder: (context, snapshot) {
                            final username = snapshot.data?.get('username') ?? 'Unknown';
                            return Text(
                              username,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.end,
                            );
                          },
                        ),
                        if (!isDeclined && battle['scores'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Score: ${battle['scores'][opponentId] ?? 0}/15',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (!isDeclined && battle['isInTieBreaker'] == true) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Iconsax.flash, color: Colors.purple[600], size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Tie-Breaker: ${battle['tieBreakerScores']?[currentUserId] ?? 0}/3',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.purple[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isDeclined)
                    IconButton(
                      icon: const Icon(Iconsax.share),
                      onPressed: () => _shareBattleResult(context),
                      tooltip: 'Share Result',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shareBattleResult(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isWinner = battle['winner'] == currentUserId;
    final isTie = battle['winner'] == 'tie';
    final prize = (battle['prize'] ?? 0) + (battle['opponentPrize'] ?? 0);
    final score = battle['scores'] != null ? battle['scores'][currentUserId] : 'N/A';

    String message;
    if (isTie) {
      message = 'I just played an epic quiz battle on GOAL that ended in a TIE! Score: $score/15. Challenge me for a rematch! #GOAL';
    } else if (isWinner) {
      message = 'I just WON a quiz battle on GOAL and earned $prize points! Score: $score/15. Think you can beat me? #GOAL';
    } else {
      message = 'I just played a challenging quiz battle on GOAL! Score: $score/15. Ready for your turn? #GOAL';
    }

    Share.share(message, subject: 'My Quiz Battle Result');
  }
}