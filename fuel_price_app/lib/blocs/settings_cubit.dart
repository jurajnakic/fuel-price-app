import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends Equatable {
  final ThemeMode themeMode;
  final Map<String, bool> fuelVisibility;
  final Map<String, bool> notificationFuels;
  final String notificationDay;
  final int notificationHour;
  final bool notificationsEnabled;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.fuelVisibility = const {},
    this.notificationFuels = const {},
    this.notificationDay = 'monday',
    this.notificationHour = 9,
    this.notificationsEnabled = true,
  });

  @override
  List<Object?> get props => [
    themeMode, fuelVisibility, notificationFuels,
    notificationDay, notificationHour, notificationsEnabled,
  ];

  SettingsState copyWith({
    ThemeMode? themeMode,
    Map<String, bool>? fuelVisibility,
    Map<String, bool>? notificationFuels,
    String? notificationDay,
    int? notificationHour,
    bool? notificationsEnabled,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      fuelVisibility: fuelVisibility ?? this.fuelVisibility,
      notificationFuels: notificationFuels ?? this.notificationFuels,
      notificationDay: notificationDay ?? this.notificationDay,
      notificationHour: notificationHour ?? this.notificationHour,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }
}

class SettingsCubit extends Cubit<SettingsState> {
  final SettingsRepository settingsRepo;

  SettingsCubit({required this.settingsRepo}) : super(const SettingsState());

  Future<void> load() async {
    final visibility = await settingsRepo.getFuelVisibility();
    final notifFuels = await settingsRepo.getNotificationFuels();
    final notifSettings = await settingsRepo.getNotificationSettings();

    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('theme_mode');
    final themeMode = switch (savedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    emit(state.copyWith(
      fuelVisibility: visibility,
      notificationFuels: notifFuels,
      notificationDay: notifSettings['day'] as String,
      notificationHour: notifSettings['hour'] as int,
      notificationsEnabled: (notifSettings['enabled'] as int) == 1,
      themeMode: themeMode,
    ));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString('theme_mode', value);
    emit(state.copyWith(themeMode: mode));
  }

  Future<void> toggleFuelVisibility(String fuelType) async {
    final current = state.fuelVisibility[fuelType] ?? true;
    await settingsRepo.setFuelVisibility(fuelType, !current);
    final updated = Map<String, bool>.from(state.fuelVisibility);
    updated[fuelType] = !current;
    emit(state.copyWith(fuelVisibility: updated));
  }

  Future<void> toggleNotificationFuel(String fuelType) async {
    final current = state.notificationFuels[fuelType] ?? true;
    await settingsRepo.setNotificationFuel(fuelType, !current);
    final updated = Map<String, bool>.from(state.notificationFuels);
    updated[fuelType] = !current;
    emit(state.copyWith(notificationFuels: updated));
  }

  Future<void> setNotificationDay(String day) async {
    await settingsRepo.saveNotificationSettings(day: day);
    emit(state.copyWith(notificationDay: day));
  }

  Future<void> setNotificationHour(int hour) async {
    await settingsRepo.saveNotificationSettings(hour: hour);
    emit(state.copyWith(notificationHour: hour));
  }

  Future<void> toggleNotifications() async {
    final newValue = !state.notificationsEnabled;
    await settingsRepo.saveNotificationSettings(enabled: newValue);
    emit(state.copyWith(notificationsEnabled: newValue));
  }
}
