import 'fuel_type.dart';

class FuelPrice {
  final int? id;
  final FuelType fuelType;
  final DateTime date;
  final double price;
  final bool isPrediction;

  const FuelPrice({
    this.id,
    required this.fuelType,
    required this.date,
    required this.price,
    required this.isPrediction,
  });

  double get roundedPrice => (price * 100).round() / 100;
  String get formattedPrice => roundedPrice.toStringAsFixed(2);

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'fuel_type': fuelType.name,
    'date': date.toIso8601String().substring(0, 10),
    'price': price,
    'is_prediction': isPrediction ? 1 : 0,
  };

  factory FuelPrice.fromMap(Map<String, dynamic> map) => FuelPrice(
    id: map['id'] as int?,
    fuelType: FuelType.values.byName(map['fuel_type'] as String),
    date: DateTime.parse(map['date'] as String),
    price: (map['price'] as num).toDouble(),
    isPrediction: (map['is_prediction'] as int) == 1,
  );
}
