import 'package:cloud_firestore/cloud_firestore.dart';
import 'reward_models.dart';

class RewardService {
  static Stream<List<RewardItem>> fetchRewardItems({int limit = 3}) {
    return FirebaseFirestore.instance
        .collection('pdf_products')
        .orderBy('price')
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RewardItem.fromMap(doc.data(), doc.id))
            .toList());
  }

  static Future<bool> isUserInTop100(String userId) async {
    if (userId.isEmpty) return false;
    
    final top100 = await FirebaseFirestore.instance
        .collection('leaderboard')
        .orderBy('score', descending: true)
        .limit(100)
        .get();
    
    return top100.docs.any((doc) => doc.id == userId);
  }
}