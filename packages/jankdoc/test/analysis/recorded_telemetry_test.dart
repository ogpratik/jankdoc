import 'dart:convert';
import 'dart:io';

import 'package:jankdoc_core/jankdoc_core.dart';
import 'package:test/test.dart';

/// Batches recorded from examples/sample_app on macOS (120 Hz) with
/// `daemon --record`, one per jank screen. Synthetic fixtures had drifted
/// from what the collector really sends — e.g. list widgets never appear in
/// rebuild counts and Opacity only shows up via the layer census — so these
/// pin the rules to real telemetry.
void main() {
  final batches = [
    for (final line
        in File('test/fixtures/sample_app_telemetry.jsonl').readAsLinesSync())
      if (line.isNotEmpty)
        TelemetryBatch.fromJson(jsonDecode(line) as Map<String, dynamic>),
  ];
  final engine = RuleEngine(BuiltInRuleProvider());

  const expected = [
    'animated-builder-rebuild-storm',
    'setstate-in-build',
    'raster-overdraw-opacity',
  ];

  for (var i = 0; i < expected.length; i++) {
    test('recorded sample-app batch ${i + 1} diagnoses ${expected[i]}', () {
      expect(engine.evaluate(batches[i])?.rule.patternId, expected[i]);
    });
  }

  test('setState loop stack points at the user closure', () {
    final userFrame = batches[1]
        .jankFrames
        .expand((f) => f.uiStack)
        .firstWhere((f) => f.isUserCode);
    expect(userFrame.file, endsWith('setstate_in_build_screen.dart'));
    expect(userFrame.function, contains('build'));
  });
}
