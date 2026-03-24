import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/ui/widgets/empty_state.dart';
import 'package:fuel_price_app/ui/widgets/sync_spinner.dart';

class FuelListScreen extends StatelessWidget {
  const FuelListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DataSyncCubit, DataSyncState>(
      listener: (context, state) {
        final cubit = context.read<DataSyncCubit>();
        if (state is SyncPartial && cubit.hasData) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ažuriranje nije u potpunosti uspjelo. Prikazani su posljednji dostupni podaci.',
              ),
            ),
          );
        } else if (state is SyncFailure && cubit.hasData) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ažuriranje nije uspjelo. Prikazani su posljednji dostupni podaci.',
              ),
            ),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<DataSyncCubit>();

        // No data states
        if (!cubit.hasData) {
          if (state is SyncInProgress) {
            return const SyncSpinner();
          }
          if (state is SyncFailure || state is SyncIdle) {
            return EmptyStateWidget(onRetry: () => cubit.sync());
          }
        }

        // Has data — show fuel list with pull-to-refresh
        return RefreshIndicator(
          onRefresh: () => cubit.sync(),
          child: Column(
            children: [
              if (cubit.lastSyncTime != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Zadnje ažuriranje: ${DateFormat('dd.MM.yyyy. HH:mm').format(cubit.lastSyncTime!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const Expanded(
                child: Center(
                  child: Text('Fuel list placeholder'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
