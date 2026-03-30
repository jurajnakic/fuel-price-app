import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/ui/widgets/empty_state.dart';
import 'package:fuel_price_app/ui/widgets/sync_spinner.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/ui/screens/fuel_detail_pager.dart';
class FuelListScreen extends StatelessWidget {
  const FuelListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Procjena'),
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
                onRefresh: () async {
                  await syncCubit.sync();
                  if (context.mounted) {
                    await context.read<FuelListCubit>().load();
                  }
                },
                child: _FuelListBody(
                  fuels: state.fuels,
                  currentPeriodStart: state.currentPeriodStart,
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
  final DateTime? currentPeriodStart;
  final DateTime? lastSyncTime;
  final void Function(int, int) onReorder;

  const _FuelListBody({
    required this.fuels,
    this.currentPeriodStart,
    required this.lastSyncTime,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        // Header with sync time and info button
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    lastSyncTime != null
                        ? 'Zadnje ažuriranje: ${DateFormat('dd.MM.yyyy. HH:mm').format(lastSyncTime!)}'
                        : '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('O cijenama'),
                      content: const Text(
                        'Prikazane cijene izračunate su prema formuli iz Uredbe '
                        'o utvrđivanju marži za naftne derivate (NN 31/2025), '
                        'na temelju prosječnih tržišnih cijena sirovina i tečaja '
                        'EUR/USD u prethodnom 14-dnevnom razdoblju.\n\n'
                        'Predviđene cijene procjenjuju cijenu za sljedeće '
                        'razdoblje na temelju trenutnih tržišnih podataka.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('U redu'),
                        ),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.help_outline,
                      size: 20,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
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
              return ReorderableDelayedDragStartListener(
                key: ValueKey(item.fuelType),
                index: index,
                child: _FuelCard(
                  item: item,
                  currentPeriodStart: currentPeriodStart,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FuelDetailPager(
                        initialFuelType: item.fuelType,
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
  final DateTime? currentPeriodStart;

  const _FuelCard({required this.item, required this.onTap, this.currentPeriodStart});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayPrice = item.currentPrice;

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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              // Fuel icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _fuelIcon(item.fuelType),
                  color: cs.onPrimaryContainer,
                  size: 26,
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
                    Text(
                      displayPrice != null
                          ? (currentPeriodStart != null
                              ? 'Cijena na ${DateFormat('d.M.yyyy.').format(currentPeriodStart!)}'
                              : 'Cijena')
                          : 'Nema podataka',
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
