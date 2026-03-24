import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fuel app color seed — calm blue
const _seedColor = Color(0xFF4A6FA5);

final lightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.light,
  ),
  useMaterial3: true,
  cardTheme: const CardThemeData(
    elevation: 0,
    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  ),
  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
  ),
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    scrolledUnderElevation: 1,
  ),
);

final darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
  cardTheme: const CardThemeData(
    elevation: 0,
    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  ),
  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
  ),
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    scrolledUnderElevation: 1,
  ),
);

/// Set up edge-to-edge display
void setupEdgeToEdge(Brightness brightness) {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: brightness == Brightness.light ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: brightness == Brightness.light ? Brightness.dark : Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}
