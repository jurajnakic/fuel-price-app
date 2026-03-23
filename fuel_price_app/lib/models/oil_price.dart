class OilPrice {
  final int? id;
  final DateTime date;
  final double cifMed;
  final String source;

  const OilPrice({this.id, required this.date, required this.cifMed, required this.source});

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'date': date.toIso8601String().substring(0, 10),
    'cif_med': cifMed,
    'source': source,
  };

  factory OilPrice.fromMap(Map<String, dynamic> map) => OilPrice(
    id: map['id'] as int?,
    date: DateTime.parse(map['date'] as String),
    cifMed: (map['cif_med'] as num).toDouble(),
    source: map['source'] as String,
  );
}
