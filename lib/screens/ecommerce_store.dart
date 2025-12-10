import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:goal/screens/reward_controller.dart';
import 'package:goal/screens/reward_models.dart';

class EcommerceScreen extends StatefulWidget {
  final String userId;
  final String username; // Added username parameter

  const EcommerceScreen({
    super.key, 
    required this.userId,
    required this.username,
  });

  @override
  State<EcommerceScreen> createState() => _EcommerceScreenState();
}

class _EcommerceScreenState extends State<EcommerceScreen> {
  late RewardController _controller;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = RewardController(userId: widget.userId);
    _controller.loadData();
  }

  Future<void> _handlePurchase(RewardItem item) async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
    });

    try {
      await _controller.purchaseItem(item, widget.userId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully purchased ${item.title}!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("PDF Store"),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          actions: [
            Consumer<RewardController>(
              builder: (_, ctrl, __) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_balance_wallet, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        "₹${ctrl.walletBalance}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Consumer<RewardController>(
          builder: (_, controller, __) {
            if (controller.isLoading) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading PDF products...'),
                  ],
                ),
              );
            }

            if (controller.items.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No products available',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                await controller.loadData();
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: controller.items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (_, index) {
                  final item = controller.items[index];
                  final isPurchased = controller.isAlreadyPurchased(item.id);
                  final canAfford = controller.walletBalance >= item.price;

                  return Card(
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: InkWell(
                      onTap: () {
                        _showProductDetails(context, item, controller);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 80,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: item.image != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        item.image!,
                                        height: 80,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Icon(
                                            Icons.picture_as_pdf,
                                            size: 40,
                                            color: Colors.red,
                                          );
                                        },
                                      ),
                                    )
                                  : const Icon(
                                      Icons.picture_as_pdf,
                                      size: 40,
                                      color: Colors.red,
                                    ),
                            ),
                            const SizedBox(height: 8),
                            
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            
                            if (item.description != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.description!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            
                            const Spacer(),
                            
                            Row(
                              children: [
                                Text(
                                  "₹${item.price}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.deepPurple,
                                  ),
                                ),
                                const Spacer(),
                                if (isPurchased)
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                              ],
                            ),
                            
                            const SizedBox(height: 8),
                            
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isProcessing
                                    ? null
                                    : isPurchased
                                        ? () => controller.viewPdf(context, item)
                                        : canAfford
                                            ? () => _handlePurchase(item)
                                            : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isPurchased
                                      ? Colors.green
                                      : canAfford
                                          ? Colors.deepPurple
                                          : Colors.grey,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                child: _isProcessing
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Text(
                                        isPurchased
                                            ? "View PDF"
                                            : canAfford
                                                ? "Buy Now"
                                                : "Can't Afford",
                                        style: const TextStyle(fontSize: 12),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        
       
      ),
    );
  }

  void _showProductDetails(BuildContext context, RewardItem item, RewardController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ProductDetailsBottomSheet(
          item: item,
          currentBalance: controller.walletBalance,
          alreadyPurchased: controller.isAlreadyPurchased(item.id),
          onPurchase: (item) => _handlePurchase(item),
          onViewPdf: () {
            Navigator.pop(context);
            controller.viewPdf(context, item);
          },
        ),
      ),
    );
  }
}

class ProductDetailsBottomSheet extends StatelessWidget {
  final RewardItem item;
  final int currentBalance;
  final bool alreadyPurchased;
  final Future<void> Function(RewardItem) onPurchase;
  final VoidCallback? onViewPdf;

  const ProductDetailsBottomSheet({
    super.key,
    required this.item,
    required this.currentBalance,
    required this.alreadyPurchased,
    required this.onPurchase,
    this.onViewPdf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAfford = currentBalance >= item.price;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${item.price}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          if (item.description != null) ...[
            Text(
              item.description!,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Your Balance: ₹$currentBalance',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: alreadyPurchased
                ? ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('View PDF'),
                    onPressed: onViewPdf,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  )
                : ElevatedButton(
                    onPressed: canAfford
                        ? () async {
                            Navigator.pop(context);
                            await onPurchase(item);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAfford
                          ? theme.primaryColor
                          : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      canAfford
                          ? 'Buy Now - ₹${item.price}'
                          : 'Need ₹${item.price - currentBalance} more',
                    ),
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}