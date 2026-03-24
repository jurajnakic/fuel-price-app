import 'package:flutter/material.dart';
import 'package:fuel_price_app/models/fuel_type.dart';

class FuelDetailScreen extends StatelessWidget {
  final FuelType fuelType;

  const FuelDetailScreen({super.key, required this.fuelType});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(fuelType.displayName),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Predicted price card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: cs.primaryContainer,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        'Predviđena cijena',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '— €/${fuelType.unit.split('/').last}',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Za sljedeću promjenu cijene',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Price chart placeholder
            Text(
              'Kretanje cijene',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: cs.surfaceContainerLow,
                child: Center(
                  child: Text(
                    'Grafikon dolazi uskoro',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
