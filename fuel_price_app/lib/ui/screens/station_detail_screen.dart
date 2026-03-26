import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fuel_price_app/models/station.dart';

/// Standalone detail screen (with Scaffold + AppBar)
class StationDetailScreen extends StatelessWidget {
  final Station station;

  const StationDetailScreen({super.key, required this.station});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(station.name)),
      body: StationDetailPage(station: station),
    );
  }
}

/// Detail page content (no Scaffold — used inside PageView)
class StationDetailPage extends StatefulWidget {
  final Station station;

  const StationDetailPage({super.key, required this.station});

  @override
  State<StationDetailPage> createState() => _StationDetailPageState();
}

class _StationDetailPageState extends State<StationDetailPage> {
  bool _ascending = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = widget.station.groupedFuels(ascending: _ascending);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Updated date
        Text(
          'Ažurirano: ${formatDateCroatian(widget.station.updated)}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),

        // Sort toggle chip
        Row(
          children: [
            ActionChip(
              avatar: Icon(
                _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 18,
              ),
              label: Text(_ascending ? 'Najjeftinije prvo' : 'Najskuplje prvo'),
              onPressed: () => setState(() => _ascending = !_ascending),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Grouped fuels
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
    );
  }
}
