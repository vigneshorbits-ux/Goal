// admin_withdraw_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminWithdrawScreen extends StatefulWidget {
  const AdminWithdrawScreen({super.key});

  @override
  State<AdminWithdrawScreen> createState() => _AdminWithdrawScreenState();
}

class _AdminWithdrawScreenState extends State<AdminWithdrawScreen> {
  // State variables
  String _filterStatus = "pending";
  String _searchQuery = "";
  bool _isSigningOut = false;
  bool _isLoading = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  // Cache for user emails to avoid repeated Firestore calls
  final Map<String, String> _userEmailCache = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    // Debounce search to avoid too many rebuilds
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.trim());
      }
    });
  }

  Future<void> _signOut() async {
    final shouldLogout = await _showConfirmationDialog(
      context,
      title: 'Confirm Logout',
      message: 'Are you sure you want to logout?',
      confirmText: 'Logout',
      isDestructive: true,
    );

    if (shouldLogout != true) return;

    setState(() => _isSigningOut = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Logout failed: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  Future<String> _getUserEmail(String uid) async {
    // Return cached email if available
    if (_userEmailCache.containsKey(uid)) {
      return _userEmailCache[uid]!;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      
      final email = userDoc.data()?['email'] as String? ?? 'Unknown User';
      
      // Cache the result
      _userEmailCache[uid] = email;
      
      return email;
    } catch (e) {
      return 'User Not Found';
    }
  }

  List<Map<String, dynamic>> _flattenWithdrawals(
      QuerySnapshot snapshot) {
    final List<Map<String, dynamic>> withdrawals = [];
    
    for (var doc in snapshot.docs) {
      final uid = doc.id;
      final walletData = doc.data() as Map<String, dynamic>;
      final userWithdrawals = (walletData['withdrawals'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      for (var withdrawal in userWithdrawals) {
        withdrawals.add({
          ...withdrawal,
          'uid': uid,
          'docId': doc.id, // Store document ID for updates
        });
      }
    }

    // Sort by date descending
    withdrawals.sort((a, b) =>
        (b['date'] as Timestamp).compareTo(a['date'] as Timestamp));

    return _filterWithdrawals(withdrawals);
  }

  List<Map<String, dynamic>> _filterWithdrawals(List<Map<String, dynamic>> withdrawals) {
    List<Map<String, dynamic>> filtered = withdrawals;

    // Filter by status
    if (_filterStatus != "all") {
      filtered = filtered
          .where((w) => (w['status'] ?? 'pending') == _filterStatus)
          .toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((w) {
        final upi = (w['upi_id'] ?? '').toString().toLowerCase();
        final uid = (w['uid'] ?? '').toString().toLowerCase();
        final amount = (w['amount'] ?? 0).toString();
        
        return upi.contains(query) ||
            uid.contains(query) ||
            amount.contains(query) ||
            (w['email']?.toString().toLowerCase().contains(query) ?? false);
      }).toList();
    }

    return filtered;
  }

  Future<void> _updateStatus(
      String uid, Map<String, dynamic> withdrawal, String status) async {
    try {
      setState(() => _isLoading = true);
      
      final firestore = FirebaseFirestore.instance;
      final docRef = firestore.collection('wallets').doc(uid);
      
      // Use transaction for data consistency
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) throw Exception("Wallet document not found");
        
        final withdrawals = List<Map<String, dynamic>>.from(snapshot['withdrawals'] ?? []);
        final index = withdrawals.indexWhere((w) =>
            w['amount'] == withdrawal['amount'] &&
            (w['date'] as Timestamp).seconds ==
                (withdrawal['date'] as Timestamp).seconds &&
            w['upi_id'] == withdrawal['upi_id']);

        if (index == -1) {
          throw Exception("Matching withdrawal not found");
        }

        // Update withdrawal status and add processed timestamp
        withdrawals[index] = {
          ...withdrawals[index],
          'status': status,
          'processedAt': FieldValue.serverTimestamp(),
          'processedBy': FirebaseAuth.instance.currentUser?.uid,
        };

        transaction.update(docRef, {'withdrawals': withdrawals});
      });

      if (mounted) {
        _showSuccessSnackBar('Withdrawal $status successfully');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar("Failed to update: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool?> _showConfirmationDialog(BuildContext context,
      {required String title,
      required String message,
      String confirmText = 'Confirm',
      bool isDestructive = false}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : Colors.green,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildStatusFilterChip(String status, String label, Color color) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: _filterStatus == status ? Colors.white : color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      selected: _filterStatus == status,
      onSelected: (selected) => setState(() => _filterStatus = status),
      selectedColor: color,
      backgroundColor: Colors.grey[200],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildWithdrawalCard(Map<String, dynamic> withdrawal) {
    final date = (withdrawal['date'] as Timestamp).toDate();
    final status = withdrawal['status'] ?? 'pending';
    final upiId = withdrawal['upi_id'] ?? '';
    final uid = withdrawal['uid'];
    final amount = (withdrawal['amount'] as num).toDouble();
    final statusColor = {
      'pending': Colors.orange,
      'completed': Colors.green,
      'rejected': Colors.red,
    }[status] ?? Colors.grey;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with amount and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₹${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Details section
            _buildDetailRow(Icons.payment, 'UPI ID', upiId),
            _buildDetailRow(Icons.calendar_today, 'Date', 
                DateFormat('MMM dd, yyyy - hh:mm a').format(date)),
            
            // User email with caching
            FutureBuilder<String>(
              future: _getUserEmail(uid),
              builder: (ctx, snap) => _buildDetailRow(
                Icons.person, 
                'User', 
                snap.data ?? 'Loading...',
                isHighlighted: true,
              ),
            ),

            // Action buttons for pending withdrawals
            if (status == 'pending') ...[
              const SizedBox(height: 16),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () => _handleStatusUpdate(uid, withdrawal, 'rejected'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _handleStatusUpdate(uid, withdrawal, 'completed'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: isHighlighted ? Colors.indigo : Colors.black87,
                    fontWeight: isHighlighted ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStatusUpdate(
      String uid, Map<String, dynamic> withdrawal, String status) async {
    final action = status == 'completed' ? 'Approve' : 'Reject';
    final confirm = await _showConfirmationDialog(
      context,
      title: '$action Withdrawal?',
      message: 'Amount: ₹${withdrawal['amount']}\nUPI: ${withdrawal['upi_id']}\n\nAre you sure you want to $action this withdrawal?',
      confirmText: action,
      isDestructive: status == 'rejected',
    );

    if (confirm == true) {
      await _updateStatus(uid, withdrawal, status);
    }
  }

  Widget _buildHeaderSection() {
    return Column(
      children: [
        // Upload PDF Button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.upload_file, size: 20),
                  label: const Text(
                    'Upload PDF Product',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  onPressed: () {
                    Navigator.pushNamed(context, '/admin-upload-pdf');
                  },
                ),
              ),
            ],
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Search by UPI, UID, amount...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey[100],
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                        _searchFocusNode.unfocus();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Status Filter Chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildStatusFilterChip('all', 'All', Colors.blue),
              const SizedBox(width: 8),
              _buildStatusFilterChip('pending', 'Pending', Colors.orange),
              const SizedBox(width: 8),
              _buildStatusFilterChip('completed', 'Completed', Colors.green),
              const SizedBox(width: 8),
              _buildStatusFilterChip('rejected', 'Rejected', Colors.red),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty 
                ? "No withdrawals match your search"
                : "No withdrawal requests found",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? "Try adjusting your search criteria"
                : "Check back later for new requests",
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Withdrawal Requests',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: _isSigningOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout, color: Colors.red),
            tooltip: "Sign Out",
            onPressed: _isSigningOut ? null : _signOut,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeaderSection(),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('wallets')
                        .where('withdrawals', isNotEqualTo: [])
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(
                                'Error loading withdrawals',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _buildEmptyState();
                      }

                      final filtered = _flattenWithdrawals(snapshot.data!);

                      if (filtered.isEmpty) {
                        return _buildEmptyState();
                      }

                      return RefreshIndicator(
                        onRefresh: () async => setState(() {}),
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, idx) => _buildWithdrawalCard(filtered[idx]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}