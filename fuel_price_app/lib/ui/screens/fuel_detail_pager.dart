import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/ui/screens/fuel_detail_screen.dart';

class FuelDetailPager extends StatefulWidget {
  final FuelType initialFuelType;

  const FuelDetailPager({super.key, required this.initialFuelType});

  @override
  State<FuelDetailPager> createState() => _FuelDetailPagerState();
}

class _FuelDetailPagerState extends State<FuelDetailPager> {
  late final List<FuelType> _fuels;
  late int _currentIndex;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    final state = context.read<FuelListCubit>().state;
    _fuels = state.fuels.map((f) => f.fuelType).toList();
    _currentIndex = _fuels.indexOf(widget.initialFuelType).clamp(0, _fuels.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fuels.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nema goriva za prikaz')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_fuels[_currentIndex].displayName)),
      body: Column(
        children: [
          // Dot indicator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_fuels.length, (i) {
                return Container(
                  width: i == _currentIndex ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _currentIndex
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _fuels.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) => FuelDetailPage(fuelType: _fuels[i]),
            ),
          ),
        ],
      ),
    );
  }
}
