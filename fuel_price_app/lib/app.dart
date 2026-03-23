import 'package:flutter/material.dart';

class FuelPriceApp extends StatelessWidget {
  const FuelPriceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuel Price Predictor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Fuel Price App'),
        ),
      ),
    );
  }
}
