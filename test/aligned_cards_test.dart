import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geosustain_clean_arranged/web/widgets/aligned_cards.dart';

void main() {
  testWidgets(
    'content changes resize aligned cards and preserve button hit targets',
    (tester) async {
      var expanded = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 700,
                child: WebAlignedCards(
                  flexes: const [2, 1],
                  children: [
                    Container(
                      key: const ValueKey('large-card'),
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: LayoutBuilder(
                        builder: (_, box) => StatefulBuilder(
                          builder: (_, update) => Column(
                            children: [
                              Text(
                                expanded
                                    ? List.filled(
                                        80,
                                        'Recorded evidence',
                                      ).join(' ')
                                    : 'Recorded evidence',
                              ),
                              FilledButton(
                                onPressed: () =>
                                    update(() => expanded = !expanded),
                                child: Text(
                                  expanded
                                      ? 'Collapse evidence'
                                      : 'Expand evidence',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    WebStretchCards(
                      children: [
                        Container(
                          key: const ValueKey('top-card'),
                          height: 70,
                          color: Colors.green,
                        ),
                        Container(
                          key: const ValueKey('bottom-card'),
                          height: 90,
                          color: Colors.blue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
      expect(rect('large-card').top, rect('top-card').top);
      expect(
        rect('large-card').bottom,
        closeTo(rect('bottom-card').bottom, .1),
      );
      final oldHeight = rect('large-card').height;
      await tester.tap(find.text('Expand evidence'));
      await tester.pumpAndSettle();
      expect(expanded, isTrue);
      expect(rect('large-card').height, greaterThan(oldHeight));
      expect(
        rect('large-card').bottom,
        closeTo(rect('bottom-card').bottom, .1),
      );
      await tester.ensureVisible(find.text('Collapse evidence'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collapse evidence'));
      await tester.pumpAndSettle();
      expect(expanded, isFalse);
      expect(rect('large-card').height, closeTo(oldHeight, .1));
      expect(
        rect('large-card').bottom,
        closeTo(rect('bottom-card').bottom, .1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
