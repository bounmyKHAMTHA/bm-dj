class TimePackageModel {
  final int id;
  final String name;
  final String description;
  final int seconds;
  final String hoursDisplay;
  final bool isUnlimited;
  final double originalPrice;
  final double? discountPrice;
  final double currentPrice;
  final bool isOnSale;
  final bool isHot;

  TimePackageModel({
    required this.id,
    required this.name,
    required this.description,
    required this.seconds,
    required this.hoursDisplay,
    required this.isUnlimited,
    required this.originalPrice,
    this.discountPrice,
    required this.currentPrice,
    required this.isOnSale,
    required this.isHot,
  });

  factory TimePackageModel.fromJson(Map<String, dynamic> json) {
    return TimePackageModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      seconds: (json['seconds'] as num?)?.toInt() ?? 0,
      hoursDisplay: json['hours_display']?.toString() ?? '',
      isUnlimited: json['is_unlimited'] == true,
      originalPrice: (json['original_price'] as num?)?.toDouble() ?? 0.0,
      discountPrice: (json['discount_price'] as num?)?.toDouble(),
      currentPrice: (json['current_price'] as num?)?.toDouble() ?? 0.0,
      isOnSale: json['is_on_sale'] == true,
      isHot: json['is_hot'] == true,
    );
  }
}

