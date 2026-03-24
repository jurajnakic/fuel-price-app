import 'package:flutter/material.dart';

class FuelListTile extends StatelessWidget {
  final String fuelName;
  final String price;
  final String unit;
  final String? trend;
  final VoidCallback onTap;

  const FuelListTile({
    super.key,
    required this.fuelName,
    required this.price,
    required this.unit,
    this.trend,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(fuelName),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$price $unit', style: Theme.of(context).textTheme.titleMedium),
          if (trend != null) ...[
            const SizedBox(width: 8),
            Text(
              trend!,
              style: TextStyle(
                fontSize: 18,
                color: _trendColor(trend!),
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }

  static Color _trendColor(String trend) {
    return switch (trend) {
      '↑' => Colors.red,
      '↓' => Colors.green,
      _ => Colors.grey,
    };
  }
}
