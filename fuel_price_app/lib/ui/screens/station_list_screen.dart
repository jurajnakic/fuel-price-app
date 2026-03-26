import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fuel_price_app/blocs/stations_cubit.dart';
import 'package:fuel_price_app/models/station.dart' show Station, formatDateCroatian;
import 'station_detail_pager.dart';

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

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                sliver: SliverReorderableList(
                  itemCount: state.stations.length,
                  itemBuilder: (context, index) {
                    final station = state.stations[index];
                    return ReorderableDragStartListener(
                      key: ValueKey(station.id),
                      index: index,
                      child: _StationTile(
                        station: station,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StationDetailPager(initialStation: station),
                          ),
                        ),
                      ),
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    context.read<StationsCubit>().reorder(oldIndex, newIndex);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StationTile extends StatelessWidget {
  final Station station;
  final VoidCallback onTap;
  const _StationTile({required this.station, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: cs.surfaceContainer,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
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
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
