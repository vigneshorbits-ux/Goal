class RewardItem {
  final String id;
  final String title;
  final String? description;
  final String? image;
  final int price;
  final String? pdfUrl;
  

  RewardItem({
    required this.id,
    required this.title,
    this.description,
    this.image,
    required this.price,
    this.pdfUrl,
  });

  factory RewardItem.fromMap(Map<String, dynamic> data, String id) {
    return RewardItem(
      id: id,
      title: data['pdfname'] ?? 'Unnamed',
      description: data['description'],
      image: data['image'],
      price: data['price'] ?? 0,
      pdfUrl: data['pdfUrl'],

    );
  }
}