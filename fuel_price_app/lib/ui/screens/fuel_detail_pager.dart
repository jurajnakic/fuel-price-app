import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fuel_price_app/blocs/fuel_list_cubit.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:fuel_price_app/ui/screens/fuel_detail_screen.dart';

/// Wraps FuelDetailScreen in a PageView for swipe navigation between fuels.
class FuelDetailPager extends StatefulWidget {
  final FuelType initialFuelType;

  const FuelDetailPager({super.key, required this.initialFuelType});

  @override
  State<FuelDetailPager> createState() => _FuelDetailPagerState();
}

class _FuelDetailPagerState extends State<FuelDetailPager> {
  late PageController _pageController;
  late List<FuelType> _fuels;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final fuelListState = context.read<FuelListCubit>().state;
    _fuels = fuelListState.fuels.map((f) => f.fuelType).toList();

    _currentIndex = _fuels.indexOf(widget.initialFuelType);
    if (_currentIndex < 0) _currentIndex = 0;

    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
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
      appBar: AppBar(
        title: AnimatedBuilder(
          animation: _pageController,
          builder: (context, _) {
            final page = _pageController.hasClients
                ? (_pageController.page?.round() ?? _currentIndex)
                : _currentIndex;
            return Text(_fuels[page].displayName);
          },
        ),
      ),
      body: Column(
        children: [
          // Dot indicator
          _DotIndicator(
            count: _fuels.length,
            controller: _pageController,
            initialIndex: _currentIndex,
          ),
          // PageView
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _fuels.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                return FuelDetailPage(fuelType: _fuels[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DotIndicator extends StatelessWidget {
  final int count;
  final PageController controller;
  final int initialIndex;

  const _DotIndicator({
    required this.count,
    required this.controller,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients
            ? (controller.page?.round() ?? initialIndex)
            : initialIndex;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(count, (i) {
              return Container(
                width: i == page ? 24 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == page ? cs.primary : cs.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
