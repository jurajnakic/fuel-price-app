import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fuel_price_app/blocs/stations_cubit.dart';
import 'package:fuel_price_app/models/station.dart';
import 'package:fuel_price_app/ui/screens/station_detail_screen.dart';

class StationDetailPager extends StatefulWidget {
  final Station initialStation;

  const StationDetailPager({super.key, required this.initialStation});

  @override
  State<StationDetailPager> createState() => _StationDetailPagerState();
}

class _StationDetailPagerState extends State<StationDetailPager> {
  late final List<Station> _stations;
  late int _currentIndex;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _stations = context.read<StationsCubit>().state.stations;
    _currentIndex = _stations.indexWhere((s) => s.id == widget.initialStation.id)
        .clamp(0, _stations.isEmpty ? 0 : _stations.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stations.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nema postaja za prikaz')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_stations[_currentIndex].name)),
      body: Column(
        children: [
          // Dot indicator
          if (_stations.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_currentIndex + 1} / ${_stations.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _stations.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) => StationDetailPage(station: _stations[i]),
            ),
          ),
        ],
      ),
    );
  }
}
