import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/ui/widgets/fuel_list_tile.dart';

void main() {
  group('FuelListTile trend indicator', () {
    testWidgets('shows ↑ in red when price rises', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FuelListTile(
              fuelName: 'Eurosuper 95',
              price: '1,42',
              unit: 'EUR/L',
              trend: '↑',
              onTap: () {},
            ),
          ),
        ),
      );
      final arrow = find.text('↑');
      expect(arrow, findsOneWidget);
      final text = tester.widget<Text>(arrow);
      expect(text.style?.color, Colors.red);
    });

    testWidgets('shows ↓ in green when price drops', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FuelListTile(
              fuelName: 'Eurodizel',
              price: '1,35',
              unit: 'EUR/L',
              trend: '↓',
              onTap: () {},
            ),
          ),
        ),
      );
      final arrow = find.text('↓');
      expect(arrow, findsOneWidget);
      final text = tester.widget<Text>(arrow);
      expect(text.style?.color, Colors.green);
    });

    testWidgets('shows → in grey when unchanged', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FuelListTile(
              fuelName: 'Eurosuper 95',
              price: '1,38',
              unit: 'EUR/L',
              trend: '→',
              onTap: () {},
            ),
          ),
        ),
      );
      final arrow = find.text('→');
      expect(arrow, findsOneWidget);
      final text = tester.widget<Text>(arrow);
      expect(text.style?.color, Colors.grey);
    });

    testWidgets('shows no arrow when trend is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FuelListTile(
              fuelName: 'Eurosuper 95',
              price: '1,42',
              unit: 'EUR/L',
              trend: null,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('↑'), findsNothing);
      expect(find.text('↓'), findsNothing);
      expect(find.text('→'), findsNothing);
    });
  });
}
