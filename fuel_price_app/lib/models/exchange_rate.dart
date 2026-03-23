class ExchangeRate {
  final int? id;
  final DateTime date;
  final double usdEur;

  const ExchangeRate({this.id, required this.date, required this.usdEur});

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'date': date.toIso8601String().substring(0, 10),
    'usd_eur': usdEur,
  };

  factory ExchangeRate.fromMap(Map<String, dynamic> map) => ExchangeRate(
    id: map['id'] as int?,
    date: DateTime.parse(map['date'] as String),
    usdEur: (map['usd_eur'] as num).toDouble(),
  );
}
