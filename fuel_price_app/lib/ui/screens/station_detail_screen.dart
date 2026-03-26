import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fuel_price_app/models/station.dart';

class StationDetailScreen extends StatefulWidget {
  final Station station;

  const StationDetailScreen({super.key, required this.station});

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  bool _ascending = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = widget.station.groupedFuels(ascending: _ascending);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.station.name),
        actions: [
          IconButton(
            icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
            tooltip: _ascending ? 'Najjeftinije prvo' : 'Najskuplje prvo',
            onPressed: () => setState(() => _ascending = !_ascending),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Ažurirano: ${formatDateCroatian(widget.station.updated)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          for (final group in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4),
              child: Text(
                group.category.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...group.fuels.map((fuel) => Card(
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
                          '${fuel.price.toStringAsFixed(2)} \u20AC',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
          const SizedBox(height: 16),
          if (widget.station.url.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                try {
                  final uri = Uri.parse(widget.station.url);
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
