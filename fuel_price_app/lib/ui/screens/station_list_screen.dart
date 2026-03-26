import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fuel_price_app/blocs/stations_cubit.dart';
import 'package:fuel_price_app/models/station.dart' show Station, formatDateCroatian;
import 'station_detail_screen.dart';

class StationListScreen extends StatefulWidget {
  const StationListScreen({super.key});

  @override
  State<StationListScreen> createState() => _StationListScreenState();
}

class _StationListScreenState extends State<StationListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cijene na postajama'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Osvježi',
            onPressed: () => context.read<StationsCubit>().refresh(),
          ),
        ],
      ),
      body: BlocBuilder<StationsCubit, StationsState>(
        builder: (context, state) {
          if (state.isLoading && state.stations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.hasError && state.stations.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text('Nema podataka. Provjerite internetsku vezu.'),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => context.read<StationsCubit>().refresh(),
                    child: const Text('Pokušaj ponovo'),
                  ),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: state.stations.length,
            onReorder: (oldIndex, newIndex) {
              context.read<StationsCubit>().reorder(oldIndex, newIndex);
            },
            proxyDecorator: (child, index, animation) {
              return Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(16),
                color: Colors.transparent,
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final station = state.stations[index];
              return _StationTile(
                key: ValueKey(station.id),
                station: station,
                index: index,
              );
            },
          );
        },
      ),
    );
  }
}

class _StationTile extends StatelessWidget {
  final Station station;
  final int index;
  const _StationTile({super.key, required this.station, required this.index});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: cs.surfaceContainer,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => StationDetailScreen(station: station)),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.local_gas_station, color: cs.onPrimaryContainer, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(station.name, style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        'Ažurirano: ${formatDateCroatian(station.updated)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle, color: cs.onSurfaceVariant, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
