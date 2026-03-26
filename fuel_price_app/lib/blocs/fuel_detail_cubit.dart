import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/fuel_type.dart';

class FuelDetailState extends Equatable {
  final FuelType fuelType;
  final double? currentPrice;
  final double? predictedPrice;
  final String? trend;
  final DateTime? lastChangeDate;
  final DateTime? nextChangeDate;
  final List<FuelPrice> priceHistory;
  final int chartDays;
  final bool isLoading;

  const FuelDetailState({
    required this.fuelType,
    this.currentPrice,
    this.predictedPrice,
    this.trend,
    this.lastChangeDate,
    this.nextChangeDate,
    this.priceHistory = const [],
    this.chartDays = 30,
    this.isLoading = true,
  });

  double? get priceDifference =>
      predictedPrice != null && currentPrice != null
          ? predictedPrice! - currentPrice!
          : null;

  @override
  List<Object?> get props => [
    fuelType, currentPrice, predictedPrice, trend,
    lastChangeDate, nextChangeDate, priceHistory, chartDays, isLoading,
  ];
}

class FuelDetailCubit extends Cubit<FuelDetailState> {
  final PriceRepository priceRepo;
  final DateTime referenceDate;
  final int cycleDays;

  FuelDetailCubit({
    required FuelType fuelType,
    required this.priceRepo,
    required this.referenceDate,
    required this.cycleDays,
  }) : super(FuelDetailState(fuelType: fuelType));

  Future<void> load() async {
    try {
      final ft = state.fuelType;
      final current = await priceRepo.getLatestPrice(ft, prediction: false);
      final predicted = await priceRepo.getLatestPrice(ft, prediction: true);
      final history = await priceRepo.getPriceHistory(ft, days: state.chartDays);

      final trend = predicted != null
          ? trendIndicator(predicted.price, current?.price)
          : null;

      final nextChange = nextPriceChangeDate(DateTime.now(), referenceDate, cycleDays);

      if (!isClosed) {
        emit(FuelDetailState(
          fuelType: ft,
          currentPrice: current?.roundedPrice,
          predictedPrice: predicted?.roundedPrice,
          trend: trend,
          lastChangeDate: current?.date,
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
      final history = await priceRepo.getPriceHistory(state.fuelType, days: days);
      if (!isClosed) {
        emit(FuelDetailState(
          fuelType: state.fuelType,
          currentPrice: state.currentPrice,
          predictedPrice: state.predictedPrice,
          trend: state.trend,
          lastChangeDate: state.lastChangeDate,
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
