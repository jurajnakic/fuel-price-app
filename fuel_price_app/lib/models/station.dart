class StationFuel {
  final String name;
  final String type;
  final double price;

  const StationFuel({
    required this.name,
    required this.type,
    required this.price,
  });

  factory StationFuel.fromJson(Map<String, dynamic> json) => StationFuel(
        name: json['name'] as String,
        type: json['type'] as String,
        price: (json['price'] as num).toDouble(),
      );

  static const _sortOrder = ['es95', 'es100', 'eurodizel', 'lpg', 'unp10kg'];

  int get sortIndex {
    final idx = _sortOrder.indexOf(type);
    return idx >= 0 ? idx : 999;
  }
}

class Station {
  final String id;
  final String name;
  final String url;
  final String updated;
  final List<StationFuel> fuels;

  const Station({
    required this.id,
    required this.name,
    required this.url,
    required this.updated,
    required this.fuels,
  });

  factory Station.fromJson(Map<String, dynamic> json) => Station(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        updated: json['updated'] as String,
        fuels: (json['fuels'] as List)
            .map((f) => StationFuel.fromJson(f as Map<String, dynamic>))
            .toList(),
      );

  List<StationFuel> get sortedFuels {
    final sorted = List<StationFuel>.from(fuels);
    sorted.sort((a, b) {
      final cmp = a.sortIndex.compareTo(b.sortIndex);
      if (cmp != 0) return cmp;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }
}

class StationsResponse {
  final String updated;
  final List<Station> stations;

  const StationsResponse({required this.updated, required this.stations});

  factory StationsResponse.fromJson(Map<String, dynamic> json) =>
      StationsResponse(
        updated: json['updated'] as String,
        stations: (json['stations'] as List)
            .map((s) => Station.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

/// Format ISO date string (YYYY-MM-DD) to Croatian format (DD.MM.YYYY.)
String formatDateCroatian(String dateStr) {
  try {
    final parts = dateStr.split('-');
    return '${parts[2]}.${parts[1]}.${parts[0]}.';
  } catch (_) {
    return dateStr;
  }
}
