import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  testWidgets('historical values retain units and approximate provenance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows =
        jsonDecode(
              File('backend/data/cagro_observations.json').readAsStringSync(),
            )
            as List;
    final locations =
        jsonDecode(File('backend/data/cagro_locations.json').readAsStringSync())
            as List;
    final row = Map<String, dynamic>.from(rows.first as Map);
    final location = Map<String, dynamic>.from(
      locations.firstWhere((l) => l['id'] == row['location_id']) as Map,
    );
    final record = {
      'cagro_soil': {
        'status': 'matched',
        'message': 'Historical locality observations.',
        'observations': [
          {
            ...location,
            ...row,
            'data_note':
                'Not an exact soil measurement for the selected polygon.',
          },
        ],
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CagroSoilObservationsCard(record: record),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('FARM 2, DAPCO'));
    await tester.tap(find.text('FARM 2, DAPCO'));
    await tester.pumpAndSettle();
    expect(
      find.text('Estimated Nitrogen (%) derived from Organic Matter: 0.09%'),
      findsOneWidget,
    );
    expect(
      find.text('Reported soil Phosphorus (ppm): 61.47 ppm'),
      findsOneWidget,
    );
    expect(
      find.text('Reported soil Potassium (ppm): 1337.2 ppm'),
      findsOneWidget,
    );
    expect(find.text('Original CAGRO sample GPS: No'), findsOneWidget);
    expect(
      find.text('Location precision: Approximate farm-area anchor'),
      findsOneWidget,
    );
    expect(find.text('Suitable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmatched locality does not display zero nutrient readings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CagroSoilObservationsCard(
            record: {
              'cagro_soil': {
                'status': 'unavailable',
                'observations': [],
                'message': 'No reliable locality match.',
              },
            },
          ),
        ),
      ),
    );
    expect(
      find.text('No matching CAGRO soil record for this area.'),
      findsOneWidget,
    );
    expect(find.text('CAGRO soil NPK: Unavailable'), findsNothing);
    await tester.tap(find.text('Local soil data'));
    await tester.pumpAndSettle();
    expect(find.text('CAGRO soil NPK: Unavailable'), findsOneWidget);
    expect(find.textContaining('0 ppm'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
