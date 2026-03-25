import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fuel_price_app/models/station.dart' show Station, formatDateCroatian;

class StationDetailScreen extends StatelessWidget {
  final Station station;

  const StationDetailScreen({super.key, required this.station});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sortedFuels = station.sortedFuels;

    return Scaffold(
      appBar: AppBar(title: Text(station.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Ažurirano: ${formatDateCroatian(station.updated)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ...sortedFuels.map((fuel) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: cs.surfaceContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(fuel.name, style: Theme.of(context).textTheme.bodyLarge),
                      ),
                      Text(
                        '${fuel.price.toStringAsFixed(2)} €',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 16),
          if (station.url.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                try {
                  final uri = Uri.parse(station.url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (_) {
                  // Silently ignore malformed URLs or launch failures
                }
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Izvor cijena'),
            ),
        ],
      ),
    );
  }
}
