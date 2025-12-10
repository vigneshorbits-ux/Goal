import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:goal/screens/reward_models.dart' as reward_models;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RewardController extends ChangeNotifier {
  List<reward_models.RewardItem> _items = [];
  List<reward_models.RewardItem> get items => _items;
  
  int _walletBalance = 0;
  int get walletBalance => _walletBalance;
  
  Set<String> _purchasedIds = {};
  Set<String> get purchasedIds => _purchasedIds;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  // Ad-related properties
  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdReady = false;
  bool _isAdLoading = false;
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String userId;

  RewardController({required this.userId});
bool _isProcessing = false;
  bool get isProcessing => _isProcessing;
  
  void setProcessing(bool value) {
    _isProcessing = value;
    notifyListeners();
  }
  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  /// Initialize the controller with wallet balance and load ads
  void initialize(int initialBalance) {
    _walletBalance = initialBalance;
    _loadInterstitialAd();
    notifyListeners();
  }

  /// Load Interstitial Ad
  void _loadInterstitialAd() {
    if (_isAdLoading) return;
    
    _isAdLoading = true;
    InterstitialAd.load(
      adUnitId: Platform.isAndroid 
          ? 'ca-app-pub-3073965007969718/3512858301'  // Your Android ad unit ID
          : 'ca-app-pub-3073965007969718/3512858301', // Your iOS ad unit ID (replace with actual iOS ID)
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdReady = true;
          _isAdLoading = false;
          debugPrint('Interstitial Ad loaded successfully');
          
          // Set up ad event callbacks
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {
              debugPrint('Interstitial ad showed full screen content');
            },
            onAdDismissedFullScreenContent: (ad) {
              debugPrint('Interstitial ad dismissed');
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialAdReady = false;
              // Preload next ad
              Future.delayed(const Duration(seconds: 1), () {
                _loadInterstitialAd();
              });
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('Interstitial ad failed to show: $error');
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialAdReady = false;
              // Retry loading
              Future.delayed(const Duration(seconds: 2), () {
                _loadInterstitialAd();
              });
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isAdLoading = false;
          debugPrint('Interstitial Ad failed to load: $error');
          // Retry loading after a delay
          Future.delayed(const Duration(seconds: 5), () {
            _loadInterstitialAd();
          });
        },
      ),
    );
  }

  /// Show Interstitial Ad before spin
  Future<bool> showInterstitialAd() async {
    if (_isInterstitialAdReady && _interstitialAd != null) {
      try {
        await _interstitialAd!.show();
        return true; // Ad was shown
      } catch (e) {
        debugPrint('Error showing interstitial ad: $e');
        return false; // Ad failed to show, but don't block user
      }
    } else {
      debugPrint('Interstitial ad not ready');
      // Try to load ad for next time
      if (!_isAdLoading) {
        _loadInterstitialAd();
      }
      return false; // No ad to show, but don't block user
    }
  }

  /// Check if ad is ready (optional - for UI feedback)
  bool get isAdReady => _isInterstitialAdReady;

  /// Load data from Firestore
  Future<void> loadData() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      await _loadWalletBalance();
      await _loadPurchasedItems();
      await _loadItemsFromFirestore();
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final doc = await _firestore.collection('wallets').doc(userId).get();
      if (doc.exists) {
        _walletBalance = (doc.data()?['wallet_balance'] ?? 0).toInt();
      } else {
        // Initialize wallet if it doesn't exist
        await _firestore.collection('wallets').doc(userId).set({
          'wallet_balance': 0,
          'last_updated': FieldValue.serverTimestamp(),
        });
        _walletBalance = 0;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading wallet balance: $e');
      // Fallback to local storage if needed
      final prefs = await SharedPreferences.getInstance();
      _walletBalance = prefs.getInt('walletBalance') ?? 0;
    }
  }

  Future<void> _updateWallet(int amount) async {
    try {
      await _firestore.collection('wallets').doc(userId).update({
        'wallet_balance': FieldValue.increment(amount),
        'last_updated': FieldValue.serverTimestamp(),
      });
      _walletBalance += amount;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating wallet: $e');
      throw Exception('Failed to update wallet');
    }
  }

  Future<void> _loadPurchasedItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _purchasedIds = prefs.getStringList('purchasedIds')?.toSet() ?? {};
    } catch (e) {
      debugPrint('Error loading purchased items: $e');
    }
  }

  Future<void> _savePurchasedItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('purchasedIds', _purchasedIds.toList());
    } catch (e) {
      debugPrint('Error saving purchased items: $e');
    }
  }

  Future<void> _loadItemsFromFirestore() async {
    try {
      final snapshot = await _firestore.collection('pdf_products').get();
      _items = snapshot.docs
          .map((doc) => reward_models.RewardItem.fromMap(doc.data(), doc.id))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading items from Firestore: $e');
    }
  }

  bool isAlreadyPurchased(String id) => _purchasedIds.contains(id);

  Future<void> purchaseItem(reward_models.RewardItem item, String userId) async {
    try {
      if (_walletBalance < item.price) {
        throw Exception('Insufficient balance. You need ₹${item.price - _walletBalance} more.');
      }

      if (_purchasedIds.contains(item.id)) {
        throw Exception('Item already purchased');
      }

      // Deduct balance from Firestore wallet
      await _updateWallet(-item.price);
      
      // Mark as purchased
      _purchasedIds.add(item.id);
      await _savePurchasedItems();
      
      // Record purchase in Firestore
      await _firestore
          .collection('users_pdf')
          .doc(userId)
          .collection('purchased_pdfs')
          .doc(item.id)
          .set({
        'title': item.title,
        'description': item.description,
        'pdfUrl': item.pdfUrl,
        'price': item.price,
        'purchasedAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('Purchase successful for item: ${item.title}');
    } catch (e) {
      debugPrint('Purchase failed: $e');
      rethrow;
    }
  }

  Future<String?> downloadPdf(String? url, String title) async {
    if (url == null || url.isEmpty) {
      debugPrint("Invalid PDF URL");
      return null;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      final filePath = "${dir.path}/$fileName.pdf";
      
      if (await File(filePath).exists()) {
        debugPrint("PDF already exists at: $filePath");
        return filePath;
      }

      debugPrint("Downloading PDF from: $url");
      final dio = Dio();
      
      final response = await dio.download(
        url, 
        filePath,
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 5),
        ),
      );
      
      if (response.statusCode == 200) {
        debugPrint("PDF downloaded successfully to: $filePath");
        return filePath;
      } else {
        debugPrint("Download failed with status: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("Download error: $e");
      return null;
    }
  }

  Future<void> viewPdf(BuildContext context, reward_models.RewardItem item) async {
    if (!_purchasedIds.contains(item.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need to purchase this PDF first')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Preparing PDF...'),
          ],
        ),
      ),
    );

    try {
      final filePath = await downloadPdf(item.pdfUrl, item.title);
      Navigator.of(context).pop();
      
      if (filePath != null && await File(filePath).exists()) {
        final result = await OpenFile.open(filePath);
        
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error opening PDF: ${result.message}')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download or open PDF')),
        );
      }
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> addBalance(int amount) async {
    await _updateWallet(amount);
  }

  Future<void> resetPurchases() async {
    _purchasedIds.clear();
    await _savePurchasedItems();
    notifyListeners();
  }

  void refreshBalance() {
    _loadWalletBalance();
  }
}