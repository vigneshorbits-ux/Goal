// product_widgets.dart
import 'package:flutter/material.dart';
import 'package:goal/screens/reward_models.dart';

class ProductCard extends StatelessWidget {
  final RewardItem item;
  final int currentBalance;
  final bool alreadyPurchased;
  final Future<void> Function(RewardItem) onPurchase;
  final VoidCallback? onViewPdf;

  const ProductCard({
    super.key,
    required this.item,
    required this.currentBalance,
    required this.alreadyPurchased,
    required this.onPurchase,
    this.onViewPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Price: ₹${item.price}", style: const TextStyle(fontSize: 14)),
            const Spacer(),
            ElevatedButton(
              onPressed: alreadyPurchased
                  ? onViewPdf
                  : () async {
                      if (currentBalance >= item.price) {
                        await onPurchase(item);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Insufficient balance")),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: alreadyPurchased ? Colors.green : Colors.deepPurple,
              ),
              child: Text(alreadyPurchased ? "View PDF" : "Buy Now"),
            ),
          ],
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