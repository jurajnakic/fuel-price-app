import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/data/services/data_sync_orchestrator.dart';
import 'package:fuel_price_app/ui/screens/fuel_list_screen.dart';
import 'package:fuel_price_app/ui/theme.dart';

class FuelPriceApp extends StatelessWidget {
  const FuelPriceApp({super.key});

  @override
  Widget build(BuildContext context) {
    setupEdgeToEdge(MediaQuery.platformBrightnessOf(context));

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => DataSyncCubit(
            orchestrator: DataSyncOrchestrator(
              fetchOilPrices: () async => throw UnimplementedError(),
              fetchExchangeRates: () async => throw UnimplementedError(),
              fetchConfig: () async => throw UnimplementedError(),
            ),
            onSyncResult: (_) async {},
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Cijene Goriva',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
        home: const FuelListScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
