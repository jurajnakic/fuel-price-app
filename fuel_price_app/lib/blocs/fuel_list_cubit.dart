import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/domain/formula_engine.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/models/fuel_price.dart';

class FuelListItem extends Equatable {
  final FuelType fuelType;
  final double? currentPrice;
  final double? predictedPrice;
  final String? trend;

  const FuelListItem({
    required this.fuelType,
    this.currentPrice,
    this.predictedPrice,
    this.trend,
  });

  @override
  List<Object?> get props => [fuelType, currentPrice, predictedPrice, trend];
}

class FuelListState extends Equatable {
  final List<FuelListItem> fuels;
  final bool isLoading;

  const FuelListState({this.fuels = const [], this.isLoading = true});

  @override
  List<Object?> get props => [fuels, isLoading];
}

class FuelListCubit extends Cubit<FuelListState> {
  final PriceRepository priceRepo;
  final SettingsRepository settingsRepo;
  final FormulaEngine formulaEngine;

  FuelListCubit({
    required this.priceRepo,
    required this.settingsRepo,
    required this.formulaEngine,
  }) : super(const FuelListState());

  Future<void> load() async {
    final order = await settingsRepo.getFuelOrder();
    final visibility = await settingsRepo.getFuelVisibility();

    final items = <FuelListItem>[];
    for (final name in order) {
      if (visibility[name] != true) continue;

      final fuelType = FuelType.values.firstWhere((f) => f.name == name);
      final current = await priceRepo.getLatestPrice(fuelType, prediction: false);
      final predicted = await priceRepo.getLatestPrice(fuelType, prediction: true);

      final trend = predicted != null
          ? trendIndicator(predicted.price, current?.price)
          : null;

      items.add(FuelListItem(
        fuelType: fuelType,
        currentPrice: current?.roundedPrice,
        predictedPrice: predicted?.roundedPrice,
        trend: trend,
      ));
    }

    emit(FuelListState(fuels: items, isLoading: false));
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final fuels = List<FuelListItem>.from(state.fuels);
    if (newIndex > oldIndex) newIndex--;
    final item = fuels.removeAt(oldIndex);
    fuels.insert(newIndex, item);
    emit(FuelListState(fuels: fuels, isLoading: false));

    await settingsRepo.saveFuelOrder(fuels.map((f) => f.fuelType.name).toList());
  }
}
