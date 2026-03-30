import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';
import 'package:fuel_price_app/models/fuel_params.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/fuel_type.dart';

class FuelDetailState extends Equatable {
  final FuelType fuelType;
  final double? predictedPrice;
  final double? previousPrice;
  final DateTime? nextChangeDate;
  final List<FuelPrice> priceHistory;
  final int chartDays;
  final bool isLoading;

  const FuelDetailState({
    required this.fuelType,
    this.predictedPrice,
    this.previousPrice,
    this.nextChangeDate,
    this.priceHistory = const [],
    this.chartDays = 30,
    this.isLoading = true,
  });

  double? get priceDifference =>
      predictedPrice != null && previousPrice != null
          ? predictedPrice! - previousPrice!
          : null;

  String? get trend {
    final diff = priceDifference;
    if (diff == null) return null;
    if (diff > 0.005) return '↑';
    if (diff < -0.005) return '↓';
    return '→';
  }

  @override
  List<Object?> get props => [
    fuelType, predictedPrice, previousPrice, nextChangeDate,
    priceHistory, chartDays, isLoading,
  ];
}

class FuelDetailCubit extends Cubit<FuelDetailState> {
  final PriceRepository priceRepo;
  final FuelParams params;
  final DateTime referenceDate;
  final int cycleDays;

  FuelDetailCubit({
    required FuelType fuelType,
    required this.priceRepo,
    required this.params,
    required this.referenceDate,
    required this.cycleDays,
  }) : super(FuelDetailState(fuelType: fuelType));

  Future<void> load() async {
    try {
      final ft = state.fuelType;
      final predicted = await priceRepo.getLatestPrice(ft, prediction: true);
      final current = await priceRepo.getLatestPrice(ft, prediction: false);

      final history = await priceRepo.getCalculatedHistory(
        ft,
        days: state.chartDays,
        params: params,
      );

      final nextChange = nextPriceChangeDate(DateTime.now(), referenceDate, cycleDays);

      if (!isClosed) {
        emit(FuelDetailState(
          fuelType: ft,
          predictedPrice: predicted?.roundedPrice,
          previousPrice: current?.roundedPrice,
          nextChangeDate: nextChange,
          priceHistory: history,
          chartDays: state.chartDays,
          isLoading: false,
        ));
      }
    } catch (_) {
      if (!isClosed) {
        emit(FuelDetailState(fuelType: state.fuelType, isLoading: false));
      }
    }
  }

  Future<void> setChartPeriod(int days) async {
    try {
      final history = await priceRepo.getCalculatedHistory(
        state.fuelType,
        days: days,
        params: params,
      );
      if (!isClosed) {
        emit(FuelDetailState(
          fuelType: state.fuelType,
          predictedPrice: state.predictedPrice,
          previousPrice: state.previousPrice,
          nextChangeDate: state.nextChangeDate,
          priceHistory: history,
          chartDays: days,
          isLoading: false,
        ));
      }
    } catch (_) {
      // Keep current state on error
    }
  }
}
