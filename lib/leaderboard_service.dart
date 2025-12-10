import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardService {
  final FirebaseFirestore firestore;

  LeaderboardService({required this.firestore});

  // Fetch the top 10 users from the leaderboard
  Future<List<Map<String, dynamic>>> fetchLeaderboard() async {
    try {
      QuerySnapshot snapshot = await firestore
          .collection('leaderboard')
          .orderBy('score', descending: true)
          .limit(100)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'userId': doc.id,
          'username': data['username'],
          'score': data['score'],
          'timestamp': data['timestamp']?.toDate(),
        };
      }).toList();
    } catch (e) {
      print("Error fetching leaderboard data: $e");
      return [];
    }
  }

  // Update the leaderboard with the user's cumulative score
  Future<void> updateLeaderboard(String userId, String username, int score) async {
    try {
      await firestore.collection('leaderboard').doc(userId).set({
        'username': username,
        'score': score,
        'timestamp': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (e) {
      print("Error updating leaderboard data: $e");
    }
  }

  // Check if the user can attempt the quiz today
  Future<bool> canAttemptQuiz(String userId) async {
    try {
      final doc = await firestore.collection('leaderboard').doc(userId).get();
      if (!doc.exists) return true;

      final data = doc.data()!;
      final lastAttempt = (data['timestamp'] as Timestamp).toDate();
      final now = DateTime.now();

      return !(lastAttempt.year == now.year &&
          lastAttempt.month == now.month &&
          lastAttempt.day == now.day);
    } catch (e) {
      print("Error checking attempt eligibility: $e");
      return true;
    }
  }

  // 🔁 Reset leaderboard after 7 days
  Future<void> resetLeaderboardIfNeeded() async {
    try {
      final metadataRef = firestore.collection('metadata').doc('leaderboard');
      final metadataSnap = await metadataRef.get();

      DateTime lastReset;

      if (!metadataSnap.exists) {
        lastReset = DateTime.now();
        await metadataRef.set({'lastReset': Timestamp.fromDate(lastReset)});
        return;
      } else {
        lastReset = (metadataSnap.data()!['lastReset'] as Timestamp).toDate();
      }

      final now = DateTime.now();
      final difference = now.difference(lastReset).inDays;

      if (difference >= 7) {
        final leaderboardSnapshot = await firestore.collection('leaderboard').get();
        for (var doc in leaderboardSnapshot.docs) {
          await doc.reference.update({'score': 0});
        }
        await metadataRef.update({'lastReset': Timestamp.fromDate(now)});
      }
    } catch (e) {
      print("Error resetting leaderboard: $e");
    }
  }

  // ✅ NEW: Check if the user is in Top 100 and eligible to spin today
  Future<bool> isEligibleToSpin(String userId) async {
    try {
      // 1. Get top 100 user IDs
      final topUsersSnapshot = await firestore
          .collection('leaderboard')
          .orderBy('score', descending: true)
          .limit(100)
          .get();

      final topUserIds = topUsersSnapshot.docs.map((doc) => doc.id).toList();

      if (!topUserIds.contains(userId)) {
        return false; // ❌ Not in Top 100
      }

      // 2. Check last spin
      final spinDoc = await firestore.collection('spins').doc(userId).get();

      if (!spinDoc.exists) {
        return true; // ✅ First time spinning
      }

      final lastSpin = (spinDoc.data()!['lastSpin'] as Timestamp).toDate();
      final now = DateTime.now();

      return !(lastSpin.year == now.year &&
          lastSpin.month == now.month &&
          lastSpin.day == now.day); // ✅ Only once per day
    } catch (e) {
      print("Error checking spin eligibility: $e");
      return false;
    }
  }

  // ✅ NEW: Log user spin
  Future<void> logUserSpin(String userId, String username) async {
    try {
      await firestore.collection('spins').doc(userId).set({
        'username': username,
        'lastSpin': Timestamp.now(),
      });
    } catch (e) {
      print("Error logging user spin: $e");
    }
  }
}
