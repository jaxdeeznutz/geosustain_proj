import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/main.dart';

void main() {
  for (final width in [320.0, 360.0, 402.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('shared rows align at $width px / $scale text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          GeoSustainApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          GeoSustainHeader(
                            title: 'Create a Farm Boundary',
                            back: () {},
                            trailing: GeoHeaderAction(
                              icon: Icons.help_outline,
                              tooltip: 'Guide',
                              onPressed: () {},
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ReferenceAction(
                                  'Create a Farm Boundary',
                                  'Walk your perimeter with live GPS.',
                                  Icons.directions_walk,
                                  () {},
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ReferenceAction(
                                  'Analyze Land Using a Polygon',
                                  'Outline an area and explore crop suitability.',
                                  Icons.edit_square,
                                  () {},
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: GeoInfoCard(
                                    icon: Icon(Icons.gps_fixed),
                                    label: 'Ready',
                                    subtitle: 'Tap Start to begin',
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: GeoInfoCard(
                                    icon: Icon(Icons.polyline),
                                    label: '0 points',
                                    subtitle: 'Boundary not started',
                                    color: GeoDesign.blue,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: GeoInfoCard(
                                    icon: Icon(Icons.signal_cellular_alt),
                                    label: 'Accuracy unknown',
                                    subtitle:
                                        'Move to an open area for better GPS',
                                    color: GeoDesign.yellow,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: GeoButton(
                                  label: 'Finish',
                                  icon: Icons.stop,
                                  onPressed: () {},
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: GeoButton(
                                  label: 'Undo last point',
                                  icon: Icons.undo,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final actions = find.byType(ReferenceAction);
        expect(tester.getSize(actions.at(0)), tester.getSize(actions.at(1)));
        expect(
          tester.getBottomLeft(actions.at(0)).dy,
          tester.getBottomLeft(actions.at(1)).dy,
        );
        final statuses = find.byType(GeoInfoCard);
        for (var i = 1; i < 3; i++) {
          expect(
            tester.getSize(statuses.at(i)).height,
            tester.getSize(statuses.at(0)).height,
          );
          expect(
            tester.getTopLeft(statuses.at(i)).dy,
            tester.getTopLeft(statuses.at(0)).dy,
          );
        }
        final buttons = find.byType(GeoButton);
        expect(tester.getSize(buttons.at(0)), tester.getSize(buttons.at(1)));
        expect(tester.getSize(buttons.at(0)).height, GeoDesign.buttonHeight);
        expect(
          tester.getSize(find.byTooltip('Notifications')),
          const Size.square(48),
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
