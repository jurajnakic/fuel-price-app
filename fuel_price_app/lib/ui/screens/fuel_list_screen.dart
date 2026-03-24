import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/ui/widgets/empty_state.dart';
import 'package:fuel_price_app/ui/widgets/sync_spinner.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/ui/screens/fuel_detail_screen.dart';
import 'package:fuel_price_app/ui/screens/settings_screen.dart';

class FuelListScreen extends StatelessWidget {
  const FuelListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cijene Goriva'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: BlocConsumer<DataSyncCubit, DataSyncState>(
        listener: _syncListener,
        builder: (context, syncState) {
          final syncCubit = context.read<DataSyncCubit>();

          // No data states
          if (!syncCubit.hasData) {
            if (syncState is SyncInProgress) {
              return const SyncSpinner();
            }
            if (syncState is SyncFailure || syncState is SyncIdle) {
              return EmptyStateWidget(onRetry: () => syncCubit.sync());
            }
          }

          // Has data — show fuel list
          return BlocBuilder<FuelListCubit, FuelListState>(
            builder: (context, state) {
              if (state.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              return RefreshIndicator(
                onRefresh: () => syncCubit.sync(),
                child: _FuelListBody(
                  fuels: state.fuels,
                  lastSyncTime: syncCubit.lastSyncTime,
                  onReorder: (oldIndex, newIndex) {
                    context.read<FuelListCubit>().reorder(oldIndex, newIndex);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _syncListener(BuildContext context, DataSyncState state) {
    final syncCubit = context.read<DataSyncCubit>();
    if (state is SyncPartial && syncCubit.hasData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ažuriranje nije u potpunosti uspjelo. Prikazani su posljednji dostupni podaci.'),
        ),
      );
    } else if (state is SyncFailure && syncCubit.hasData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ažuriranje nije uspjelo. Prikazani su posljednji dostupni podaci.'),
        ),
      );
    }
  }
}

class _FuelListBody extends StatelessWidget {
  final List<FuelListItem> fuels;
  final DateTime? lastSyncTime;
  final void Function(int, int) onReorder;

  const _FuelListBody({
    required this.fuels,
    required this.lastSyncTime,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        // Last sync timestamp
        if (lastSyncTime != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Zadnje ažuriranje: ${DateFormat('dd.MM.yyyy. HH:mm').format(lastSyncTime!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),

        // Fuel list
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverReorderableList(
            itemCount: fuels.length,
            itemBuilder: (context, index) {
              final item = fuels[index];
              return ReorderableDragStartListener(
                key: ValueKey(item.fuelType),
                index: index,
                child: _FuelCard(
                  item: item,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FuelDetailScreen(
                        fuelType: item.fuelType,
                      ),
                    ),
                  ),
                ),
              );
            },
            onReorder: onReorder,
          ),
        ),
      ],
    );
  }
}

class _FuelCard extends StatelessWidget {
  final FuelListItem item;
  final VoidCallback onTap;

  const _FuelCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayPrice = item.predictedPrice ?? item.currentPrice;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // Fuel icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _fuelIcon(item.fuelType),
                  color: cs.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),

              // Fuel name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fuelType.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (item.predictedPrice != null)
                      Text(
                        'Predviđena cijena',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),

              // Price + trend
              if (displayPrice != null) ...[
                Text(
                  '${displayPrice.toStringAsFixed(2)} €',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.trend != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    item.trend!,
                    style: TextStyle(
                      fontSize: 20,
                      color: _trendColor(item.trend!, cs),
                    ),
                  ),
                ],
              ] else
                Text(
                  '—',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),

              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _fuelIcon(FuelType ft) {
    return switch (ft) {
      FuelType.es95 || FuelType.es100 => Icons.local_gas_station,
      FuelType.eurodizel => Icons.local_gas_station_outlined,
      FuelType.unp10kg => Icons.propane_tank_outlined,
    };
  }

  static Color _trendColor(String trend, ColorScheme cs) {
    return switch (trend) {
      '↑' => Colors.red.shade400,
      '↓' => Colors.green.shade400,
      _ => cs.onSurfaceVariant,
    };
  }
}
