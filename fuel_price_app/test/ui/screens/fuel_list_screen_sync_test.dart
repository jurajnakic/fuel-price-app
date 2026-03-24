import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/blocs/data_sync_cubit.dart';
import 'package:fuel_price_app/blocs/data_sync_state.dart';
import 'package:fuel_price_app/ui/screens/fuel_list_screen.dart';

class MockDataSyncCubit extends MockCubit<DataSyncState> implements DataSyncCubit {
  bool _hasData = false;
  DateTime? _lastSyncTime;

  @override
  bool get hasData => _hasData;

  @override
  DateTime? get lastSyncTime => _lastSyncTime;

  void setHasData(bool value) => _hasData = value;
  void setLastSyncTime(DateTime? value) => _lastSyncTime = value;
}

void main() {
  late MockDataSyncCubit mockSyncCubit;

  setUp(() {
    mockSyncCubit = MockDataSyncCubit();
  });

  Widget buildSubject() {
    return MaterialApp(
      home: Scaffold(
        body: BlocProvider<DataSyncCubit>.value(
          value: mockSyncCubit,
          child: const FuelListScreen(),
        ),
      ),
    );
  }

  group('FuelListScreen sync integration', () {
    testWidgets('shows spinner when SyncInProgress and no data', (tester) async {
      when(() => mockSyncCubit.state).thenReturn(const SyncInProgress());
      mockSyncCubit.setHasData(false);
      await tester.pumpWidget(buildSubject());
      expect(find.text('Preuzimanje podataka...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state on SyncFailure with no data', (tester) async {
      when(() => mockSyncCubit.state).thenReturn(const SyncFailure(message: 'fail'));
      mockSyncCubit.setHasData(false);
      await tester.pumpWidget(buildSubject());
      expect(
        find.text('Nema dostupnih podataka. Provjerite internetsku vezu i pritisnite gumb za ažuriranje.'),
        findsOneWidget,
      );
      expect(find.text('Ažuriraj'), findsOneWidget);
    });

    testWidgets('shows snackbar on SyncPartial with existing data', (tester) async {
      mockSyncCubit.setHasData(true);
      whenListen(
        mockSyncCubit,
        Stream<DataSyncState>.fromIterable([
          const SyncPartial(failedSources: ['oilPrices']),
        ]),
        initialState: const SyncSuccess(),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(
        find.text('Ažuriranje nije u potpunosti uspjelo. Prikazani su posljednji dostupni podaci.'),
        findsOneWidget,
      );
    });

    testWidgets('shows snackbar on SyncFailure with existing data', (tester) async {
      mockSyncCubit.setHasData(true);
      whenListen(
        mockSyncCubit,
        Stream<DataSyncState>.fromIterable([
          const SyncFailure(message: 'fail'),
        ]),
        initialState: const SyncSuccess(),
      );
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(
        find.text('Ažuriranje nije uspjelo. Prikazani su posljednji dostupni podaci.'),
        findsOneWidget,
      );
    });

    testWidgets('shows last update timestamp', (tester) async {
      when(() => mockSyncCubit.state).thenReturn(const SyncSuccess());
      mockSyncCubit.setHasData(true);
      mockSyncCubit.setLastSyncTime(DateTime(2026, 3, 24, 18, 0));
      await tester.pumpWidget(buildSubject());
      expect(find.textContaining('Zadnje ažuriranje:'), findsOneWidget);
      expect(find.textContaining('24.03.2026.'), findsOneWidget);
    });
  });
}
