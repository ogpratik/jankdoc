// End-to-end regression test for the whole JankDoc pipeline:
// JankDoc.attach() → daemon auto-start → telemetry → rule tier → SSE stream.
//
// Runs the real sample app on a desktop device, opens each jank screen for a
// few seconds of live frames, and asserts the daemon streamed the expected
// diagnoses.
//
//   cd examples/sample_app
//   flutter test integration_test/e2e_test.dart -d macos
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jankdoc/jankdoc.dart';
import 'package:jankdoc_sample_app/main.dart';

const _screens = {
  'A · AnimatedBuilder rebuild storm': 'animated-builder-rebuild-storm',
  'B · setState inside build()': 'setstate-in-build',
  'C · Opacity raster overdraw': 'raster-overdraw-opacity',
};

const _dwell = Duration(seconds: 6);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real frames at real time, so FrameTiming callbacks fire like in the app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('each sample screen produces its expected diagnosis',
      (tester) async {
    await JankDoc.attach();

    // Not awaited: the daemon only sends SSE headers with its first event.
    final seen = <String>{};
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    unawaited(_listenForPatterns(client, seen));

    await tester.pumpWidget(const SampleApp());
    await tester.pumpAndSettle();

    for (final title in _screens.keys) {
      await tester.tap(find.text(title));
      await tester.runAsync(() => Future<void>.delayed(_dwell));
      await tester.pageBack();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
    }

    // Allow the last telemetry batch (500 ms cadence) to be diagnosed.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));

    // ignore: avoid_print
    print('[e2e] diagnoses seen: ${seen.toList()..sort()}');
    for (final MapEntry(key: title, value: patternId) in _screens.entries) {
      expect(seen, contains(patternId), reason: 'screen "$title"');
    }
  });
}

/// Subscribes to the daemon's SSE stream and records every pattern_id.
Future<void> _listenForPatterns(HttpClient client, Set<String> seen) async {
  final request =
      await client.getUrl(Uri.parse('http://127.0.0.1:9101/diagnoses/stream'));
  final response = await request.close();
  await response
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .where((line) => line.startsWith('data: '))
      .forEach((line) {
    try {
      final json = jsonDecode(line.substring(6)) as Map<String, dynamic>;
      final id = json['pattern_id'];
      if (id is String) seen.add(id);
    } on FormatException {
      // [DONE] sentinels and keep-alives are not JSON.
    }
  }).catchError((Object _) {
    // Teardown force-closes the client mid-stream; that ends the listener.
  }, test: (e) => e is HttpException);
}
