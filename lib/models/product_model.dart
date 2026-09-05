class ProductModel {
  final String id;
  final String name;
  final String category;
  final int price;
  final int adminFee;
  final bool isActive;
  final int? costPrice;

  ProductModel({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.adminFee,
    required this.isActive,
    this.costPrice,
  });

  factory ProductModel.fromMap(String id, Map<String, dynamic> map) {
    return ProductModel(
      id: id,
      name: map['name'] ?? '',
      category: map['category'] ?? '',
      price: (map['price'] as num?)?.toInt() ?? 0,
      adminFee: (map['adminFee'] as num?)?.toInt() ?? 0,
      isActive: map['isActive'] ?? true,
      costPrice: (map['costPrice'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category,
      'price': price,
      'adminFee': adminFee,
      'isActive': isActive,
      if (costPrice != null) 'costPrice': costPrice,
    };
  }
}