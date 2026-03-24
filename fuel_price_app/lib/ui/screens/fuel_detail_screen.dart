import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:fuel_price_app/blocs/fuel_detail_cubit.dart';
import 'package:fuel_price_app/data/repositories/price_repository.dart';
import 'package:fuel_price_app/models/fuel_params.dart';
import 'package:fuel_price_app/models/fuel_price.dart';
import 'package:fuel_price_app/models/fuel_type.dart';

/// Standalone detail screen (with Scaffold + AppBar)
class FuelDetailScreen extends StatelessWidget {
  final FuelType fuelType;

  const FuelDetailScreen({super.key, required this.fuelType});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(fuelType.displayName)),
      body: FuelDetailPage(fuelType: fuelType),
    );
  }
}

/// Detail page content (no Scaffold — used inside PageView)
class FuelDetailPage extends StatelessWidget {
  final FuelType fuelType;

  const FuelDetailPage({super.key, required this.fuelType});

  @override
  Widget build(BuildContext context) {
    final priceRepo = context.read<PriceRepository>();
    final params = FuelParams.defaultParams;

    return BlocProvider(
      create: (_) => FuelDetailCubit(
        fuelType: fuelType,
        priceRepo: priceRepo,
        referenceDate: DateTime.parse(params.referenceDate),
        cycleDays: params.cycleDays,
      )..load(),
      child: BlocBuilder<FuelDetailCubit, FuelDetailState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return _DetailBody(state: state);
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final FuelDetailState state;

  const _DetailBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prediction card
          _PredictionCard(state: state),

          const SizedBox(height: 24),

          // Chart
          Text('Kretanje cijene', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          // Period selector
          _PeriodSelector(
            selected: state.chartDays,
            onChanged: (days) => context.read<FuelDetailCubit>().setChartPeriod(days),
          ),
          const SizedBox(height: 12),

          // Chart
          SizedBox(
            height: 220,
            child: state.priceHistory.isEmpty
                ? Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    color: cs.surfaceContainer,
                    child: Center(
                      child: Text(
                        'Nema podataka za prikaz',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : _PriceChart(prices: state.priceHistory),
          ),

          const SizedBox(height: 24),

          // Info row at bottom
          if (state.lastChangeDate != null || state.nextChangeDate != null)
            _InfoRow(state: state),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PredictionCard extends StatelessWidget {
  final FuelDetailState state;

  const _PredictionCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final predicted = state.predictedPrice;
    final diff = state.priceDifference;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: cs.primaryContainer,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'Predviđena cijena',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                predicted != null
                    ? '${predicted.toStringAsFixed(2)} €/${state.fuelType.unit.split('/').last}'
                    : '— €',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onPrimaryContainer,
                ),
              ),
              if (diff != null) ...[
                const SizedBox(height: 8),
                _DiffChip(diff: diff, trend: state.trend),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffChip extends StatelessWidget {
  final double diff;
  final String? trend;

  const _DiffChip({required this.diff, this.trend});

  @override
  Widget build(BuildContext context) {
    final isUp = diff > 0.005;
    final isDown = diff < -0.005;
    final color = isUp ? Colors.red.shade400 : isDown ? Colors.green.shade400 : Colors.grey;
    final sign = isUp ? '+' : '';
    final arrow = trend ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$arrow $sign${diff.toStringAsFixed(3)} €',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final FuelDetailState state;

  const _InfoRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy.');

    return Row(
      children: [
        if (state.lastChangeDate != null)
          Expanded(
            child: _InfoTile(
              icon: Icons.history,
              label: 'Zadnja izmjena',
              value: df.format(state.lastChangeDate!),
            ),
          ),
        if (state.nextChangeDate != null)
          Expanded(
            child: _InfoTile(
              icon: Icons.event,
              label: 'Sljedeća promjena',
              value: df.format(state.nextChangeDate!),
            ),
          ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _PeriodSelector({required this.selected, required this.onChanged});

  static const _periods = [
    (7, '7d'),
    (30, '30d'),
    (90, '90d'),
    (180, '6m'),
    (365, '1g'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: _periods.map((p) {
        final isSelected = p.$1 == selected;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(p.$2),
            selected: isSelected,
            onSelected: (_) => onChanged(p.$1),
            selectedColor: cs.primaryContainer,
            showCheckmark: false,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        );
      }).toList(),
    );
  }
}

class _PriceChart extends StatelessWidget {
  final List<FuelPrice> prices;

  const _PriceChart({required this.prices});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (prices.isEmpty) return const SizedBox();

    final spots = prices.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.roundedPrice);
    }).toList();

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 0.05;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 0.05;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: _calculateInterval(maxY - minY),
              getDrawingHorizontalLine: (value) => FlLine(
                color: cs.outlineVariant.withValues(alpha: 0.3),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: (spots.length / 4).ceilToDouble(),
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= prices.length) return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        DateFormat('d.M.').format(prices[idx].date),
                        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  interval: _calculateInterval(maxY - minY),
                  getTitlesWidget: (value, meta) => Text(
                    value.toStringAsFixed(2),
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minY: minY,
            maxY: maxY,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.2,
                color: cs.primary,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: cs.primary.withValues(alpha: 0.08),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final idx = spot.spotIndex;
                    final price = prices[idx];
                    return LineTooltipItem(
                      '${DateFormat('dd.MM.').format(price.date)}\n${price.roundedPrice.toStringAsFixed(2)} €',
                      TextStyle(color: cs.onPrimaryContainer, fontSize: 12),
                    );
                  }).toList();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _calculateInterval(double range) {
    if (range <= 0.1) return 0.02;
    if (range <= 0.5) return 0.1;
    if (range <= 1.0) return 0.2;
    return 0.5;
  }
}
