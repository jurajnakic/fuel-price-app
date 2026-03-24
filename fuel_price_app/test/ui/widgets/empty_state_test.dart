import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_price_app/ui/widgets/empty_state.dart';

void main() {
  group('EmptyStateWidget', () {
    testWidgets('shows error message text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(onRetry: () {}),
          ),
        ),
      );
      expect(
        find.text('Nema dostupnih podataka. Provjerite internetsku vezu i pritisnite gumb za ažuriranje.'),
        findsOneWidget,
      );
    });

    testWidgets('shows retry button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(onRetry: () {}),
          ),
        ),
      );
      expect(find.text('Ažuriraj'), findsOneWidget);
    });

    testWidgets('tap retry button calls onRetry', (tester) async {
      bool called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(onRetry: () => called = true),
          ),
        ),
      );
      await tester.tap(find.text('Ažuriraj'));
      expect(called, isTrue);
    });

    testWidgets('shows cloud-off icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(onRetry: () {}),
          ),
        ),
      );
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}
