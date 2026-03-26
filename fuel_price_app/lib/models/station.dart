/// Fuel category for grouping station fuels by type.
enum FuelCategory {
  eurosuper('Eurosuper', 0),
  eurodizel('Eurodizel', 1),
  lpg('LPG / UNP', 2),
  ostalo('Ostalo', 3);

  const FuelCategory(this.label, this.sortOrder);
  final String label;
  final int sortOrder;
}

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

  /// Returns the fuel category for grouping purposes.
  FuelCategory get category {
    if (type.startsWith('es')) return FuelCategory.eurosuper;
    if (type.startsWith('eurodizel')) return FuelCategory.eurodizel;
    if (type == 'lpg' || type == 'unp10kg') return FuelCategory.lpg;
    // Heuristic: check name for common patterns
    final nameLower = name.toLowerCase();
    if (nameLower.contains('eurosuper') || nameLower.contains('es ') ||
        nameLower.contains('super') || nameLower.contains('benzin')) {
      return FuelCategory.eurosuper;
    }
    if (nameLower.contains('dizel') || nameLower.contains('diesel')) {
      return FuelCategory.eurodizel;
    }
    if (nameLower.contains('lpg') || nameLower.contains('unp') ||
        nameLower.contains('autoplin')) {
      return FuelCategory.lpg;
    }
    return FuelCategory.ostalo;
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

  /// Returns fuels grouped by category, sorted by price within each group.
  /// [ascending] controls price sort direction within each category.
  List<({FuelCategory category, List<StationFuel> fuels})> groupedFuels({
    bool ascending = true,
  }) {
    final groups = <FuelCategory, List<StationFuel>>{};
    for (final fuel in fuels) {
      (groups[fuel.category] ??= []).add(fuel);
    }

    // Sort fuels within each group by price
    for (final list in groups.values) {
      list.sort((a, b) => ascending
          ? a.price.compareTo(b.price)
          : b.price.compareTo(a.price));
    }

    // Sort groups by category order
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.sortOrder.compareTo(b.key.sortOrder));

    return entries
        .map((e) => (category: e.key, fuels: e.value))
        .toList();
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
