import 'package:flutter_test/flutter_test.dart';
import 'package:jankdoc_sample_app/main.dart';

void main() {
  testWidgets('SampleApp renders the three jank screens', (tester) async {
    await tester.pumpWidget(const SampleApp());
    expect(find.text('JankDoc Sample App'), findsOneWidget);
    expect(find.textContaining('AnimatedBuilder rebuild storm'), findsOneWidget);
    expect(find.textContaining('setState inside build()'), findsOneWidget);
    expect(find.textContaining('Opacity raster overdraw'), findsOneWidget);
  });
}
