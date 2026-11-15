import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jankdoc/src/telemetry/layer_census.dart';

void main() {
  testWidgets('counts fading Opacity and saveLayer clips only', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Opacity(opacity: 0.5, child: SizedBox(width: 10, height: 10)),
            Opacity(opacity: 0.2, child: SizedBox(width: 10, height: 10)),
            Opacity(opacity: 1, child: SizedBox(width: 10, height: 10)),
            Opacity(opacity: 0, child: SizedBox(width: 10, height: 10)),
            ClipRRect(
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: SizedBox(width: 10, height: 10),
            ),
            ClipRRect(child: SizedBox(width: 10, height: 10)),
          ],
        ),
      ),
    );

    expect(LayerCensus.take(), {'Opacity': 2, 'ClipRRect': 1});
  });
}
