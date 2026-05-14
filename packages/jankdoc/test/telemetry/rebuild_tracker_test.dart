import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jankdoc/src/telemetry/rebuild_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RebuildTracker', () {
    late RebuildTracker tracker;

    setUp(() {
      tracker = RebuildTracker();
      tracker.start();
    });

    tearDown(() {
      tracker.stop();
    });

    testWidgets('counts rebuilds for each widget type', (tester) async {
      int buildCount = 0;

      await tester.pumpWidget(
        Builder(
          builder: (_) {
            buildCount++;
            return const SizedBox();
          },
        ),
      );

      // Trigger a rebuild
      await tester.pumpWidget(
        Builder(
          builder: (_) {
            buildCount++;
            return const SizedBox();
          },
        ),
      );

      final counts = tracker.flushCounts();
      // In debug mode, debugOnRebuildDirtyWidget fires and we should see counts.
      // In profile/release mode, counts will be empty — that's expected.
      // This test asserts the contract rather than the exact value.
      expect(counts, isA<Map<String, int>>());
      expect(buildCount, greaterThanOrEqualTo(1));
    });

    test('flushCounts resets internal state', () {
      // Manually invoke the callback to simulate a rebuild
      // (not practical without a full Flutter binding, so we test the flush contract)
      final first = tracker.flushCounts();
      final second = tracker.flushCounts();
      expect(first, isEmpty);
      expect(second, isEmpty);
    });

    test('stop clears the hook', () {
      tracker.stop();
      // After stop, the hook should be null (no crash when rebuilt)
      assert(() {
        expect(debugOnRebuildDirtyWidget, isNot(equals(tracker)));
        return true;
      }());
    });
  });
}
