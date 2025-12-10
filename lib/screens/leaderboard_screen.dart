import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/scheduler.dart';
import 'package:goal/leaderboard_service.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:math' as math;

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  _LeaderboardScreenState createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  final LeaderboardService _leaderboardService = LeaderboardService(
    firestore: FirebaseFirestore.instance,
  );

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _leaderboardService.resetLeaderboardIfNeeded();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          '🏆 ELITE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 32,
            letterSpacing: 2,
            fontFamily: 'Poppins',
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: GestureDetector(
                onTap: () => _showLeaderboardInfo(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.cyan.shade300, Colors.blue.shade500],
                    ),
                  ),
                  child: const Icon(Iconsax.info_circle,
                      color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Animated background
          _buildAnimatedBackground(),
          // Main content
          Column(
            children: [
              const SizedBox(height: 80),
              // Top 3 spotlight section
              _buildSpotlight(),
              const SizedBox(height: 24),
              // Full leaderboard
              Expanded(
                child: _buildLeaderboardList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0a0e27),
            const Color(0xFF16213e),
            const Color(0xFF0f3460),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Animated orbs
          Positioned(
            top: -100,
            right: -50,
            child: RotationTransition(
              turns: _rotationController,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.cyan.shade400.withOpacity(0.3),
                      Colors.cyan.shade400.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -80,
            child: RotationTransition(
              turns: Tween(begin: 1.0, end: 0.0).animate(_rotationController),
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.purple.shade400.withOpacity(0.2),
                      Colors.purple.shade400.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpotlight() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('leaderboard')
          .orderBy('score', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final topThree = snapshot.data!.docs;

        return SizedBox(
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Second place (left)
              if (topThree.length > 1)
                Positioned(
                  left: 20,
                  bottom: 20,
                  child: _buildSpotlightCard(topThree[1], 2),
                ),
              // First place (center, elevated)
              if (topThree.isNotEmpty)
                Positioned(
                  top: 0,
                  child: _buildSpotlightCard(topThree[0], 1),
                ),
              // Third place (right)
              if (topThree.length > 2)
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: _buildSpotlightCard(topThree[2], 3),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpotlightCard(DocumentSnapshot doc, int rank) {
    final data = doc.data() as Map<String, dynamic>;
    final username = _validateUsername(data['username']);
    final score = _validateScore(data['score']);

    final isFirst = rank == 1;
    final colors = _getGradientColors(rank);

    return GestureDetector(
      onTap: () => _showUserDetails(context, username, score, rank),
      child: ScaleTransition(
        scale: isFirst
            ? Tween(begin: 1.0, end: 1.05).animate(_pulseController)
            : AlwaysStoppedAnimation(1.0),
        child: Container(
          width: isFirst ? 160 : 130,
          height: isFirst ? 200 : 160,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(isFirst ? 28 : 20),
            boxShadow: [
              BoxShadow(
                color: colors[0].withOpacity(0.6),
                blurRadius: isFirst ? 30 : 20,
                spreadRadius: isFirst ? 5 : 2,
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 2,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow effect
              if (isFirst)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        colors[0].withOpacity(0.4),
                        colors[0].withOpacity(0),
                      ],
                    ),
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [colors[0], colors[1]],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors[0].withOpacity(0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: _buildRankIcon(rank),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: isFirst ? 16 : 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$score',
                    style: TextStyle(
                      fontSize: isFirst ? 24 : 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'PTS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 1,
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

  Widget _buildRankIcon(int rank) {
    switch (rank) {
      case 1:
        return const Icon(Iconsax.crown_1, color: Colors.amber, size: 32);
      case 2:
        return const Icon(Iconsax.crown, color: Colors.grey, size: 28);
      case 3:
        return const Icon(Iconsax.star, color: Colors.orange, size: 28);
      default:
        return const SizedBox();
    }
  }

  List<Color> _getGradientColors(int rank) {
    switch (rank) {
      case 1:
        return [Colors.amber.shade600, Colors.amber.shade800];
      case 2:
        return [Colors.blueGrey.shade500, Colors.blueGrey.shade700];
      case 3:
        return [Colors.orange.shade500, Colors.orange.shade700];
      default:
        return [Colors.deepPurple.shade400, Colors.deepPurple.shade600];
    }
  }

  Widget _buildLeaderboardList() {
    return RefreshIndicator(
      backgroundColor: Colors.deepPurple[800],
      color: Colors.cyan.shade300,
      displacement: 40,
      onRefresh: () async {
        setState(() {});
        return Future.delayed(const Duration(seconds: 1));
      },
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('leaderboard')
            .orderBy('score', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildShimmerLoader();
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final leaderboard = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: leaderboard.length,
            itemBuilder: (context, index) {
              final data = leaderboard[index].data() as Map<String, dynamic>;
              final username = _validateUsername(data['username']);
              final score = _validateScore(data['score']);
              final rank = index + 1;

              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 300 + (index * 100)),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: Opacity(
                      opacity: value,
                      child: child,
                    ),
                  );
                },
                child: _buildLeaderboardTile(username, score, rank),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLeaderboardTile(String username, int score, int rank) {
    return GestureDetector(
      onTap: () => _showUserDetails(context, username, score, rank),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Rank badge
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Colors.cyan.shade300.withOpacity(0.3),
                      Colors.blue.shade500.withOpacity(0.3),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.cyan.shade300.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '#$rank',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Username and score
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$score points',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.cyan.shade200,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              // Score display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.cyan.shade300.withOpacity(0.2),
                      Colors.blue.shade500.withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.cyan.shade300.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  '$score',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoader() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withOpacity(0.08),
      highlightColor: Colors.white.withOpacity(0.15),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 10,
        itemBuilder: (_, index) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Iconsax.warning_2, size: 80, color: Colors.redAccent),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Failed to load leaderboard',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.cyan.shade200,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Iconsax.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Iconsax.ranking_1, size: 100, color: Colors.cyan.shade300),
          const SizedBox(height: 24),
          Text(
            'Be the first to claim the throne!',
            style: TextStyle(
              fontSize: 20,
              color: Colors.cyan.shade200,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Play now and top the leaderboard',
            style: TextStyle(
              fontSize: 16,
              color: Colors.cyan.shade100.withOpacity(0.7),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  void _showLeaderboardInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1a1a2e),
              Color(0xFF16213e),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(
            top: BorderSide(
              color: Colors.cyan.shade300.withOpacity(0.3),
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Leaderboard Info',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 24),
            _buildInfoItem(
                Iconsax.crown_1, 'Top 3 players get special badges', Colors.amber),
            _buildInfoItem(
                Iconsax.clock, 'Scores reset every 7 days', Colors.cyan),
            _buildInfoItem(Iconsax.star, 'Earn points by completing daily quizzes',
                Colors.orange),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              ),
              child: const Text('Got it!'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
              ),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserDetails(
      BuildContext context, String username, int score, int rank) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1a1a2e),
                const Color(0xFF16213e),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.cyan.shade300.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.cyan.shade300.withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 10,
              ),
            ],
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: rank == 1
                        ? [Colors.amber.shade600, Colors.amber.shade800]
                        : rank == 2
                            ? [
                                Colors.blueGrey.shade500,
                                Colors.blueGrey.shade700
                              ]
                            : [Colors.cyan.shade400, Colors.blue.shade600],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withOpacity(0.3),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: _buildRankIcon(rank),
              ),
              const SizedBox(height: 20),
              Text(
                username,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.cyan.shade300.withOpacity(0.2),
                      Colors.blue.shade500.withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.cyan.shade300.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  'Rank #$rank',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.cyan.shade200,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Text(
                          'Score',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.cyan.shade200,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$score',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 60,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    Column(
                      children: [
                        Text(
                          'Achievements',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.cyan.shade200,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(
                            3,
                            (i) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Iconsax.star,
                                color: i < rank
                                    ? Colors.amber
                                    : Colors.white.withOpacity(0.2),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
                  elevation: 8,
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _validateUsername(dynamic username) {
    if (username is String && username.isNotEmpty) {
      return username;
    }
    return 'Anonymous';
  }

  int _validateScore(dynamic score) {
    if (score is int && score >= 0) {
      return score;
    }
    return 0;
  }
}